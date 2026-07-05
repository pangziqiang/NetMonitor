import Foundation

public enum VisibilityElement: String {
    case dock
    case menuBar
    case floating
    case floatingContent
}

public struct VisibilityHelper {
    public let showDockIcon: Bool
    public let menuShowSpeed: Bool
    public let menuShowDailyTraffic: Bool
    public let menuShowCPU: Bool
    public let menuShowGPU: Bool
    public let menuShowMemory: Bool
    public let showFloatingWindow: Bool
    public let floatShowSpeed: Bool
    public let floatShowTraffic: Bool
    public let floatShowCPU: Bool
    public let floatShowGPU: Bool
    public let floatShowMemory: Bool

    public init(
        showDockIcon: Bool,
        menuShowSpeed: Bool,
        menuShowDailyTraffic: Bool,
        menuShowCPU: Bool,
        menuShowGPU: Bool,
        menuShowMemory: Bool,
        showFloatingWindow: Bool,
        floatShowSpeed: Bool,
        floatShowTraffic: Bool,
        floatShowCPU: Bool,
        floatShowGPU: Bool,
        floatShowMemory: Bool
    ) {
        self.showDockIcon = showDockIcon
        self.menuShowSpeed = menuShowSpeed
        self.menuShowDailyTraffic = menuShowDailyTraffic
        self.menuShowCPU = menuShowCPU
        self.menuShowGPU = menuShowGPU
        self.menuShowMemory = menuShowMemory
        self.showFloatingWindow = showFloatingWindow
        self.floatShowSpeed = floatShowSpeed
        self.floatShowTraffic = floatShowTraffic
        self.floatShowCPU = floatShowCPU
        self.floatShowGPU = floatShowGPU
        self.floatShowMemory = floatShowMemory
    }

    public init(settings: AppSettings) {
        self.init(
            showDockIcon: settings.showDockIcon,
            menuShowSpeed: settings.menuShowSpeed,
            menuShowDailyTraffic: settings.menuShowDailyTraffic,
            menuShowCPU: settings.menuShowCPU,
            menuShowGPU: settings.menuShowGPU,
            menuShowMemory: settings.menuShowMemory,
            showFloatingWindow: settings.showFloatingWindow,
            floatShowSpeed: settings.floatShowSpeed,
            floatShowTraffic: settings.floatShowTraffic,
            floatShowCPU: settings.floatShowCPU,
            floatShowGPU: settings.floatShowGPU,
            floatShowMemory: settings.floatShowMemory
        )
    }

    public var hasMenuBarItem: Bool {
        menuShowSpeed || menuShowDailyTraffic || menuShowCPU || menuShowGPU || menuShowMemory
    }

    public var hasFloatingWindowContent: Bool {
        floatShowSpeed || floatShowTraffic || floatShowCPU || floatShowGPU || floatShowMemory
    }

    public var isFloatingWindowVisible: Bool {
        showFloatingWindow && hasFloatingWindowContent
    }

    public var hasAnyVisibleElement: Bool {
        showDockIcon || hasMenuBarItem || isFloatingWindowVisible
    }

    public var menuBarVisibleCount: Int {
        var count = 0
        if menuShowSpeed { count += 1 }
        if menuShowDailyTraffic { count += 1 }
        if menuShowCPU { count += 1 }
        if menuShowGPU { count += 1 }
        if menuShowMemory { count += 1 }
        return count
    }

    public var floatingContentCount: Int {
        var count = 0
        if floatShowSpeed { count += 1 }
        if floatShowTraffic { count += 1 }
        if floatShowCPU { count += 1 }
        if floatShowGPU { count += 1 }
        if floatShowMemory { count += 1 }
        return count
    }

    public func canDisable(_ element: VisibilityElement) -> Bool {
        switch element {
        case .dock:
            return hasMenuBarItem || isFloatingWindowVisible
        case .menuBar:
            return menuBarVisibleCount > 1 || showDockIcon || isFloatingWindowVisible
        case .floating:
            return showDockIcon || hasMenuBarItem
        case .floatingContent:
            return floatingContentCount > 1 || showDockIcon || hasMenuBarItem
        }
    }

    public func canDisable(_ element: String) -> Bool {
        guard let el = VisibilityElement(rawValue: element) else { return true }
        return canDisable(el)
    }

    /// Returns `true` if the app has no visible elements and needs to restore at least one.
    public func needsVisibilityRestore() -> Bool {
        !hasAnyVisibleElement
    }
}
