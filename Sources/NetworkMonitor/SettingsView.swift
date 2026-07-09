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
    case permissions
    var displayName: String {
        switch self {
        case .general: return L10n.tr("General")
        case .permissions: return L10n.tr("Permissions")
        }
    }
    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .permissions: return "lock.shield.fill"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State private var showWarningAlert = false
    var floatingWindowManager: FloatingWindowManager?

    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }

    // MARK: - Visibility Check
    private var visibility: VisibilityHelper {
        VisibilityHelper(settings: settings)
    }

    private var hasMenuBarItem: Bool { visibility.hasMenuBarItem }
    private var hasFloatingWindowContent: Bool { visibility.hasFloatingWindowContent }
    private var hasAnyVisibleElement: Bool { visibility.hasAnyVisibleElement }

    private func canDisable(_ element: String) -> Bool {
        visibility.canDisable(element)
    }

    private func exportDiagnostics() {
        let json = DatabaseManager.shared?.exportDiagnostics() ?? "{}"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let safeDate = safeFilenameDate()
        panel.nameFieldStringValue = "NetMonitor-diagnostic-\(safeDate).json"
        panel.title = L10n.tr("Export Diagnostics")
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try json.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                LogService.error("diagnostics_export_failed", detail: error.localizedDescription)
            }
            LogService.log(.userAction, event: "diagnostics_exported")
        }
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
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    PermissionsView()
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
                .padding(.top, Spacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(theme.appBg)
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
            }

            settingsSection(L10n.tr("Diagnostics"), textColor: theme.textMuted) {
                Button {
                    exportDiagnostics()
                } label: {
                    HStack {
                        Image(systemName: "doc.badge.arrow.up").font(.system(size: 12)).foregroundColor(theme.textMuted).frame(width: 20)
                        Text(L10n.tr("Export Diagnostics")).font(.system(size: 12)).foregroundColor(theme.textSecondary)
                        Spacer()
                        Image(systemName: "square.and.arrow.up").font(.system(size: 11)).foregroundColor(theme.textMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("Export Diagnostics"))
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

// MARK: - Export Data Sheet
// MARK: - Permissions View
