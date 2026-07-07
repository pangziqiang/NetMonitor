import NetworkMonitorCore
import AppKit
import Combine
import os

@MainActor
class FloatingWindowManager {
    private let engine: NetworkMonitorEngine
    private let system: SystemMonitor
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var panel: NSPanel?
    private var hostingView: FloatingWindowView?
    private let onOpenSettings: (() -> Void)?
    private let onDoubleClick: (() -> Void)?
    private static let floatingWindowLevel = NSWindow.Level(rawValue: 103)

    init(engine: NetworkMonitorEngine, system: SystemMonitor, settings: AppSettings,
         onDoubleClick: (() -> Void)? = nil,
         onOpenSettings: (() -> Void)? = nil) {
        self.engine = engine
        self.system = system
        self.settings = settings
        self.onDoubleClick = onDoubleClick
        self.onOpenSettings = onOpenSettings
        setupObservation()
    }

    private func setupObservation() {
        // Speed data refresh — throttled to avoid excessive redraws
        engine.$currentDownSpeed
            .combineLatest(engine.$currentUpSpeed)
            .receive(on: DispatchQueue.main)
            .throttle(for: .seconds(2), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _, _ in
                self?.update()
            }
            .store(in: &cancellables)

        // Settings changes — immediate response (bypasses the throttle above)
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.update()
            }
            .store(in: &cancellables)
    }

    func update() {
        guard settings.showFloatingWindow else {
            hidePanel()
            return
        }
        // Check if there's any content to display
        let hasContent = settings.floatShowSpeed || settings.floatShowTraffic || 
                        settings.floatShowCPU || settings.floatShowGPU || settings.floatShowMemory
        guard hasContent else {
            hidePanel()
            return
        }
        showPanel()
    }

    func hidePanel() {
        panel?.orderOut(nil)
    }

    private func showPanel() {
        if panel == nil {
            createPanel()
        }
        guard let panel, let view = hostingView else { return }

        view.downSpeed = engine.currentDownSpeed
        view.upSpeed = engine.currentUpSpeed
        view.todayDown = engine.todayDown
        view.todayUp = engine.todayUp
        view.cpuUsage = system.cpuUsage
        view.gpuUsage = system.gpuUsage
        view.memoryUsage = system.memoryUsage
        view.cpuTemp = system.thermal.cpuTemperature
        view.gpuTemp = system.thermal.gpuTemperature
        view.memTemp = system.thermal.memoryTemperature

        view.showSpeed = settings.floatShowSpeed
        view.showTraffic = settings.floatShowTraffic
        view.showCPU = settings.floatShowCPU
        view.showGPU = settings.floatShowGPU
        view.showMemory = settings.floatShowMemory
        view.displayUnit = settings.displayUnit
        view.dataUnit = settings.dataUnit

        // Calculate and resize BEFORE drawing
        let requiredSize = view.calculateRequiredSize()
        let currentFrame = panel.frame
        if abs(currentFrame.width - requiredSize.width) > 1 || abs(currentFrame.height - requiredSize.height) > 1 {
            let newY = currentFrame.origin.y + currentFrame.height - requiredSize.height
            panel.setFrame(NSRect(x: currentFrame.origin.x, y: newY, width: requiredSize.width, height: requiredSize.height), display: true)
        }

        view.needsDisplay = true
        panel.orderFrontRegardless()
    }

    private func createPanel() {
        let view = FloatingWindowView(frame: NSRect(x: 0, y: 0, width: 240, height: 140))
        view.floatingWindowManager = self
        view.onDoubleClick = { [weak self] in self?.onDoubleClick?() }
        hostingView = view

        // Initial position: top-right corner
        guard let screen = NSScreen.main else {
            os_log(.error, log: OSLog(subsystem: AppConstants.logSubsystem, category: "Floating"), "NSScreen.main is nil, cannot create floating panel")
            return
        }
        let screenFrame = screen.visibleFrame
        let initialX = screenFrame.maxX - 260
        let initialY = screenFrame.maxY - 160

        let panel = FloatingPanel(
            contentRect: NSRect(x: initialX, y: initialY, width: 240, height: 140),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = Self.floatingWindowLevel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isMovableByWindowBackground = true
        panel.contentView = view

        self.panel = panel
    }

    @objc func closePanel() {
        settings.showFloatingWindow = false
        hidePanel()
    }

    func showContextMenu() {
        NSApp.activate()
        guard let panel = panel else { return }
        panel.makeKey()
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: L10n.tr("Floating Window Settings"),
                                      action: #selector(openSettings(_:)), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let closeItem = NSMenuItem(title: L10n.tr("Close Floating Window"),
                                   action: #selector(closeFloatingWindow(_:)), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)
        let savedLevel = panel.level
        panel.level = .floating
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        panel.level = savedLevel
        panel.orderFrontRegardless()
    }

    @objc private func openSettings(_ sender: Any?) {
        onOpenSettings?()
    }

    @objc private func closeFloatingWindow(_ sender: Any?) {
        closePanel()
    }
}

// MARK: - Floating Panel

private class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Floating Window View

private class FloatingWindowView: NSView {
    var downSpeed: Double = 0
    var upSpeed: Double = 0
    var todayDown: UInt64 = 0
    var todayUp: UInt64 = 0
    var cpuUsage: Double = 0
    var gpuUsage: Double = 0
    var memoryUsage: Double = 0
    var cpuTemp: Double?
    var gpuTemp: Double?
    var memTemp: Double?

    var showSpeed = true
    var showTraffic = true
    var showCPU = true
    var showGPU = true
    var showMemory = true
    var displayUnit: DisplayUnit = .auto
    var dataUnit: DataUnit = .auto

