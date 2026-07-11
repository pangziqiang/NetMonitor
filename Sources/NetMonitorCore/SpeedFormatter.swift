import Foundation

private let BYTES_PER_KB: Double = 1024
private let BYTES_PER_MB: Double = BYTES_PER_KB * BYTES_PER_KB
private let BYTES_PER_GB: Double = BYTES_PER_MB * BYTES_PER_KB

public enum DisplayUnit: String, CaseIterable, Identifiable {
    case auto = "自动"
    case kb = "KB/s"
    case mb = "MB/s"
    public var id: String { rawValue }
}

public enum DataUnit: String, CaseIterable, Identifiable {
    case auto = "自动"
    case kb = "KB"
    case mb = "MB"
    case gb = "GB"
    public var id: String { rawValue }
}

public func formatBytes(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unitIndex = 0
    while abs(value) >= BYTES_PER_KB && unitIndex < units.count - 1 {
        value /= BYTES_PER_KB
        unitIndex += 1
    }
    if unitIndex <= 1 {
        return String(format: "%.0f %@", value, units[unitIndex])
    }
    return String(format: "%.1f %@", value, units[unitIndex])
}

public func formatBytes(_ bytes: UInt64, unit: DisplayUnit) -> String {
    switch unit {
    case .auto: return formatBytes(bytes)
    case .kb: return String(format: "%.1f KB", Double(bytes) / BYTES_PER_KB)
    case .mb: return String(format: "%.2f MB", Double(bytes) / BYTES_PER_MB)
    }
}

public func formatBytes(_ bytes: UInt64, dataUnit: DataUnit) -> String {
    switch dataUnit {
    case .auto: return formatBytes(bytes)
    case .kb: return String(format: "%.1f KB", Double(bytes) / BYTES_PER_KB)
    case .mb: return String(format: "%.2f MB", Double(bytes) / BYTES_PER_MB)
    case .gb: return String(format: "%.2f GB", Double(bytes) / BYTES_PER_GB)
    }
}

public func formatSpeed(_ bps: Double) -> String {
    if bps < 0 { return "0 KB/s" }
    let kbps = bps / BYTES_PER_KB
    if kbps < BYTES_PER_KB { return String(format: "%.1f KB/s", kbps) }
    return String(format: "%.1f MB/s", kbps / BYTES_PER_KB)
}

public func formatSpeed(_ bps: Double, unit: DisplayUnit) -> String {
    switch unit {
    case .auto: return formatSpeed(bps)
    case .kb: return String(format: "%.1f KB/s", bps / BYTES_PER_KB)
    case .mb: return String(format: "%.2f MB/s", bps / BYTES_PER_MB)
    }
}

public func shortSpeed(_ bps: Double) -> String {
    if bps <= 0 { return "0KB" }
    let kbps = bps / BYTES_PER_KB
    if kbps < BYTES_PER_KB { return String(format: "%.0fKB", kbps) }
    return String(format: "%.1fMB", kbps / BYTES_PER_KB)
}

public func shortSpeed(_ bps: Double, unit: DisplayUnit) -> String {
    if bps <= 0 { return "0KB" }
    switch unit {
    case .auto: return shortSpeed(bps)
    case .kb: return String(format: "%.1fKB", bps / BYTES_PER_KB)
    case .mb: return String(format: "%.2fMB", bps / BYTES_PER_MB)
    }
}

private let dateFormatterLock = NSLock()
private let _sharedDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

public func currentDateStamp() -> String {
    dateFormatterLock.lock()
    defer { dateFormatterLock.unlock() }
    return _sharedDateFormatter.string(from: Date())
}

public func currentDateStamp(from date: Date) -> String {
    dateFormatterLock.lock()
    defer { dateFormatterLock.unlock() }
    return _sharedDateFormatter.string(from: date)
}

public func makeTimeFormatter() -> DateFormatter {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}

private let _safeFilenameDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

public func safeFilenameDate() -> String {
    dateFormatterLock.lock()
    defer { dateFormatterLock.unlock() }
    return _safeFilenameDateFormatter.string(from: Date())
}
