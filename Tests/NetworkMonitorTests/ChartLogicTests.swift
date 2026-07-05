import Testing
import Foundation
import CoreGraphics
@testable import NetworkMonitorCore

@Test func speedChartMaxLowSpeed() {
    let kb1 = 1024.0
    let kb5 = 5.0 * 1024
    let kb10 = 10.0 * 1024
    let kb25 = 25.0 * 1024
    let kb50 = 50.0 * 1024
    let kb100 = 100.0 * 1024
    let kb200 = 200.0 * 1024
    let kb500 = 500.0 * 1024

    #expect(speedChartMax(peak: 0) == kb1)
    #expect(speedChartMax(peak: 512) == kb1)
    #expect(speedChartMax(peak: 1024) == kb1)
    #expect(speedChartMax(peak: 1025) == kb5)
    #expect(speedChartMax(peak: 5 * 1024) == kb5)
    #expect(speedChartMax(peak: 5.1 * 1024) == kb10)
    #expect(speedChartMax(peak: 10 * 1024) == kb10)
    #expect(speedChartMax(peak: 10.1 * 1024) == kb25)
    #expect(speedChartMax(peak: 25 * 1024) == kb25)
    #expect(speedChartMax(peak: 25.1 * 1024) == kb50)
    #expect(speedChartMax(peak: 50 * 1024) == kb50)
    #expect(speedChartMax(peak: 51 * 1024) == kb100)
    #expect(speedChartMax(peak: 100 * 1024) == kb100)
    #expect(speedChartMax(peak: 101 * 1024) == kb200)
    #expect(speedChartMax(peak: 200 * 1024) == kb200)
    #expect(speedChartMax(peak: 201 * 1024) == kb500)
    #expect(speedChartMax(peak: 500 * 1024) == kb500)
}

@Test func speedChartMaxMediumSpeed() {
    let mb1 = 1024.0 * 1024.0
    #expect(speedChartMax(peak: 501 * 1024) == mb1)
    #expect(speedChartMax(peak: mb1) == mb1)
    #expect(speedChartMax(peak: mb1 * 1.5) == mb1 * 2)
    #expect(speedChartMax(peak: mb1 * 2) == mb1 * 2)
    #expect(speedChartMax(peak: mb1 * 3) == mb1 * 5)
    #expect(speedChartMax(peak: mb1 * 5) == mb1 * 5)
    #expect(speedChartMax(peak: mb1 * 7) == mb1 * 10)
    #expect(speedChartMax(peak: mb1 * 10) == mb1 * 10)
}

@Test func speedChartMaxHighSpeed() {
    let mb1 = 1024.0 * 1024.0
    #expect(speedChartMax(peak: mb1 * 15) == mb1 * 20)
    #expect(speedChartMax(peak: mb1 * 50) == mb1 * 50)
    #expect(speedChartMax(peak: mb1 * 100) == mb1 * 100)
}

@Test func tooltipPositionDefault() {
    let size = CGSize(width: 300, height: 100)
    let pos = tooltipPosition(dotX: 50, dotY: 30, chartSize: size)
    #expect(pos.x == CGFloat(50 + 16 + 90 / 2))
    #expect(pos.y == CGFloat(30 + 16 + 40 / 2))
}

@Test func tooltipPositionFlipX() {
    let size = CGSize(width: 300, height: 100)
    let pos = tooltipPosition(dotX: 250, dotY: 30, chartSize: size)
    #expect(pos.x == CGFloat(250 - 16 - 90 / 2))
}

@Test func tooltipPositionFlipY() {
    let size = CGSize(width: 300, height: 100)
    let pos = tooltipPosition(dotX: 50, dotY: 80, chartSize: size)
    #expect(pos.y == CGFloat(80 - 16 - 40 / 2))
}

@Test func tooltipPositionFlipBoth() {
    let size = CGSize(width: 300, height: 100)
    let pos = tooltipPosition(dotX: 250, dotY: 80, chartSize: size)
    #expect(pos.x == CGFloat(250 - 16 - 90 / 2))
    #expect(pos.y == CGFloat(80 - 16 - 40 / 2))
}

@Test func chartDataIndexBasic() {
    #expect(chartDataIndex(atX: 0, width: 100, count: 11) == 0)
    #expect(chartDataIndex(atX: 50, width: 100, count: 11) == 5)
    #expect(chartDataIndex(atX: 100, width: 100, count: 11) == 10)
    #expect(chartDataIndex(atX: 0, width: 100, count: 1) == nil)
    #expect(chartDataIndex(atX: 0, width: 0, count: 11) == nil)
}
