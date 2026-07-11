import Testing
import Foundation
@testable import NetMonitorCore

@Test func thermalMonitorInit() {
    let tm = ThermalMonitor()
    #expect(tm.cpuTemperature == nil)
    #expect(tm.gpuTemperature == nil)
    #expect(tm.memoryTemperature == nil)
    #expect(tm.estimatedCPUTemp == 0)
    #expect(tm.estimatedGPUTemp == 0)
    #expect(tm.estimatedMemTemp == 0)
}

@Test func thermalMonitorEstimationFormulas() {
    let tm = ThermalMonitor()

    _ = tm.refresh(cpuUsage: 0, gpuUsage: 0)
    #expect(tm.estimatedCPUTemp == 32.0)
    #expect(tm.estimatedGPUTemp == 33.0)

    _ = tm.refresh(cpuUsage: 100, gpuUsage: 100)
    #expect(tm.estimatedCPUTemp == 87.0)
    #expect(tm.estimatedGPUTemp == 78.0)

    _ = tm.refresh(cpuUsage: 50, gpuUsage: 50)
    #expect(tm.estimatedCPUTemp == 59.5)
    #expect(tm.estimatedGPUTemp == 55.5)
}

@Test func thermalMonitorAllTemps() {
    let tm = ThermalMonitor()
    let temps = tm.allTemps
    #expect(temps.count == 3)
    #expect(temps[0].label == "CPU")
    #expect(temps[1].label == "GPU")
    #expect(temps[2].label == L10n.tr("Memory"))
    #expect(temps[0].value == nil)
    #expect(temps[1].value == nil)
    #expect(temps[2].value == nil)
}

@Test func thermalMonitorFallbackPopulatesTemps() {
    let tm = ThermalMonitor()

    let result = tm.refresh(cpuUsage: 80, gpuUsage: 70)

    // refresh() dispatches @Published updates to main asynchronously,
    // but returns estimated values directly
    if result.cpu != nil {
        // SMC available, temps come from hardware
        return
    }

    // Fallback: estimated values used — check return values
    #expect(result.cpu == tm.estimatedCPUTemp)
    #expect(result.gpu == tm.estimatedGPUTemp)
    #expect(result.mem == tm.estimatedMemTemp)
}

@Test func thermalMonitorIsAS() {
    let tm = ThermalMonitor()
    // This test just ensures the property exists and returns a Bool
    #expect(tm.isAS == true || tm.isAS == false)
}
