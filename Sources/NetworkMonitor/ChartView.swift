import SwiftUI
import AppKit
import NetworkMonitorCore

// MARK: - CGContext Chart Engine (0 CVDisplayLink threads)

final class ChartHostView: NSView {
    override var isFlipped: Bool { true }
    var renderer: ((CGContext, CGSize, Bool) -> Void)?
    var isDark: Bool = true
    var onHover: ((CGFloat?, CGSize?) -> Void)?
    var dataFingerprint: Int = 0
    var hoverFingerprint: Int = -1
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let newArea = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        trackingArea = newArea
        addTrackingArea(newArea)
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        onHover?(loc.x, bounds.size)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(nil, nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        renderer?(ctx, bounds.size, isDark)
    }
}

struct ChartView: NSViewRepresentable {
    let renderer: (CGContext, CGSize, Bool) -> Void
    var hoverX: Binding<CGFloat?>? = nil
    var hoverSize: Binding<CGSize?>? = nil
    var dataFingerprint: Int = 0
    var hoverFingerprint: Int = -1

    func makeNSView(context: Context) -> ChartHostView {
        let v = ChartHostView()
        v.wantsLayer = true
        v.layer?.backgroundColor = .clear
        return v
    }

    func updateNSView(_ nsView: ChartHostView, context: Context) {
        let dark = context.environment.colorScheme == .dark
        let darkChanged = nsView.isDark != dark
        let dataChanged = nsView.dataFingerprint != dataFingerprint
        let hoverChanged = nsView.hoverFingerprint != hoverFingerprint
        nsView.isDark = dark
        nsView.dataFingerprint = dataFingerprint
        nsView.hoverFingerprint = hoverFingerprint
        nsView.onHover = { x, size in
            hoverX?.wrappedValue = x
            hoverSize?.wrappedValue = size
        }
        if darkChanged || dataChanged || hoverChanged {
            nsView.renderer = renderer
            nsView.needsDisplay = true
        }
    }
}

// MARK: - Color & text helpers for CGContext

extension Color {
    var cg: CGColor { NSColor(self).cgColor }
    var ns: NSColor { NSColor(self) }
}

func drawCGText(_ text: String, at point: CGPoint, font: NSFont, color: NSColor, centered: Bool = true) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color
    ]
    let size = (text as NSString).size(withAttributes: attrs)
    let drawPoint = centered
        ? CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        : point
    (text as NSString).draw(at: drawPoint, withAttributes: attrs)
}

// MARK: - CGContext smooth curve path

func smoothCurvePath(ctx: CGContext, data: [Double], stepX: CGFloat, scaleY: CGFloat, height: CGFloat) {
    let n = data.count
    guard n > 0 else { return }
    let pts = (0..<n).map { i in
        CGPoint(x: stepX * CGFloat(i), y: height - CGFloat(data[i]) * CGFloat(scaleY))
    }
    ctx.move(to: pts[0])
    guard n > 1 else { return }
    if n == 2 {
        ctx.addLine(to: pts[1])
        return
    }
    for i in 1..<n {
        let p0 = pts[max(0, i - 2)]
        let p1 = pts[i - 1]
        let p2 = pts[min(n - 1, i)]
        let p3 = pts[min(n - 1, i + 1)]
        let cp1y = max(0, min(height, p1.y + (p2.y - p0.y) / 6))
        let cp2y = max(0, min(height, p2.y - (p3.y - p1.y) / 6))
        ctx.addCurve(to: p2,
                     control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: cp1y),
                     control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: cp2y))
    }
}

func niceYAxisLabels(maxVal: Double) -> [Double] {
    guard maxVal > 0 else { return [] }
    let magnitude = pow(10, floor(log10(maxVal)))
    let normalized = maxVal / magnitude
    let niceMax: Double
    if normalized <= 1 { niceMax = 1 }
    else if normalized <= 2 { niceMax = 2 }
    else if normalized <= 5 { niceMax = 5 }
    else { niceMax = 10 }
    let rounded = niceMax * magnitude
    return [rounded * 0.25, rounded * 0.5, rounded * 0.75, rounded]
}

func dataIndex(atX x: CGFloat, width: CGFloat, count: Int) -> Int? {
    return chartDataIndex(atX: x, width: width, count: count)
}

// MARK: - GraphCanvas (used in GraphDetailView)

struct GraphCanvas: View {
    let data: [Double]
    let color: Color
    var showLabels: Bool = true
    var yUnit: DisplayUnit = .auto
    var times: [Date] = []

    var body: some View {
        let chartMax = speedChartMax(peak: data.max() ?? 0)
        ChartView(
            renderer: { ctx, size, isDark in
                let w = size.width
                let h = size.height
                guard data.count >= 2, w > 0, h > 0 else { return }

                let textColor = isDark ? NSColor.white.withAlphaComponent(0.5) : NSColor.black.withAlphaComponent(0.5)
                let gridColor = isDark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.08)

                let stepX = w / CGFloat(data.count - 1)
                let scaleY = h / CGFloat(chartMax)

                // Grid lines
                if showLabels {
                    let labels = niceYAxisLabels(maxVal: chartMax)
                    ctx.setStrokeColor(gridColor.cgColor)
                    ctx.setLineWidth(0.5)
                    for label in labels {
                        let y = h - CGFloat(label) * scaleY
                        ctx.move(to: CGPoint(x: 0, y: y))
                        ctx.addLine(to: CGPoint(x: w, y: y))
                        ctx.strokePath()
                        drawCGText(formatSpeed(label, unit: yUnit), at: CGPoint(x: 4, y: y - 2), font: NSFont.systemFont(ofSize: 9), color: textColor, centered: false)
                    }
                }

                // Fill
                ctx.saveGState()
                smoothCurvePath(ctx: ctx, data: data, stepX: stepX, scaleY: scaleY, height: h)
                ctx.addLine(to: CGPoint(x: w, y: h))
                ctx.addLine(to: CGPoint(x: 0, y: h))
                ctx.closePath()
                let fillAlpha: CGFloat = isDark ? 0.15 : 0.1
                ctx.setFillColor(color.ns.withAlphaComponent(fillAlpha).cgColor)
                ctx.fillPath()
                ctx.restoreGState()

                // Stroke
                ctx.saveGState()
                smoothCurvePath(ctx: ctx, data: data, stepX: stepX, scaleY: scaleY, height: h)
                ctx.setStrokeColor(color.ns.cgColor)
                ctx.setLineWidth(1.5)
                ctx.strokePath()
                ctx.restoreGState()
            },
            dataFingerprint: data.count
        )
    }
}
