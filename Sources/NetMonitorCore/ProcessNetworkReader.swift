import Foundation
import os.log

/// Per-process network traffic reader using a continuous nettop in logging mode.
///
/// nettop stays alive with `-L 0` and samples incrementally every `-s` seconds,
/// which is far cheaper than the previous `-L 2` burst+restart loop: each fresh
/// launch re-enumerates every socket (~1.2s of CPU), while incremental samples
/// cost only ~0.05-0.1s each. Measured on Intel (12 cores): ~0.7% of one core.
final class ProcessNetworkReader {
    static let shared = ProcessNetworkReader()

    private var task: Process?
    private let queue = DispatchQueue(label: "com.opencode.networkmonitor.nettop", qos: .utility)
    private var isRunning = false
    private var isStopping = false
    private let lock = NSLock()
    private var retryCount = 0
    private let maxRetries = 5

    private let minuteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HH"
        f.timeZone = TimeZone.current
        return f
    }()

    private struct Accumulator {
        var totalDown: UInt64 = 0
        var totalUp: UInt64 = 0
        var lastFlushMinute: String = ""
        var flushedDown: UInt64 = 0
        var flushedUp: UInt64 = 0
    }
    private var accumulators: [String: Accumulator] = [:]
    // For ProcessMonitor to consume instead of running its own nettop
    public func topProcesses() -> [ProcessSnapshot] {
        accumLock.lock()
        defer { accumLock.unlock() }
        var result: [ProcessSnapshot] = []
        for (key, acc) in accumulators {
            guard acc.totalDown > 0 || acc.totalUp > 0 else { continue }
            // Key format: pid|name|startTime
            let parts = key.split(separator: "|", maxSplits: 2)
            guard parts.count >= 3, let pid = Int32(parts[0]), let startTime = time_t(parts[2]) else { continue }
            let name = String(parts[1])
            let down = Double(acc.totalDown)
            let up = Double(acc.totalUp)
            result.append(ProcessSnapshot(pid: pid, name: name, cpuPercent: 0, rssBytes: 0, downloadBytes: down, uploadBytes: up, startTime: startTime))
        }
        return result.sorted { ($0.downloadBytes + $0.uploadBytes) > ($1.downloadBytes + $1.uploadBytes) }
    }
    private let accumLock = NSLock()

    private init() {}

    func start() {
        lock.lock()
        guard !isRunning else { lock.unlock(); return }
        isRunning = true
        isStopping = false
        lock.unlock()
        queue.async { [weak self] in self?.runReader() }
    }

    func stop() {
        lock.lock()
        isStopping = true
        lock.unlock()
        task?.terminate()
    }

    // MARK: - Continuous reader

    private func runReader() {
        // Clear accumulators from previous burst so each burst starts fresh
        accumLock.lock()
        accumulators.removeAll()
        accumLock.unlock()
        let task = Process()
        task.launchPath = "/usr/bin/nettop"
        // -P: per-process view; -L 0: logging mode, 0 = infinite samples (never exits);
        // -s 2: sample every 2 seconds (keeps nettop state, cheap incremental updates)
        task.arguments = ["-P", "-L", "0", "-n", "-s", "2"]
        // Give nettop a readable stdin (not /dev/null): with /dev/null stdin it
        // ignores -s and samples at full speed (~120% of one core).
        task.standardInput = Pipe()
        task.standardError = FileHandle.nullDevice

        let pipe = Pipe()
        task.standardOutput = pipe

        task.terminationHandler = { [weak self] _ in
            self?.queue.async {
                self?.isRunning = false
                if let self, !self.isStopping {
                    self.scheduleRestart()
                }
            }
        }

        do { try task.run() } catch {
            os_log("nettop launch failed: %{private}@", log: .default, type: .error, error.localizedDescription)
            lock.lock(); isRunning = false; lock.unlock()
            scheduleRestart()
            return
        }

        self.task = task
        retryCount = 0  // successful launch resets retry count
        os_log("nettop reader started (continuous, -s 2)", log: .default, type: .info)

        let reader = pipe.fileHandleForReading
        var buffer = Data()
        var lastFlushDate = Date()

        while !isStopping {
            let available = reader.availableData
            if available.isEmpty { break }
            buffer.append(available)

            while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                autoreleasepool {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)
                if let line = String(data: lineData, encoding: .utf8) {
                    parseLine(line)
                }
                }
            }
            if Date().timeIntervalSince(lastFlushDate) >= 60 {
                flushAccumulatorsToDB()
                lastFlushDate = Date()
            }
        }

        task.waitUntilExit()
        lock.lock(); isRunning = false; lock.unlock()
    }

    private func scheduleRestart() {
        retryCount += 1
        guard retryCount <= maxRetries else {
            os_log("nettop: max retries (%d) reached, stopping", log: .default, type: .error, maxRetries)
            return
        }
        let delay: Double
        switch retryCount {
        case 1: delay = 10.0
        case 2: delay = 20.0
        case 3: delay = 40.0
        case 4: delay = 80.0
        default: delay = 160.0
        }
        os_log("nettop restart #%d in %.0fs", log: .default, type: .info, retryCount, delay)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isStopping else { return }
            self.lock.lock()
            let shouldRestart = !self.isRunning
            self.lock.unlock()
            if shouldRestart { self.runReader() }
        }
    }

    // MARK: - Parse nettop CSV line

    private func parseLine(_ line: String) {
        // Skip header line
        guard !line.hasPrefix("time,") && !line.hasPrefix("seconds,") else { return }
        let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        // nettop -P format: time, name.pid, interface, state, bytes_in, bytes_out, ...
        guard cols.count >= 6 else { return }

        // Parse "name.pid" from col2
        let namePid = cols[1].trimmingCharacters(in: .whitespaces)
        guard let dotIndex = namePid.lastIndex(of: ".") else { return }
        let name = String(namePid[namePid.startIndex..<dotIndex])
        guard let pid = Int32(namePid[namePid.index(after: dotIndex)...]) else { return }

        let downVal = UInt64(cols[4].trimmingCharacters(in: .whitespaces)) ?? 0
        let upVal = UInt64(cols[5].trimmingCharacters(in: .whitespaces)) ?? 0

        guard downVal > 0 || upVal > 0 else { return }

        let startTime = getProcessStartTime(pid: pid)
        let key = "\(pid)|\(name)|\(startTime)"

        accumLock.lock()
        var acc = accumulators[key] ?? Accumulator(lastFlushMinute: currentMinuteString())
        acc.totalDown += downVal
        acc.totalUp += upVal
        accumulators[key] = acc
        accumLock.unlock()
    }

    // MARK: - Helpers

    private func currentMinuteString() -> String {
        minuteFormatter.string(from: Date())
    }

    private func getProcessStartTime(pid: Int32) -> time_t {
        var info = kinfo_proc()
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, 4, &info, &size, nil, 0)
        guard result == 0 else { return 0 }
        return time_t(info.kp_proc.p_starttime.tv_sec)
    }

    /// 把累计的进程流量按分钟差值写入 process_traffic（历史明细数据源）。
    private func flushAccumulatorsToDB() {
        typealias Entry = (pid: Int32, name: String, startTime: time_t, down: UInt64, up: UInt64)
        var entries: [Entry] = []
        accumLock.lock()
        for (key, acc) in accumulators {
            let down = acc.totalDown > acc.flushedDown ? acc.totalDown - acc.flushedDown : 0
            let up = acc.totalUp > acc.flushedUp ? acc.totalUp - acc.flushedUp : 0
            guard down > 0 || up > 0 else { continue }
            let parts = key.split(separator: "|", maxSplits: 2)
            guard parts.count >= 3, let pid = Int32(parts[0]), let startTime = time_t(parts[2]) else { continue }
            entries.append((pid, String(parts[1]), startTime, down, up))
            accumulators[key]?.flushedDown = acc.totalDown
            accumulators[key]?.flushedUp = acc.totalUp
        }
        accumLock.unlock()

        for e in entries {
            DatabaseManager.shared?.accumulateProcessTraffic(pid: e.pid, name: e.name, startTime: e.startTime, down: e.down, up: e.up)
        }
    }
}
