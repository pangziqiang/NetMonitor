import Foundation
import Combine

public class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private let userDefaults: UserDefaults
    private var isLoadingDefaults = false

    // MARK: - Display Units

    @Published public var displayUnitRaw: String = DisplayUnit.auto.rawValue {
        didSet { if !isLoadingDefaults { userDefaults.set(displayUnitRaw, forKey: "displayUnit") } }
    }
    @Published public var dataUnitRaw: String = DataUnit.auto.rawValue {
        didSet { if !isLoadingDefaults { userDefaults.set(dataUnitRaw, forKey: "dataUnit") } }
    }

    public var displayUnit: DisplayUnit {
        get { DisplayUnit(rawValue: displayUnitRaw) ?? .auto }
        set { displayUnitRaw = newValue.rawValue }
    }

    public var dataUnit: DataUnit {
        get { DataUnit(rawValue: dataUnitRaw) ?? .auto }
        set { dataUnitRaw = newValue.rawValue }
    }

    // MARK: - Menu Bar Settings

    @Published public var menuShowSpeed: Bool = true {
        didSet { if !isLoadingDefaults { userDefaults.set(menuShowSpeed, forKey: "menuShowSpeed") } }
    }
    @Published public var menuShowDailyTraffic: Bool = false {
        didSet { if !isLoadingDefaults { userDefaults.set(menuShowDailyTraffic, forKey: "menuShowDailyTraffic") } }
    }
    @Published public var menuShowCPU: Bool = false {
        didSet { if !isLoadingDefaults { userDefaults.set(menuShowCPU, forKey: "menuShowCPU") } }
    }
    @Published public var menuShowGPU: Bool = false {
        didSet { if !isLoadingDefaults { userDefaults.set(menuShowGPU, forKey: "menuShowGPU") } }
    }
    @Published public var menuShowMemory: Bool = false {
        didSet { if !isLoadingDefaults { userDefaults.set(menuShowMemory, forKey: "menuShowMemory") } }
    }
    @Published public var menuShowTopProcesses: Bool = true {
        didSet { if !isLoadingDefaults { userDefaults.set(menuShowTopProcesses, forKey: "menuShowTopProcesses") } }
    }
    @Published public var menuTopProcessesCount: Int = 8 {
        didSet {
            if !isLoadingDefaults {
                userDefaults.set(menuTopProcessesCount, forKey: "menuTopProcessesCount")
                LogService.log(.userAction, event: "process_count_changed", detail: "\(menuTopProcessesCount)")
            }
        }
    }
    @Published public var menuBarOrderRaw: String = "speed,dailyTraffic,cpu,gpu,memory" {
        didSet { if !isLoadingDefaults { userDefaults.set(menuBarOrderRaw, forKey: "menuBarOrder") } }
    }

    public var menuBarOrder: [String] {
        get { menuBarOrderRaw.split(separator: ",").map(String.init) }
        set { menuBarOrderRaw = newValue.joined(separator: ",") }
    }

    public func moveMenuItem(from source: IndexSet, to destination: Int) {
        var order = menuBarOrder
        // move(fromOffsets:toOffset:) is a SwiftUI-only API; implement manually
        let elements = source.map { order[$0] }
        for index in source.reversed() {
            order.remove(at: index)
        }
        let adjustedDest = min(destination, order.count)
        for (offset, element) in elements.enumerated() {
            order.insert(element, at: adjustedDest + offset)
        }
        menuBarOrder = order
    }

    public func moveMenuItemUp(_ index: Int) {
        guard index > 0 else { return }
        var order = menuBarOrder
        order.swapAt(index, index - 1)
        menuBarOrder = order
    }

    public func moveMenuItemDown(_ index: Int) {
        var order = menuBarOrder
        guard index < order.count - 1 else { return }
        order.swapAt(index, index + 1)
        menuBarOrder = order
    }

    // MARK: - App Behavior

    @Published public var showDockIcon: Bool = false {
        didSet {
            if !isLoadingDefaults {
                userDefaults.set(showDockIcon, forKey: "showDockIcon")
                LogService.log(.userAction, event: "dock_icon_changed", detail: "\(showDockIcon)")
            }
        }
    }

    // MARK: - Floating Window

    @Published public var showFloatingWindow: Bool = false {
        didSet {
            if !isLoadingDefaults {
                userDefaults.set(showFloatingWindow, forKey: "showFloatingWindow")
                LogService.log(.userAction, event: "floating_window_changed", detail: "\(showFloatingWindow)")
            }
        }
    }
    @Published public var floatShowSpeed: Bool = true {
        didSet { if !isLoadingDefaults { userDefaults.set(floatShowSpeed, forKey: "floatShowSpeed") } }
    }
    @Published public var floatShowTraffic: Bool = true {
        didSet { if !isLoadingDefaults { userDefaults.set(floatShowTraffic, forKey: "floatShowTraffic") } }
    }
    @Published public var floatShowCPU: Bool = true {
        didSet { if !isLoadingDefaults { userDefaults.set(floatShowCPU, forKey: "floatShowCPU") } }
    }
    @Published public var floatShowGPU: Bool = true {
        didSet { if !isLoadingDefaults { userDefaults.set(floatShowGPU, forKey: "floatShowGPU") } }
    }
    @Published public var floatShowMemory: Bool = true {
        didSet { if !isLoadingDefaults { userDefaults.set(floatShowMemory, forKey: "floatShowMemory") } }
    }

    // MARK: - Initialization

    private init() {
        self.userDefaults = .standard
        registerDefaults()
        loadFromDefaults()
    }

    /// Internal initializer for testing without a SwiftUI host.
    internal init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        registerDefaults()
        loadFromDefaults()
    }

    private func registerDefaults() {
        userDefaults.register(defaults: [
            "displayUnit": DisplayUnit.auto.rawValue,
            "dataUnit": DataUnit.auto.rawValue,
            "showDockIcon": false,
            "showFloatingWindow": false,
            "floatShowSpeed": true,
            "floatShowTraffic": true,
            "floatShowCPU": true,
            "floatShowGPU": true,
            "floatShowMemory": true,
            "menuShowSpeed": true,
            "menuShowDailyTraffic": false,
            "menuShowCPU": false,
            "menuShowGPU": false,
            "menuShowMemory": false,
            "menuShowTopProcesses": true,
            "menuTopProcessesCount": 8,
            "menuBarOrder": "speed,dailyTraffic,cpu,gpu,memory"
        ])
    }

    private func loadFromDefaults() {
        isLoadingDefaults = true
        defer { isLoadingDefaults = false }
        if let stored = userDefaults.string(forKey: "displayUnit"), DisplayUnit(rawValue: stored) != nil {
            displayUnitRaw = stored
        } else {
            displayUnitRaw = DisplayUnit.auto.rawValue
        }
        if let stored = userDefaults.string(forKey: "dataUnit"), DataUnit(rawValue: stored) != nil {
            dataUnitRaw = stored
        } else {
            dataUnitRaw = DataUnit.auto.rawValue
        }
        menuShowSpeed = userDefaults.bool(forKey: "menuShowSpeed")
        menuShowDailyTraffic = userDefaults.bool(forKey: "menuShowDailyTraffic")
        menuShowCPU = userDefaults.bool(forKey: "menuShowCPU")
        menuShowGPU = userDefaults.bool(forKey: "menuShowGPU")
        menuShowMemory = userDefaults.bool(forKey: "menuShowMemory")
        menuShowTopProcesses = userDefaults.bool(forKey: "menuShowTopProcesses")
        menuTopProcessesCount = userDefaults.integer(forKey: "menuTopProcessesCount")
        if menuTopProcessesCount < 3 || menuTopProcessesCount > 10 { menuTopProcessesCount = 8 }
        let validItems: Set<String> = ["speed", "dailyTraffic", "cpu", "gpu", "memory"]
        if let stored = userDefaults.string(forKey: "menuBarOrder") {
            let items = stored.split(separator: ",").map(String.init).filter { validItems.contains($0) }
            menuBarOrderRaw = items.isEmpty ? "speed,dailyTraffic,cpu,gpu,memory" : items.joined(separator: ",")
        } else {
            menuBarOrderRaw = "speed,dailyTraffic,cpu,gpu,memory"
        }
        showDockIcon = userDefaults.bool(forKey: "showDockIcon")
        showFloatingWindow = userDefaults.bool(forKey: "showFloatingWindow")
        floatShowSpeed = userDefaults.bool(forKey: "floatShowSpeed")
        floatShowTraffic = userDefaults.bool(forKey: "floatShowTraffic")
        floatShowCPU = userDefaults.bool(forKey: "floatShowCPU")
        floatShowGPU = userDefaults.bool(forKey: "floatShowGPU")
        floatShowMemory = userDefaults.bool(forKey: "floatShowMemory")
    }
}
