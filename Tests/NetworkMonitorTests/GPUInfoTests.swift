import Testing
import Foundation
@testable import NetworkMonitorCore

@Test func gpuInfoStructProperties() {
    let info = GPUInfo(usagePercent: 45.5, vramFree: 4_000_000_000, vramTotal: 8_000_000_000, vramUsed: 3_500_000_000, renderUtil: 30, tilerUtil: 20)
    #expect(info.usagePercent == 45.5)
    #expect(info.vramFree == 4_000_000_000)
    #expect(info.vramTotal == 8_000_000_000)
    #expect(info.vramUsed == 3_500_000_000)
    #expect(info.renderUtil == 30)
    #expect(info.tilerUtil == 20)
}

@Test func gpuInfoNoVRAM() {
    let info = GPUInfo(usagePercent: 100, vramFree: nil, vramTotal: nil, vramUsed: nil, renderUtil: nil, tilerUtil: nil)
    #expect(info.usagePercent == 100)
    #expect(info.vramFree == nil)
    #expect(info.vramTotal == nil)
    #expect(info.vramUsed == nil)
    #expect(info.renderUtil == nil)
    #expect(info.tilerUtil == nil)
}

@Test func gpuInfoZeroUsage() {
    let info = GPUInfo(usagePercent: 0, vramFree: nil, vramTotal: nil, vramUsed: nil, renderUtil: nil, tilerUtil: nil)
    #expect(info.usagePercent == 0)
}
