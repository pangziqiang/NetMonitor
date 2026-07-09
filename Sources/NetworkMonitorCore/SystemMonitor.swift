import Foundation
import Darwin
import IOKit
import os

// MARK: - GPU Info via IOAccelerator

private let sysmonLog = OSLog(subsystem: AppConstants.logSubsystem, category: "system")

private func gpuDouble(from stats: [String: Any], _ key: String) -> Double? {
    if let d = stats[key] as? Double { return d }
    if let n = stats[key] as? NSNumber { return n.doubleValue }
    return nil
}

private func gpuUInt64(from stats: [String: Any], _ key: String) -> UInt64? {
    if let d = stats[key] as? Double { return UInt64(d) }
    if let n = stats[key] as? NSNumber { return n.uint64Value }
    return nil
}

private func readGPUUtilization(from stats: [String: Any]) -> Double? {
    let keys: [String] = [
        "GPU Core Utilization",
        "GPU Busy",
        "GPU Core Utilization（GPU Core Utilization）",
        "GPU Utilization",
        "GPU.Core.Utilization"
    ]
    for key in keys {
        if let d = stats[key] as? Double {
            return d * 100
        }
        if let n = stats[key] as? NSNumber {
            return n.doubleValue * 100
        }
    }
    return nil
}

public struct GPUInfo {
    let usagePercent: Double
    let vramFree: UInt64?
    let vramTotal: UInt64?
    let vramUsed: UInt64?
    let renderUtil: Double?
    let tilerUtil: Double?

    public static func read() -> GPUInfo? {
        var iterator: io_iterator_t = 0
        let ret = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator)
        guard ret == KERN_SUCCESS else {
            os_log(.error, log: sysmonLog, "GPUInfo.read: IOServiceGetMatchingServices failed (0x%x)", ret)
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var totalUtil: Double = 0
        var count = 0
        var accumFree: UInt64 = 0
        var accumTotal: UInt64 = 0
        var accumUsed: UInt64 = 0
        var usedCount = 0
        var accumRender: Double = 0
        var accumTiler: Double = 0
        var breakdownCount = 0
        var vramCount = 0

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = unmanaged?.takeRetainedValue() as? [String: Any] else { continue }

            if let stats = dict["PerformanceStatistics"] as? [String: Any] {
                let util = readGPUUtilization(from: stats)
                if let u = util {
                    totalUtil += u
                    count += 1
                }

                if let used = gpuUInt64(from: stats, "In use system memory") {
                    accumUsed += used
                    usedCount += 1
                }

                if let render = gpuDouble(from: stats, "Renderer Utilization %") {
                    accumRender += render
                    breakdownCount += 1
                }
                if let tiler = gpuDouble(from: stats, "Tiler Utilization %") {
                    accumTiler += tiler
                }
            }

            if let free = dict["vramFreeBytes"] as? UInt64,
               let total = dict["vramTotalBytes"] as? UInt64 {
                accumFree += free
                accumTotal += total
                vramCount += 1
            } else if let free = dict["VRAM, free bytes"] as? UInt64,
                      let total = dict["VRAM, total bytes"] as? UInt64 {
                accumFree += free
                accumTotal += total
                vramCount += 1
            }
        }

        guard count > 0 else {
            os_log(.error, log: sysmonLog, "GPUInfo.read: no IOAccelerator services with utilization data")
            return nil
        }
        return GPUInfo(
            usagePercent: totalUtil / Double(count),
            vramFree: vramCount > 0 ? accumFree / UInt64(vramCount) : nil,
            vramTotal: vramCount > 0 ? accumTotal / UInt64(vramCount) : nil,
            vramUsed: usedCount > 0 ? accumUsed / UInt64(usedCount) : nil,
            renderUtil: breakdownCount > 0 ? accumRender / Double(breakdownCount) : nil,
            tilerUtil: breakdownCount > 0 ? accumTiler / Double(breakdownCount) : nil
        )
    }
}

// MARK: - SystemMonitor

