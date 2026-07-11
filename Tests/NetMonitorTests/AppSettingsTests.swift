import Testing
import Foundation
@testable import NetMonitorCore

@Suite(.serialized)
struct AppSettingsTests {

    private func makeSettings() -> AppSettings {
        let suiteName = "AppSettingsTests_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return AppSettings(userDefaults: defaults)
    }

    @Test func appSettingsMenuOrderComputed() {
        let settings = makeSettings()
        settings.menuBarOrderRaw = "cpu,speed,memory"
        let order = settings.menuBarOrder
        #expect(order == ["cpu", "speed", "memory"])
        #expect(settings.menuBarOrderRaw == "cpu,speed,memory")
    }

    @Test func appSettingsMoveMenuItemUp() {
        let settings = makeSettings()
        settings.menuBarOrder = ["cpu", "speed", "memory"]
        settings.moveMenuItemUp(1)
        #expect(settings.menuBarOrder == ["speed", "cpu", "memory"])
    }

    @Test func appSettingsMoveMenuItemDown() {
        let settings = makeSettings()
        settings.menuBarOrder = ["cpu", "speed", "memory"]
        settings.moveMenuItemDown(0)
        #expect(settings.menuBarOrder == ["speed", "cpu", "memory"])
    }

    @Test func appSettingsDisplayUnit() {
        let settings = makeSettings()
        #expect(settings.displayUnit == .auto)
        settings.displayUnit = .kb
        #expect(settings.displayUnit == .kb)
        #expect(settings.displayUnitRaw == "KB/s")
    }

    @Test func appSettingsUserDefaultsPersistence() {
        let suiteName = "AppSettingsPersist_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let s1 = AppSettings(userDefaults: defaults)
        s1.menuShowSpeed = false
        s1.floatShowCPU = false
        let s2 = AppSettings(userDefaults: defaults)
        #expect(s2.menuShowSpeed == false)
        #expect(s2.floatShowCPU == false)
    }
}
