import Foundation
import os.log

/// Per-process network traffic reader using continuous nettop (high precision mode).
/// Runs nettop continuously, parses output, and flushes per-process data every 60 seconds.
/// CPU cost: ~130% (nettop is a full-speed network sampler).
final class ProcessNetworkReader {
    static let shared = ProcessNetworkReader()

    private var task: Process?
    private let queue = DispatchQueue(label: "com.opencode.networkmonitor.nettop", qos: .utility)
    private var isRunning = false
    private var isStopping = false
    private let lock = NSLock()

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
            guard parts.count >= 2, let pid = Int32(parts[0]) else { continue }
            let name = String(parts[1])
            let down = Double(acc.totalDown)
            let up = Double(acc.totalUp)
            result.append(ProcessSnapshot(pid: pid, name: name, cpuPercent: 0, rssBytes: 0, downloadBytes: down, uploadBytes: up))
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

    func tick() {}

    // MARK: - Continuous reader

    private func runReader() {
        // Clear accumulators from previous burst so each burst starts fresh
        accumLock.lock()
        accumulators.removeAll()
        accumLock.unlock()
        let task = Process()
        task.launchPath = "/usr/bin/nettop"
        // -P: packet/process view, -L 2: 2 samples per burst, -s 1: 1s interval
        task.arguments = ["-P", "-L", "2", "-n"]
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
        os_log("nettop reader started (continuous, high precision)", log: .default, type: .info)

        let reader = pipe.fileHandleForReading
        var buffer = Data()

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
        }

        task.waitUntilExit()
        lock.lock(); isRunning = false; lock.unlock()
    }

    private func scheduleRestart() {
        queue.asyncAfter(deadline: .now() + 10.0) { [weak self] in
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
        if accumulators[key] == nil {
            accumulators[key] = Accumulator(lastFlushMinute: currentMinuteString())
        }
        accumulators[key]!.totalDown += downVal
        accumulators[key]!.totalUp += upVal
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
}