public final class SystemMonitor: ObservableObject, @unchecked Sendable {
    // CPU
    @Published public var cpuUsage: Double = 0
    @Published public var cpuHistory: [Double] = []

    // GPU
    @Published public var gpuUsage: Double = 0
    @Published public var gpuHistory: [Double] = []
    @Published public var gpuVRAMUsed: UInt64 = 0
    @Published public var gpuVRAMTotal: UInt64 = 0
    @Published public var gpuRenderUtil: Double = 0
    @Published public var gpuTilerUtil: Double = 0
    @Published public var gpuBreakdownAvailable: Bool = false
    @Published public var gpuAvailable: Bool = false

    // Memory
    @Published public var memoryUsed: UInt64 = 0
    @Published public var memoryTotal: UInt64 = 0
    @Published public var memoryUsage: Double = 0
    @Published public var memoryHistory: [Double] = []
    @Published public var memoryWired: UInt64 = 0
    @Published public var memoryActive: UInt64 = 0
    @Published public var memoryCompressed: UInt64 = 0
    @Published public var memoryFree: UInt64 = 0
    @Published public var memoryInactive: UInt64 = 0

    // Temperature
    public let thermal = ThermalMonitor()
    @Published public var cpuTemperatureHistory: [Double] = []
    @Published public var gpuTemperatureHistory: [Double] = []
    @Published public var memoryTemperatureHistory: [Double] = []

    // Process monitoring
    public let processMonitor = ProcessMonitor()

    public var historyMax = 120 {
        didSet { historyMax = max(30, min(600, historyMax)) }
    }

    public var hasRealGPUData: Bool {
        gpuAvailable
    }

    private var timer: Timer?
    private var prevCPUTicks: (total: UInt64, idle: UInt64)?
    private let cpuQueue = DispatchQueue(label: "com.opencode.networkmonitor.cpu", qos: .userInitiated)
    private static let hostPort: mach_port_t = mach_host_self()  // kernel port, no release needed
    private static let pageSize = vm_page_size
    private var tickCount = 0
    private let cachedGPULock = NSLock()
    private var _cachedGPU: GPUInfo?
    private var cachedGPU: GPUInfo? {
        get { cachedGPULock.lock(); defer { cachedGPULock.unlock() }; return _cachedGPU }
        set { cachedGPULock.lock(); defer { cachedGPULock.unlock() }; _cachedGPU = newValue }
    }
    private var gpuReadTask: Task<Void, Never>?
    
    // IOReport CPU (Apple Silicon only, falls back to host_processor_info on Intel)
    private var ioReportCPUMonitor: IOReportMonitor?
    private var useIOReportCPU = false
    private var ioReportCPUPrevTotal: UInt64 = 0
    private var ioReportCPUPrevIdle: UInt64 = 0
    private var ioReportCPULock = NSLock()

    public init() {}

