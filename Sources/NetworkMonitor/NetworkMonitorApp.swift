import NetworkMonitorCore
import SwiftUI
import AppKit
import os.log

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let engine = NetworkMonitorEngine()
    let system = SystemMonitor()
    let appState = AppState()
    let settings = AppSettings.shared
    var statusItemManager: StatusItemManager?
    var floatingWindowManager: FloatingWindowManager?
    static let openSettingsNotification = Notification.Name("OpenSettingsWindow")
    private var settingsWindow: NSWindow?
    private var settingsWindowObserver: NSObjectProtocol?
    private static let settingsWindowLevel = NSWindow.Level(rawValue: 102)
    private static let log = OSLog(subsystem: AppConstants.logSubsystem, category: "SettingsWindow")

    func applicationWillTerminate(_ notification: Notification) {
        LogService.log(.lifecycle, event: "app_terminating")
        statusItemManager?.cleanup()
        engine.stop()
        system.stop()
        DatabaseManager.shared?.flushPendingTrafficSync()
        if let obs = settingsWindowObserver {
            NotificationCenter.default.removeObserver(obs)
            settingsWindowObserver = nil
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LogService.log(.lifecycle, event: "app_launched", detail: "os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        engine.start()
        system.start()
        let mgr = StatusItemManager(engine: engine, system: system, appState: appState, settings: settings)
        mgr.setup()
        statusItemManager = mgr
        floatingWindowManager = FloatingWindowManager(engine: engine, system: system, settings: settings,
            onDoubleClick: { [weak self] in
                self?.appState.settingsTab = .general
                NotificationCenter.default.post(name: Self.openSettingsNotification, object: nil)
            }) {
            NotificationCenter.default.post(name: Self.openSettingsNotification, object: nil)
        }
        floatingWindowManager?.update()
        ensureVisibility()
        NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
        // Hide settings window if it appeared at launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.settingsWindow?.orderOut(nil)
        }
    }

    func setSettingsWindow(_ win: NSWindow?) {
        guard let win else { return }
        if settingsWindow !== win {
            settingsWindow = win
            win.delegate = self
            if let obs = settingsWindowObserver { NotificationCenter.default.removeObserver(obs) }
            let level = Self.settingsWindowLevel
            settingsWindowObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: win, queue: .main
            ) { n in
                guard let w = n.object as? NSWindow else { return }
                if w.level != level { w.level = level }
            }
        }
        if win.level != Self.settingsWindowLevel { win.level = Self.settingsWindowLevel }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }

    private func ensureVisibility() {
        let v = VisibilityHelper(settings: settings)
        if v.needsVisibilityRestore() { settings.menuShowSpeed = true }
        if settings.showFloatingWindow && !v.hasFloatingWindowContent { settings.floatShowSpeed = true }
    }
}

private struct SettingsWindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { [weak v] in self.onWindow(v?.window) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in self.onWindow(nsView?.window) }
    }
}

@main
struct NetworkMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window(L10n.tr("Settings"), id: "settings") {
            SettingsView(floatingWindowManager: appDelegate.floatingWindowManager)
                .environmentObject(appDelegate.appState)
                .environmentObject(appDelegate.settings)
                .frame(width: 400)
                .background(SettingsWindowAccessor { appDelegate.setSettingsWindow($0) })
                .onChange(of: appDelegate.appState.historySeconds) { _, n in
                    appDelegate.engine.historyMax = n
                    appDelegate.system.historyMax = n
                }
                .onReceive(NotificationCenter.default.publisher(for: AppDelegate.openSettingsNotification)) { _ in
                    openWindow(id: "settings")
                    NSApp.activate()
                }
        }
        .defaultSize(width: 400, height: 600)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu(L10n.tr("NetMonitor")) {
                Button(L10n.tr("Toggle Popover")) { appDelegate.statusItemManager?.togglePopover(nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .newItem) {}
            CommandMenu(L10n.tr("Monitor")) {
                Picker(L10n.tr("Time Window"), selection: Binding(
                    get: { appDelegate.appState.historySeconds },
                    set: { appDelegate.appState.historySeconds = $0 }
                )) {
                    Text(L10n.tr("30 seconds")).tag(30)
                    Text(L10n.tr("1 minute")).tag(60)
                    Text(L10n.tr("2 minutes")).tag(120)
                    Text(L10n.tr("3 minutes")).tag(180)
                    Text(L10n.tr("5 minutes")).tag(300)
                    Text(L10n.tr("10 minutes")).tag(600)
                }
                Divider()
                Toggle(L10n.tr("Show Dock Icon"), isOn: Binding(
                    get: { appDelegate.settings.showDockIcon },
                    set: { appDelegate.settings.showDockIcon = $0; NSApp.setActivationPolicy($0 ? .regular : .accessory) }
                ))
                Divider()
                Button(L10n.tr("Settings…")) { openWindow(id: "settings"); NSApp.activate() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appSettings) {}
            CommandGroup(replacing: .undoRedo) {
                Button(L10n.tr("Undo")) { NSApp.sendAction(#selector(UndoManager.undo), to: nil, from: nil) }.keyboardShortcut("z")
                Button(L10n.tr("Redo")) { NSApp.sendAction(#selector(UndoManager.redo), to: nil, from: nil) }.keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .pasteboard) {
                Button(L10n.tr("Cut")) { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }.keyboardShortcut("x")
                Button(L10n.tr("Copy")) { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }.keyboardShortcut("c")
                Button(L10n.tr("Paste")) { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }.keyboardShortcut("v")
            }
            CommandGroup(replacing: .textEditing) {
                Button(L10n.tr("Select All")) { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }.keyboardShortcut("a")
            }
            CommandMenu(L10n.tr("Window")) {
                Button(L10n.tr("Minimize")) { NSApp.keyWindow?.miniaturize(nil) }.keyboardShortcut("m")
                Button(L10n.tr("Zoom")) { NSApp.keyWindow?.zoom(nil) }
                Divider()
                Button(L10n.tr("Show All")) { NSApp.arrangeInFront(nil) }
            }
            CommandMenu(L10n.tr("Help")) {
                Button(L10n.tr("NetMonitor Help")) {
                    if let url = URL(string: AppConstants.helpURL) { NSWorkspace.shared.open(url) }
                }
            }
        }

        Window(L10n.tr("Traffic Graph Detail"), id: "graphDetail") {
            GraphDetailView(engine: appDelegate.engine, unit: appDelegate.settings.displayUnit)
                .environmentObject(appDelegate.appState).environmentObject(appDelegate.settings)
        }
        .defaultSize(width: 600, height: 520).windowResizability(.contentMinSize).windowStyle(.hiddenTitleBar)

        Window(L10n.tr("System Resource Detail"), id: "systemGraphDetail") {
            SystemGraphDetailView(system: appDelegate.system)
                .environmentObject(appDelegate.appState).environmentObject(appDelegate.settings)
        }
        .defaultSize(width: 600, height: 520).windowResizability(.contentMinSize).windowStyle(.hiddenTitleBar)
    }
}
