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
    public var isActive = false
    public var maxProcesses = 8
    public let processorCount: Int

    private let networkQueue = DispatchQueue(label: "com.opencode.network-monitor.nettop")
    private var prevNetworkBytes: [Int32: (download: UInt64, upload: UInt64)] = [:]
    private var lastNetworkTime = Date()
    private var networkHasBaseline = false

    private var lastTicks: [Int32: UInt64] = [:]
    private var lastSampleTime = Date()
    private var hasBaseline = false
    private let selfPID = ProcessInfo.processInfo.processIdentifier

    public init() {
        processorCount = ProcessInfo.processInfo.processorCount
    }

    public func tick() {
        guard isActive else { return }

        let now = Date()
        var snapshots: [ProcessSnapshot] = []
        var currentTicks: [Int32: UInt64] = [:]

        let allPids = enumeratePIDs()
        var selfSnapshot: ProcessSnapshot?
        for pid in allPids {
            guard let info = taskInfo(pid) else { continue }

            let totalTicks = info.pti_total_user + info.pti_total_system
            currentTicks[pid] = totalTicks

            let rss = info.pti_resident_size

            var cpuPercent: Double = 0
            if hasBaseline, let prev = lastTicks[pid], totalTicks > prev {
                let tickDelta = Double(totalTicks - prev) / 1_000_000_000.0
                let elapsed = now.timeIntervalSince(lastSampleTime)
                cpuPercent = elapsed > 0 ? (tickDelta / elapsed) * 100.0 : 0
            }

            let name = processName(pid)
            let snap = ProcessSnapshot(pid: pid, name: name, cpuPercent: cpuPercent, rssBytes: rss)

            if pid == selfPID {
                selfSnapshot = snap
            } else {
                snapshots.append(snap)
            }
        }

        lastTicks = currentTicks
        lastSampleTime = now
        hasBaseline = true

        topByCPU = Array(snapshots.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(20))
        topByMemory = Array(snapshots.sorted { $0.rssBytes > $1.rssBytes }.prefix(20))
        topByCPUTotal = Array(snapshots.sorted { ($0.cpuPercent / Double(processorCount)) > ($1.cpuPercent / Double(processorCount)) }.prefix(20))
        selfInfo = selfSnapshot

        tickNetwork()
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
                if self.networkHasBaseline, let prev = self.prevNetworkBytes[pid] {
                    let interval = now.timeIntervalSince(self.lastNetworkTime)
                    if interval > 0 {
                        let dlDelta = dl > prev.download ? dl - prev.download : 0
                        let ulDelta = ul > prev.upload ? ul - prev.upload : 0
                        downloadSpeed = Double(dlDelta) / interval
                        uploadSpeed = Double(ulDelta) / interval
                    }
                }

                let name = processName(pid)
                let snap = ProcessSnapshot(pid: pid, name: name, cpuPercent: 0, rssBytes: 0, downloadBytes: downloadSpeed, uploadBytes: uploadSpeed)
                snapshots.append(snap)
            }

            self.prevNetworkBytes = raw
            self.lastNetworkTime = now
            self.networkHasBaseline = true

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
        task.arguments = [
            "-P", "-L", "1", "-n",
            "-k", "time,interface,state,rx_dupe,rx_ooo,re-tx,rtt_avg,rcvsize,tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W,arch"
        ]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            LogService.error("nettop_launch_failed", detail: error.localizedDescription)
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        var result: [Int32: (download: UInt64, upload: UInt64)] = [:]
        output.enumerateLines { line, _ in
            guard !line.hasPrefix("#") else { return }
            let parts = line.split(separator: ",")
            guard parts.count >= 3 else { return }
            let namePid = parts[0].split(separator: ".")
            guard let pidStr = namePid.last, let pid = Int32(pidStr),
                  let download = UInt64(parts[1]),
                  let upload = UInt64(parts[2]) else { return }
            result[pid] = (download, upload)
        }
        return result
    }

    public func stop() {
        isActive = false
        lastTicks.removeAll()
        hasBaseline = false
        topByCPU = []
        topByMemory = []
        topByCPUTotal = []
        topByNetwork = []
        selfInfo = nil

        networkQueue.async { [weak self] in
            guard let self else { return }
            self.prevNetworkBytes = [:]
            self.networkHasBaseline = false
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
