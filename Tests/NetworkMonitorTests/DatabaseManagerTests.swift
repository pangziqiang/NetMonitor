import Testing
import Foundation
@testable import NetworkMonitorCore

@Suite(.serialized)
struct DatabaseManagerTests {

    @Test func databaseManagerAccumulateAndTodayTraffic() throws {
        let db = try DatabaseManager(path: ":memory:")
        db.accumulateTraffic(down: 1024, up: 512)
        db.accumulateTraffic(down: 2048, up: 1024)
        let today = db.todayTraffic()
        #expect(today.down == 3072)
        #expect(today.up == 1536)
    }

    @Test func databaseManagerClearAllTraffic() throws {
        let db = try DatabaseManager(path: ":memory:")
        db.accumulateTraffic(down: 100, up: 50)
        let before = db.todayTraffic()
        #expect(before.down == 100)
        #expect(before.up == 50)
        db.clearAllTraffic()
        let after = db.todayTraffic()
        #expect(after.down == 0)
        #expect(after.up == 0)
        let daily = db.dailyTraffic(days: 7)
        #expect(daily.count == 0)
    }

    @Test func databaseManagerDailyTraffic() throws {
        let db = try DatabaseManager(path: ":memory:")
        db.accumulateTraffic(down: 500, up: 200)
        let daily = db.dailyTraffic(days: 7)
        #expect(daily.count == 1)
        #expect(daily[0].down == 500)
        #expect(daily[0].up == 200)
    }

    @Test func databaseManagerMinutelyTraffic() throws {
        let db = try DatabaseManager(path: ":memory:")
        let minutely = db.minutelyTraffic(minutes: 60)
        #expect(minutely.count == 0)
    }

    @Test func databaseErrorDescriptions() {
        let cannotOpen = DatabaseError.cannotOpen
        #expect(cannotOpen.errorDescription != nil)
        #expect(cannotOpen.errorDescription!.contains("数据库"))

        let execFailed = DatabaseError.execFailed("test error")
        #expect(execFailed.errorDescription != nil)
        #expect(execFailed.errorDescription!.contains("test error"))
    }

    @Test func databaseManagerMultipleAccumulations() throws {
        let db = try DatabaseManager(path: ":memory:")
        for i in 1...100 {
            db.accumulateTraffic(down: UInt64(i), up: UInt64(i * 2))
        }
        let today = db.todayTraffic()
        #expect(today.down == 5050) // 1+2+...+100
        #expect(today.up == 10100) // 2+4+...+200
    }

    @Test func databaseManagerTodayTrafficEmpty() throws {
        let db = try DatabaseManager(path: ":memory:")
        let today = db.todayTraffic()
        #expect(today.down == 0)
        #expect(today.up == 0)
    }

    @Test func databaseManagerClearAndReaccumulate() throws {
        let db = try DatabaseManager(path: ":memory:")
        db.accumulateTraffic(down: 100, up: 50)
        db.clearAllTraffic()
        db.accumulateTraffic(down: 200, up: 100)
        let today = db.todayTraffic()
        #expect(today.down == 200)
        #expect(today.up == 100)
    }
}
