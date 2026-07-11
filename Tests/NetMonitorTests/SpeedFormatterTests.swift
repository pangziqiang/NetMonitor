import Testing
import Foundation
@testable import NetMonitorCore

@Test func formatBytesAuto() {
    #expect(formatBytes(0) == "0 B")
    #expect(formatBytes(1023) == "1023 B")
    #expect(formatBytes(1024) == "1 KB")
    #expect(formatBytes(1536) == "2 KB")
    #expect(formatBytes(1024 * 1024) == "1.0 MB")
    #expect(formatBytes(1024 * 1024 * 1024) == "1.0 GB")
    #expect(formatBytes(UInt64(1024 * 1024 * 1024 * 1.5)) == "1.5 GB")
}

@Test func formatBytesWithUnit() {
    #expect(formatBytes(2048, unit: .auto) == "2 KB")
    #expect(formatBytes(2048, unit: .kb) == "2.0 KB")
    #expect(formatBytes(1048576, unit: .mb) == "1.00 MB")
    #expect(formatBytes(0, unit: .auto) == "0 B")
}

@Test func formatSpeedBps() {
    #expect(formatSpeed(0) == "0.0 KB/s")
    #expect(formatSpeed(1024) == "1.0 KB/s")
    #expect(formatSpeed(1024 * 1024) == "1.0 MB/s")
    #expect(formatSpeed(500) == "0.5 KB/s")
}

@Test func formatSpeedWithUnit() {
    #expect(formatSpeed(2048, unit: .kb) == "2.0 KB/s")
    #expect(formatSpeed(2_097_152, unit: .mb) == "2.00 MB/s")
    #expect(formatSpeed(1024, unit: .auto) == "1.0 KB/s")
}

@Test func shortSpeedBps() {
    #expect(shortSpeed(0) == "0KB")
    #expect(shortSpeed(1024) == "1KB")
    #expect(shortSpeed(1536) == "2KB")
    #expect(shortSpeed(1024 * 1024) == "1.0MB")
}

@Test func shortSpeedWithUnit() {
    #expect(shortSpeed(2048, unit: .kb) == "2.0KB")
    #expect(shortSpeed(2_097_152, unit: .mb) == "2.00MB")
    #expect(shortSpeed(1024, unit: .auto) == "1KB")
}

@Test func displayUnitIdentifiable() {
    let units = DisplayUnit.allCases
    #expect(units.count == 3)
    #expect(DisplayUnit.auto.id == "自动")
    #expect(DisplayUnit.kb.id == "KB/s")
    #expect(DisplayUnit.mb.id == "MB/s")
}

@Test func formatBytesLargeValues() {
    let tb = UInt64(1024 * 1024 * 1024) * 1024
    #expect(formatBytes(tb) == "1.0 TB")
    #expect(formatBytes(tb * 2) == "2.0 TB")
}

@Test func formatSpeedLargeValues() {
    let mbps = 1024.0 * 1024.0
    let result = formatSpeed(mbps)
    #expect(result.contains("MB/s"))
}

@Test func formatBytesZeroWithUnit() {
    #expect(formatBytes(0, unit: .kb) == "0.0 KB")
    #expect(formatBytes(0, unit: .mb) == "0.00 MB")
}

@Test func formatSpeedZeroWithUnit() {
    #expect(formatSpeed(0, unit: .kb) == "0.0 KB/s")
    #expect(formatSpeed(0, unit: .mb) == "0.00 MB/s")
}

@Test func shortSpeedLargeValues() {
    let mb10 = 1024.0 * 1024.0 * 10.0
    let result = shortSpeed(mb10)
    #expect(result.contains("MB"))
}

@Test func dataUnitIdentifiable() {
    let units = DataUnit.allCases
    #expect(units.count == 4)
    #expect(DataUnit.auto.id == "自动")
    #expect(DataUnit.kb.id == "KB")
    #expect(DataUnit.mb.id == "MB")
    #expect(DataUnit.gb.id == "GB")
}
