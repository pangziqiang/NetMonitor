import Foundation
import SQLite3
import os

private let log = OSLog(subsystem: AppConstants.logSubsystem, category: "db")
private let MINUTELY_RETENTION_DAYS = 30
private let SECONDS_PER_DAY: TimeInterval = 86400
private let FLUSH_INTERVAL_SECONDS: TimeInterval = 15

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
    private var lastHourAggregated: Int = -1
    private var flushTimer: Timer?
    private var flushCount = 0
    private let accumLock = NSLock()

    private var pendingPeakDown: Double = 0
    private var pendingPeakUp: Double = 0
    private var pendingProcesses: String? = nil
    private let peakLock = NSLock()

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
        flushTimer = nil
        closed = true
        
        // Drain pending traffic via queue.sync to ensure all pending queue operations complete first
        // Use a direct synchronous approach to avoid deadlock with the timer
        queue.sync {
            // Flush accumulators
            accumLock.lock()
            let down = minuteAccumDown
            let up = minuteAccumUp
            minuteAccumDown = 0
            minuteAccumUp = 0
            let now = Date()
            accumLock.unlock()

            peakLock.lock()
            let peakD = pendingPeakDown
            let peakU = pendingPeakUp
            let procs = pendingProcesses
            pendingPeakDown = 0
            pendingPeakUp = 0
            pendingProcesses = nil
            peakLock.unlock()

            guard down > 0 || up > 0 else { return }
            
            let ts = iso8601String(from: now)
            _insertMinutely(ts: ts, down: down, up: up, peakDown: peakD, peakUp: peakU, processes: procs)
        }
        
        let dbToClose = db
        db = nil
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
        try exec("""
            CREATE TABLE IF NOT EXISTS traffic_hourly (
                hour TEXT NOT NULL PRIMARY KEY,
                avg_down REAL NOT NULL,
                avg_up REAL NOT NULL,
                peak_down INTEGER NOT NULL,
                peak_up INTEGER NOT NULL,
                total_down INTEGER NOT NULL,
                total_up INTEGER NOT NULL
            )
        """)
        try migrateMinutelyColumns()
        try migrateHourlyPeakTimeColumns()
        try backfillHourlyData()
    }

    private func migrateHourlyPeakTimeColumns() throws {
        guard let db else { return }
        var existing: Set<String> = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(traffic_hourly)", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = sqlite3_column_text(stmt, 1) {
                    existing.insert(String(cString: name))
                }
            }
        }
        sqlite3_finalize(stmt)
        if !existing.contains("peak_down_time") { try exec("ALTER TABLE traffic_hourly ADD COLUMN peak_down_time TEXT DEFAULT NULL") }
        if !existing.contains("peak_up_time") { try exec("ALTER TABLE traffic_hourly ADD COLUMN peak_up_time TEXT DEFAULT NULL") }
    }

    private func backfillHourlyData() throws {
        guard let db else { return }
        var stmt: OpaquePointer?
        let checkSql = "SELECT COUNT(*) FROM traffic_hourly"
        guard sqlite3_prepare_v2(db, checkSql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_int64(stmt, 0) == 0 else { return }
        sqlite3_finalize(stmt)
        stmt = nil

        let sql = """
            INSERT OR IGNORE INTO traffic_hourly (hour, avg_down, avg_up, peak_down, peak_up, total_down, total_up)
            SELECT SUBSTR(timestamp, 1, 13) || ':00:00.000Z' as hour,
                   AVG(bytes_down), AVG(bytes_up),
                   MAX(peak_down), MAX(peak_up),
                   SUM(bytes_down), SUM(bytes_up)
            FROM traffic_minutely
            GROUP BY hour
        """
        try exec(sql)
    }

    private func migrateMinutelyColumns() throws {
        guard let db else { return }
        var existing: Set<String> = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(traffic_minutely)", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = sqlite3_column_text(stmt, 1) {
                    existing.insert(String(cString: name))
                }
            }
        }
        sqlite3_finalize(stmt)
        if !existing.contains("peak_down") { try exec("ALTER TABLE traffic_minutely ADD COLUMN peak_down INTEGER DEFAULT 0") }
        if !existing.contains("peak_up") { try exec("ALTER TABLE traffic_minutely ADD COLUMN peak_up INTEGER DEFAULT 0") }
        if !existing.contains("top_processes") { try exec("ALTER TABLE traffic_minutely ADD COLUMN top_processes TEXT DEFAULT NULL") }
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

    public func updatePeak(down: Double, up: Double) {
        peakLock.lock()
        if down > pendingPeakDown { pendingPeakDown = down }
        if up > pendingPeakUp { pendingPeakUp = up }
        peakLock.unlock()
    }

    public func updateProcesses(_ json: String?) {
        peakLock.lock()
        pendingProcesses = json
        peakLock.unlock()
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

        peakLock.lock()
        let peakD = pendingPeakDown
        let peakU = pendingPeakUp
        let procs = pendingProcesses
        pendingPeakDown = 0
        pendingPeakUp = 0
        pendingProcesses = nil
        peakLock.unlock()

        guard down > 0 || up > 0 else { return }

        let ts = iso8601String(from: now)

        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            self._insertMinutely(ts: ts, down: down, up: up, peakDown: peakD, peakUp: peakU, processes: procs)
            
            // Run retention once per hour (not every 15 min)
            let hour = Calendar.current.component(.hour, from: now)
            if hour != self.lastHourAggregated {
                self.lastHourAggregated = hour
                self._retainMinutely()
                self._retainHourly()
                self.retainEvents()
                self._aggregateHourly(endingAt: now)
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

        peakLock.lock()
        let peakD = pendingPeakDown
        let peakU = pendingPeakUp
        let procs = pendingProcesses
        pendingPeakDown = 0
        pendingPeakUp = 0
        pendingProcesses = nil
        peakLock.unlock()

        guard down > 0 || up > 0 else { return }

        let ts = iso8601String(from: now)

        queue.sync {
            if closed { return }
            self._insertMinutely(ts: ts, down: down, up: up, peakDown: peakD, peakUp: peakU, processes: procs)
        }
    }

    private func _insertMinutely(ts: String, down: UInt64, up: UInt64, peakDown: Double = 0, peakUp: Double = 0, processes: String? = nil) {
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = "INSERT INTO traffic_minutely (timestamp, bytes_down, bytes_up, peak_down, peak_up, top_processes) VALUES (?, ?, ?, ?, ?, ?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            os_log(.error, log: log, "insertMinutely prepare failed: %{private}@", String(cString: sqlite3_errmsg(db)))
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, ts, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, Int64(down))
        sqlite3_bind_int64(stmt, 3, Int64(up))
        sqlite3_bind_int64(stmt, 4, Int64(peakDown))
        sqlite3_bind_int64(stmt, 5, Int64(peakUp))
        if let processes {
            sqlite3_bind_text(stmt, 6, processes, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
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
        let cutoff = iso8601String(from: Date().addingTimeInterval(-SECONDS_PER_DAY * Double(MINUTELY_RETENTION_DAYS)))
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

    private let HOURLY_RETENTION_DAYS = 730

    private func _retainHourly() {
        guard let db else { return }
        let cutoff = iso8601String(from: Date().addingTimeInterval(-SECONDS_PER_DAY * Double(HOURLY_RETENTION_DAYS)))
        var stmt: OpaquePointer?
        let sql = "DELETE FROM traffic_hourly WHERE hour < ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            os_log(.error, log: log, "retainHourly prepare failed: %{private}@", String(cString: sqlite3_errmsg(db)))
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, cutoff, -1, SQLITE_TRANSIENT)
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE {
            os_log(.error, log: log, "retainHourly step failed: %d", rc)
        }
    }

    /// Returns today's total download and upload bytes from the daily summary table.
    public func todayTraffic() -> (down: UInt64, up: UInt64) {
        let dateStr = currentDateStamp()
        return dailyTraffic(for: dateStr)
    }

    public func dailyTraffic(for dateStr: String) -> (down: UInt64, up: UInt64) {
        return queue.sync {
            guard let db else { return (0, 0) }
            var stmt: OpaquePointer?
            let sql = "SELECT bytes_down, bytes_up FROM traffic_daily WHERE date = ?"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                os_log(.error, log: log, "dailyTraffic prepare failed: %{private}@", String(cString: sqlite3_errmsg(db)))
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
            let cutoff = iso8601String(from: Date().addingTimeInterval(-Double(minutes) * 60))
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
                if let date = iso8601Date(from: ts) {
                    result.append((date, down, up))
                }
            }
            return result
        }
    }

    // MARK: - Range Queries

    public func dailyTraffic(from: Date, to: Date) -> [(date: String, down: UInt64, up: UInt64)] {
        let fromStr = String(currentDateStamp(from: from).prefix(10))
        let toStr = String(currentDateStamp(from: to).prefix(10))
        return queue.sync {
            guard let db else { return [] }
            var stmt: OpaquePointer?
            let sql = "SELECT date, bytes_down, bytes_up FROM traffic_daily WHERE date >= ? AND date <= ? ORDER BY date ASC"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, fromStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, toStr, -1, SQLITE_TRANSIENT)
            var result: [(String, UInt64, UInt64)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let textPtr = sqlite3_column_text(stmt, 0) else { continue }
                let date = String(cString: textPtr)
                result.append((date, UInt64(sqlite3_column_int64(stmt, 1)), UInt64(sqlite3_column_int64(stmt, 2))))
            }
            return result
        }
    }

    public func minutelyTraffic(from: Date, to: Date) -> [(time: Date, down: UInt64, up: UInt64, peakDown: UInt64, peakUp: UInt64, processes: String?)] {
        let fromStr = iso8601String(from: from)
        let toStr = iso8601String(from: to)
        return queue.sync {
            guard let db else { return [] }
            var stmt: OpaquePointer?
            let sql = "SELECT timestamp, bytes_down, bytes_up, peak_down, peak_up, top_processes FROM traffic_minutely WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp ASC"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, fromStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, toStr, -1, SQLITE_TRANSIENT)
            var result: [(Date, UInt64, UInt64, UInt64, UInt64, String?)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let textPtr = sqlite3_column_text(stmt, 0) else { continue }
                let ts = String(cString: textPtr)
                if let date = iso8601Date(from: ts) {
                    let procs = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
                    result.append((
                        date,
                        UInt64(sqlite3_column_int64(stmt, 1)),
                        UInt64(sqlite3_column_int64(stmt, 2)),
                        UInt64(sqlite3_column_int64(stmt, 3)),
                        UInt64(sqlite3_column_int64(stmt, 4)),
                        procs
                    ))
                }
            }
            return result
        }
    }

    // MARK: - CSV Export

    private static let csvBOM = "\u{FEFF}"

    public func exportDailyCSV(from: Date, to: Date) -> String {
        let data = dailyTraffic(from: from, to: to)
        var csv = Self.csvBOM
        csv += "日期,下载(字节),上传(字节)\n"
        for row in data {
            csv += "\(row.date),\(row.down),\(row.up)\n"
        }
        return csv
    }

    public func exportMinutelyCSV(from: Date, to: Date) -> String {
        let data = minutelyTraffic(from: from, to: to)
        var csv = Self.csvBOM
        csv += "时间,下载(字节),上传(字节),峰值下行(bytes/s),峰值上行(bytes/s),活跃进程\n"
        for row in data {
            let ts = iso8601String(from: row.time)
            let procs = row.processes?.replacingOccurrences(of: ",", with: ";") ?? ""
            csv += "\(ts),\(row.down),\(row.up),\(row.peakDown),\(row.peakUp),\"\(procs)\"\n"
        }
        return csv
    }

    public func exportDailyJSON(from: Date, to: Date) -> String {
        let data = dailyTraffic(from: from, to: to)
        let arr = data.map { ["date": $0.date, "down": "\($0.down)", "up": "\($0.up)"] }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: jsonData, encoding: .utf8) else { return "[]" }
        return json
    }

    public func exportMinutelyJSON(from: Date, to: Date) -> String {
        let data = minutelyTraffic(from: from, to: to)
        var arr: [[String: Any]] = []
        for row in data {
            var dict: [String: Any] = [
                "time": iso8601String(from: row.time),
                "down": row.down, "up": row.up,
                "peak_down": row.peakDown, "peak_up": row.peakUp
            ]
            if let procs = row.processes, let data = procs.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                dict["processes"] = parsed
            }
            arr.append(dict)
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: jsonData, encoding: .utf8) else { return "[]" }
        return json
    }

    // MARK: - Hourly Aggregation

    private func _aggregateHourly(endingAt date: Date) {
        guard let db else { return }
        let cal = Calendar.current
        guard let hourInterval = cal.dateInterval(of: .hour, for: date) else { return }
        guard let hourStart = cal.date(byAdding: .hour, value: -1, to: hourInterval.start) else { return }
        let hourEnd = hourInterval.start
        let hourStr = iso8601String(from: hourStart)
        let startStr = iso8601String(from: hourStart)
        let endStr = iso8601String(from: hourEnd)

        var stmt: OpaquePointer?
        let sql = "SELECT AVG(bytes_down), AVG(bytes_up), MAX(peak_down), MAX(peak_up), SUM(bytes_down), SUM(bytes_up) FROM traffic_minutely WHERE timestamp >= ? AND timestamp < ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            os_log(.error, log: log, "aggregateHourly prepare failed: %{private}@", String(cString: sqlite3_errmsg(db)))
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, startStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, endStr, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return }

        let avgDown = sqlite3_column_double(stmt, 0)
        let avgUp = sqlite3_column_double(stmt, 1)
        let peakDown = UInt64(sqlite3_column_int64(stmt, 2))
        let peakUp = UInt64(sqlite3_column_int64(stmt, 3))
        let totalDown = UInt64(sqlite3_column_int64(stmt, 4))
        let totalUp = UInt64(sqlite3_column_int64(stmt, 5))
        guard totalDown > 0 || totalUp > 0 else { return }

        let peakDownTime = _findPeakTime(column: "peak_down", start: startStr, end: endStr)
        let peakUpTime = _findPeakTime(column: "peak_up", start: startStr, end: endStr)

        var insertStmt: OpaquePointer?
        let insertSql = "INSERT OR REPLACE INTO traffic_hourly (hour, avg_down, avg_up, peak_down, peak_up, total_down, total_up, peak_down_time, peak_up_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        guard sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil) == SQLITE_OK else {
            os_log(.error, log: log, "aggregateHourly insert prepare failed: %{private}@", String(cString: sqlite3_errmsg(db)))
            return
        }
        defer { sqlite3_finalize(insertStmt) }
        sqlite3_bind_text(insertStmt, 1, hourStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(insertStmt, 2, avgDown)
        sqlite3_bind_double(insertStmt, 3, avgUp)
        sqlite3_bind_int64(insertStmt, 4, Int64(peakDown))
        sqlite3_bind_int64(insertStmt, 5, Int64(peakUp))
        sqlite3_bind_int64(insertStmt, 6, Int64(totalDown))
        sqlite3_bind_int64(insertStmt, 7, Int64(totalUp))
        if let peakDownTime {
            sqlite3_bind_text(insertStmt, 8, peakDownTime, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(insertStmt, 8)
        }
        if let peakUpTime {
            sqlite3_bind_text(insertStmt, 9, peakUpTime, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(insertStmt, 9)
        }
        let rc = sqlite3_step(insertStmt)
        if rc != SQLITE_DONE {
            os_log(.error, log: log, "aggregateHourly insert step failed: %d", rc)
        }
    }

    private func _findPeakTime(column: String, start: String, end: String) -> String? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        let sql = "SELECT timestamp FROM traffic_minutely WHERE timestamp >= ? AND timestamp < ? ORDER BY \(column) DESC LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, start, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, end, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    // MARK: - Hourly Queries

    public struct HourlyRecord {
        public let hour: Date
        public let avgDown: Double
        public let avgUp: Double
        public let peakDown: UInt64
        public let peakUp: UInt64
        public let totalDown: UInt64
        public let totalUp: UInt64
        public let peakDownTime: Date?
        public let peakUpTime: Date?

        public init(hour: Date, avgDown: Double, avgUp: Double, peakDown: UInt64, peakUp: UInt64, totalDown: UInt64, totalUp: UInt64, peakDownTime: Date? = nil, peakUpTime: Date? = nil) {
            self.hour = hour
            self.avgDown = avgDown
            self.avgUp = avgUp
            self.peakDown = peakDown
            self.peakUp = peakUp
            self.totalDown = totalDown
            self.totalUp = totalUp
            self.peakDownTime = peakDownTime
            self.peakUpTime = peakUpTime
        }
    }

    private static func _parseHourlyRecord(stmt: OpaquePointer) -> HourlyRecord? {
        guard let textPtr = sqlite3_column_text(stmt, 0) else { return nil }
        let dateStr = String(cString: textPtr)
        guard let date = iso8601Date(from: dateStr) else { return nil }
        let peakDownTime = sqlite3_column_text(stmt, 7).flatMap { iso8601Date(from: String(cString: $0)) }
        let peakUpTime = sqlite3_column_text(stmt, 8).flatMap { iso8601Date(from: String(cString: $0)) }
        return HourlyRecord(
            hour: date,
            avgDown: sqlite3_column_double(stmt, 1),
            avgUp: sqlite3_column_double(stmt, 2),
            peakDown: UInt64(sqlite3_column_int64(stmt, 3)),
            peakUp: UInt64(sqlite3_column_int64(stmt, 4)),
            totalDown: UInt64(sqlite3_column_int64(stmt, 5)),
            totalUp: UInt64(sqlite3_column_int64(stmt, 6)),
            peakDownTime: peakDownTime,
            peakUpTime: peakUpTime
        )
    }

    public func hourlyTrafficToday() -> [HourlyRecord] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        let startStr = iso8601String(from: startOfDay)
        return queue.sync {
            guard let db else { return [] as [HourlyRecord] }
            var stmt: OpaquePointer?
            let sql = "SELECT hour, avg_down, avg_up, peak_down, peak_up, total_down, total_up, peak_down_time, peak_up_time FROM traffic_hourly WHERE hour >= ? ORDER BY hour ASC"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] as [HourlyRecord] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, startStr, -1, SQLITE_TRANSIENT)
            var result: [HourlyRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let record = Self._parseHourlyRecord(stmt: stmt!) { result.append(record) }
            }
            return result
        }
    }

    public func hourlyTrafficRange(from: Date, to: Date) -> [HourlyRecord] {
        let fromStr = iso8601String(from: from)
        let toStr = iso8601String(from: to)
        return queue.sync {
            guard let db else { return [] as [HourlyRecord] }
            var stmt: OpaquePointer?
            let sql = "SELECT hour, avg_down, avg_up, peak_down, peak_up, total_down, total_up, peak_down_time, peak_up_time FROM traffic_hourly WHERE hour >= ? AND hour <= ? ORDER BY hour ASC"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] as [HourlyRecord] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, fromStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, toStr, -1, SQLITE_TRANSIENT)
            var result: [HourlyRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let record = Self._parseHourlyRecord(stmt: stmt!) { result.append(record) }
            }
            return result
        }
    }

    public func dailyTrafficSummary(days: Int) -> [(date: String, avgDown: Double, avgUp: Double, peakDown: UInt64, peakUp: UInt64, totalDown: UInt64, totalUp: UInt64)] {
        return queue.sync {
            guard let db else { return [] }
            let cal = Calendar.current
            let endDate = cal.startOfDay(for: Date())
            guard let startDate = cal.date(byAdding: .day, value: -days, to: endDate) else { return [] }
            let fromStr = iso8601String(from: startDate)
            var stmt: OpaquePointer?
            let sql = """
                SELECT SUBSTR(hour, 1, 10) as day,
                       AVG(avg_down), AVG(avg_up),
                       MAX(peak_down), MAX(peak_up),
                       SUM(total_down), SUM(total_up)
                FROM traffic_hourly WHERE hour >= ?
                GROUP BY day ORDER BY day ASC
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, fromStr, -1, SQLITE_TRANSIENT)
            var result: [(String, Double, Double, UInt64, UInt64, UInt64, UInt64)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let textPtr = sqlite3_column_text(stmt, 0) else { continue }
                let date = String(cString: textPtr)
                result.append((
                    date,
                    sqlite3_column_double(stmt, 1),
                    sqlite3_column_double(stmt, 2),
                    UInt64(sqlite3_column_int64(stmt, 3)),
                    UInt64(sqlite3_column_int64(stmt, 4)),
                    UInt64(sqlite3_column_int64(stmt, 5)),
                    UInt64(sqlite3_column_int64(stmt, 6))
                ))
            }
            return result
        }
    }

    public func weeklyTrafficSummary(weeks: Int) -> [(week: String, avgDown: Double, avgUp: Double, peakDown: UInt64, peakUp: UInt64, totalDown: UInt64, totalUp: UInt64)] {
        return queue.sync {
            guard let db else { return [] }
            let cal = Calendar.current
            let endDate = cal.startOfDay(for: Date())
            guard let startDate = cal.date(byAdding: .day, value: -weeks * 7, to: endDate) else { return [] }
            let fromStr = iso8601String(from: startDate)
            var stmt: OpaquePointer?
            let sql = """
                SELECT SUBSTR(hour, 1, 10) as day,
                       AVG(avg_down), AVG(avg_up),
                       MAX(peak_down), MAX(peak_up),
                       SUM(total_down), SUM(total_up)
                FROM traffic_hourly WHERE hour >= ?
                GROUP BY day ORDER BY day ASC
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, fromStr, -1, SQLITE_TRANSIENT)
            var dailyRows: [(String, Double, Double, UInt64, UInt64, UInt64, UInt64)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let textPtr = sqlite3_column_text(stmt, 0) else { continue }
                dailyRows.append((
                    String(cString: textPtr),
                    sqlite3_column_double(stmt, 1),
                    sqlite3_column_double(stmt, 2),
                    UInt64(sqlite3_column_int64(stmt, 3)),
                    UInt64(sqlite3_column_int64(stmt, 4)),
                    UInt64(sqlite3_column_int64(stmt, 5)),
                    UInt64(sqlite3_column_int64(stmt, 6))
                ))
            }
            var weeklyResult: [(String, Double, Double, UInt64, UInt64, UInt64, UInt64)] = []
            var weekBucket: [(String, Double, Double, UInt64, UInt64, UInt64, UInt64)] = []
            var lastWeekStr = ""
            for row in dailyRows {
                let dateStr = row.0
                guard let date = iso8601Date(from: dateStr + "T00:00:00.000Z") else { continue }
                let weekStart = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
                let weekStr = String(iso8601String(from: weekStart).prefix(10))
                if weekStr != lastWeekStr && !weekBucket.isEmpty {
                    weeklyResult.append(aggregateWeek(weekStr: lastWeekStr, days: weekBucket))
                    weekBucket = []
                }
                lastWeekStr = weekStr
                weekBucket.append(row)
            }
            if !weekBucket.isEmpty {
                weeklyResult.append(aggregateWeek(weekStr: lastWeekStr, days: weekBucket))
            }
            return weeklyResult
        }
    }

    private func aggregateWeek(weekStr: String, days: [(String, Double, Double, UInt64, UInt64, UInt64, UInt64)]) -> (String, Double, Double, UInt64, UInt64, UInt64, UInt64) {
        let avgDown = days.map(\.1).reduce(0, +) / Double(days.count)
        let avgUp = days.map(\.2).reduce(0, +) / Double(days.count)
        let peakDown = days.map(\.3).max() ?? 0
        let peakUp = days.map(\.4).max() ?? 0
        let totalDown = days.map(\.5).reduce(0, +)
        let totalUp = days.map(\.6).reduce(0, +)
        return (weekStr, avgDown, avgUp, peakDown, peakUp, totalDown, totalUp)
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
        let cutoff = iso8601String(from: Date().addingTimeInterval(-SECONDS_PER_DAY * Double(EVENT_RETENTION_DAYS)))
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
            result["exported_at"] = iso8601String(from: Date())
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

    /// Deletes all rows from minutely, daily, and hourly traffic tables within a single transaction.
    /// Requires explicit confirmation to prevent accidental data loss.
    internal func clearAllTraffic(confirm: Bool = false) {
        guard confirm else {
            os_log(.error, log: log, "clearAllTraffic called without confirm=true")
            return
        }
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
        rc = sqlite3_exec(db, "DELETE FROM traffic_hourly", nil, nil, &errMsg)
        if rc != SQLITE_OK {
            os_log(.error, log: log, "clearTables DELETE hourly failed: %d", rc)
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

// Thread-safe ISO8601 formatter factory
private func makeISO8601Formatter() -> ISO8601DateFormatter {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}

private func iso8601String(from date: Date) -> String {
    return makeISO8601Formatter().string(from: date)
}

private func iso8601Date(from string: String) -> Date? {
    return makeISO8601Formatter().date(from: string)
}
