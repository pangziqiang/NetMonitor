import SwiftUI
import NetworkMonitorCore

extension AppSettings {

    /// Returns a SwiftUI `Binding<Bool>` for the given menu-bar item toggle.
    public func bindingForMenuToggle(_ itemId: String) -> Binding<Bool> {
        Binding(
            get: {
                switch itemId {
                case "speed": return self.menuShowSpeed
                case "dailyTraffic": return self.menuShowDailyTraffic
                case "cpu": return self.menuShowCPU
                case "gpu": return self.menuShowGPU
                case "memory": return self.menuShowMemory
                default: return false
                }
            },
            set: { newValue in
                switch itemId {
                case "speed": self.menuShowSpeed = newValue
                case "dailyTraffic": self.menuShowDailyTraffic = newValue
                case "cpu": self.menuShowCPU = newValue
                case "gpu": self.menuShowGPU = newValue
                case "memory": self.menuShowMemory = newValue
                default: break
                }
            }
        )
    }

    /// Returns the localized display label for a menu-bar item.
    public func menuBarItemLabel(_ itemId: String) -> String {
        switch itemId {
        case "speed": return L10n.tr("Current Speed")
        case "dailyTraffic": return L10n.tr("Today Traffic")
        case "cpu": return L10n.tr("CPU Usage")
        case "gpu": return L10n.tr("GPU Usage")
        case "memory": return L10n.tr("Memory Usage")
        default: return itemId
        }
    }

    /// Returns the SF Symbol name for a menu-bar item.
    public func menuBarItemIcon(_ itemId: String) -> String {
        switch itemId {
        case "speed": return "speedometer"
        case "dailyTraffic": return "chart.pie.fill"
        case "cpu": return "cpu"
        case "gpu": return "display"
        case "memory": return "memorychip"
        default: return "questionmark"
        }
    }
}
