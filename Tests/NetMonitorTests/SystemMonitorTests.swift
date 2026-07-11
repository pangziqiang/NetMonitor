import Testing
import Foundation
@testable import NetMonitorCore

@Test func systemMonitorInit() {
    let sm = SystemMonitor()
    #expect(sm.cpuUsage == 0)
    #expect(sm.gpuUsage == 0)
    #expect(sm.memoryUsage == 0)
    #expect(sm.cpuHistory.isEmpty)
    #expect(sm.gpuHistory.isEmpty)
    #expect(sm.memoryHistory.isEmpty)
    #expect(sm.cpuTemperatureHistory.isEmpty)
    #expect(sm.gpuTemperatureHistory.isEmpty)
    #expect(sm.memoryTemperatureHistory.isEmpty)
    #expect(sm.memoryTotal == 0)
    #expect(sm.memoryUsed == 0)
    #expect(sm.historyMax == 120)
}

@Test func systemMonitorHistoryMaxClamping() {
    let sm = SystemMonitor()
    sm.historyMax = 10
    #expect(sm.historyMax == 30)

    sm.historyMax = 1000
    #expect(sm.historyMax == 600)

    sm.historyMax = 300
    #expect(sm.historyMax == 300)
}

@Test func systemMonitorHasRealGPUData() {
    let sm = SystemMonitor()

    sm.gpuAvailable = false
    #expect(sm.hasRealGPUData == false)

    sm.gpuAvailable = true
    #expect(sm.hasRealGPUData == true)
}

@Test func systemMonitorThermalMonitorAttached() {
    let sm = SystemMonitor()
    #expect(sm.thermal.cpuTemperature == nil)
}
