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
        panel.nameFieldStringValue = "NetMonitor-diagnostic-\(ISO8601DateFormatter().string(from: Date())).json"
        panel.title = L10n.tr("Export Diagnostics")
        if panel.runModal() == .OK, let url = panel.url {
            try? json.write(to: url, atomically: true, encoding: .utf8)
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

                Divider().padding(.vertical, 4)

                Button {
                    let alert = NSAlert()
                    alert.messageText = L10n.tr("Clear DB Title")
                    alert.informativeText = L10n.tr("Clear DB Message")
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: L10n.tr("Clear All"))
                    alert.addButton(withTitle: L10n.tr("Cancel"))
                    if alert.runModal() == .alertFirstButtonReturn {
                        DatabaseManager.shared?.clearAllTraffic()
                    }
                } label: {
                    HStack {
                        Image(systemName: "trash").font(.system(size: 12)).foregroundColor(.errorColor).frame(width: 20)
                        Text(L10n.tr("Clear Traffic Data")).font(.system(size: 12)).foregroundColor(.errorColor)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("Clear Traffic Data"))
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

enum HistoryTimeRange: String, CaseIterable {
    case today = "今日"
    case week = "本周"
    case month = "本月"
}

struct HistoryView: View {
    @State private var timeRange: HistoryTimeRange = .today
    @State private var hourlyData: [DatabaseManager.HourlyRecord] = []
    @State private var dailySummary: [(date: String, avgDown: Double, avgUp: Double, peakDown: UInt64, peakUp: UInt64, totalDown: UInt64, totalUp: UInt64)] = []
    @State private var weeklySummary: [(week: String, avgDown: Double, avgUp: Double, peakDown: UInt64, peakUp: UInt64, totalDown: UInt64, totalUp: UInt64)] = []
    @State private var showExportSheet = false
    @EnvironmentObject var settings: AppSettings
    @Environment(\.colorScheme) var colorScheme
    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }
    
    private static let cacheQueue = DispatchQueue(label: "com.opencode.historycache")
    private static var _hourlyCache: (timestamp: Date, data: [DatabaseManager.HourlyRecord])?
    private static var _dailyCache: (timestamp: Date, data: [(String, Double, Double, UInt64, UInt64, UInt64, UInt64)])?
    private static var _weeklyCache: (timestamp: Date, data: [(String, Double, Double, UInt64, UInt64, UInt64, UInt64)])?
    private static let cacheTTL: TimeInterval = 30

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Title + time range
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill").font(.system(size: 14))
                    Text(L10n.tr("Traffic Stats")).font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(theme.textPrimary)
                .lineLimit(1)
                Spacer()
                Picker("", selection: $timeRange) {
                    ForEach(HistoryTimeRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            // Main content: left sidebar + right data table
            HStack(alignment: .top, spacing: Spacing.lg) {
                // Left sidebar
                sidebarSummary
                    .frame(width: 180)

                // Right: data table
                dataTable
            }

            // Charts
            VStack(spacing: Spacing.md) {
                SpeedTrendChart(records: chartRecords, displayUnit: settings.displayUnit)
                TrafficBarChart(records: chartRecords, dataUnit: settings.dataUnit)
            }

            // Export button
            HStack {
                Spacer()
                Button {
                    showExportSheet = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 12))
                        Text(L10n.tr("Export Data")).font(.system(size: 12))
                    }
                }
                .buttonStyle(.glass(.primary))
                .frame(width: 160)
                .accessibilityLabel(L10n.tr("Export Data"))
                Spacer()
            }
        }
        .padding(20)
        .sheet(isPresented: $showExportSheet) {
            ExportDataSheet(isPresented: $showExportSheet, theme: theme)
        }
        .task { await loadData() }
        .onChange(of: timeRange) { _, _ in
            Task { await loadData() }
        }
    }

    private var chartRecords: [DatabaseManager.HourlyRecord] {
        switch timeRange {
        case .today: return hourlyData
        case .week: return dailySummaryToHourly(dailySummary)
        case .month: return weeklySummaryToHourly(weeklySummary)
        }
    }

    private func dailySummaryToHourly(_ data: [(date: String, avgDown: Double, avgUp: Double, peakDown: UInt64, peakUp: UInt64, totalDown: UInt64, totalUp: UInt64)]) -> [DatabaseManager.HourlyRecord] {
        data.map { d in
            DatabaseManager.HourlyRecord(
                hour: ISO8601Formatter.date(from: d.date + "T00:00:00.000Z") ?? Date(),
                avgDown: d.avgDown, avgUp: d.avgUp,
                peakDown: d.peakDown, peakUp: d.peakUp,
                totalDown: d.totalDown, totalUp: d.totalUp
            )
        }
    }

    private func weeklySummaryToHourly(_ data: [(week: String, avgDown: Double, avgUp: Double, peakDown: UInt64, peakUp: UInt64, totalDown: UInt64, totalUp: UInt64)]) -> [DatabaseManager.HourlyRecord] {
        data.map { d in
            DatabaseManager.HourlyRecord(
                hour: ISO8601Formatter.date(from: d.week + "T00:00:00.000Z") ?? Date(),
                avgDown: d.avgDown, avgUp: d.avgUp,
                peakDown: d.peakDown, peakUp: d.peakUp,
                totalDown: d.totalDown, totalUp: d.totalUp
            )
        }
    }

    private var sidebarSummary: some View {
        let totalD: UInt64
        let totalU: UInt64
        let avgD: Double
        let avgU: Double

        switch timeRange {
        case .today:
            totalD = hourlyData.reduce(0) { $0 + $1.totalDown }
            totalU = hourlyData.reduce(0) { $0 + $1.totalUp }
            avgD = hourlyData.map(\.avgDown).average
            avgU = hourlyData.map(\.avgUp).average
        case .week:
            totalD = dailySummary.reduce(0) { $0 + $1.totalDown }
            totalU = dailySummary.reduce(0) { $0 + $1.totalUp }
            avgD = dailySummary.map(\.avgDown).average
            avgU = dailySummary.map(\.avgUp).average
        case .month:
            totalD = weeklySummary.reduce(0) { $0 + $1.totalDown }
            totalU = weeklySummary.reduce(0) { $0 + $1.totalUp }
            avgD = weeklySummary.map(\.avgDown).average
            avgU = weeklySummary.map(\.avgUp).average
        }

        return VStack(alignment: .leading, spacing: 0) {
            sidebarRow(label: L10n.tr("Download"), value: formatBytes(totalD, dataUnit: settings.dataUnit), color: .downloadColor)
            sidebarDivider
            sidebarRow(label: L10n.tr("Upload"), value: formatBytes(totalU, dataUnit: settings.dataUnit), color: .uploadColor)
            sidebarDivider
            sidebarRow(label: L10n.tr("Avg Download"), value: formatSpeed(avgD, unit: settings.displayUnit), color: .downloadColor)
            sidebarDivider
            sidebarRow(label: L10n.tr("Avg Upload"), value: formatSpeed(avgU, unit: settings.displayUnit), color: .uploadColor)
        }
        .padding(12)
        .background(theme.textMuted.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sidebarRow(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(theme.textMuted)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.vertical, 10)
    }

    private var sidebarDivider: some View {
        Divider().opacity(0.15)
    }

    private var summaryCards: some View {
        let totalD: UInt64
        let totalU: UInt64
        let avgD: Double
        let avgU: Double
        let peakD: UInt64
        let peakU: UInt64
        let peakDTime: Date?
        let peakUTime: Date?

        switch timeRange {
        case .today:
            totalD = hourlyData.reduce(0) { $0 + $1.totalDown }
            totalU = hourlyData.reduce(0) { $0 + $1.totalUp }
            avgD = hourlyData.map(\.avgDown).average
            avgU = hourlyData.map(\.avgUp).average
            let peakDRecord = hourlyData.max(by: { $0.peakDown < $1.peakDown })
            let peakURecord = hourlyData.max(by: { $0.peakUp < $1.peakUp })
            peakD = peakDRecord?.peakDown ?? 0
            peakU = peakURecord?.peakUp ?? 0
            peakDTime = peakDRecord?.peakDownTime ?? peakDRecord?.hour
            peakUTime = peakURecord?.peakUpTime ?? peakURecord?.hour
        case .week:
            totalD = dailySummary.reduce(0) { $0 + $1.totalDown }
            totalU = dailySummary.reduce(0) { $0 + $1.totalUp }
            avgD = dailySummary.map(\.avgDown).average
            avgU = dailySummary.map(\.avgUp).average
            peakD = dailySummary.map(\.peakDown).max() ?? 0
            peakU = dailySummary.map(\.peakUp).max() ?? 0
            peakDTime = nil
            peakUTime = nil
        case .month:
            totalD = weeklySummary.reduce(0) { $0 + $1.totalDown }
            totalU = weeklySummary.reduce(0) { $0 + $1.totalUp }
            avgD = weeklySummary.map(\.avgDown).average
            avgU = weeklySummary.map(\.avgUp).average
            peakD = weeklySummary.map(\.peakDown).max() ?? 0
            peakU = weeklySummary.map(\.peakUp).max() ?? 0
            peakDTime = nil
            peakUTime = nil
        }

        return VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                summaryCard(icon: "arrow.up.circle.fill", color: .uploadColor, label: L10n.tr("Total Upload"), value: formatBytes(totalU, dataUnit: settings.dataUnit))
                summaryCard(icon: "arrow.down.circle.fill", color: .downloadColor, label: L10n.tr("Total Download"), value: formatBytes(totalD, dataUnit: settings.dataUnit))
            }
            HStack(spacing: Spacing.sm) {
                summaryCard(icon: "speedometer", color: .uploadColor, label: L10n.tr("Avg Upload"), value: formatSpeed(avgU, unit: settings.displayUnit))
                summaryCard(icon: "speedometer", color: .downloadColor, label: L10n.tr("Avg Download"), value: formatSpeed(avgD, unit: settings.displayUnit))
            }
            if timeRange == .today {
                HStack(spacing: Spacing.sm) {
                    peakCard(color: .uploadColor, label: L10n.tr("Peak Upload"), speed: Double(peakU), time: peakUTime)
                    peakCard(color: .downloadColor, label: L10n.tr("Peak Download"), speed: Double(peakD), time: peakDTime)
                }
            }
        }
    }

    private func summaryCard(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 10)).foregroundColor(theme.textMuted)
                Text(value).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundColor(color)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.12), lineWidth: 0.5))
    }

    private func peakCard(color: Color, label: String, speed: Double, time: Date?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.circle").font(.system(size: 14)).foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(label).font(.system(size: 10)).foregroundColor(theme.textMuted)
                    if let time {
                        Text("@\(formatPeakTime(time))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(theme.textMuted)
                    }
                }
                Text(formatSpeed(speed, unit: settings.displayUnit))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.12), lineWidth: 0.5))
    }

    private func formatPeakTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        switch timeRange {
        case .today: fmt.dateFormat = "HH:mm:ss"
        default: fmt.dateFormat = "MM/dd HH:mm"
        }
        return fmt.string(from: date)
    }

    private var dataTable: some View {
        let rows: [(String, String, String, String, String)]
        let headerTime: String

        switch timeRange {
        case .today:
            headerTime = L10n.tr("Hour")
            rows = hourlyData.map { r in
                let cal = Calendar.current
                let h = cal.component(.hour, from: r.hour)
                return ("\(String(format: "%02d:00", h))", formatSpeed(r.avgDown, unit: settings.displayUnit), formatSpeed(Double(r.peakDown), unit: settings.displayUnit), formatBytes(r.totalDown, dataUnit: settings.dataUnit), formatBytes(r.totalUp, dataUnit: settings.dataUnit))
            }
        case .week:
            headerTime = L10n.tr("Date")
            rows = dailySummary.map { d in
                (String(d.date.suffix(5)), formatSpeed(d.avgDown, unit: settings.displayUnit), formatSpeed(Double(d.peakDown), unit: settings.displayUnit), formatBytes(d.totalDown, dataUnit: settings.dataUnit), formatBytes(d.totalUp, dataUnit: settings.dataUnit))
            }
        case .month:
            headerTime = L10n.tr("Week")
            rows = weeklySummary.map { w in
                (String(w.week.suffix(4)), formatSpeed(w.avgDown, unit: settings.displayUnit), formatSpeed(Double(w.peakDown), unit: settings.displayUnit), formatBytes(w.totalDown, dataUnit: settings.dataUnit), formatBytes(w.totalUp, dataUnit: settings.dataUnit))
            }
        }

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(headerTime).font(.system(size: 11, weight: .medium)).foregroundColor(theme.textMuted).frame(width: 50, alignment: .leading)
                Spacer()
                Text(L10n.tr("Avg Speed")).font(.system(size: 11, weight: .medium)).foregroundColor(theme.textMuted).frame(width: 70, alignment: .trailing)
                Text(L10n.tr("Peak Speed")).font(.system(size: 11, weight: .medium)).foregroundColor(theme.textMuted).frame(width: 70, alignment: .trailing)
                Text(L10n.tr("Download")).font(.system(size: 11, weight: .medium)).foregroundColor(.downloadColor).frame(width: 60, alignment: .trailing)
                Text(L10n.tr("Upload")).font(.system(size: 11, weight: .medium)).foregroundColor(.uploadColor).frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal, Spacing.md).padding(.top, Spacing.md).padding(.bottom, Spacing.sm)

            Divider().padding(.horizontal, Spacing.md)

            if rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis").font(.title2).foregroundColor(theme.textMuted.opacity(0.4))
                    Text(L10n.tr("No Data")).font(.system(size: 12)).foregroundColor(theme.textMuted)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows.indices, id: \.self) { i in
                            let row = rows[i]
                            HStack {
                                Text(row.0).font(.system(size: 11, design: .monospaced)).foregroundColor(theme.textSecondary).frame(width: 50, alignment: .leading)
                                Spacer()
                                Text(row.1).font(.system(size: 11, design: .monospaced)).foregroundColor(theme.textSecondary).frame(width: 70, alignment: .trailing)
                                Text(row.2).font(.system(size: 11, design: .monospaced)).foregroundColor(theme.textSecondary).frame(width: 70, alignment: .trailing)
                                Text(row.3).font(.system(size: 11, design: .monospaced)).foregroundColor(.downloadColor).frame(width: 60, alignment: .trailing)
                                Text(row.4).font(.system(size: 11, design: .monospaced)).foregroundColor(.uploadColor).frame(width: 60, alignment: .trailing)
                            }
                            .padding(.vertical, 4).padding(.horizontal, Spacing.md)
                            if i < rows.count - 1 {
                                Divider().padding(.horizontal, Spacing.md)
                            }
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
        }
        .card(.glass)
    }

    @MainActor
    private func loadData() async {
        switch timeRange {
        case .today:
            let cached: [DatabaseManager.HourlyRecord]? = Self.cacheQueue.sync {
                guard let c = Self._hourlyCache, Date().timeIntervalSince(c.timestamp) < Self.cacheTTL else { return nil }
                return c.data
            }
            if let cached {
                self.hourlyData = cached
                return
            }
            let data = await Task.detached(priority: .userInitiated) {
                DatabaseManager.shared?.hourlyTrafficToday() ?? []
            }.value
            Self.cacheQueue.sync { Self._hourlyCache = (Date(), data) }
            self.hourlyData = data
        case .week:
            let cached = Self.cacheQueue.sync { () -> [(String, Double, Double, UInt64, UInt64, UInt64, UInt64)]? in
                guard let c = Self._dailyCache, Date().timeIntervalSince(c.timestamp) < Self.cacheTTL else { return nil }
                return c.data
            }
            if let cached {
                self.dailySummary = cached
                return
            }
            let data = await Task.detached(priority: .userInitiated) {
                DatabaseManager.shared?.dailyTrafficSummary(days: 7) ?? []
            }.value
            Self.cacheQueue.sync { Self._dailyCache = (Date(), data) }
            self.dailySummary = data
        case .month:
            let cached = Self.cacheQueue.sync { () -> [(String, Double, Double, UInt64, UInt64, UInt64, UInt64)]? in
                guard let c = Self._weeklyCache, Date().timeIntervalSince(c.timestamp) < Self.cacheTTL else { return nil }
                return c.data
            }
            if let cached {
                self.weeklySummary = cached
                return
            }
            let data = await Task.detached(priority: .userInitiated) {
                DatabaseManager.shared?.weeklyTrafficSummary(weeks: 4) ?? []
            }.value
            Self.cacheQueue.sync { Self._weeklyCache = (Date(), data) }
            self.weeklySummary = data
        }
    }
}

private extension Array where Element == Double {
    var average: Double { isEmpty ? 0 : reduce(0, +) / Double(count) }
}

// MARK: - Export Data Sheet
// MARK: - Permissions View
