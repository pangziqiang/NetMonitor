import Foundation

/// 整机硬件信息（用于设置页「当前设备」卡片，对标 Stats 仪表盘）。
/// 纯 Foundation，不依赖 SwiftUI。
public struct HardwareInfo {
    public let machineModel: String
    public let cpuBrand: String
    public let physicalCores: Int
    public let logicalCores: Int
    public let ramBytes: UInt64
    public let gpuName: String
    public let gpuVRAM: String
    public let osVersion: String

    /// 同步加载全部信息；GPU 名首次会调 system_profiler（~1-2s），之后走缓存。
    public static func load() -> HardwareInfo {
        let gpu = gpuInfo()
        return HardwareInfo(
            machineModel: sysctlString("hw.model"),
            cpuBrand: sysctlString("machdep.cpu.brand_string"),
            physicalCores: sysctlInt("hw.physicalcpu"),
            logicalCores: sysctlInt("hw.logicalcpu"),
            ramBytes: sysctlUInt64("hw.memsize"),
            gpuName: gpu.name,
            gpuVRAM: gpu.vram,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    // MARK: - GPU (system_profiler, 带缓存)

    private static let gpuCacheLock = NSLock()
    private static var gpuCache: (name: String, vram: String)?

    private static func gpuInfo() -> (name: String, vram: String) {
        gpuCacheLock.lock()
        defer { gpuCacheLock.unlock() }
        if let cached = gpuCache { return cached }

        var name = L10n.tr("Unknown")
        var vram = "—"
        let task = Process()
        task.launchPath = "/usr/sbin/system_profiler"
        task.arguments = ["SPDisplaysDataType", "-json"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let displays = json["SPDisplaysDataType"] as? [[String: Any]],
               let first = displays.first {
                if let model = first["sppci_model"] as? String, !model.isEmpty {
                    name = model
                }
                if let v = first["spdisplays_vram"] as? String, !v.isEmpty {
                    vram = v
                }
            }
        } catch {
            // 保持占位值
        }
        gpuCache = (name, vram)
        return gpuCache!
    }
}

// MARK: - sysctl helpers

private func sysctlString(_ name: String) -> String {
    var size: size_t = 0
    sysctlbyname(name, nil, &size, nil, 0)
    guard size > 0 else { return "" }
    var buf = [CChar](repeating: 0, count: size)
    sysctlbyname(name, &buf, &size, nil, 0)
    return String(cString: buf).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func sysctlInt(_ name: String) -> Int {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    sysctlbyname(name, &value, &size, nil, 0)
    return Int(value)
}

private func sysctlUInt64(_ name: String) -> UInt64 {
    var value: UInt64 = 0
    var size = MemoryLayout<UInt64>.size
    sysctlbyname(name, &value, &size, nil, 0)
    return value
}
