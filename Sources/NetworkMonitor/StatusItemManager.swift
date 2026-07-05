import NetworkMonitorCore
import SwiftUI
import AppKit
import Combine

class MenuBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        var result = frameRect
        if let screen {
            result.origin.x = max(screen.visibleFrame.minX, min(result.origin.x, screen.visibleFrame.maxX - result.width))
            result.origin.y = max(screen.visibleFrame.minY, min(result.origin.y, screen.visibleFrame.maxY - result.height))
        }
        return result
    }
}

@MainActor
class StatusItemManager: NSObject {
    private var statusItem: NSStatusItem?
    private var popoverWindow: NSWindow?
    private var hostingView: NSHostingView<AnyView>?
    private var eventMonitor: Any?
    private var hostingController: NSHostingController<AnyView>?
    private var resizeTimer: Timer?

    let engine: NetworkMonitorEngine
    let system: SystemMonitor
    private let appState: AppState
    private let settings: AppSettings

    init(engine: NetworkMonitorEngine, system: SystemMonitor, appState: AppState, settings: AppSettings) {
        self.engine = engine
        self.system = system
        self.appState = appState
        self.settings = settings
        super.init()
    }

    func setup() {
        // Remove existing monitor if setup() is called again
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        // Clean up previous status item
        if let oldItem = statusItem {
            NSStatusBar.system.removeStatusItem(oldItem)
        }
        hostingView?.removeFromSuperview()
        hostingView = nil

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        let swiftUIView = StatusBarView(engine: engine, system: system, settings: settings)
        hostingView = NSHostingView(rootView: AnyView(swiftUIView))
        hostingView?.frame = CGRect(x: 0, y: 0, width: 1, height: 22)
        hostingView?.translatesAutoresizingMaskIntoConstraints = false
        guard let hostingView else { return }
        button.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
            hostingView.topAnchor.constraint(equalTo: button.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])

        // Support both left and right click on menu bar
        button.action = #selector(togglePopover)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Borderless panel — no title bar, no arrow, pure rounded rectangle
        let controller = NSHostingController(
            rootView: AnyView(MenuBarPopover(engine: engine, system: system, settings: settings)
                .environmentObject(appState))
        )
        hostingController = controller
        let panel = MenuBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 650),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.transient, .ignoresCycle, .moveToActiveSpace]
        panel.contentViewController = controller
        popoverWindow = panel
        PopoverManager.shared.panel = panel

        // Close panel when clicking outside (unless pinned)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak panel, weak self] _ in
            guard let panel, panel.isVisible else { return }
            guard let self, !PopoverManager.shared.isPinned else { return }
            panel.orderOut(nil)
            self.resizeTimer?.invalidate()
            self.resizeTimer = nil
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let panel = popoverWindow else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            resizeTimer?.invalidate()
            resizeTimer = nil
        } else {
            let buttonRect = button.convert(button.bounds, to: nil)
            guard let screenRect = button.window?.convertToScreen(buttonRect) else { return }
            let panelW: CGFloat = 400
            let contentHeight = measureContentHeight()
            let panelH = max(contentHeight, 400)
            let x = screenRect.midX - panelW / 2
            let y = screenRect.minY - panelH - 4
            PopoverManager.shared.hasMoved = false
            panel.setFrame(NSRect(x: x, y: y, width: panelW, height: panelH), display: true)
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate()
            startResizeTimer()
        }
    }

    private func measureContentHeight() -> CGFloat {
        guard let controller = hostingController else { return 650 }
        controller.view.layoutSubtreeIfNeeded()
        let size = controller.view.fittingSize
        return size.height
    }

    private func startResizeTimer() {
        resizeTimer?.invalidate()
        resizeTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.popoverWindow, panel.isVisible else {
                    self?.resizeTimer?.invalidate()
                    return
                }
                let newHeight = max(self.measureContentHeight(), 400)
                let frame = panel.frame
                guard abs(frame.height - newHeight) > 2 else { return }
                let newY = frame.origin.y + frame.height - newHeight
                panel.setFrame(NSRect(x: frame.origin.x, y: newY, width: frame.width, height: newHeight), display: true, animate: true)
            }
        }
    }

    func cleanup() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        resizeTimer?.invalidate()
        resizeTimer = nil
        popoverWindow?.orderOut(nil)
    }

    deinit {
        // Event monitor removal must happen; deinit runs on arbitrary thread
        // but NSEvent.removeMonitor is safe from any thread
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        resizeTimer?.invalidate()
    }
}

struct StatusBarView: View {
    @ObservedObject var engine: NetworkMonitorEngine
    @ObservedObject var system: SystemMonitor
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) var colorScheme
    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }

    var body: some View {
        HStack(spacing: 14) {
            ForEach(settings.menuBarOrder, id: \.self) { item in
                switch item {
                case "speed":
                    if settings.menuShowSpeed {
                        HStack(spacing: 5) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.downloadColor)
                                Text(shortSpeed(engine.currentDownSpeed))
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(.downloadColor)
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.uploadColor)
                                Text(shortSpeed(engine.currentUpSpeed))
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(.uploadColor)
                            }
                        }
                        .accessibilityLabel("\(L10n.tr("Network Speed")) \(L10n.tr("Download")) \(shortSpeed(engine.currentDownSpeed)) \(L10n.tr("Upload")) \(shortSpeed(engine.currentUpSpeed))")
                    }
                case "dailyTraffic":
                    if settings.menuShowDailyTraffic {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 11))
                                .foregroundColor(theme.textSecondary)
                            Text(formatBytes(engine.todayDown + engine.todayUp, dataUnit: settings.dataUnit))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(theme.textSecondary)
                        }
                        .accessibilityLabel("\(L10n.tr("Today Traffic Short")) \(formatBytes(engine.todayDown + engine.todayUp, dataUnit: settings.dataUnit))")
                    }
                case "cpu":
                    if settings.menuShowCPU {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.system(size: 11))
                                .foregroundColor(.cpuColor)
                            Text("\(String(format: "%.0f", system.cpuUsage))%")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.cpuColor)
                        }
                        .accessibilityLabel("\(L10n.tr("CPU Usage")) \(String(format: "%.0f", system.cpuUsage))%")
                    }
                case "gpu":
                    if settings.menuShowGPU {
                        HStack(spacing: 4) {
                            Image(systemName: "display")
                                .font(.system(size: 11))
                                .foregroundColor(.gpuColor)
                            Text("\(String(format: "%.0f", system.gpuUsage))%")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.gpuColor)
                        }
                        .accessibilityLabel("\(L10n.tr("GPU Usage")) \(String(format: "%.0f", system.gpuUsage))%")
                    }
                case "memory":
                    if settings.menuShowMemory {
                        HStack(spacing: 4) {
                            Image(systemName: "memorychip")
                                .font(.system(size: 11))
                                .foregroundColor(.memoryColor)
                            Text("\(String(format: "%.0f", system.memoryUsage))%")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.memoryColor)
                        }
                        .accessibilityLabel("\(L10n.tr("Memory Usage")) \(String(format: "%.0f", system.memoryUsage))%")
                    }
                default:
                    EmptyView()
                }
            }
        }
        .fixedSize()
    }
}

