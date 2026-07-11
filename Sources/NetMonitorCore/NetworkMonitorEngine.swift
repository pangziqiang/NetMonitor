import Foundation
import Darwin
import Combine
import os

private let netLog = OSLog(subsystem: AppConstants.logSubsystem, category: "network")

// MARK: - Interface filtering constants
private let includedInterfacePrefixes = ["en", "utun"]
private var excludedInterfacePrefixes: [String] {
    AppSettings.shared.excludedInterfacePrefixes
}

struct InterfaceSnapshot {
    let up: UInt64
    let down: UInt64
    let timestamp: Date
}

// MARK: - IOReport Network Monitor (preferred on macOS 10.15+)

private final class IOReportNetMonitor {
    private var monitor: IOReportMonitor?
    private var state = NetMonitorState()
    private let lock = NSLock()
    
    /// Callback fires with (bytesInDelta, bytesOutDelta, interval) on each IOReport sample.
    var onSample: ((UInt64, UInt64, TimeInterval) -> Void)?
    
    func start() {
        guard IOReportMonitor.isAvailable() else { return }
        
        let m = IOReportMonitor(group: .network)
        self.monitor = m
        
        _ = m.start { [weak self] channelName, value in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            
            let isDown = channelName.contains("bytes_in") || channelName.contains("ibytes")
            let isUp = channelName.contains("bytes_out") || channelName.contains("obytes")
            
            guard isDown || isUp else { return }
            
            let now = Date()
            let prev = self.state.lastTimestamp
            let prevIn = self.state.lastBytesIn
            let prevOut = self.state.lastBytesOut
            
            if isDown { self.state.lastBytesIn += UInt64(value) }
            if isUp { self.state.lastBytesOut += UInt64(value) }
            self.state.lastTimestamp = now
            
            if let prev, now.timeIntervalSince(prev) > 0.1 {
                let interval = now.timeIntervalSince(prev)
                let deltaIn = self.state.lastBytesIn > prevIn ? self.state.lastBytesIn - prevIn : 0
                let deltaOut = self.state.lastBytesOut > prevOut ? self.state.lastBytesOut - prevOut : 0
                
                DispatchQueue.main.async {
                    self.onSample?(deltaIn, deltaOut, interval)
                }
            }
        }
    }
    
    func stop() {
        monitor?.stop()
        monitor = nil
        lock.lock()
        state = NetMonitorState()
        lock.unlock()
    }
    
    deinit { stop() }
}

private final class NetMonitorState {
    var lastBytesIn: UInt64 = 0
    var lastBytesOut: UInt64 = 0
    var lastTimestamp: Date? = nil
}

// MARK: - NetMonitorEngine

public class NetMonitorEngine: ObservableObject {
    @Published public var currentDownSpeed: Double = 0
    @Published public var currentUpSpeed: Double = 0
    @Published public var totalSessionDown: UInt64 = 0
    @Published public var totalSessionUp: UInt64 = 0
    @Published public var downHistory: [Double] = []
    @Published public var upHistory: [Double] = []
    @Published public var downHistoryTimes: [Date] = []
    @Published public var upHistoryTimes: [Date] = []
    @Published public var isPaused = false

    public var todayDown: UInt64 {
        get { todayDownUnsafe }
        set { todayDownUnsafe = newValue }
    }
    public var todayUp: UInt64 {
        get { todayUpUnsafe }
        set { todayUpUnsafe = newValue }
    }

    public var historyMax = 120 {
        didSet {
            historyMax = max(30, min(600, historyMax))
            trimHistory()
        }
    }

    private var baseline: InterfaceSnapshot?
    private var lastSnapshot: InterfaceSnapshot?
    private var timer: Timer?
    private let smoothAlpha: Double = 0.35
    private let stateLock = NSLock()
    private var _lastAccumSecond: Int = -1
    private var _lastTodayDate: String = ""
    private var _todayDown: UInt64 = 0
    private var _todayUp: UInt64 = 0
    
    private var ioReportMonitor: IOReportNetMonitor?
    private var useIOReport = false

