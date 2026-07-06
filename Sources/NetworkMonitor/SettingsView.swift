import NetworkMonitorCore
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

enum SettingsTab: String, CaseIterable {
    case general
    case history
    case permissions
    var displayName: String {
        switch self {
        case .general: return L10n.tr("General")
        case .history: return L10n.tr("Traffic Statistics")
        case .permissions: return L10n.tr("Permissions")
        }
    }
    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .history: return "chart.bar.fill"
        case .permissions: return "lock.shield.fill"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State private var showWarningAlert = false
    @State private var cachedVisibility: VisibilityHelper?
    var floatingWindowManager: FloatingWindowManager?

    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }

    // MARK: - Visibility Check
    private var visibility: VisibilityHelper {
        if let cached = cachedVisibility { return cached }
        let v = VisibilityHelper(settings: settings)
        cachedVisibility = v
        return v
    }

    private var hasMenuBarItem: Bool { visibility.hasMenuBarItem }
    private var hasFloatingWindowContent: Bool { visibility.hasFloatingWindowContent }
    private var hasAnyVisibleElement: Bool { visibility.hasAnyVisibleElement }

    private func canDisable(_ element: String) -> Bool {
        visibility.canDisable(element)
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsTabBar.padding(.top, 20).padding(.horizontal, 20)
            if appState.settingsTab == .general {
                VStack(alignment: .leading, spacing: 0) {
                    generalSettings
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
                .padding(.top, Spacing.md)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else if appState.settingsTab == .history {
                VStack(alignment: .leading, spacing: 0) {
                    HistoryView(unit: settings.displayUnit)
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
                .padding(.top, Spacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    PermissionsView()
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
                .padding(.top, Spacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background {
            ZStack {
                theme.appBg
                Color.clear.background(.regularMaterial)
            }
            .ignoresSafeArea()
        }
    }

    private var settingsTabBar: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                let isSelected = appState.settingsTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { appState.settingsTab = tab }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon).font(.system(size: 12))
                        Text(tab.displayName).font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(isSelected ? Color.downloadColor.opacity(0.15) : Color.clear)
                    .foregroundColor(isSelected ? .downloadColor : theme.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel(tab.displayName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer()
        }
    }

    private var generalSettings: some View {
        VStack(spacing: Spacing.lg) {
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

            settingsSection(L10n.tr("Unit"), textColor: theme.textMuted) {
                pickerRow(L10n.tr("Speed Unit"), icon: "speedometer", selection: $settings.displayUnitRaw, options: DisplayUnit.allCases)
                dataPickerRow(L10n.tr("Traffic Unit"), icon: "chart.pie.fill", selection: $settings.dataUnitRaw, options: DataUnit.allCases)
            }

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
            }

        }
        .alert(L10n.tr("Need Visible Element"), isPresented: $showWarningAlert) {
            Button(L10n.tr("OK")) {}
        } message: {
            Text(L10n.tr("Need Visible Element Message"))
        }
    }

    private func toggleRow(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
            Text(title).font(.system(size: 12)).foregroundColor(theme.textSecondary)
            Spacer()
            Toggle("", isOn: isOn).toggleStyle(.switch).controlSize(.small).accessibilityLabel(title)
        }
    }

    private func pickerRow(_ title: String, icon: String, selection: Binding<String>, options: [DisplayUnit]) -> some View {
        HStack {
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
            Text(title).font(.system(size: 12)).foregroundColor(theme.textSecondary)
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.rawValue) { opt in Text(opt.rawValue).tag(opt.rawValue) }
            }
            .pickerStyle(.menu).frame(width: 100)
        }
    }

    private func dataPickerRow(_ title: String, icon: String, selection: Binding<String>, options: [DataUnit]) -> some View {
        HStack {
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
            Text(title).font(.system(size: 12)).foregroundColor(theme.textSecondary)
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.rawValue) { opt in Text(opt.rawValue).tag(opt.rawValue) }
            }
            .pickerStyle(.menu).frame(width: 100)
        }
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

