import Foundation
import Darwin

public struct ProcessSnapshot {
    public let pid: Int32
    public let name: String
    public let cpuPercent: Double
    public let rssBytes: UInt64
    public let downloadBytes: Double
    public let uploadBytes: Double

    public init(pid: Int32, name: String, cpuPercent: Double, rssBytes: UInt64, downloadBytes: Double = 0, uploadBytes: Double = 0) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.rssBytes = rssBytes
        self.downloadBytes = downloadBytes
        self.uploadBytes = uploadBytes
    }
}

public class ProcessMonitor: ObservableObject {
    @Published public var topByCPU: [ProcessSnapshot] = []
    @Published public var topByMemory: [ProcessSnapshot] = []
    @Published public var topByCPUTotal: [ProcessSnapshot] = []
    @Published public var topByNetwork: [ProcessSnapshot] = []
    @Published public var selfInfo: ProcessSnapshot?
    private let _isActiveLock = NSLock()
    private var _isActive = false
    public var isActive: Bool {
        get { _isActiveLock.lock(); defer { _isActiveLock.unlock() }; return _isActive }
        set { _isActiveLock.lock(); defer { _isActiveLock.unlock() }; _isActive = newValue }
    }
    public var maxProcesses = 8
    public let processorCount: Int

    private let networkQueue = DispatchQueue(label: "com.opencode.networkmonitor.nettop")
    private let networkLock = NSLock()
    private var prevNetworkBytes: [String: (startTime: time_t, download: UInt64, upload: UInt64)] = [:]
    private var lastNetworkTime = Date()
    private var networkHasBaseline = false

    private let processNetworkReader = ProcessNetworkReader.shared

    private var lastTicks: [Int32: UInt64] = [:]
    private var lastSampleTime = Date()
    private var hasBaseline = false
    private let selfPID = ProcessInfo.processInfo.processIdentifier

    public init() {
        processorCount = ProcessInfo.processInfo.processorCount
        processNetworkReader.start()
    }

    public func start() {
        processNetworkReader.start()
    }

    private let tickQueue = DispatchQueue(label: "com.opencode.networkmonitor.process", qos: .utility)

    // MARK: - Configurable nettop timeout
    private static let nettopTimeout: TimeInterval = 15.0

    public func tick() {
        guard isActive else { return }

        tickQueue.async { [weak self] in
            guard let self else { return }

            let now = Date()
            var snapshots: [ProcessSnapshot] = []
            var currentTicks: [Int32: UInt64] = [:]

            let allPids = self.enumeratePIDs()
            var selfSnapshot: ProcessSnapshot?
            for pid in allPids {
                guard let info = self.taskInfo(pid) else { continue }

                let totalTicks = info.pti_total_user + info.pti_total_system
                currentTicks[pid] = totalTicks

                let rss = info.pti_resident_size

                var cpuPercent: Double = 0
                if self.hasBaseline, let prev = self.lastTicks[pid], totalTicks > prev {
                    let tickDelta = Double(totalTicks - prev) / 1_000_000_000.0
                    let elapsed = now.timeIntervalSince(self.lastSampleTime)
                    cpuPercent = elapsed > 0 ? (tickDelta / elapsed) * 100.0 : 0
                }

                let name = processName(pid)
                let snap = ProcessSnapshot(pid: pid, name: name, cpuPercent: cpuPercent, rssBytes: rss)

                if pid == self.selfPID {
                    selfSnapshot = snap
                } else {
                    snapshots.append(snap)
                }
            }

            self.lastTicks = currentTicks
            self.lastSampleTime = now
            self.hasBaseline = true

            let byCPU = Array(snapshots.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(20))
            let byMemory = Array(snapshots.sorted { $0.rssBytes > $1.rssBytes }.prefix(20))
            let byCPUTotal = Array(snapshots.sorted { ($0.cpuPercent / Double(self.processorCount)) > ($1.cpuPercent / Double(self.processorCount)) }.prefix(20))
            let selfSnap = selfSnapshot

            DispatchQueue.main.async {
                self.topByCPU = byCPU
                self.topByMemory = byMemory
                self.topByCPUTotal = byCPUTotal
                self.selfInfo = selfSnap
            }

            self.tickNetwork()
        }
    }

    private func tickNetwork() {
        networkQueue.async { [weak self] in
            guard let self, self.isActive else { return }
            let now = Date()

            guard let raw = self.readNettop(), !raw.isEmpty else { return }

            var snapshots: [ProcessSnapshot] = []
            for (pid, (dl, ul)) in raw {
                var downloadSpeed: Double = 0
                var uploadSpeed: Double = 0
                let startTime = getProcessStartTime(pid)
                let key = "\(pid)_\(startTime)"

                self.networkLock.lock()
                let hasBaseline = self.networkHasBaseline
                var interval: TimeInterval = 0
                var dlDelta: UInt64 = 0
                var ulDelta: UInt64 = 0

                if hasBaseline, let prev = self.prevNetworkBytes[key] {
                    interval = now.timeIntervalSince(self.lastNetworkTime)
                    if interval > 0 {
                        dlDelta = dl > prev.download ? dl - prev.download : 0
                        ulDelta = ul > prev.upload ? ul - prev.upload : 0
                        downloadSpeed = Double(dlDelta) / interval
                        uploadSpeed = Double(ulDelta) / interval
                    }
                }
                // Always update stored bytes
                self.prevNetworkBytes[key] = (startTime, dl, ul)
                self.networkLock.unlock()

                let name = processName(pid)
                let snap = ProcessSnapshot(pid: pid, name: name, cpuPercent: 0, rssBytes: 0, downloadBytes: downloadSpeed, uploadBytes: uploadSpeed)
                snapshots.append(snap)
            }

            self.networkLock.lock()
            self.lastNetworkTime = now
            self.networkHasBaseline = true
            self.networkLock.unlock()

            let sorted = snapshots.sorted { ($0.downloadBytes + $0.uploadBytes) > ($1.downloadBytes + $1.uploadBytes) }
            let top = Array(sorted.prefix(20))
            DispatchQueue.main.async {
                self.topByNetwork = top
            }
        }
    }

