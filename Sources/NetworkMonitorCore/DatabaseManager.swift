import Foundation
import SQLite3
import os

private let log = OSLog(subsystem: AppConstants.logSubsystem, category: "db")
private let MINUTELY_RETENTION_DAYS = 7
private let SECONDS_PER_DAY: TimeInterval = 86400
private let FLUSH_INTERVAL_SECONDS: TimeInterval = 60

/// Reusable SQLITE_TRANSIENT sentinel — tells SQLite to copy bound strings.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum DatabaseError: Error, LocalizedError {
    case cannotOpen
    case execFailed(String)
    public var errorDescription: String? {
        switch self {
        case .cannotOpen: return "无法打开数据库"
        case .execFailed(let msg): return "SQL 错误: \(msg)"
        }
    }
}

public class DatabaseManager {
    public static let shared: DatabaseManager? = {
        do {
            return try DatabaseManager()
        } catch {
            os_log(.error, log: log, "DatabaseManager init failed: %{private}@", error.localizedDescription)
            return nil
        }
    }()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "\(AppConstants.bundleID).db", qos: .utility)
    private let closedLock = NSLock()
    private var _closed = false
    private var closed: Bool {
        get { closedLock.lock(); defer { closedLock.unlock() }; return _closed }
        set { closedLock.lock(); defer { closedLock.unlock() }; _closed = newValue }
    }

    private var minuteAccumDown: UInt64 = 0
    private var minuteAccumUp: UInt64 = 0
    private var lastMinuteFlush = Date()
    private var flushTimer: Timer?
    private var flushCount = 0
    private let accumLock = NSLock()

    private init() throws {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw DatabaseError.cannotOpen
        }
        let appDir = dir.appendingPathComponent("NetMonitor")
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let path = appDir.appendingPathComponent("traffic.db").path
        os_log("DB path: %{private}@", log: log, path)
        try open(path: path)
        do {
            try createTables()
        } catch {
            sqlite3_close(db)
            db = nil
            throw error
        }
        startFlushTimer()
    }

    /// Internal initializer for testing — supports in-memory SQLite via path ":memory:".
    internal init(path: String) throws {
        try open(path: path)
        do {
            try createTables()
        } catch {
            sqlite3_close(db)
            db = nil
            throw error
        }
    }

    deinit {
        flushTimer?.invalidate()
        flushPendingTrafficSync()
        closed = true
        let dbToClose = db
        queue.async {
            if let db = dbToClose { sqlite3_close(db) }
        }
    }

    private func open(path: String) throws {
        let rc = sqlite3_open(path, &db)
        if rc != SQLITE_OK { throw DatabaseError.cannotOpen }
    }

    private func createTables() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS traffic_minutely (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                bytes_down INTEGER NOT NULL,
                bytes_up INTEGER NOT NULL
            )
        """)
        try exec("""
            CREATE TABLE IF NOT EXISTS traffic_daily (
                date TEXT NOT NULL,
                bytes_down INTEGER NOT NULL,
                bytes_up INTEGER NOT NULL,
                PRIMARY KEY (date)
            )
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_minutely_ts ON traffic_minutely(timestamp)")
        try exec("""
            CREATE TABLE IF NOT EXISTS app_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                category TEXT NOT NULL,
                event TEXT NOT NULL,
                detail TEXT
            )
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_events_ts ON app_events(timestamp)")
    }

    private func exec(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw DatabaseError.execFailed(msg)
        }
    }

    private func startFlushTimer() {
        lastMinuteFlush = Date()
        let timer = Timer(timeInterval: FLUSH_INTERVAL_SECONDS, repeats: true) { [weak self] _ in
            self?.flushMinute()
        }
        flushTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Accumulates traffic bytes for the current session, updating daily and minutely buffers.
    public func accumulateTraffic(down: UInt64, up: UInt64) {
        accumLock.lock()
        minuteAccumDown += down
        minuteAccumUp += up
        accumLock.unlock()

        let dateStr = currentDateStamp()
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            self._updateDaily(date: dateStr, down: down, up: up)
        }
    }

    private func flushMinute() {
        accumLock.lock()
        let down = minuteAccumDown
        let up = minuteAccumUp
        minuteAccumDown = 0
        minuteAccumUp = 0
        let now = lastMinuteFlush
        lastMinuteFlush = Date()
        accumLock.unlock()
        guard down > 0 || up > 0 else { return }

        let ts = ISO8601Formatter.string(from: now)

        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            self._insertMinutely(ts: ts, down: down, up: up)
            self.flushCount += 1
            if self.flushCount % 60 == 0 {
                self._retainMinutely()
                self.retainEvents()
            }
        }
    }

    /// Flushes pending minutely traffic data synchronously. Called on deinit to avoid data loss.
    public func flushPendingTrafficSync() {
        accumLock.lock()
        let down = minuteAccumDown
        let up = minuteAccumUp
        minuteAccumDown = 0
        minuteAccumUp = 0
        let now = Date()
        accumLock.unlock()
        guard down > 0 || up > 0 else { return }

        let ts = ISO8601Formatter.string(from: now)

        queue.sync {
            if closed { return }
            self._insertMinutely(ts: ts, down: down, up: up)
        }
    }

    private func _insertMinutely(ts: String, down: UInt64, up: UInt64) {
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = "INSERT INTO traffic_minutely (timestamp, bytes_down, bytes_up) VALUES (?, ?, ?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            os_log(.error, log: log, "insertMinutely prepare failed: %{private}@", String(cString: sqlite3_errmsg(db)))
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, ts, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, Int64(down))
        sqlite3_bind_int64(stmt, 3, Int64(up))
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE {
            os_log(.error, log: log, "insertMinutely step failed: %d", rc)
        }
    }

    private func _updateDaily(date: String, down: UInt64, up: UInt64) {
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = """
            INSERT INTO traffic_daily (date, bytes_down, bytes_up) VALUES (?, ?, ?)
            ON CONFLICT(date) DO UPDATE SET
                bytes_down = bytes_down + ?,
                bytes_up = bytes_up + ?
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            os_log(.error, log: log, "updateDaily prepare failed: %{private}@", String(cString: sqlite3_errmsg(db)))
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, date, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, Int64(down))
        sqlite3_bind_int64(stmt, 3, Int64(up))
        sqlite3_bind_int64(stmt, 4, Int64(down))
        sqlite3_bind_int64(stmt, 5, Int64(up))
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE {
            os_log(.error, log: log, "updateDaily step failed: %d", rc)
        }
    }

    private func _retainMinutely() {
        guard let db else { return }
        let cutoff = ISO8601Formatter.string(from: Date().addingTimeInterval(-SECONDS_PER_DAY * Double(MINUTELY_RETENTION_DAYS)))
        var stmt: OpaquePointer?
        let sql = "DELETE FROM traffic_minutely WHERE timestamp < ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            os_log(.error, log: log, "retainMinutely prepare failed: %{private}@", String(cString: sqlite3_errmsg(db)))
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, cutoff, -1, SQLITE_TRANSIENT)
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE {
            os_log(.error, log: log, "retainMinutely step failed: %d", rc)
        }
    }

    /// Returns today's total download and upload bytes from the daily summary table.
    public func todayTraffic() -> (down: UInt64, up: UInt64) {
        let dateStr = currentDateStamp()
        return queue.sync {
            guard let db else { return (0, 0) }
            var stmt: OpaquePointer?
            let sql = "SELECT bytes_down, bytes_up FROM traffic_daily WHERE date = ?"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                os_log(.error, log: log, "todayTraffic prepare failed: %{private}@", String(cString: sqlite3_errmsg(db)))
                return (0, 0)
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, dateStr, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return (0, 0) }
            return (
                UInt64(sqlite3_column_int64(stmt, 0)),
                UInt64(sqlite3_column_int64(stmt, 1))
            )
        }
    }

    /// Returns daily traffic summaries for the past `days` days, ordered oldest to newest.
    /// Filters out invalid rows: empty date, wrong format, or zero traffic.
    public func dailyTraffic(days: Int = 7) -> [(date: String, down: UInt64, up: UInt64)] {
        return queue.sync {
            guard let db else { return [] }
            var stmt: OpaquePointer?
            let sql = "SELECT date, bytes_down, bytes_up FROM traffic_daily ORDER BY date DESC LIMIT ?"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                os_log(.error, log: log, "dailyTraffic prepare failed: %{private}@", String(cString: sqlite3_errmsg(db)))
                return []
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(days))
            var result: [(String, UInt64, UInt64)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let textPtr = sqlite3_column_text(stmt, 0) else { continue }
                let date = String(cString: textPtr)
                let down = UInt64(sqlite3_column_int64(stmt, 1))
                let up = UInt64(sqlite3_column_int64(stmt, 2))
                // Filter out invalid rows: empty date, wrong format, or no digits
                guard !date.isEmpty,
                      date.count == 10,
                      date[date.index(date.startIndex, offsetBy: 4)] == "-",
                      date[date.index(date.startIndex, offsetBy: 7)] == "-"
                else { continue }
                result.append((date, down, up))
            }
            return result.reversed()
        }
    }

    /// Returns minutely traffic records for the past `minutes` minutes, ordered by time ascending.
    public func minutelyTraffic(minutes: Int = 60) -> [(time: Date, down: UInt64, up: UInt64)] {
        return queue.sync {
            guard let db else { return [] }
            var stmt: OpaquePointer?
            let sql = "SELECT timestamp, bytes_down, bytes_up FROM traffic_minutely WHERE timestamp >= ? ORDER BY timestamp ASC"
            let cutoff = ISO8601Formatter.string(from: Date().addingTimeInterval(-Double(minutes) * 60))
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                os_log(.error, log: log, "minutelyTraffic prepare failed: %{private}@", String(cString: sqlite3_errmsg(db)))
                return []
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, cutoff, -1, SQLITE_TRANSIENT)
            var result: [(Date, UInt64, UInt64)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let textPtr = sqlite3_column_text(stmt, 0) else { continue }
                let ts = String(cString: textPtr)
                let down = UInt64(sqlite3_column_int64(stmt, 1))
                let up = UInt64(sqlite3_column_int64(stmt, 2))
                if let date = ISO8601Formatter.date(from: ts) {
                    result.append((date, down, up))
                }
            }
            return result
        }
    }

    // MARK: - Event Logging

    private let EVENT_RETENTION_DAYS = 90

    public func insertEvent(timestamp: String, category: String, event: String, detail: String?) {
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            self._insertEvent(ts: timestamp, category: category, event: event, detail: detail)
        }
    }

    private func _insertEvent(ts: String, category: String, event: String, detail: String?) {
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = "INSERT INTO app_events (timestamp, category, event, detail) VALUES (?, ?, ?, ?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            os_log(.error, log: log, "insertEvent prepare failed: %{private}@", String(cString: sqlite3_errmsg(db)))
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, ts, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, category, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, event, -1, SQLITE_TRANSIENT)
        if let detail {
            sqlite3_bind_text(stmt, 4, detail, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE {
            os_log(.error, log: log, "insertEvent step failed: %d", rc)
        }
    }

    private func retainEvents() {
        guard let db else { return }
        let cutoff = ISO8601Formatter.string(from: Date().addingTimeInterval(-SECONDS_PER_DAY * Double(EVENT_RETENTION_DAYS)))
        var stmt: OpaquePointer?
        let sql = "DELETE FROM app_events WHERE timestamp < ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            os_log(.error, log: log, "retainEvents prepare failed: %{private}@", String(cString: sqlite3_errmsg(db)))
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, cutoff, -1, SQLITE_TRANSIENT)
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE {
            os_log(.error, log: log, "retainEvents step failed: %d", rc)
        }
    }

    public func exportDiagnostics() -> String {
        return queue.sync {
            guard let db else { return "{}" }

            var result: [String: Any] = [:]
            result["exported_at"] = ISO8601Formatter.string(from: Date())
            result["app_version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "unknown"
            result["os_version"] = ProcessInfo.processInfo.operatingSystemVersionString
            result["processor_count"] = ProcessInfo.processInfo.processorCount

            // Recent events
            var events: [[String: String]] = []
            var stmt: OpaquePointer?
            let evSql = "SELECT timestamp, category, event, detail FROM app_events ORDER BY id DESC LIMIT 500"
            if sqlite3_prepare_v2(db, evSql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    var row: [String: String] = [:]
                    row["ts"] = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                    row["cat"] = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                    row["evt"] = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                    row["detail"] = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
                    events.append(row)
                }
            }
            sqlite3_finalize(stmt)
            result["events"] = events

            // Today traffic (inline query to avoid queue.sync deadlock)
            let dateStr = currentDateStamp()
            var todayDown: UInt64 = 0
            var todayUp: UInt64 = 0
            stmt = nil
            let tSql = "SELECT bytes_down, bytes_up FROM traffic_daily WHERE date = ?"
            if sqlite3_prepare_v2(db, tSql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, dateStr, -1, SQLITE_TRANSIENT)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    todayDown = UInt64(sqlite3_column_int64(stmt, 0))
                    todayUp = UInt64(sqlite3_column_int64(stmt, 1))
                }
            }
            sqlite3_finalize(stmt)
            result["today_traffic"] = ["down": todayDown, "up": todayUp]

            // Recent daily traffic
            var daily: [[String: Any]] = []
            let dSql = "SELECT date, bytes_down, bytes_up FROM traffic_daily ORDER BY date DESC LIMIT 7"
            stmt = nil
            if sqlite3_prepare_v2(db, dSql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let date = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                    daily.append([
                        "date": date,
                        "down": sqlite3_column_int64(stmt, 1),
                        "up": sqlite3_column_int64(stmt, 2)
                    ])
                }
            }
            sqlite3_finalize(stmt)
            result["daily_traffic"] = daily

            guard let jsonData = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
                  let json = String(data: jsonData, encoding: .utf8) else {
                return "{}"
            }
            return json
        }
    }

    /// Deletes all rows from both minutely and daily traffic tables within a single transaction.
    public func clearAllTraffic() {
        queue.sync { [weak self] in
            guard let self, !self.closed else { return }
            self._clearTables()
        }
    }

    private func _clearTables() {
        guard let db else { return }
        var errMsg: UnsafeMutablePointer<CChar>?
        var rc = sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, &errMsg)
        if rc != SQLITE_OK {
            os_log(.error, log: log, "clearTables BEGIN failed: %d", rc)
            sqlite3_free(errMsg)
            return
        }
        var hasError = false
        rc = sqlite3_exec(db, "DELETE FROM traffic_minutely", nil, nil, &errMsg)
        if rc != SQLITE_OK {
            os_log(.error, log: log, "clearTables DELETE minutely failed: %d", rc)
            sqlite3_free(errMsg)
            hasError = true
        }
        rc = sqlite3_exec(db, "DELETE FROM traffic_daily", nil, nil, &errMsg)
        if rc != SQLITE_OK {
            os_log(.error, log: log, "clearTables DELETE daily failed: %d", rc)
            sqlite3_free(errMsg)
            hasError = true
        }
        if hasError {
            rc = sqlite3_exec(db, "ROLLBACK", nil, nil, &errMsg)
            if rc != SQLITE_OK {
                os_log(.error, log: log, "clearTables ROLLBACK failed: %d", rc)
                sqlite3_free(errMsg)
            }
        } else {
            rc = sqlite3_exec(db, "COMMIT", nil, nil, &errMsg)
            if rc != SQLITE_OK {
                os_log(.error, log: log, "clearTables COMMIT failed: %d", rc)
                sqlite3_free(errMsg)
            }
        }
    }
}

private let ISO8601Formatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