    weak var floatingWindowManager: FloatingWindowManager?
    var onDoubleClick: (() -> Void)?

    // MARK: - Color Constants
    private static let downloadColor = NSColor(red: 0x34/255.0, green: 0xd3/255.0, blue: 0x99/255.0, alpha: 1.0)
    private static let uploadColor = NSColor(red: 0x9d/255.0, green: 0x78/255.0, blue: 0xfc/255.0, alpha: 1.0)
    private static let cpuColor = NSColor(red: 0xfb/255.0, green: 0xbf/255.0, blue: 0x24/255.0, alpha: 1.0)
    private static let gpuColor = NSColor(red: 0x4e/255.0, green: 0x8c/255.0, blue: 0xf7/255.0, alpha: 1.0)
    private static let memoryColor = NSColor(red: 0x38/255.0, green: 0xdf/255.0, blue: 0xc4/255.0, alpha: 1.0)
    private static let textWhite = NSColor(white: 0.95, alpha: 1.0)
    private static let bgColor = NSColor(white: 0.1, alpha: 0.85)

    override var isFlipped: Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        floatingWindowManager?.showContextMenu()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        }
        super.mouseDown(with: event)
    }

    // MARK: - Accessibility

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func accessibilityLabel() -> String? { L10n.tr("Floating Window") }

    override func accessibilityValue() -> Any? {
        var parts: [String] = []
        if showSpeed {
            parts.append("\(L10n.tr("Download")) \(formatSpeed(downSpeed, unit: displayUnit))")
            parts.append("\(L10n.tr("Upload")) \(formatSpeed(upSpeed, unit: displayUnit))")
        }
        if showCPU { parts.append("CPU \(Int(cpuUsage))%") }
        if showGPU { parts.append("GPU \(Int(gpuUsage))%") }
        if showMemory { parts.append("MEM \(Int(memoryUsage))%") }
        return parts.joined(separator: ", ")
    }

    override func accessibilityChildren() -> [Any]? {
        var children: [Any] = []
        let rows = buildRows()
        for row in rows {
            let element = NSAccessibilityElement()
            element.setAccessibilityRole(.staticText)
            element.setAccessibilityLabel(row.text)
            element.setAccessibilityFrame(convert(bounds, to: nil))
            children.append(element)
        }
        return children
    }

    func calculateRequiredSize() -> CGSize {
        let rows = buildRows()

        guard !rows.isEmpty else { return CGSize(width: 160, height: 50) }

        let textFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let rowHeight: CGFloat = 24
        let padding: CGFloat = 10
        let iconWidth: CGFloat = 36

        var maxTextWidth: CGFloat = 0
        for row in rows {
            let textStr = NSAttributedString(string: row.text, attributes: [.font: textFont])
            maxTextWidth = max(maxTextWidth, textStr.size().width)
        }

        let width = max(padding + iconWidth + maxTextWidth + padding, 160)
        let height = max(padding + CGFloat(rows.count) * rowHeight + padding, 50)
        return CGSize(width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let rows = buildRows()
        guard !rows.isEmpty else { return }

        let iconFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        let textFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let rowHeight: CGFloat = 24
        let padding: CGFloat = 10
        let iconWidth: CGFloat = 36

        // Draw dark background
        let bgRect = bounds.insetBy(dx: 2, dy: 2)
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.addPath(bgPath)
        ctx.setFillColor(Self.bgColor.cgColor)
        ctx.fillPath()

        // Draw rows - centered vertically
        let totalContentHeight = CGFloat(rows.count) * rowHeight
        var y = max(padding, (bounds.height - totalContentHeight) / 2)

        for row in rows {
            let iconStr = NSAttributedString(string: row.icon, attributes: [
                .font: iconFont, .foregroundColor: row.iconColor
            ])
            let textStr = NSAttributedString(string: row.text, attributes: [
                .font: textFont, .foregroundColor: Self.textWhite
            ])

            let iconSize = iconStr.size()
            let textY = y + (rowHeight - iconSize.height) / 2

            iconStr.draw(at: NSPoint(x: padding, y: textY))
            textStr.draw(at: NSPoint(x: padding + iconWidth, y: textY))

            y += rowHeight
        }
    }

    private func buildRows() -> [(icon: String, iconColor: NSColor, text: String)] {
        var rows: [(icon: String, iconColor: NSColor, text: String)] = []

        if showSpeed {
            rows.append(("↓", Self.downloadColor, formatSpeed(downSpeed, unit: displayUnit)))
            rows.append(("↑", Self.uploadColor, formatSpeed(upSpeed, unit: displayUnit)))
        }

        if showTraffic {
            rows.append(("↓", Self.downloadColor, formatBytes(todayDown, dataUnit: dataUnit)))
            rows.append(("↑", Self.uploadColor, formatBytes(todayUp, dataUnit: dataUnit)))
        }

        if showCPU {
            let tempStr = cpuTemp.map { String(format: "  %.0f°C", $0) } ?? ""
            rows.append(("CPU", Self.cpuColor, "\(Int(cpuUsage))%" + tempStr))
        }

        if showGPU {
            let tempStr = gpuTemp.map { String(format: "  %.0f°C", $0) } ?? ""
            rows.append(("GPU", Self.gpuColor, "\(Int(gpuUsage))%" + tempStr))
        }

        if showMemory {
            let tempStr = memTemp.map { String(format: "  %.0f°C", $0) } ?? ""
            rows.append(("MEM", Self.memoryColor, "\(Int(memoryUsage))%" + tempStr))
        }

        return rows
    }
}
