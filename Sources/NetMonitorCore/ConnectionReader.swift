import Foundation
import Combine

/// 一条实时网络连接（进程归属 + 协议 + 本地/远端地址 + 状态）。
public struct NetworkConnection: Identifiable {
    public let id: String
    public let pid: Int32
    public let process: String
    public let protocolName: String
    public let local: String
    public let remote: String
    public let state: String
}

/// 通过 `lsof -nP -i` 每 5 秒刷新一次连接表。
@MainActor
public final class ConnectionReader: ObservableObject {
    @Published public private(set) var connections: [NetworkConnection] = []
    @Published public private(set) var lastUpdated: Date?

    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.opencode.networkmonitor.lsof", qos: .utility)

    public init() {}

    public func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        queue.async { [weak self] in
            let conns = Self.readConnections()
            DispatchQueue.main.async {
                self?.connections = conns
                self?.lastUpdated = Date()
            }
        }
    }

    private static func readConnections() -> [NetworkConnection] {
        let task = Process()
        task.launchPath = "/usr/sbin/lsof"
        task.arguments = ["-nP", "-i"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            // lsof 对部分非 UTF-8 进程名会输出原始字节，用 lossy 解码避免整批解析失败
            let text = String(decoding: data, as: UTF8.self)
            return parse(text)
        } catch {
            return []
        }
    }

    private static func parse(_ text: String) -> [NetworkConnection] {
        var result: [NetworkConnection] = []
        var seen = Set<String>()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            // COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME...
            guard parts.count >= 8, let pid = Int32(parts[1]) else { continue }
            let name = parts[8...].joined(separator: " ")
            guard let protoToken = name.split(separator: " ").first else { continue }
            let protocolName = String(protoToken)
            var rest = String(name.dropFirst(protocolName.count)).trimmingCharacters(in: .whitespaces)
            var state = ""
            if rest.hasSuffix(")"), let open = rest.lastIndex(of: "(") {
                state = String(rest[rest.index(after: open)..<rest.index(before: rest.endIndex)])
                rest = String(rest[..<open]).trimmingCharacters(in: .whitespaces)
            }
            let local: String
            let remote: String
            if let arrow = rest.range(of: "->") {
                local = String(rest[..<arrow.lowerBound])
                remote = String(rest[arrow.upperBound...])
            } else {
                local = rest
                remote = ""
            }
            let id = "\(pid)|\(protocolName)|\(local)|\(remote)"
            guard seen.insert(id).inserted else { continue }
            result.append(NetworkConnection(
                id: id, pid: pid, process: String(parts[0]),
                protocolName: protocolName, local: local, remote: remote, state: state
            ))
        }
        return result
    }
}