    private var lastAccumSecond: Int {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _lastAccumSecond }
        set { stateLock.lock(); _lastAccumSecond = newValue; stateLock.unlock() }
    }
    private var lastTodayDate: String {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _lastTodayDate }
        set { stateLock.lock(); _lastTodayDate = newValue; stateLock.unlock() }
    }
    private var todayDownUnsafe: UInt64 {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _todayDown }
        set { stateLock.lock(); _todayDown = newValue; stateLock.unlock() }
    }
    private var todayUpUnsafe: UInt64 {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _todayUp }
        set { stateLock.lock(); _todayUp = newValue; stateLock.unlock() }
    }

    public init() {
        lastTodayDate = Self.todayDateString()
        loadTodayFromDB()
        
        // Prefer IOReport on macOS 10.15+
        if IOReportMonitor.isAvailable() {
            useIOReport = true
        }
    }

    private static func todayDateString() -> String {
        currentDateStamp()
    }

    /// Starts traffic sampling — uses IOReport if available, falls back to getifaddrs polling.
    public func start() {
        if useIOReport {
            startIOReport()
        } else {
            startPolling()
        }
    }

    /// Stops traffic sampling (both IOReport and polling paths).
    public func stop() {
        ioReportMonitor?.stop()
        ioReportMonitor = nil
        timer?.invalidate()
        timer = nil
    }

    deinit { stop() }

    public func pause() { isPaused = true }

    public func resume() {
        if useIOReport {
            // IOReport is callback-based, just resume
            isPaused = false
        } else {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let snapshot = self.readInterfaceBytes()
                DispatchQueue.main.async {
                    self.lastSnapshot = snapshot
                    self.isPaused = false
                }
            }
        }
    }

    // MARK: - IOReport path

    private func startIOReport() {
        let monitor = IOReportNetMonitor()
        self.ioReportMonitor = monitor
        
        // Take baseline
        let snapshot = readInterfaceBytes()
        baseline = snapshot
        lastSnapshot = snapshot
        
        monitor.onSample = { [weak self] deltaIn, deltaOut, interval in
            guard let self, !self.isPaused else { return }
            self.applyIOReportSample(deltaIn: deltaIn, deltaOut: deltaOut, interval: interval)
        }
        
        monitor.start()
        os_log(.info, log: netLog, "Started with IOReport Network monitoring")
    }
    
    private func applyIOReportSample(deltaIn: UInt64, deltaOut: UInt64, interval: TimeInterval) {
        let rawDown = Double(deltaIn) / interval
        let rawUp = Double(deltaOut) / interval
        
        currentDownSpeed = currentDownSpeed * (1 - smoothAlpha) + rawDown * smoothAlpha
        currentUpSpeed = currentUpSpeed * (1 - smoothAlpha) + rawUp * smoothAlpha
        
        // Session totals: accumulate from baseline
        if let base = baseline {
            totalSessionDown = (lastSnapshot?.down ?? base.down) > base.down ? (lastSnapshot?.down ?? base.down) - base.down : 0
            totalSessionUp = (lastSnapshot?.up ?? base.up) > base.up ? (lastSnapshot?.up ?? base.up) - base.up : 0
        }
        
        // Update running snapshot for next sample
        let now = Date()
        let prevDown = lastSnapshot?.down ?? 0
        let prevUp = lastSnapshot?.up ?? 0
        lastSnapshot = InterfaceSnapshot(up: prevUp + deltaOut, down: prevDown + deltaIn, timestamp: now)
        
        downHistory.append(currentDownSpeed)
        upHistory.append(currentUpSpeed)
        downHistoryTimes.append(now)
        upHistoryTimes.append(now)
        if downHistory.count > historyMax {
            downHistory = Array(downHistory.suffix(historyMax))
            downHistoryTimes = Array(downHistoryTimes.suffix(historyMax))
        }
        if upHistory.count > historyMax {
            upHistory = Array(upHistory.suffix(historyMax))
            upHistoryTimes = Array(upHistoryTimes.suffix(historyMax))
        }
        
        // Day change check
        let todayStr = Self.todayDateString()
        if todayStr != lastTodayDate {
            lastTodayDate = todayStr
            loadTodayFromDB()
        }
        
        // Accumulate to DB (once per second)
        let sec = Int(now.timeIntervalSince1970)
        if sec != lastAccumSecond {
            if let db = DatabaseManager.shared {
                db.accumulateTraffic(down: deltaIn, up: deltaOut)
                db.updatePeak(down: currentDownSpeed, up: currentUpSpeed)
            } else {
                os_log(.error, log: netLog, "DatabaseManager.shared is nil, traffic data dropped")
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                }
            }
            todayDownUnsafe += deltaIn
            todayUpUnsafe += deltaOut
            lastAccumSecond = sec
        }
    }

    // MARK: - Fallback polling path (getifaddrs)

    private func startPolling() {
        let snapshot = readInterfaceBytes()
        baseline = snapshot
        lastSnapshot = snapshot
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self, !self.isPaused else { return }
            self.tick()
        }
    }

    private func loadTodayFromDB() {
        if let db = DatabaseManager.shared {
            let t = db.todayTraffic()
            todayDown = t.down
            todayUp = t.up
        }
    }

    private func trimHistory() {
        if downHistory.count > historyMax { downHistory = Array(downHistory.suffix(historyMax)); downHistoryTimes = Array(downHistoryTimes.suffix(historyMax)) }
        if upHistory.count > historyMax { upHistory = Array(upHistory.suffix(historyMax)); upHistoryTimes = Array(upHistoryTimes.suffix(historyMax)) }
    }

    private func tick() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let now = self.readInterfaceBytes()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.applyTick(now: now)
            }
        }
    }

    private func applyTick(now: InterfaceSnapshot) {
        guard let last = lastSnapshot else { lastSnapshot = now; return }

        let interval = now.timestamp.timeIntervalSince(last.timestamp)
        if interval <= 0 { return }

        let downDiff = now.down > last.down ? now.down - last.down : 0
        let upDiff = now.up > last.up ? now.up - last.up : 0

        let rawDown = Double(downDiff) / interval
        let rawUp = Double(upDiff) / interval

        currentDownSpeed = currentDownSpeed * (1 - smoothAlpha) + rawDown * smoothAlpha
        currentUpSpeed = currentUpSpeed * (1 - smoothAlpha) + rawUp * smoothAlpha

        if let base = baseline {
            totalSessionDown = now.down > base.down ? now.down - base.down : 0
            totalSessionUp = now.up > base.up ? now.up - base.up : 0
        }

        downHistory.append(currentDownSpeed)
        upHistory.append(currentUpSpeed)
        let nowDate = Date()
        downHistoryTimes.append(nowDate)
        upHistoryTimes.append(nowDate)
        if downHistory.count > historyMax {
            downHistory = Array(downHistory.suffix(historyMax))
            downHistoryTimes = Array(downHistoryTimes.suffix(historyMax))
        }
        if upHistory.count > historyMax {
            upHistory = Array(upHistory.suffix(historyMax))
            upHistoryTimes = Array(upHistoryTimes.suffix(historyMax))
        }

        lastSnapshot = now

        // Check for day change
        let todayStr = Self.todayDateString()
        if todayStr != lastTodayDate {
            lastTodayDate = todayStr
            loadTodayFromDB()
        }

        let sec = Int(now.timestamp.timeIntervalSince1970)
        if sec != lastAccumSecond {
            if let db = DatabaseManager.shared {
                db.accumulateTraffic(down: downDiff, up: upDiff)
                db.updatePeak(down: currentDownSpeed, up: currentUpSpeed)
            } else {
                os_log(.error, log: netLog, "DatabaseManager.shared is nil, traffic data dropped")
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                }
            }
            todayDownUnsafe += downDiff
            todayUpUnsafe += upDiff
            lastAccumSecond = sec
        }
    }

    private func readInterfaceBytes() -> InterfaceSnapshot {
        var down: UInt64 = 0
        var up: UInt64 = 0
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else {
            os_log(.error, log: netLog, "readInterfaceBytes: getifaddrs failed")
            return InterfaceSnapshot(up: 0, down: 0, timestamp: Date())
        }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            let addr = current.pointee.ifa_addr
            guard let addr else { continue }
            guard addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = current.pointee.ifa_data
            else { continue }
            let name = String(cString: current.pointee.ifa_name)
            guard includedInterfacePrefixes.contains(where: { name.hasPrefix($0) }) else { continue }
            guard !excludedInterfacePrefixes.contains(where: { name.hasPrefix($0) }) else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            down += UInt64(stats.ifi_ibytes)
            up += UInt64(stats.ifi_obytes)
        }
        return InterfaceSnapshot(up: up, down: down, timestamp: Date())
    }
}
