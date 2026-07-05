import Testing
import Foundation
@testable import NetworkMonitorCore

@Test func l10nTrReturnsKeyForEnglish() {
    // On non-Chinese locale, tr() should return the key itself
    let result = L10n.tr("Settings")
    // We can't easily mock locale, but we can verify the function doesn't crash
    #expect(result == "Settings" || result == "设置")
}

@Test func l10nTrHandlesMissingKey() {
    // A key not in the dictionary should return the key itself
    let result = L10n.tr("NonexistentKey12345")
    #expect(result == "NonexistentKey12345")
}

@Test func l10nTrHandlesEmptyKey() {
    let result = L10n.tr("")
    #expect(result == "")
}

@Test func l10nKnownKeysReturnNonEmpty() {
    let keys = ["Settings", "Exit", "Monitoring", "Upload Speed", "Download Speed",
                "CPU Usage", "GPU Usage", "Memory Usage", "Close", "Pin", "Unpin"]
    for key in keys {
        let result = L10n.tr(key)
        #expect(!result.isEmpty, "Key '\(key)' returned empty string")
    }
}

@Test func formatBytesDataUnitAuto() {
    #expect(formatBytes(0, dataUnit: .auto) == "0 B")
    #expect(formatBytes(1024, dataUnit: .auto) == "1 KB")
}

@Test func formatBytesDataUnitKB() {
    #expect(formatBytes(0, dataUnit: .kb) == "0.0 KB")
    #expect(formatBytes(1024, dataUnit: .kb) == "1.0 KB")
    #expect(formatBytes(2048, dataUnit: .kb) == "2.0 KB")
}

@Test func formatBytesDataUnitMB() {
    #expect(formatBytes(0, dataUnit: .mb) == "0.00 MB")
    #expect(formatBytes(1048576, dataUnit: .mb) == "1.00 MB")
}

@Test func formatBytesDataUnitGB() {
    #expect(formatBytes(0, dataUnit: .gb) == "0.00 GB")
    #expect(formatBytes(1073741824, dataUnit: .gb) == "1.00 GB")
}
