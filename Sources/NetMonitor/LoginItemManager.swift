import AppKit
import NetMonitorCore
import ServiceManagement

/// Manages the "launch at login" state via SMAppService (macOS 13+).
@MainActor
enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Applies the desired state; returns false if the system rejected the change.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return true }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status == .enabled else { return true }
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            LogService.error("login_item_set_failed", detail: "enabled=\(enabled) error=\(error)")
            return false
        }
    }

    /// Syncs the persisted setting with the real system state (call once at launch).
    static func sync(with settings: AppSettings) {
        let real = isEnabled
        if real != settings.launchAtLogin {
            settings.launchAtLogin = real
        }
    }
}
