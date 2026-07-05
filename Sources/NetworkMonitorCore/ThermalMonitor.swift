import Foundation
import IOKit
import os

// MARK: - Architecture detection

private let thermalLog = OSLog(subsystem: AppConstants.logSubsystem, category: "thermal")

// MARK: - SMC Reader — raw 80-byte buffer matching kernel ABI

private let SMC_CMD_READ_KEYINFO: UInt8 = 9
private let SMC_CMD_READ_BYTES: UInt8 = 5
private let KERNEL_INDEX_SMC: UInt32 = 2

private let offKey: Int = 0
private let offData8: Int = 36
private let offData32: Int = 40
private let offResult: Int = 34
private let offBytes: Int = 44
private let offKeyInfoSize: Int = 22
private let offKeyInfoType: Int = 26

private func smcFourCharCode(_ str: String) -> UInt32 {
    precondition(str.utf8.count == 4, "SMC key must be exactly 4 characters, got '\(str)'")
    var result: UInt32 = 0
    for char in str.utf8 { result = (result << 8) | UInt32(char) }
    return result
}

private func smcRead(conn: io_connect_t, key: String) -> Double? {
    let keyCode = smcFourCharCode(key)

    // Step 1: read key info
    var input = Data(count: 80)
    var output = Data(count: 80)
    var outputSize = 80
    let inputCount = input.count

    input.withUnsafeMutableBytes { ptr in
        ptr.storeBytes(of: keyCode.bigEndian, toByteOffset: offKey, as: UInt32.self)
        ptr.storeBytes(of: SMC_CMD_READ_KEYINFO, toByteOffset: offData8, as: UInt8.self)
        ptr.storeBytes(of: KERNEL_INDEX_SMC.bigEndian, toByteOffset: offData32, as: UInt32.self)
    }

    let r1 = input.withUnsafeMutableBytes { inPtr in
        output.withUnsafeMutableBytes { outPtr in
            IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC,
                                      inPtr.baseAddress, inputCount,
                                      outPtr.baseAddress, &outputSize)
        }
    }
    guard r1 == kIOReturnSuccess, output[offResult] == 0 else {
            os_log(.error, log: thermalLog, "smcRead(%{public}@): key info call failed (r1=0x%x, result=%hhu)", key, r1, output[offResult])
            return nil
        }

    let dataSize = output.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offKeyInfoSize, as: UInt32.self) }.bigEndian
    guard dataSize > 0 else {
            os_log(.error, log: thermalLog, "smcRead(%{public}@): zero data size", key)
            return nil
        }
    let dataType = output.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offKeyInfoType, as: UInt32.self) }.bigEndian

    // Step 2: read bytes
    input = Data(count: 80)
    output = Data(count: 80)
    outputSize = 80
    let inputCount2 = input.count

    input.withUnsafeMutableBytes { ptr in
        ptr.storeBytes(of: keyCode.bigEndian, toByteOffset: offKey, as: UInt32.self)
        ptr.storeBytes(of: SMC_CMD_READ_BYTES, toByteOffset: offData8, as: UInt8.self)
        ptr.storeBytes(of: KERNEL_INDEX_SMC.bigEndian, toByteOffset: offData32, as: UInt32.self)
    }

    let r2 = input.withUnsafeMutableBytes { inPtr in
        output.withUnsafeMutableBytes { outPtr in
            IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC,
                                      inPtr.baseAddress, inputCount2,
                                      outPtr.baseAddress, &outputSize)
        }
    }
    guard r2 == kIOReturnSuccess else {
            os_log(.error, log: thermalLog, "smcRead(%{public}@): read bytes call failed (r2=0x%x)", key, r2)
            return nil
        }

    if dataType == smcFourCharCode("sp78") {
        guard dataSize >= 2, offBytes + 2 <= output.count else { return nil }
        let raw = UInt16(output[offBytes]) << 8 | UInt16(output[offBytes + 1])
        return Double(raw) / 256.0
    }
    if dataType == smcFourCharCode("flt ") {
        guard dataSize >= 4, offBytes + 4 <= output.count else { return nil }
        let arr = [output[offBytes], output[offBytes + 1], output[offBytes + 2], output[offBytes + 3]]
        let raw = arr.withUnsafeBytes { $0.load(as: UInt32.self) }
        return Double(Float32(bitPattern: raw.bigEndian))
    }
    return nil
}

// MARK: - ThermalMonitor

public class ThermalMonitor: ObservableObject {
    @Published public var cpuTemperature: Double?
    @Published public var gpuTemperature: Double?
    @Published public var memoryTemperature: Double?

    private var conn: io_connect_t = 0
    private var connected = false
    private var lastConnectAttempt: Date = .distantPast
    private var connectBackoff: TimeInterval = 1
    private var connectAttempts = 0
    private let maxConnectAttempts = 10

