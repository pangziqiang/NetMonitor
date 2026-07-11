import Foundation
import Darwin

// MARK: - IOReport C Types

private typealias IOReportChannelArray = UnsafeMutablePointer<io_object_t>?
private typealias CopyChannelsInGroupFunc = @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<IOReportChannelArray>, UnsafeMutablePointer<UInt32>) -> Int32
private typealias CopyChannelDescriptionFunc = @convention(c) (io_object_t, UnsafeMutableRawPointer) -> Int32
private typealias CopyDriverNameFunc = @convention(c) (io_object_t, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32
private typealias CreateSubscriptionFunc = @convention(c) (UnsafePointer<io_object_t>, UInt32, UInt32, UnsafeMutablePointer<io_object_t>) -> Int32
private typealias IterateNewSamplesFunc = @convention(c) (io_object_t, (@convention(c) (UnsafeMutableRawPointer?, io_object_t, UnsafeMutableRawPointer?, UInt32) -> Int32)?, UnsafeMutableRawPointer?) -> Int32
private typealias SimpleGetIntegerValueFunc = @convention(c) (io_object_t, UnsafeMutablePointer<Int64>) -> Int32
private typealias ReleaseFunc = @convention(c) (io_object_t) -> Int32

// MARK: - Dynamic Library Loading

private final class IOReportLib {
    static let shared: IOReportLib? = IOReportLib()

    private let handle: UnsafeMutableRawPointer
    let copyChannelsInGroup: CopyChannelsInGroupFunc
    let copyChannelDescription: CopyChannelDescriptionFunc
    let copyDriverName: CopyDriverNameFunc
    let createSubscription: CreateSubscriptionFunc
    let iterateNewSamples: IterateNewSamplesFunc
    let simpleGetIntegerValue: SimpleGetIntegerValueFunc
    let release: ReleaseFunc

    private init?() {
        guard let libHandle = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else {
            return nil
        }
        self.handle = libHandle

        func sym<T>(_ name: String) -> T? {
            guard let ptr = dlsym(libHandle, name) else { return nil }
            return unsafeBitCast(ptr, to: T.self)
        }

        guard let c1: CopyChannelsInGroupFunc = sym("IOReportCopyChannelsInGroup"),
              let c2: CopyChannelDescriptionFunc = sym("IOReportChannelCopyDescription"),
              let c3: CopyDriverNameFunc = sym("IOReportCopyDriverName"),
              let c4: CreateSubscriptionFunc = sym("IOReportCreateSubscription"),
              let c5: IterateNewSamplesFunc = sym("IOReportIterateNewSamples"),
              let c6: SimpleGetIntegerValueFunc = sym("IOReportSimpleGetIntegerValue"),
              let c7: ReleaseFunc = sym("IOObjectRelease")
        else {
            dlclose(libHandle)
            return nil
        }

        self.copyChannelsInGroup = c1
        self.copyChannelDescription = c2
        self.copyDriverName = c3
        self.createSubscription = c4
        self.iterateNewSamples = c5
        self.simpleGetIntegerValue = c6
        self.release = c7
    }

    deinit {
        dlclose(handle)
    }
}

// C-compatible channel type (matching kernel header)
private struct C_IOReportChannelType {
    var report_format: UInt8 = 0
    var reserved: UInt8 = 0
    var categories: UInt16 = 0
    var nelements: UInt16 = 0
    var element_idx: Int16 = 0
}

// MARK: - IOReportMonitor

public enum IOReportGroup: String {
    case network = "Network"
    case cpu = "CPU"
}

public final class IOReportMonitor {
    public let group: IOReportGroup
    private var subscription: io_object_t = 0
    private var channels: [io_object_t] = []
    private var releasedChannels: Set<io_object_t> = []
    private var channelInfos: [io_object_t: (name: String, driver: String)] = [:]
    private let callbackQueue = DispatchQueue(label: "com.opencode.ioreport.callback", qos: .utility)
    private var valueCallback: ((String, Int64) -> Void)?
    private let lock = NSLock()
    private var isStopping = false
    
    public init(group: IOReportGroup) {
        self.group = group
    }

    deinit {
        stop()
    }

    public func start(onValue: @escaping (String, Int64) -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard subscription == 0 else { return true }
        self.valueCallback = onValue
        self.isStopping = false

        guard let lib = IOReportLib.shared else { return false }

        // 1. Get channels in group
        var channelArray: IOReportChannelArray = nil
        var channelCount: UInt32 = 0
        let groupName = group.rawValue

        let kr1 = groupName.withCString { cStr in
            lib.copyChannelsInGroup(cStr, &channelArray, &channelCount)
        }
        guard kr1 == 0, let channels = channelArray, channelCount > 0 else {
            return false
        }

        var validChannels: [io_object_t] = []
        validChannels.reserveCapacity(Int(channelCount))
        releasedChannels.removeAll()

        for i in 0..<Int(channelCount) {
            let ch = channels[i]

            // Get driver name
            var driverNamePtr: UnsafeMutablePointer<CChar>?
            let krDriver = lib.copyDriverName(ch, &driverNamePtr)
            let driver = (krDriver == 0 && driverNamePtr != nil) ? String(cString: driverNamePtr!) : "unknown"
            if driverNamePtr != nil { free(driverNamePtr) }

            // Get channel description
            var cType = C_IOReportChannelType()
            let krType = lib.copyChannelDescription(ch, &cType)
            if krType != 0 {
                _ = lib.release(ch)
                releasedChannels.insert(ch)
                continue
            }

            // Only handle simple format (1 = kIOReportFormatSimple)
            guard cType.report_format == 1 else {
                _ = lib.release(ch)
                releasedChannels.insert(ch)
                continue
            }

            // Check category
            let isTraffic = (cType.categories & (1 << 1)) != 0
            let isPerformance = (cType.categories & (1 << 2)) != 0

            let accept: Bool
            switch group {
            case .network: accept = isTraffic
            case .cpu: accept = isPerformance
            }

            if !accept {
                _ = lib.release(ch)
                releasedChannels.insert(ch)
                continue
            }

            let name = "\(driver).\(i)"
            channelInfos[ch] = (name, driver)
            validChannels.append(ch)
        }

        // Release the channel array (only those not already released)
        for i in 0..<Int(channelCount) {
            let ch = channels[i]
            if !releasedChannels.contains(ch) {
                _ = lib.release(ch)
            }
        }
        free(channels)

        guard !validChannels.isEmpty else { return false }

        // Create subscription
        subscription = 0
        let krSub = validChannels.withUnsafeBufferPointer { ptr in
            lib.createSubscription(ptr.baseAddress!, UInt32(ptr.count), 0, &subscription)
        }
        guard krSub == 0, subscription != 0 else { return false }

        self.channels = validChannels

        // Start iteration - use passRetained to keep monitor alive during callbacks
        let context = UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())
        let krIterate = lib.iterateNewSamples(subscription, { ctx, channel, buffer, count in
            guard let ctx else { return -1 }
            let monitor = Unmanaged<IOReportMonitor>.fromOpaque(ctx).takeUnretainedValue()
            return monitor.handleSample(channel: channel, buffer: buffer, count: count)
        }, context)

        // If start failed, release the retained reference
        if krIterate != 0 {
            Unmanaged<IOReportMonitor>.fromOpaque(context).release()
        }

        return krIterate == 0
    }

    public func stop() {
        lock.lock()
        guard !isStopping else {
            lock.unlock()
            return
        }
        isStopping = true
        let subs = subscription
        let chans = channels
        let lib = IOReportLib.shared
        subscription = 0
        channels.removeAll()
        channelInfos.removeAll()
        releasedChannels.removeAll()
        valueCallback = nil
        lock.unlock()

        // Release outside lock to avoid deadlock
        if let lib, subs != 0 {
            _ = lib.release(subs)
        }
        if let lib {
            for ch in chans {
                _ = lib.release(ch)
            }
        }
    }

    private func handleSample(channel: io_object_t, buffer: UnsafeMutableRawPointer?, count: UInt32) -> Int32 {
        lock.lock()
        guard !isStopping,
              let lib = IOReportLib.shared,
              let info = channelInfos[channel] else {
            lock.unlock()
            return -1
        }
        lock.unlock()

        var value: Int64 = 0
        let kr = lib.simpleGetIntegerValue(channel, &value)
        guard kr == 0 else { return -1 }

        callbackQueue.async { [weak self] in
            self?.valueCallback?(info.name, value)
        }
        return 0
    }

    /// Returns true only on Apple Silicon where libIOReport.dylib works.
    public static func isAvailable() -> Bool {
        #if arch(arm64)
        return IOReportLib.shared != nil
        #else
        return false
        #endif
    }
}