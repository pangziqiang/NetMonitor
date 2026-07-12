import Foundation
import Darwin
import os.log

public final class ProcessNetworkReader {
    public static let shared = ProcessNetworkReader()

    private let networkQueue = DispatchQueue(label: "com.opencode.networkmonitor.nettop.reader", qos: .utility)
    private let parseQueue = DispatchQueue(label: "com.opencode.networkmonitor.nettop.parse", qos: .utility)
    private let flushQueue = DispatchQueue(label: "com.opencode.networkmonitor.nettop.flush", qos: .utility)

    private var task: Process?
    private var pipe: Pipe?
    private var isRunning = false
    private var isStopping = false

    private struct ProcessInfo {
        let startTime: time_t
        let name: String
    }
    private var processCache: [Int32: ProcessInfo] = [:]
    private let cacheLock = NSLock()

    private struct Accumulator {
        let startTime: time_t
        var totalDown: UInt64 = 0
        var totalUp: UInt64 = 0
        var lastDown: UInt64 = 0
        var lastUp: UInt64 = 0
        var lastFlushMinute: String = ""

        init(startTime: time_t) {
            self.startTime = startTime
        }
    }
    private var accumulators: [String: Accumulator] = [:]
    private let accumLock = NSLock()

    private init() {}

    public func start() {
        networkQueue.async { [weak self] in
            self?.runReader()
        }
    }

    public func stop() {
        networkQueue.async { [weak self] in
            self?.terminateReader()
        }
    }

    private func runReader() {
        guard !isRunning else { return }
        isRunning = true

        let task = Process()
        task.launchPath = "/usr/bin/nettop"
        task.arguments = ["-P", "-L", "0", "-n"]
        task.standardError = FileHandle.nullDevice

        let pipe = Pipe()
        task.standardOutput = pipe

        self.task = task
        self.pipe = pipe

        task.terminationHandler = { [weak self] _ in
            self?.networkQueue.async {
                self?.isRunning = false
                if let self, !self.isStopping {
                    self.scheduleRestart()
                }
            }
        }

        do {
            try task.run()
            os_log("nettop reader started", log: .default, type: .info)
        } catch {
            os_log("nettop launch failed: %{private}@", log: .default, type: .error, error.localizedDescription)
            isRunning = false
            scheduleRestart()
            return
        }

        readPipe(pipe)
    }

    private func terminateReader() {
        isStopping = true
        task?.terminate()
        pipe?.fileHandleForReading.closeFile()
        task = nil
        pipe = nil
        isRunning = false
        isStopping = false
        accumLock.lock()
        accumulators.removeAll()
        accumLock.unlock()
    }

    private func scheduleRestart() {
        networkQueue.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.runReader()
        }
    }

    private func readPipe(_ pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        let bufferSize = 65536
        var leftover = ""

        while isRunning {
            let data = handle.readData(ofLength: bufferSize)
            if data.isEmpty { break }
            guard let chunk = String(data: data, encoding: .utf8) else { continue }

            let lines = (leftover + chunk).split(separator: "\n", omittingEmptySubsequences: false)
            leftover = lines.last?.hasSuffix("\n") == false ? String(lines.last!) : ""
            let completeLines = leftover.isEmpty ? lines : lines.dropLast()

            for line in completeLines {
                parseQueue.async { [weak self] in
                    self?.parseLine(String(line))
                }
            }
        }
    }

    private func parseLine(_ line: String) {
        guard !line.hasPrefix("#") else { return }
        let parts = line.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 6 else { return }

        let pidName = String(parts[1])
        let pidNameParts = pidName.split(separator: ".")
        guard let pidStr = pidNameParts.last, let pid = Int32(pidStr) else { return }

        guard let down = UInt64(parts[4]), let up = UInt64(parts[5]) else { return }

        let info = getProcessInfo(pid)
        let key = "\(pid)_\(info.startTime)"

        let now = Date()
        let minute = iso8601MinuteString(from: now)

        accumLock.lock()
        var acc = accumulators[key] ?? Accumulator(startTime: info.startTime)
        let deltaDown = down > acc.lastDown ? down - acc.lastDown : 0
        let deltaUp = up > acc.lastUp ? up - acc.lastUp : 0
        acc.totalDown += deltaDown
        acc.totalUp += deltaUp
        acc.lastDown = down
        acc.lastUp = up

        if acc.lastFlushMinute != minute {
            if !acc.lastFlushMinute.isEmpty {
                flushAccumulator(key: key, name: info.name, pid: pid, startTime: info.startTime, minute: acc.lastFlushMinute, down: acc.totalDown, up: acc.totalUp)
            }
            acc.lastFlushMinute = minute
        }
        accumulators[key] = acc
        accumLock.unlock()
    }

    private func flushAccumulator(key: String, name: String, pid: Int32, startTime: time_t, minute: String, down: UInt64, up: UInt64) {
        guard down > 0 || up > 0 else { return }
        flushQueue.async {
            DatabaseManager.shared?.accumulateProcessTraffic(pid: pid, name: name, startTime: startTime, down: down, up: up)
        }
    }

    private func getProcessInfo(_ pid: Int32) -> ProcessInfo {
        cacheLock.lock()
        if let cached = processCache[pid] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let startTime = getProcessStartTime(pid)
        let name = getProcessName(pid)

        let info = ProcessInfo(startTime: startTime, name: name)

        cacheLock.lock()
        processCache[pid] = info
        cacheLock.unlock()

        return info
    }

    private func getProcessStartTime(_ pid: Int32) -> time_t {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        return ret == size ? time_t(info.pbi_start_tvsec) : 0
    }

    private func getProcessName(_ pid: Int32) -> String {
        var buf = [CChar](repeating: 0, count: 64)
        let len = proc_name(pid, &buf, UInt32(buf.count))
        if len > 0 {
            return String(cString: buf)
        }
        return "pid_\(pid)"
    }

    private func iso8601MinuteString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let str = formatter.string(from: date)
        return String(str.prefix(16)) + ":00.000Z"
    }
}

private struct ProcessInfo {
    let startTime: time_t
    let name: String
}

private struct Accumulator {
    let startTime: time_t
    var totalDown: UInt64 = 0
    var totalUp: UInt64 = 0
    var lastDown: UInt64 = 0
    var lastUp: UInt64 = 0
    var lastFlushMinute: String = ""

    init(startTime: time_t) {
        self.startTime = startTime
    }
}

private let PROC_PIDTBSDINFO: Int32 = 6