import Foundation
import Darwin

public struct ProcessSnapshot {
    public let pid: Int32
    public let name: String
    public let cpuPercent: Double
    public let rssBytes: UInt64
}

public class ProcessMonitor: ObservableObject {
    @Published public var topByCPU: [ProcessSnapshot] = []
    @Published public var topByMemory: [ProcessSnapshot] = []
    @Published public var selfInfo: ProcessSnapshot?
    public var isActive = false
    public var maxProcesses = 8

    private var lastTicks: [Int32: UInt64] = [:]
    private var lastSampleTime = Date()
    private var hasBaseline = false
    private let selfPID = ProcessInfo.processInfo.processIdentifier

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

        topByCPU = Array(snapshots.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(maxProcesses))
        topByMemory = Array(snapshots.sorted { $0.rssBytes > $1.rssBytes }.prefix(maxProcesses))
        selfInfo = selfSnapshot
    }

    public func stop() {
        isActive = false
        lastTicks.removeAll()
        hasBaseline = false
        topByCPU = []
        topByMemory = []
        selfInfo = nil
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
