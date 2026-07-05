import Foundation
import CoreGraphics

// MARK: - Chart calculation helpers (pure functions, no UI dependency)

public func speedChartMax(peak: Double) -> Double {
    let kb1 = Double(1024)
    let kb5 = Double(5 * 1024)
    let kb10 = Double(10 * 1024)
    let kb25 = Double(25 * 1024)
    let kb50 = Double(50 * 1024)
    let kb100 = Double(100 * 1024)
    let kb200 = Double(200 * 1024)
    let kb500 = Double(500 * 1024)
    let mb1 = Double(1024 * 1024)
    if peak <= kb1 { return kb1 }
    if peak <= kb5 { return kb5 }
    if peak <= kb10 { return kb10 }
    if peak <= kb25 { return kb25 }
    if peak <= kb50 { return kb50 }
    if peak <= kb100 { return kb100 }
    if peak <= kb200 { return kb200 }
    if peak <= kb500 { return kb500 }
    let mb = peak / mb1
    let niceMax: Double
    if mb <= 1 { niceMax = 1 }
    else if mb <= 2 { niceMax = 2 }
    else if mb <= 5 { niceMax = 5 }
    else if mb <= 10 { niceMax = 10 }
    else { niceMax = ceil(mb / 10) * 10 }
    return niceMax * mb1
}

public struct TooltipPosition {
    public let x: CGFloat
    public let y: CGFloat
    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }
}

public func tooltipPosition(dotX: CGFloat, dotY: CGFloat, chartSize: CGSize, tooltipWidth: CGFloat = 90, tooltipHeight: CGFloat = 40, offset: CGFloat = 16) -> TooltipPosition {
    let x = dotX + offset + tooltipWidth <= chartSize.width
        ? dotX + offset + tooltipWidth / 2
        : dotX - offset - tooltipWidth / 2
    let y = dotY + offset + tooltipHeight <= chartSize.height
        ? dotY + offset + tooltipHeight / 2
        : dotY - offset - tooltipHeight / 2
    return TooltipPosition(x: x, y: y)
}

public func chartDataIndex(atX x: CGFloat, width: CGFloat, count: Int) -> Int? {
    guard count >= 2, width > 0 else { return nil }
    let stepX = width / CGFloat(count - 1)
    let idx = Int(round(x / stepX))
    return max(0, min(idx, count - 1))
}