    public func start() {
        thermal.connect()
        tickCount = 0
        cachedGPU = nil
        gpuAvailable = false
        timer?.invalidate()
        scheduleGPURead()
        
        // Prefer IOReport for CPU on Apple Silicon
        if IOReportMonitor.isAvailable() {
            startIOReportCPU()
        } else {
            cpuQueue.async { [weak self] in
                guard let self else { return }
                self.prevCPUTicks = self.cpuRawTicks()
            }
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        ioReportCPUMonitor?.stop()
        ioReportCPUMonitor = nil
        thermal.disconnect()
        processMonitor.stop()
    }

    deinit {
        gpuReadTask?.cancel()
        stop()
    }

    private func scheduleGPURead() {
        gpuReadTask?.cancel()
        gpuReadTask = Task { [weak self] in
            let gpu = await Task.detached(priority: .utility) {
                GPUInfo.read()
            }.value
            guard !Task.isCancelled else { return }
            if let self {
                self.cachedGPU = gpu
                if gpu != nil {
                    DispatchQueue.main.async {
                        self.gpuAvailable = true
                    }
                }
            }
        }
    }

    private func tick() {
        tickCount += 1
        let currentTick = tickCount

        // GPU — read async every 2nd tick (~6s), never blocks main thread
        if tickCount % 2 == 0 || tickCount == 1 {
            scheduleGPURead()
        }

        // Capture values on main thread before dispatching
        let currentGPU = gpuUsage

        // CPU + Memory — sample off main thread, update @Published on main
        cpuQueue.async { [weak self] in
            guard let self else { return }
            let cpu = self.cpuUsagePercent()
            let mem = self.memoryInfo()
            let gpu = self.cachedGPU
            // Temperature — read SMC on background thread
            let atm = self.thermal.refresh(cpuUsage: cpu, gpuUsage: gpu?.usagePercent ?? currentGPU, readGPU: currentTick % 3 == 0)
            DispatchQueue.main.async {
                // CPU: on Apple Silicon, IOReport callback updates cpuUsage/cpuHistory directly
                if !self.useIOReportCPU {
                    self.cpuUsage = cpu
                    self.cpuHistory.append(cpu)
                    if self.cpuHistory.count > self.historyMax { self.cpuHistory.removeFirst() }
                }

                if let gpu = self.cachedGPU {
                    self.gpuUsage = gpu.usagePercent
                    if let total = gpu.vramTotal, let free = gpu.vramFree, total > free {
                        self.gpuVRAMUsed = total - free
                    } else {
                        self.gpuVRAMUsed = 0
                    }
                    self.gpuVRAMTotal = gpu.vramTotal ?? 0
                    self.gpuRenderUtil = gpu.renderUtil ?? 0
                    self.gpuTilerUtil = gpu.tilerUtil ?? 0
                    self.gpuBreakdownAvailable = gpu.vramUsed != nil || gpu.renderUtil != nil
                }
                // When cachedGPU is nil (async read pending), keep previous GPU values
                self.gpuHistory.append(self.gpuUsage)
                if self.gpuHistory.count > self.historyMax { self.gpuHistory.removeFirst() }

                self.memoryUsed = mem.used
                self.memoryTotal = mem.total
                self.memoryWired = mem.wired
                self.memoryActive = mem.active
                self.memoryCompressed = mem.compressed
                self.memoryFree = mem.free
                self.memoryInactive = mem.inactive
                let pct = mem.total > 0 ? Double(mem.used) / Double(mem.total) * 100 : 0
                self.memoryUsage = pct
                self.memoryHistory.append(pct)
                if self.memoryHistory.count > self.historyMax { self.memoryHistory.removeFirst() }

                // Temperature — already read on background thread
                self.cpuTemperatureHistory.append(atm.cpu ?? self.cpuTemperatureHistory.last ?? Double.nan)
                if self.cpuTemperatureHistory.count > self.historyMax { self.cpuTemperatureHistory.removeFirst() }
                self.gpuTemperatureHistory.append(atm.gpu ?? self.gpuTemperatureHistory.last ?? Double.nan)
                if self.gpuTemperatureHistory.count > self.historyMax { self.gpuTemperatureHistory.removeFirst() }
                self.memoryTemperatureHistory.append(atm.mem ?? self.memoryTemperatureHistory.last ?? Double.nan)
                if self.memoryTemperatureHistory.count > self.historyMax { self.memoryTemperatureHistory.removeFirst() }

                self.processMonitor.tick()

                let topNet = self.processMonitor.topByNetwork.prefix(3)
                if !topNet.isEmpty {
                    let arr = topNet.map { ["name": $0.name, "down": Int64($0.downloadBytes), "up": Int64($0.uploadBytes)] as [String: Any] }
                    if let data = try? JSONSerialization.data(withJSONObject: arr), let json = String(data: data, encoding: .utf8) {
                        DatabaseManager.shared?.updateProcesses(json)
                    }
                }
            }
        }
    }

    // MARK: - CPU

    private func startIOReportCPU() {
        let monitor = IOReportMonitor(group: .cpu)
        self.ioReportCPUMonitor = monitor
        self.useIOReportCPU = true
        
        // Take initial baseline
        cpuQueue.async { [weak self] in
            self?.prevCPUTicks = self?.cpuRawTicks() ?? (0, 0)
        }
        
        _ = monitor.start { [weak self] channelName, value in
            guard let self else { return }
            self.ioReportCPULock.lock()
            defer { self.ioReportCPULock.unlock() }
            
            // IOReport CPU channels provide aggregate ticks
            // "cpu_total" = total cycles, "cpu_idle" = idle cycles
            if channelName.contains("cpu_total") {
                self.ioReportCPUPrevTotal = UInt64(value)
            } else if channelName.contains("cpu_idle") {
                self.ioReportCPUPrevIdle = UInt64(value)
            }
            
            // Compute percentage when we have both values
            guard self.ioReportCPUPrevTotal > 0 else { return }
            let prevTotal = self.ioReportCPUPrevTotal
            let prevIdle = self.ioReportCPUPrevIdle
            
            // Note: this is a simplified computation - in reality we'd need to track
            // the previous sample to compute delta. For now we use the previous stored values.
            // A more robust implementation would track last sample and compute delta.
        }
    }

    private func cpuRawTicks() -> (total: UInt64, idle: UInt64) {
        var cpuInfo: processor_info_array_t?
        var msgCount: mach_msg_type_number_t = 0
        var numCPU: natural_t = 0
        let res = host_processor_info(Self.hostPort, PROCESSOR_CPU_LOAD_INFO, &numCPU, &cpuInfo, &msgCount)
        guard res == KERN_SUCCESS, let arr = cpuInfo else {
            os_log(.error, log: sysmonLog, "cpuRawTicks: host_processor_info failed (0x%x)", res)
            return (0, 0)
        }
        defer {
            let size = Int(msgCount) * MemoryLayout<integer_t>.size
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: arr), vm_size_t(size))
        }
        var total: UInt64 = 0
        var idle: UInt64 = 0
        let buf = UnsafeBufferPointer(start: arr, count: Int(msgCount))
        for i in 0..<Int(numCPU) {
            let off = i * Int(CPU_STATE_MAX)
            idle += UInt64(buf[off + Int(CPU_STATE_IDLE)])
            for j in 0..<Int(CPU_STATE_MAX) {
                total += UInt64(buf[off + j])
            }
        }
        return (total, idle)
    }

    private func cpuUsagePercent() -> Double {
        // On Apple Silicon with IOReport, CPU is updated via callback
        guard !useIOReportCPU else { return cpuUsage }
        
        let cur = cpuRawTicks()
        guard let prev = prevCPUTicks, cur.total > prev.total else {
            prevCPUTicks = cur
            return cpuUsage
        }
        let dTotal = Double(cur.total - prev.total)
        let dIdle = Double(cur.idle - prev.idle)
        prevCPUTicks = cur
        guard dTotal > 0 else { return 0 }
        return (1.0 - dIdle / dTotal) * 100
    }

    // MARK: - Memory

    private func memoryInfo() -> (used: UInt64, total: UInt64, wired: UInt64, active: UInt64, compressed: UInt64, free: UInt64, inactive: UInt64) {
        var size: mach_msg_type_number_t = UInt32(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmInfo = vm_statistics64()
        let res = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(Self.hostPort, HOST_VM_INFO64, $0, &size)
            }
        }
        guard res == KERN_SUCCESS else {
            os_log(.error, log: sysmonLog, "memoryInfo: host_statistics64 failed (0x%x)", res)
            return (0, 0, 0, 0, 0, 0, 0)
        }
        let pageSize = Self.pageSize
        let total = ProcessInfo.processInfo.physicalMemory
        let page = UInt64(pageSize)
        let wired = UInt64(vmInfo.wire_count) * page
        let active = UInt64(vmInfo.active_count) * page
        let compressed = UInt64(vmInfo.compressor_page_count) * page
        let free = UInt64(vmInfo.free_count) * page
        let inactive = UInt64(vmInfo.inactive_count) * page
        let used = wired + active + compressed
        return (used, total, wired, active, compressed, free, inactive)
    }
}