    private func readNettop() -> [Int32: (download: UInt64, upload: UInt64)]? {
        let task = Process()
        task.launchPath = "/usr/bin/nettop"
        task.arguments = ["-P", "-L", "1", "-n"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        let semaphore = DispatchSemaphore(value: 0)
        var timedOut = false
        var outputData: Data?

        do {
            let timeoutWork = DispatchWorkItem {
                timedOut = true
                task.terminate()
                semaphore.signal()
            }
            task.terminationHandler = { _ in semaphore.signal() }
            try task.run()
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.nettopTimeout, execute: timeoutWork)
        } catch {
            LogService.error("nettop_launch_failed", detail: error.localizedDescription)
            return nil
        }

        semaphore.wait()
        if timedOut {
            LogService.error("nettop_timeout", detail: "nettop did not complete within \(Self.nettopTimeout)s")
            return nil
        }

        outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let data = outputData, let output = String(data: data, encoding: .utf8) else { return nil }
        return Self.parseNettopOutput(output)
    }

    public func stop() {
        isActive = false
        lastTicks.removeAll()
        hasBaseline = false
        topByCPU = []
        topByMemory = []
        topByCPUTotal = []
        selfInfo = nil

        processNetworkReader.stop()

        networkQueue.async { [weak self] in
            guard let self else { return }
            self.networkLock.lock()
            self.prevNetworkBytes = [:]
            self.networkHasBaseline = false
            self.networkLock.unlock()
            DispatchQueue.main.async {
                self.topByNetwork = []
            }
        }
    }

    private func enumeratePIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count))
        let size = Int32(count) * Int32(MemoryLayout<Int32>.size)
        let actual = proc_listallpids(&pids, size)
        guard actual > 0 else { return [] }
        return Array(pids.prefix(Int(actual)))
    }

    private func taskInfo(_ pid: Int32) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let ret = proc_pidinfo(pid, Int32(PROC_PIDTASKINFO), 0, &info, size)
        guard ret == size else { return nil }
        return info
    }

    /// Parses nettop CSV output into per-PID download/upload byte counts.
    /// Dynamically parses header row to find command, rx_bytes, tx_bytes columns.
    /// Lines starting with `#` are treated as comments and skipped.
    internal static func parseNettopOutput(_ output: String) -> [Int32: (download: UInt64, upload: UInt64)] {
        var result: [Int32: (download: UInt64, upload: UInt64)] = [:]
        var header: [String] = []
        var headerParsed = false

        output.enumerateLines { line, _ in
            guard !line.hasPrefix("#") else { return }
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            if !headerParsed {
                header = parts.map(String.init)
                headerParsed = true
                return
            }
            guard parts.count >= header.count else { return }

            // macOS Sonoma: "time", "", "interface", "state", "bytes_in", "bytes_out", ...
            // macOS older: "command","rx_bytes","tx_bytes",...
            let cmdIdx: Int
            if let idx = header.firstIndex(of: "command") {
                cmdIdx = idx
            } else {
                cmdIdx = 1 // unnamed column after "time"
            }

            let rxIdx: Int
            if let idx = header.firstIndex(of: "bytes_in") {
                rxIdx = idx
            } else if let idx = header.firstIndex(of: "rx_bytes") {
                rxIdx = idx
            } else {
                rxIdx = 4
            }

            let txIdx: Int
            if let idx = header.firstIndex(of: "bytes_out") {
                txIdx = idx
            } else if let idx = header.firstIndex(of: "tx_bytes") {
                txIdx = idx
            } else {
                txIdx = 5
            }

            guard parts.count > max(cmdIdx, rxIdx, txIdx) else { return }

            let namePid = parts[cmdIdx].split(separator: ".")
            guard let pidStr = namePid.last, let pid = Int32(pidStr),
                  let download = UInt64(parts[rxIdx]),
                  let upload = UInt64(parts[txIdx]) else { return }
            result[pid] = (download, upload)
        }
        return result
    }
}

private let PROC_PIDTASKINFO: Int32 = 4

private func processName(_ pid: Int32) -> String {
    var buf = [CChar](repeating: 0, count: 64)
    let len = proc_name(pid, &buf, UInt32(buf.count))
    if len > 0 {
        return String(cString: buf)
    }
    return "pid_\(pid)"
}

private func getProcessStartTime(_ pid: Int32) -> time_t {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    let ret = proc_pidinfo(pid, Int32(PROC_PIDTBSDINFO), 0, &info, size)
    guard ret == size else { return 0 }
    return time_t(info.pbi_start_tvsec)
}
