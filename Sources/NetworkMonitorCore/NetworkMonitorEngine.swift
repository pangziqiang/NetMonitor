import Foundation
import Darwin
import Combine
import os

private let netLog = OSLog(subsystem: AppConstants.logSubsystem, category: "network")

// MARK: - Interface filtering constants
// Physical Ethernet interfaces are typically en0-en4.
// en5-en9 are often virtual interfaces (Thunderbolt bridge, VPN, etc.)
// that would cause double-counting. Adjust if your device differs.
//
// To customize for your device:
// 1. Run `ifconfig` to see all network interfaces
// 2. Identify which interfaces are physical (en0-en4) vs virtual (en5+)
// 3. Update excludedInterfacePrefixes accordingly
private let excludedInterfacePrefixes = ["en5", "en6", "en7", "en8", "en9"]
private let includedInterfacePrefixes = ["en", "utun"]

struct InterfaceSnapshot {
    let up: UInt64
    let down: UInt64
    let timestamp: Date
}

public class NetworkMonitorEngine: ObservableObject {
    @Published public var currentDownSpeed: Double = 0
    @Published public var currentUpSpeed: Double = 0
    @Published public var totalSessionDown: UInt64 = 0
    @Published public var totalSessionUp: UInt64 = 0
    @Published public var downHistory: [Double] = []
    @Published public var upHistory: [Double] = []
    @Published public var downHistoryTimes: [Date] = []
    @Published public var upHistoryTimes: [Date] = []
    @Published public var isPaused = false
    @Published public var todayDown: UInt64 = 0
    @Published public var todayUp: UInt64 = 0

    public var historyMax = 120 {
        didSet {
            historyMax = max(30, min(600, historyMax))
            trimHistory()
        }
    }

    private var lastSnapshot: InterfaceSnapshot?
    private var baseline: InterfaceSnapshot?
    private var timer: Timer?
    private let smoothAlpha: Double = 0.35
    private var lastAccumSecond: Int = -1
    private var lastTodayDate: String = ""

    public init() {
        lastTodayDate = Self.todayDateString()
        loadTodayFromDB()
    }

    private static func todayDateString() -> String {
        currentDateStamp()
    }

    /// Starts the 3-second sampling timer that reads interface bytes and updates speeds/history.
    public func start() {
        let snapshot = readInterfaceBytes()
        baseline = snapshot
        lastSnapshot = snapshot
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self, !self.isPaused else { return }
            self.tick()
        }
    }

    /// Stops the sampling timer and releases timer resources.
    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { stop() }

    /// Pauses traffic sampling; tick() will be skipped while paused.
    public func pause() { isPaused = true }

    /// Resumes traffic sampling after a pause, re-reading the interface baseline asynchronously.
    public func resume() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let snapshot = self.readInterfaceBytes()
            DispatchQueue.main.async {
                self.lastSnapshot = snapshot
                self.isPaused = false
            }
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
            } else {
                os_log(.error, log: netLog, "DatabaseManager.shared is nil, traffic data dropped")
            }
            todayDown += downDiff
            todayUp += upDiff
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
