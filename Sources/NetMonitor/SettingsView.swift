import NetMonitorCore
import SwiftUI
import Foundation
import AppKit

// MARK: - Thin scroller injection for SwiftUI ScrollView

class ScrollConfigView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        var current = superview
        while current != nil {
            if let scrollView = current as? NSScrollView {
                scrollView.borderType = .noBorder
                scrollView.automaticallyAdjustsContentInsets = false
                scrollView.contentInsets = NSEdgeInsetsZero
                scrollView.scrollerStyle = .overlay
                scrollView.verticalScroller = ThinScroller()
                break
            }
            current = current?.superview
        }
    }
}

struct ThinScrollConfig: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ScrollConfigView() }
    func updateNSView(_: NSView, context: Context) {}
}

enum GeneralCategory: String, CaseIterable, Identifiable {
    case display
    case floating
    case app
    case permissions

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .display: return L10n.tr("Display & Charts")
        case .floating: return L10n.tr("Floating Window")
        case .app: return L10n.tr("App")
        case .permissions: return L10n.tr("Permissions")
        }
    }

    var icon: String {
        switch self {
        case .display: return "rectangle.3.group"
        case .floating: return "pip"
        case .app: return "gearshape"
        case .permissions: return "lock.shield.fill"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State private var showWarningAlert = false
    @State private var selectedCategory: GeneralCategory = .display
    var floatingWindowManager: FloatingWindowManager?

    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }

    // MARK: - Visibility Check
    private var visibility: VisibilityHelper {
        VisibilityHelper(settings: settings)
    }

    private var hasMenuBarItem: Bool { visibility.hasMenuBarItem }
    private var hasFloatingWindowContent: Bool { visibility.hasFloatingWindowContent }
    private var hasAnyVisibleElement: Bool { visibility.hasAnyVisibleElement }

    private var versionText: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
        return Text("NetMonitor v\(version)")
            .font(.system(size: 10))
            .foregroundColor(theme.textMuted.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Spacing.sm)
            .padding(.bottom, 8)
    }

    private func canDisable(_ element: String) -> Bool {
        visibility.canDisable(element)
    }

    var body: some View {
        generalSettings
        .background(theme.appBg)
    }

    private var generalSettings: some View {
        HStack(spacing: 0) {
            categorySidebar
            Divider()
            categoryDetail
        }
        .alert(L10n.tr("Need Visible Element"), isPresented: $showWarningAlert) {
            Button(L10n.tr("OK")) {}
        } message: {
            Text(L10n.tr("Need Visible Element Message"))
        }
    }

    // MARK: - 通用分类侧边栏

    private var categorySidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(GeneralCategory.allCases) { cat in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedCategory = cat }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: cat.icon)
                            .font(.system(size: 12))
                            .frame(width: 18)
                        Text(cat.displayName)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(selectedCategory == cat ? Color.downloadColor.opacity(0.15) : Color.clear)
                    .foregroundColor(selectedCategory == cat ? .downloadColor : theme.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(width: 150)
    }

    private var categoryDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                switch selectedCategory {
                case .display: displaySection
                case .floating: floatingWindowSection
                case .app: appSection
                case .permissions: PermissionsView()
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var displaySection: some View {
        VStack(spacing: Spacing.lg) {
            menuBarSection
            processSection
            timeWindowSection
        }
    }

    @ViewBuilder
    private var appSection: some View {
        VStack(spacing: Spacing.lg) {
            dockSection
            startupSection
            updatesSection
        }
    }

    private var menuBarSection: some View {
        settingsSection(L10n.tr("Menu Bar Items"), textColor: theme.textMuted) {
                ForEach(Array(settings.menuBarOrder.enumerated()), id: \.element) { idx, itemId in
                    HStack(spacing: 8) {
                        // Two separate sort buttons
                        Button { settings.moveMenuItemUp(idx) } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 26, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(idx > 0 ? theme.textSecondary : theme.textMuted.opacity(0.2))
                        .disabled(idx == 0)
                        .background(theme.textMuted.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.textMuted.opacity(0.10), lineWidth: 0.5))
                        .accessibilityLabel("\(L10n.tr("Move Up")) \(settings.menuBarItemLabel(itemId))")

                        Button { settings.moveMenuItemDown(idx) } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 26, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(idx < settings.menuBarOrder.count - 1 ? theme.textSecondary : theme.textMuted.opacity(0.2))
                        .disabled(idx == settings.menuBarOrder.count - 1)
                        .background(theme.textMuted.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.textMuted.opacity(0.10), lineWidth: 0.5))
                        .accessibilityLabel("\(L10n.tr("Move Down")) \(settings.menuBarItemLabel(itemId))")

                        Image(systemName: settings.menuBarItemIcon(itemId))
                            .font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
                        Text(settings.menuBarItemLabel(itemId))
                            .font(.system(size: 12)).foregroundColor(theme.textSecondary)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { settings.bindingForMenuToggle(itemId).wrappedValue },
                            set: { newValue in
                                if !newValue && !canDisable("menuBar") {
                                    showWarningAlert = true
                                    return
                                }
                                settings.bindingForMenuToggle(itemId).wrappedValue = newValue
                            }
                        ))
                        .toggleStyle(.switch).controlSize(.small).accessibilityLabel(settings.menuBarItemLabel(itemId))
                    }
                    .padding(.vertical, 6)
                }
            }

    }

    private var processSection: some View {
        settingsSection(L10n.tr("Process Monitor"), textColor: theme.textMuted) {
                HStack {
                    Image(systemName: "app.badge").font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
                    Text(L10n.tr("Show Top Processes")).font(.system(size: 12)).foregroundColor(theme.textSecondary)
                    Spacer()
                    Toggle("", isOn: $settings.menuShowTopProcesses)
                        .toggleStyle(.switch).controlSize(.small).accessibilityLabel(L10n.tr("Show Top Processes"))
                }
                HStack {
                    Image(systemName: "number").font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
                    Text(L10n.tr("Process Count")).font(.system(size: 12)).foregroundColor(theme.textSecondary)
                    Spacer()
                    Picker("", selection: $settings.menuTopProcessesCount) {
                        Text("3").tag(3)
                        Text("5").tag(5)
                        Text("8").tag(8)
                        Text("10").tag(10)
                    }
                    .pickerStyle(.menu).frame(width: 60)
                    .disabled(!settings.menuShowTopProcesses)
                    .opacity(settings.menuShowTopProcesses ? 1.0 : 0.4)
                }
            }

    }

    private var timeWindowSection: some View {
        settingsSection(L10n.tr("Time Window"), textColor: theme.textMuted) {
                HStack {
                    Image(systemName: "clock").font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
                    Text(L10n.tr("Chart Time Window")).font(.system(size: 12)).foregroundColor(theme.textSecondary)
                    Spacer()
                    Picker("", selection: $appState.historySeconds) {
                        Text(L10n.tr("30 seconds")).tag(30)
                        Text(L10n.tr("1 minute")).tag(60)
                        Text(L10n.tr("2 minutes")).tag(120)
                        Text(L10n.tr("3 minutes")).tag(180)
                        Text(L10n.tr("5 minutes")).tag(300)
                        Text(L10n.tr("10 minutes")).tag(600)
                    }
                    .pickerStyle(.menu).frame(width: 100)
                }
            }

    }

    private var dockSection: some View {
        settingsSection(L10n.tr("Dock"), textColor: theme.textMuted) {
                HStack {
                    Image(systemName: "menubar.dock.rectangle").font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
                    Text(L10n.tr("Show Dock Icon")).font(.system(size: 12)).foregroundColor(theme.textSecondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settings.showDockIcon },
                        set: { newValue in
                            if !newValue && !canDisable("dock") {
                                showWarningAlert = true
                                return
                            }
                            settings.showDockIcon = newValue
                            NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                        }
                    ))
                    .toggleStyle(.switch).controlSize(.small).accessibilityLabel(L10n.tr("Show Dock Icon"))
                }
            }

    }

    private var floatingWindowSection: some View {
        settingsSection(L10n.tr("Floating Window"), textColor: theme.textMuted) {
                HStack {
                    Image(systemName: "pip").font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
                    Text(L10n.tr("Enable Floating Window")).font(.system(size: 12)).foregroundColor(theme.textSecondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settings.showFloatingWindow },
                        set: { newValue in
                            if !newValue && !canDisable("floating") {
                                showWarningAlert = true
                                return
                            }
                            settings.showFloatingWindow = newValue
                            if newValue {
                                floatingWindowManager?.update()
                            } else {
                                floatingWindowManager?.hidePanel()
                            }
                        }
                    ))
                    .toggleStyle(.switch).controlSize(.small).accessibilityLabel(L10n.tr("Enable Floating Window"))
                }
                HStack {
                    Image(systemName: "speedometer").font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
                    Text(L10n.tr("Show Speed")).font(.system(size: 12)).foregroundColor(theme.textSecondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settings.floatShowSpeed },
                        set: { newValue in
                            if !newValue && !canDisable("floatingContent") {
                                showWarningAlert = true
                                return
                            }
                            settings.floatShowSpeed = newValue
                            floatingWindowManager?.update()
                        }
                    ))
                    .toggleStyle(.switch).controlSize(.small).accessibilityLabel(L10n.tr("Show Speed"))
                    .disabled(!settings.showFloatingWindow)
                    .opacity(settings.showFloatingWindow ? 1.0 : 0.4)
                }
                HStack {
                    Image(systemName: "chart.pie.fill").font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
                    Text(L10n.tr("Show Traffic")).font(.system(size: 12)).foregroundColor(theme.textSecondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settings.floatShowTraffic },
                        set: { newValue in
                            if !newValue && !canDisable("floatingContent") {
                                showWarningAlert = true
                                return
                            }
                            settings.floatShowTraffic = newValue
                            floatingWindowManager?.update()
                        }
                    ))
                    .toggleStyle(.switch).controlSize(.small).accessibilityLabel(L10n.tr("Show Traffic"))
                    .disabled(!settings.showFloatingWindow)
                    .opacity(settings.showFloatingWindow ? 1.0 : 0.4)
                }
                HStack {
                    Image(systemName: "cpu").font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
                    Text(L10n.tr("Show CPU")).font(.system(size: 12)).foregroundColor(theme.textSecondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settings.floatShowCPU },
                        set: { newValue in
                            if !newValue && !canDisable("floatingContent") {
                                showWarningAlert = true
                                return
                            }
                            settings.floatShowCPU = newValue
                            floatingWindowManager?.update()
                        }
                    ))
                    .toggleStyle(.switch).controlSize(.small).accessibilityLabel(L10n.tr("Show CPU"))
                    .disabled(!settings.showFloatingWindow)
                    .opacity(settings.showFloatingWindow ? 1.0 : 0.4)
                }
                HStack {
                    Image(systemName: "display").font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
                    Text(L10n.tr("Show GPU")).font(.system(size: 12)).foregroundColor(theme.textSecondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settings.floatShowGPU },
                        set: { newValue in
                            if !newValue && !canDisable("floatingContent") {
                                showWarningAlert = true
                                return
                            }
                            settings.floatShowGPU = newValue
                            floatingWindowManager?.update()
                        }
                    ))
                    .toggleStyle(.switch).controlSize(.small).accessibilityLabel(L10n.tr("Show GPU"))
                    .disabled(!settings.showFloatingWindow)
                    .opacity(settings.showFloatingWindow ? 1.0 : 0.4)
                }
                HStack {
                    Image(systemName: "memorychip").font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
                    Text(L10n.tr("Show Memory")).font(.system(size: 12)).foregroundColor(theme.textSecondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settings.floatShowMemory },
                        set: { newValue in
                            if !newValue && !canDisable("floatingContent") {
                                showWarningAlert = true
                                return
                            }
                            settings.floatShowMemory = newValue
                            floatingWindowManager?.update()
                        }
                    ))
                    .toggleStyle(.switch).controlSize(.small).accessibilityLabel(L10n.tr("Show Memory"))
                    .disabled(!settings.showFloatingWindow)
                    .opacity(settings.showFloatingWindow ? 1.0 : 0.4)
                }
                HStack {
                    Image(systemName: "hand.tap").font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
                    Text(L10n.tr("Double-click floating window")).font(.system(size: 12)).foregroundColor(theme.textSecondary)
                    Spacer()
                    Picker("", selection: $settings.floatDoubleClickActionRaw) {
                        Text(L10n.tr("Open Settings")).tag(FloatDoubleClickAction.settings.rawValue)
                        Text(L10n.tr("Traffic Stats")).tag(FloatDoubleClickAction.trafficStats.rawValue)
                    }
                    .pickerStyle(.menu).frame(width: 100)
                    .disabled(!settings.showFloatingWindow)
                    .opacity(settings.showFloatingWindow ? 1.0 : 0.4)
                }
                HStack {
                    Image(systemName: "thermometer").font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
                    Text(L10n.tr("Show Temperature")).font(.system(size: 12)).foregroundColor(theme.textSecondary)
                    Spacer()
                    Toggle("", isOn: $settings.floatShowTemp)
                        .toggleStyle(.switch).controlSize(.small)
                        .accessibilityLabel(L10n.tr("Show Temperature"))
                        .disabled(!settings.showFloatingWindow)
                        .opacity(settings.showFloatingWindow ? 1.0 : 0.4)
                }
                HStack {
                    Image(systemName: "square.dashed").font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
                    Text(L10n.tr("Show Border")).font(.system(size: 12)).foregroundColor(theme.textSecondary)
                    Spacer()
                    Toggle("", isOn: $settings.floatShowBorder)
                        .toggleStyle(.switch).controlSize(.small)
                        .accessibilityLabel(L10n.tr("Show Border"))
                        .disabled(!settings.showFloatingWindow)
                        .opacity(settings.showFloatingWindow ? 1.0 : 0.4)
                }
                HStack {
                    Image(systemName: "circle.lefthalf.filled").font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
                    Text(L10n.tr("Opacity")).font(.system(size: 12)).foregroundColor(theme.textSecondary)
                    Spacer()
                    Slider(value: $settings.floatOpacity, in: 0.3...1.0)
                        .frame(width: 140)
                        .disabled(!settings.showFloatingWindow)
                        .opacity(settings.showFloatingWindow ? 1.0 : 0.4)
                }
            }

    }

    private var startupSection: some View {
        settingsSection(L10n.tr("Startup"), textColor: theme.textMuted) {
                HStack {
                    Image(systemName: "power").font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
                    Text(L10n.tr("Launch at Login")).font(.system(size: 12)).foregroundColor(theme.textSecondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { newValue in
                            settings.launchAtLogin = newValue
                            if !LoginItemManager.setEnabled(newValue) {
                                settings.launchAtLogin = !newValue
                            }
                        }
                    ))
                    .toggleStyle(.switch).controlSize(.small).accessibilityLabel(L10n.tr("Launch at Login"))
                }
            }
    }

    @ViewBuilder
    private var updatesSection: some View {
        settingsSection(L10n.tr("Updates"), textColor: theme.textMuted) {
                HStack {
                    Image(systemName: "arrow.down.circle").font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
                    Text("\(L10n.tr("Current Version")) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                        .font(.system(size: 12)).foregroundColor(theme.textSecondary)
                    Spacer()
                    Button(L10n.tr("Check for Updates")) {
                        Updater.shared.checkForUpdates()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

        versionText
    }
}

// MARK: - Settings Section

extension View {
    func settingsSection<Content: View>(_ title: String, textColor: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundColor(textColor)
                .padding(.horizontal, Spacing.md).padding(.top, Spacing.md).padding(.bottom, Spacing.sm)
            content().padding(.horizontal, Spacing.md).padding(.bottom, Spacing.md)
        }
        .card(.glass)
    }
}

// MARK: - Export Data Sheet
// MARK: - Permissions View
