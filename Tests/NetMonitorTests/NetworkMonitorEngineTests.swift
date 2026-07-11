import Testing
import Foundation
@testable import NetMonitorCore

@Test func engineHistoryMaxDefault() {
    let engine = NetMonitorEngine()
    #expect(engine.historyMax == 120)
}

@Test func engineHistoryMaxClamping() {
    let engine = NetMonitorEngine()
    engine.historyMax = 10
    #expect(engine.historyMax == 30)
    engine.historyMax = 1000
    #expect(engine.historyMax == 600)
    engine.historyMax = 300
    #expect(engine.historyMax == 300)
}

@Test func engineInitialState() {
    let engine = NetMonitorEngine()
    #expect(engine.currentDownSpeed == 0)
    #expect(engine.currentUpSpeed == 0)
    #expect(engine.totalSessionDown == 0)
    #expect(engine.totalSessionUp == 0)
    #expect(engine.isPaused == false)
    #expect(engine.downHistory.isEmpty)
    #expect(engine.upHistory.isEmpty)
}

@Test func enginePauseResume() async throws {
    let engine = NetMonitorEngine()
    #expect(engine.isPaused == false)
    engine.pause()
    #expect(engine.isPaused == true)
    engine.resume()
    try await Task.sleep(for: .milliseconds(200))
    #expect(engine.isPaused == false)
}
