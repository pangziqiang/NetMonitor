import AppKit

class ThinScroller: NSScroller {
    override func draw(_ dirtyRect: NSRect) {
        // Don't call super.draw to avoid drawing default scroller
        let barRect = rect(for: .knob)
        guard barRect.width > 0 && barRect.height > 0 else { return }
        let pill = NSBezierPath(roundedRect: barRect, xRadius: 4, yRadius: 4)
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (isDark ? NSColor.white.withAlphaComponent(0.3) : NSColor.black.withAlphaComponent(0.2)).setFill()
        pill.fill()
    }
}
