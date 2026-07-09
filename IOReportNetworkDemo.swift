#!/usr/bin/env swift
// IOReport Network Demo — 最小可跑通示例
// 编译: swiftc IOReportNetworkDemo.swift -o IOReportNetworkDemo
// 运行: ./IOReportNetworkDemo
//
// 需要 macOS 10.15+，在 Terminal 直接运行即可

import Foundation
import IOKit
import IOKit.network.IOReport

// MARK: - 工具函数

func ioReportError(_ msg: String, _ code: kern_return_t) -> Never {
    let errStr = String(cString: mach_error_string(code))
    fputs("❌ \(msg): \(errStr) (0x\(String(code, radix: 16)))\n", stderr)
    exit(1)
}

func formatBytes(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB"]
    var value = Double(bytes)
    var idx = 0
    while value >= 1024 && idx < units.count - 1 {
        value /= 1024
        idx += 1
    }
    return String(format: "%.2f %@", value, units[idx])
}

// MARK: - IOReport 网络监控类

final class IOReportNetworkMonitor {
    private var subscription: IOReportSubscriptionRef?
    private let queue: DispatchQueue
    private var lastValues: [String: UInt64] = [:]
    private var lastTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    
    init() {
        self.queue = DispatchQueue(label: "com.example.ioreport.network", qos: .userInitiated)
    }
    
    deinit {
        stop()
    }
    
    func start() throws {
        // 1. 获取 Network 组的所有通道
        var channelsRef: Unmanaged<CFArray>?
        let kr1 = IOReportCopyChannelsInGroup("Network" as CFString, &channelsRef)
        guard kr1 == KERN_SUCCESS else { ioReportError("IOReportCopyChannelsInGroup", kr1) }
        defer { channelsRef?.release() }
        
        guard let channels = channelsRef?.takeRetainedValue() as? [CFString] else {
            fputs("❌ 无法转换通道数组\n", stderr)
            exit(1)
        }
        
        print("📡 发现 \(channels.count) 个 Network 通道")
        
        // 2. 过滤我们需要的通道：inputBytes / outputBytes
        // 通道名格式通常为: "com.apple.iokit.IONetworkInterface.en0.inputBytes"
        let wantedChannels = channels.compactMap { channel -> CFString? in
            let name = channel as String
            return (name.hasSuffix(".inputBytes") || name.hasSuffix(".outputBytes")) ? channel : nil
        }
        
        print("🎯 筛选出 \(wantedChannels.count) 个相关通道:")
        for ch in wantedChannels {
            print("   - \(ch)")
        }
        
        guard !wantedChannels.empty else {
            fputs("❌ 未找到 inputBytes/outputBytes 通道\n", stderr)
            exit(1)
        }
        
        // 3. 创建订阅
        var subscriptionRef: IOReportSubscriptionRef?
        let kr2 = IOReportCreateSubscription(
            wantedChannels as CFArray,
            0,  // options
            &subscriptionRef
        )
        guard kr2 == KERN_SUCCESS else { ioReportError("IOReportCreateSubscription", kr2) }
        self.subscription = subscriptionRef
        
        // 4. 设置回调队列
        IOReportSetDispatchQueue(subscriptionRef!, queue)
        
        // 5. 设置回调处理函数
        let callback: IOReportCallback = { context, reportRef in
            let monitor = Unmanaged<IOReportNetworkMonitor>.fromOpaque(context!).takeUnretainedValue()
            monitor.handleReport(reportRef!)
        }
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        IOReportSetCallback(subscriptionRef!, callback, selfPtr)
        
        // 6. 启动订阅
        let kr3 = IOReportStart(subscriptionRef!)
        guard kr3 == KERN_SUCCESS else { ioReportError("IOReportStart", kr3) }
        
        print("✅ IOReport 订阅已启动，等待数据...\n")
    }
    
    func stop() {
        if let sub = subscription {
            IOReportStop(sub)
            IOReportSetCallback(sub, nil, nil)
            subscription = nil
        }
    }
    
    private func handleReport(_ report: IOReportReportRef) {
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastTime
        lastTime = now
        
        // 遍历报告中的所有通道值
        var iterator: IOReportIteratorRef?
        let kr = IOReportCreateIterator(report, &iterator)
        guard kr == KERN_SUCCESS, let iter = iterator else { return }
        defer { IOObjectRelease(iter) }
        
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        
        while true {
            var channel: CFString?
            var value: UInt64 = 0
            let kr = IOReportIteratorNext(iter, &channel, &value)
            if kr != KERN_SUCCESS { break }
            guard let ch = channel else { continue }
            
            let name = ch as String
            let prev = lastValues[name] ?? 0
            lastValues[name] = value
            
            if value > prev {
                let delta = value - prev
                if name.hasSuffix(".inputBytes") {
                    totalIn += delta
                } else if name.hasSuffix(".outputBytes") {
                    totalOut += delta
                }
            }
        }
        
        if elapsed > 0 && (totalIn > 0 || totalOut > 0) {
            let inSpeed = Double(totalIn) / elapsed
            let outSpeed = Double(totalOut) / elapsed
            print("↓ \(formatBytes(UInt64(inSpeed)))/s  ↑ \(formatBytes(UInt64(outSpeed)))/s  (Δt: \(String(format: "%.2f", elapsed))s)")
        }
    }
}

// MARK: - 主程序

print("""
========================================
IOReport Network Monitor Demo
macOS \(ProcessInfo.processInfo.operatingSystemVersionString) | \(ProcessInfo.processInfo.machineHardwareName)
========================================
""")

let monitor = IOReportNetworkMonitor()

do {
    try monitor.start()
    
    // 运行 30 秒
    let runLoop = RunLoop.current
    let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in
        print("\n⏰ 演示结束，停止监控...")
        monitor.stop()
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
    runLoop.add(timer, forMode: .default)
    runLoop.run()
    
} catch {
    fputs("❌ 启动失败: \(error)\n", stderr)
    exit(1)
}