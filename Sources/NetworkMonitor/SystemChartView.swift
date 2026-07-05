import NetworkMonitorCore
import SwiftUI

struct SeriesConfig {
    let data: [Double]
    let color: Color
    let yMax: Double
    let label: String
    let formatValue: (Double) -> String
    let formatYLabel: (Double) -> String
}

struct DualSeriesChart: View {
    let title: String
    let series1: SeriesConfig
    let series2: SeriesConfig?
    var showCard: Bool = true
    @Environment(\.colorScheme) var colorScheme
    @State private var hoverX: CGFloat? = nil
    @State private var hoverSize: CGSize? = nil
    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }

    var body: some View {
        let chartContent = VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(series1.color).frame(width: 7, height: 7)
                Text(title).font(.subheadline).foregroundColor(theme.textSecondary)
                if let last = series1.data.last {
                    Text(series1.formatValue(last))
                        .font(.system(.callout, design: .monospaced)).fontWeight(.semibold)
                        .foregroundColor(series1.color)
                }
                Spacer()
                if let s2 = series2, let last = s2.data.last, last > 0 {
                    Circle().fill(s2.color).frame(width: 7, height: 7)
                    Text(s2.formatValue(last))
                        .font(.system(.caption, design: .monospaced)).fontWeight(.semibold)
                        .foregroundColor(s2.color)
                }
            }
            ZStack(alignment: .topTrailing) {
                ChartView(renderer: drawDualChart, hoverX: $hoverX, hoverSize: $hoverSize,
                          dataFingerprint: series1.data.count &* 31 &+ (series1.data.last.map { Int($0 * 1000) } ?? 0))
                if let hx = hoverX, let sz = hoverSize,
                   let idx = dataIndex(atX: hx, width: sz.width, count: series1.data.count) {
                    let val = series1.data[idx]
                    Text(series1.formatValue(val))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(series1.color)
                        .padding(4)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }
            }
        }
        .padding(14)

        return Group {
            if showCard {
                chartContent.card(.tone(series1.color))
            } else {
                chartContent
            }
        }
    }

    private func drawDualChart(ctx: CGContext, size: CGSize, isDark: Bool) {
        let w = size.width, h = size.height
        let labelH: CGFloat = 14
        let chartH = h - labelH
        guard chartH > 0, !series1.data.isEmpty, series1.yMax >= 1, series1.data.count >= 2 else { return }
        let n = series1.data.count
        let stepX = w / CGFloat(n - 1)
        let scale1 = chartH / CGFloat(series1.yMax)
        let muted = isDark ? NSColor.white.withAlphaComponent(0.5) : NSColor(red: 0.42, green: 0.45, blue: 0.5, alpha: 1)
        let gridColor = (isDark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.06)).cgColor

        // Grid lines
        for pct in [0.25, 0.5, 0.75] {
            let y = chartH - CGFloat(series1.yMax * pct) / CGFloat(series1.yMax) * chartH
            ctx.setStrokeColor(gridColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: w, y: y))
            ctx.strokePath()
        }
        let vStep = max(1, n / 6)
        for i in stride(from: 0, to: n, by: vStep) {
            let x = stepX * CGFloat(i)
            ctx.setStrokeColor(gridColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: chartH))
            ctx.strokePath()
        }

        ctx.saveGState()
        ctx.beginPath()
        smoothCurvePath(ctx: ctx, data: series1.data.map { min($0, series1.yMax) }, stepX: stepX, scaleY: scale1, height: chartH)
        ctx.addLine(to: CGPoint(x: stepX * CGFloat(n - 1), y: chartH))
        ctx.addLine(to: CGPoint(x: 0, y: chartH))
        ctx.closePath()
        ctx.clip()
        let gradColors = [series1.color.ns.withAlphaComponent(0.12).cgColor, series1.color.ns.withAlphaComponent(0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gradColors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: chartH), options: [])
        }
        ctx.resetClip()
        ctx.restoreGState()

        ctx.beginPath()
        smoothCurvePath(ctx: ctx, data: series1.data.map { min($0, series1.yMax) }, stepX: stepX, scaleY: scale1, height: chartH)
        ctx.setStrokeColor(series1.color.cg)
        ctx.setLineWidth(2)
        ctx.strokePath()

        if let s2 = series2, s2.yMax > 0, s2.data.count == n {
            let scale2 = chartH / CGFloat(s2.yMax)
            ctx.beginPath()
            smoothCurvePath(ctx: ctx, data: s2.data.map { min($0, s2.yMax) }, stepX: stepX, scaleY: scale2, height: chartH)
            ctx.setStrokeColor(s2.color.cg)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }

        for yl in [series1.yMax * 0.25, series1.yMax * 0.5, series1.yMax * 0.75, series1.yMax] {
            let y = chartH - CGFloat(yl) / CGFloat(series1.yMax) * chartH - 4
            drawCGText(series1.formatYLabel(yl), at: CGPoint(x: 15, y: max(4, y)),
                       font: .monospacedDigitSystemFont(ofSize: 8, weight: .regular), color: muted)
        }

        for i in stride(from: 0, to: n, by: max(1, n / 5)) {
            let x = stepX * CGFloat(i)
            let sec = n - 1 - i
            let label = sec <= 0 ? L10n.tr("Now") : "\(sec)s"
            drawCGText(label, at: CGPoint(x: x, y: chartH + labelH * 0.5),
                       font: .monospacedDigitSystemFont(ofSize: 8, weight: .regular), color: muted)
        }

        if let max1 = series1.data.max() {
            let idx1 = series1.data.firstIndex(of: max1) ?? (n - 1)
            let px = stepX * CGFloat(idx1)
            let py = chartH - CGFloat(min(max1, series1.yMax)) * scale1 - 6
            drawCGText(series1.formatValue(max1), at: CGPoint(x: px, y: max(0, py)),
                       font: .monospacedDigitSystemFont(ofSize: 9, weight: .bold),
                       color: series1.color.ns.withAlphaComponent(0.9))
        }
    }
}
