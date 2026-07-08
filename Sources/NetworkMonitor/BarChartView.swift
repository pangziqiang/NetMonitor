import NetworkMonitorCore
import SwiftUI
import AppKit

// MARK: - Design Config (from chart-design-params.json, DO NOT MODIFY)

struct BarChartConfig {
    let barGap: CGFloat = 16
    let barOff: CGFloat = 10
    let barR: CGFloat = 2
    let barW: CGFloat = 38
    let cH: CGFloat = 200
    let statsH: CGFloat = 60
    let showY: Bool = false
    let yW: CGFloat = 48
    let yTicks: Int = 5
    let xS1: CGFloat = 12
    let xS2: CGFloat = 10
    let xPad: CGFloat = 5
    let xGap: CGFloat = 3
    let autoFS: Bool = false
    let fsMax: CGFloat = 12
    let manFS: CGFloat = 12
    let vg: CGFloat = 2
    let pW: CGFloat = 1320

    static let shared = BarChartConfig()
}

// MARK: - Data Model

struct BarChartPage {
    let dn: [UInt64]
    let up: [UInt64]
    let l1: [String]
    let l2: [String]
    let fut: (Int) -> Bool
    let hasData: (Int) -> Bool
    let title: String
    let s1: UInt64
    let s2: UInt64
    let a1: Double
    let a2: Double
}

// MARK: - niceMax Algorithm

func barNiceMax(_ arr: [UInt64]) -> Double {
    let p = Double(arr.max() ?? 1) * 1.2
    let m = pow(10, floor(log10(p)))
    let n = p / m
    return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * m
}

// MARK: - Byte Formatter (matches JS fmt)

func barFormatBytes(_ b: UInt64) -> String {
    if b == 0 { return "0" }
    if b < 1024 { return "\(b)B" }
    if b < 1048576 { return "\(b / 1024)KB" }
    if b < 1073741824 { return String(format: "%.1fMB", Double(b) / 1048576.0) }
    return String(format: "%.2fGB", Double(b) / 1073741824.0)
}

// MARK: - Speed Formatter (matches JS fmtS)

func barFormatSpeed(_ b: Double) -> String {
    if b <= 0 { return "0 KB/s" }
    let kb = b / 1024.0
    if kb < 1024 { return "\(Int(kb))KB/s" }
    return String(format: "%.1fMB/s", kb / 1024.0)
}

// MARK: - Bar Chart Renderer

struct BarChartRenderer: View {
    let data: [UInt64]
    let color: Color
    let labels1: [String]
    let labels2: [String]
    let isFuture: (Int) -> Bool
    let hasData: (Int) -> Bool
    let sharedMax: Double
    let config: BarChartConfig

    @Environment(\.colorScheme) var colorScheme

    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // chart-name
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(color == .downloadColor ? L10n.tr("Download Traffic") : L10n.tr("Upload Traffic"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.53))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)

            // chart-body: [yaxis] + plot
            HStack(alignment: .top, spacing: 0) {
                if config.showY { yAxisView }
                plotAreaView
            }
        }
    }

    // MARK: - Y Axis

    private var yAxisView: some View {
        VStack(spacing: 0) {
            ForEach(0..<config.yTicks, id: \.self) { i in
                let val = sharedMax * Double(config.yTicks - 1 - i) / Double(config.yTicks - 1)
                Text(barFormatBytes(UInt64(val)))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.3))
                    .frame(height: config.cH / CGFloat(config.yTicks - 1), alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(width: config.yW)
        .padding(.trailing, 4)
    }

    // MARK: - Plot Area (plot-area with border-left + border-bottom)

    private var plotAreaView: some View {
        barsCanvas
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1),
                alignment: .leading
            )
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1),
                alignment: .bottom
            )
    }

    // MARK: - Bars + Labels Canvas (all drawn in one Canvas for perfect alignment)

    private var barsCanvas: some View {
        let labelH: CGFloat = 30
        let totalH = config.cH + config.xPad + labelH
        return Canvas { ctx, size in
            let n = data.count
            guard n > 0 else { return }

            // Grid horizontal
            for gt in 1..<config.yTicks {
                let y = config.cH * CGFloat(gt) / CGFloat(config.yTicks - 1)
                var hPath = Path()
                hPath.move(to: CGPoint(x: 0, y: y))
                hPath.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(hPath, with: .color(Color.white.opacity(0.06)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
            }

            // Grid vertical (centered in gap between bars)
            if n > 1 {
                for i in 1..<n {
                    let x1 = config.barOff + CGFloat(i - 1) * (config.barW + config.barGap) + config.barW
                    let x2 = config.barOff + CGFloat(i) * (config.barW + config.barGap)
                    let x = (x1 + x2) / 2
                    var vPath = Path()
                    vPath.move(to: CGPoint(x: x, y: 0))
                    vPath.addLine(to: CGPoint(x: x, y: config.cH))
                    ctx.stroke(vPath, with: .color(Color.white.opacity(0.05)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
                }
            }

            // Bars + value labels + x labels
            for i in 0..<n {
                let val = data[i]
                let isFut = isFuture(i)
                let x = config.barOff + CGFloat(i) * (config.barW + config.barGap)
                let centerX = x + config.barW / 2
                let pct = sharedMax > 0 ? Double(val) / sharedMax : 0
                let hPx: CGFloat = isFut ? 3 : CGFloat(pct) * config.cH
                let barY = config.cH - hPx

                // Value label above bar (only if has data)
                if !isFut && hasData(i) {
                    let valStr = barFormatBytes(val)
                    let fs = config.autoFS ? max(8, min(config.fsMax, round(config.barW * 0.4))) : config.manFS
                    let text = Text(valStr)
                        .font(.system(size: fs, weight: .semibold, design: .monospaced))
                        .foregroundColor(color)
                    let resolved = ctx.resolve(text)
                    ctx.draw(resolved, at: CGPoint(x: centerX, y: barY - config.vg - 7), anchor: .center)
                }

                // Bar rect
                let barRect = CGRect(x: x, y: barY, width: config.barW, height: hPx)
                let barPath = Path(roundedRect: barRect, cornerSize: CGSize(width: config.barR, height: config.barR))
                ctx.fill(barPath, with: .color(isFut ? Color.white.opacity(0.04) : color))

                // X label (primary)
                let labelY = config.cH + config.xPad + 8
                let l1Text = Text(l1Safe(i))
                    .font(.system(size: config.xS1))
                    .foregroundColor(Color.white.opacity(isFut ? 0.2 : 0.5))
                let l1Resolved = ctx.resolve(l1Text)
                ctx.draw(l1Resolved, at: CGPoint(x: centerX, y: labelY), anchor: .center)

                // X label (secondary)
                let l2 = l2Safe(i)
                if !l2.isEmpty {
                    let l2Text = Text(l2)
                        .font(.system(size: config.xS2))
                        .foregroundColor(Color.white.opacity(isFut ? 0.1 : 0.4))
                    let l2Resolved = ctx.resolve(l2Text)
                    ctx.draw(l2Resolved, at: CGPoint(x: centerX, y: labelY + config.xS1 + config.xGap), anchor: .center)
                }
            }
        }
        .frame(width: config.barOff * 2 + config.barW * CGFloat(data.count) + config.barGap * CGFloat(max(data.count - 1, 0)), height: totalH)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func l1Safe(_ i: Int) -> String {
        i < labels1.count ? labels1[i] : ""
    }

    private func l2Safe(_ i: Int) -> String {
        i < labels2.count ? labels2[i] : ""
    }
}