struct HistoryView: View {
    @State private var dailyData: [(date: String, down: UInt64, up: UInt64)] = []
    @Environment(\.colorScheme) var colorScheme
    var unit: DisplayUnit = .auto
    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }

    private var totalDown: UInt64 { dailyData.reduce(0) { $0 + $1.down } }
    private var totalUp: UInt64 { dailyData.reduce(0) { $0 + $1.up } }

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Summary cards
            HStack(spacing: Spacing.sm) {
                trafficSummaryCard(
                    icon: "arrow.up.circle.fill",
                    color: .uploadColor,
                    label: L10n.tr("Total Upload"),
                    value: formatBytes(totalUp, unit: unit)
                )
                trafficSummaryCard(
                    icon: "arrow.down.circle.fill",
                    color: .downloadColor,
                    label: L10n.tr("Total Download"),
                    value: formatBytes(totalDown, unit: unit)
                )
            }

            // Daily breakdown list
            if dailyData.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "chart.bar.xaxis").font(.title2).foregroundColor(theme.textMuted.opacity(0.4))
                    Text(L10n.tr("No Data")).font(.system(size: 12)).foregroundColor(theme.textMuted)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
                .card(.glass)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    // Header row
                    HStack {
                        Text(L10n.tr("Date"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(theme.textMuted)
                            .frame(width: 60, alignment: .leading)
                        Spacer()
                        HStack(spacing: 12) {
                            Text(L10n.tr("Upload"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.uploadColor)
                                .frame(width: 70, alignment: .trailing)
                            Text(L10n.tr("Download"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.downloadColor)
                                .frame(width: 70, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, Spacing.md).padding(.top, Spacing.md).padding(.bottom, Spacing.sm)

                    Divider().padding(.horizontal, Spacing.md)

                    // Data rows
                    ForEach(dailyData.indices, id: \.self) { i in
                        let item = dailyData[i]
                        HStack {
                            Text(String(item.date.suffix(5)))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(theme.textSecondary)
                                .frame(width: 60, alignment: .leading)
                            Spacer()
                            HStack(spacing: 12) {
                                Text(formatBytes(item.up, unit: unit))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.uploadColor)
                                    .frame(width: 70, alignment: .trailing)
                                Text(formatBytes(item.down, unit: unit))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.downloadColor)
                                    .frame(width: 70, alignment: .trailing)
                            }
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, Spacing.md)
                        if i < dailyData.count - 1 {
                            Divider().padding(.horizontal, Spacing.md)
                        }
                    }
                }
                .card(.glass)
            }

            // Clear database button
            Button {
                let alert = NSAlert()
                alert.messageText = L10n.tr("Clear DB Title")
                alert.informativeText = L10n.tr("Clear DB Message")
                alert.alertStyle = .warning
                alert.addButton(withTitle: L10n.tr("Clear All"))
                alert.addButton(withTitle: L10n.tr("Cancel"))
                if alert.runModal() == .alertFirstButtonReturn {
                    DatabaseManager.shared?.clearAllTraffic()
                    dailyData = []
                }
            } label: {
                HStack {
                    Image(systemName: "trash").font(.system(size: 12))
                    Text(L10n.tr("Clear Database")).font(.system(size: 12))
                    Spacer()
                }
            }
            .buttonStyle(.glass(.destructive))
            .accessibilityLabel(L10n.tr("Clear Database"))
        }
        .task { await loadData() }
    }

    private func trafficSummaryCard(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 16)).foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 11)).foregroundColor(theme.textMuted)
                Text(value).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundColor(color)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.12), lineWidth: 0.5))
    }

    @MainActor
    private func loadData() async {
        let daily = await Task.detached(priority: .userInitiated) {
            DatabaseManager.shared?.dailyTraffic(days: 7) ?? []
        }.value
        self.dailyData = daily
    }
}

// MARK: - Permissions View

struct PermissionsView: View {
    @State private var isAppleSilicon = false
    @Environment(\.colorScheme) var colorScheme
    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Architecture info
            settingsSection(L10n.tr("Current Device"), textColor: theme.textMuted) {
                HStack {
                    Image(systemName: isAppleSilicon ? "cpu" : "cpu.fill")
                        .font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
                    Text(isAppleSilicon ? L10n.tr("Apple Silicon") : L10n.tr("Intel"))
                        .font(.system(size: 12)).foregroundColor(theme.textSecondary)
                    Spacer()
                    Circle().fill(Color.statusActive).frame(width: 8, height: 8)
                }
            }

            // Permissions
            settingsSection(L10n.tr("System Permissions"), textColor: theme.textMuted) {
                permissionRow(
                    icon: "network", name: L10n.tr("Network Monitor"),
                    description: L10n.tr("Network Monitor Desc"),
                    granted: true
                )
                permissionRow(
                    icon: "pip", name: L10n.tr("Floating Window"),
                    description: L10n.tr("Floating Window Desc"),
                    granted: true
                )
            }
        }
        .onAppear {
            isAppleSilicon = ThermalMonitor.isAppleSilicon
        }
    }

    private func permissionRow(icon: String, name: String, description: String, granted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(granted ? .statusActive : theme.textMuted)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 12)).foregroundColor(theme.textSecondary)
                Text(description).font(.system(size: 10)).foregroundColor(theme.textMuted)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(granted ? Color.statusActive : Color.errorColor)
                    .frame(width: 7, height: 7)
                Text(granted ? L10n.tr("Authorized") : L10n.tr("Unauthorized"))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(granted ? .statusActive : .errorColor)
            }
        }
        .padding(.vertical, 4)
    }

}