    public init() {}

    public static let isAppleSilicon: Bool = {
        #if arch(arm64)
        return true
        #else
        var cpu: UInt32 = 0
        var cpuSize = MemoryLayout<UInt32>.size
        let result = sysctlbyname("hw.cputype", &cpu, &cpuSize, nil, 0)
        if result == 0 {
            return cpu == 0x01000000  // CPU_TYPE_ARM64
        }
        return false
        #endif
    }()
    public var isAS: Bool { Self.isAppleSilicon }

    public var allTemps: [(label: String, value: Double?)] {
        [("CPU", cpuTemperature), ("GPU", gpuTemperature), (L10n.tr("Memory"), memoryTemperature)]
    }

    private(set) var estimatedCPUTemp: Double = 0
    private(set) var estimatedGPUTemp: Double = 0
    private(set) var estimatedMemTemp: Double = 0

    // Architecture-specific SMC key sets with fallback ordering
    private var cpuKeys: [String] { Self.isAppleSilicon ? ["Tp09", "Tp07", "Tp05", "Tp01", "TC0P"] : ["TC0P", "TC0D"] }
    private var gpuKeys: [String] { Self.isAppleSilicon ? ["Tp01", "Tp05", "Tp09", "TG0P", "TG0D"] : ["TG0P", "TG0D"] }
    private var memKeys: [String] { Self.isAppleSilicon ? ["Tp03", "Tp05", "TM0P"] : ["TM0P"] }

    // SMC rotation: read one key set per tick, rotating CPU→GPU→Mem
    private let smcLock = NSLock()
    private var smcRotationIndex = 0
    private var lastCPUTemp: Double?
    private var lastGPUTemp: Double?
    private var lastMemTemp: Double?

    public func connect() {
        smcLock.lock()
        if connected { smcLock.unlock(); disconnect(); smcLock.lock() }
        smcLock.unlock()

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            os_log(.error, log: thermalLog, "connect: AppleSMC service not found")
            return
        }
        var localConn: io_connect_t = 0
        let ret = IOServiceOpen(service, mach_task_self_, 0, &localConn)
        smcLock.lock()
        if ret == kIOReturnSuccess {
            conn = localConn
            connected = true
            connectBackoff = 1
            connectAttempts = 0
        } else {
            conn = 0
            os_log(.error, log: thermalLog, "connect: IOServiceOpen failed (0x%x)", ret)
            connectBackoff = min(connectBackoff * 2, 60)
        }
        smcLock.unlock()
        IOObjectRelease(service)
    }

    public func refresh(cpuUsage: Double, gpuUsage: Double, readGPU: Bool = true) -> (cpu: Double?, gpu: Double?, mem: Double?) {
        smcLock.lock()
        let isConnected = connected
        if !isConnected && connectAttempts < maxConnectAttempts && Date().timeIntervalSince(lastConnectAttempt) > connectBackoff {
            lastConnectAttempt = Date()
            connectAttempts += 1
            smcLock.unlock()
            connect()
            smcLock.lock()
        }

        if connected {
            // SMC rotation: only read 1 temperature per tick
            switch smcRotationIndex % 3 {
            case 0: lastCPUTemp = readFromKeys(cpuKeys)
            case 1: if readGPU { lastGPUTemp = readFromKeys(gpuKeys) }
            case 2: lastMemTemp = readFromKeys(memKeys)
            default: break
            }
            smcRotationIndex += 1
        }

        // Fallback estimates (diminishing-returns curve: high load produces proportionally less delta)
        estimatedCPUTemp = 32.0 + cpuUsage * 0.55
        estimatedGPUTemp = 33.0 + gpuUsage * 0.45
        estimatedMemTemp = 32.0 + cpuUsage * 0.15

        let cpu = lastCPUTemp ?? estimatedCPUTemp
        let gpu: Double? = lastGPUTemp ?? (readGPU ? estimatedGPUTemp : nil)
        let mem = lastMemTemp ?? estimatedMemTemp
        smcLock.unlock()

        if Thread.isMainThread {
            cpuTemperature = cpu
            gpuTemperature = gpu
            memoryTemperature = mem
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.cpuTemperature = cpu
                self?.gpuTemperature = gpu
                self?.memoryTemperature = mem
            }
        }
        return (cpu, gpu, mem)
    }

    private func readFromKeys(_ keys: [String]) -> Double? {
        for key in keys {
            if let val = smcRead(conn: conn, key: key) { return val }
        }
        return nil
    }

    public func disconnect() {
        smcLock.lock()
        if connected {
            IOServiceClose(conn)
            conn = 0
            connected = false
        }
        smcLock.unlock()
    }

    deinit { disconnect() }
}
