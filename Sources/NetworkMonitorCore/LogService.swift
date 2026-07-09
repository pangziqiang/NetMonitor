import Foundation
import os

public enum LogCategory: String {
    case lifecycle
    case userAction
    case error
}

private func iso8601String(from date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: date)
}

public enum LogService {
    private static let log = OSLog(subsystem: AppConstants.logSubsystem, category: "app")

    public static func log(_ category: LogCategory, event: String, detail: String? = nil) {
        let ts = iso8601String(from: Date())
        os_log(.default, log: log, "[%{public}@] %{public}@ %{private}@", category.rawValue, event, detail ?? "")
        DatabaseManager.shared?.insertEvent(timestamp: ts, category: category.rawValue, event: event, detail: detail)
    }

    public static func error(_ event: String, detail: String? = nil) {
        let ts = iso8601String(from: Date())
        os_log(.error, log: log, "[error] %{public}@ %{private}@", event, detail ?? "")
        DatabaseManager.shared?.insertEvent(timestamp: ts, category: LogCategory.error.rawValue, event: event, detail: detail)
    }
}
