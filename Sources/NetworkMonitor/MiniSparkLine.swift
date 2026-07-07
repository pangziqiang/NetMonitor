import NetworkMonitorCore
import SwiftUI

struct MiniSparkLine: View {
    let data: [Double]
    var times: [Date] = []
    let color: Color
    var showAxis: Bool = false
    var showPeak: Bool = false
    var fixedMax: Double? = nil
    var formatValue: ((Double) -> String)? = nil
    @State private var hoverX: CGFloat? = nil
    @State private var hoverSize: CGSize? = nil

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ChartView(
                renderer: { ctx, size, isDark in drawChart(ctx: ctx, size: size, isDark: isDark) },
                hoverX: $hoverX,
                hoverSize: $hoverSize,
                dataFingerprint: data.count &* 31 &+ (data.last.map { Int($0 * 1000) } ?? 0),
                hoverFingerprint: hoverX.map { Int($0 * 10) } ?? -1
            )

            if let hx = hoverX, let sz = hoverSize,
               let idx = dataIndex(atX: hx, width: sz.width, count: data.count),
               idx < data.count {
                let val = data[idx]
                let timeStr = idx < times.count ? Self.timeFormatter.string(from: times[idx]) : ""
                let maxVal = fixedMax ?? max(data.max() ?? 1, 1.0)
                let stepX = sz.width / CGFloat(max(data.count - 1, 1))
                let dotX = stepX * CGFloat(idx)
                let dotY = sz.height - CGFloat(val) / CGFloat(maxVal) * sz.height

                VStack(alignment: .leading, spacing: 4) {
                    Text(formatValue?(val) ?? String(format: "%.1f%%", val))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(color)
                    if !timeStr.isEmpty {
                        Text(timeStr)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(color.opacity(0.7))
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .position(
                    x: tooltipPosition(dotX: dotX, dotY: dotY, chartSize: sz).x,
                    y: tooltipPosition(dotX: dotX, dotY: dotY, chartSize: sz).y
                )
            }
        }
        .accessibilityLabel(L10n.tr("Data Chart"))
        .accessibilityValue(data.last.map { formatValue?($0) ?? String(format: "%.1f", $0) } ?? L10n.tr("No Data Value"))
    }

    private func drawChart(ctx: CGContext, size: CGSize, isDark: Bool = true) {
        guard data.count >= 2 else { return }
        let w = size.width, h = size.height
        let maxVal = fixedMax ?? max(data.max() ?? 1, 1.0)
        let stepX = w / CGFloat(data.count - 1)
        let scaleY = h / CGFloat(maxVal)

        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let mutedAlpha: CGFloat = highContrast ? 0.85 : (isDark ? 0.45 : 0.3)
        let gridAlpha: CGFloat = highContrast ? 0.3 : (isDark ? 0.08 : 0.06)
        let lineWidth: CGFloat = highContrast ? 2.0 : 1.5
        let muted = isDark ? NSColor.white.withAlphaComponent(mutedAlpha) : NSColor.black.withAlphaComponent(mutedAlpha)
        let gridColor = (isDark ? NSColor.white.withAlphaComponent(gridAlpha) : NSColor.black.withAlphaComponent(gridAlpha)).cgColor

        for pct in [0.25, 0.5, 0.75] {
            let y = h - CGFloat(maxVal * pct) / CGFloat(maxVal) * h
            ctx.setStrokeColor(gridColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: w, y: y))
            ctx.strokePath()
            if showAxis {
                let label = String(format: "%.0f", maxVal * pct)
                drawCGText(label, at: CGPoint(x: 2, y: y),
                           font: .monospacedDigitSystemFont(ofSize: 8, weight: .regular), color: muted, centered: false)
            }
        }

        let vStep = max(1, data.count / 6)
        for i in stride(from: 0, to: data.count, by: vStep) {
            let x = stepX * CGFloat(i)
            ctx.setStrokeColor(gridColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: h))
            ctx.strokePath()
        }

        ctx.saveGState()
        ctx.beginPath()
        smoothCurvePath(ctx: ctx, data: data.map { min($0, maxVal) }, stepX: stepX, scaleY: scaleY, height: h)
        ctx.addLine(to: CGPoint(x: stepX * CGFloat(data.count - 1), y: h))
        ctx.addLine(to: CGPoint(x: 0, y: h))
        ctx.closePath()
        ctx.clip()
        let gradColors = [color.ns.withAlphaComponent(0.2).cgColor, color.ns.withAlphaComponent(0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gradColors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        }
        ctx.resetClip()
        ctx.restoreGState()

        ctx.beginPath()
        smoothCurvePath(ctx: ctx, data: data.map { min($0, maxVal) }, stepX: stepX, scaleY: scaleY, height: h)
        ctx.setStrokeColor(color.cg)
        ctx.setLineWidth(lineWidth)
        ctx.strokePath()

        if showPeak, let maxValData = data.max(), maxValData > 0,
           let peakIdx = data.firstIndex(of: maxValData) {
            let px = stepX * CGFloat(peakIdx)
            let py = h - CGFloat(maxValData) / CGFloat(maxVal) * h
            ctx.setFillColor(color.cgColor ?? CGColor(gray: 0.5, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: px - 4, y: py - 4, width: 8, height: 8))
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
            ctx.fillEllipse(in: CGRect(x: px - 2, y: py - 2, width: 4, height: 4))
            let peakText = formatValue?(maxValData) ?? String(format: "%.1f%%", maxValData)
            drawCGText(peakText,
                       at: CGPoint(x: px, y: max(8, py - 10)),
                       font: .monospacedDigitSystemFont(ofSize: 8, weight: .bold),
                       color: color.ns.withAlphaComponent(0.9))
        }

        if let hx = hoverX,
           let idx = dataIndex(atX: hx, width: w, count: data.count),
           idx < data.count {
            let val = data[idx]
            let dotX = stepX * CGFloat(idx)
            let dotY = h - CGFloat(val) / CGFloat(maxVal) * h
            ctx.saveGState()
            ctx.setStrokeColor(color.ns.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(0.8)
            ctx.setLineDash(phase: 0, lengths: [3, 3])
            ctx.move(to: CGPoint(x: dotX, y: 0))
            ctx.addLine(to: CGPoint(x: dotX, y: h))
            ctx.move(to: CGPoint(x: 0, y: dotY))
            ctx.addLine(to: CGPoint(x: w, y: dotY))
            ctx.strokePath()
            ctx.restoreGState()
            ctx.setFillColor(color.cgColor ?? CGColor(gray: 0.5, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: dotX - 3, y: dotY - 3, width: 6, height: 6))
        }
    }
}
