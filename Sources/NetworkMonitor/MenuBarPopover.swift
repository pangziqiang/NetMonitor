import NetworkMonitorCore
import SwiftUI
import AppKit

struct MenuBarPopover: View {
    @ObservedObject var engine: NetworkMonitorEngine
    @ObservedObject var system: SystemMonitor
    @ObservedObject var settings: AppSettings
    @ObservedObject var popoverManager = PopoverManager.shared
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) var colorScheme
    @State private var uploadShowSession = false
    @State private var downloadShowSession = false
    enum ProcessSortMode: String, CaseIterable {
        case cpuPerCore = "By CPU"
        case cpuTotal = "By CPU Total"
        case memory = "By Memory"
        case network = "By Network"
    }
    @State private var processSortMode: ProcessSortMode = .cpuPerCore

    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerSection
            trafficSection
            systemSection
            if settings.menuShowTopProcesses {
                topProcessesSection
            }
            actionsSection
        }
        .padding(.vertical, Spacing.sm)
        .frame(minWidth: 380, maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size) { _, newSize in
                        PopoverManager.shared.contentSize = newSize
                    }
            }
        )
        .onAppear {
            system.processMonitor.isActive = true
        }
        .onDisappear {
            system.processMonitor.isActive = false
        }
        .onChange(of: settings.menuShowTopProcesses) { _, show in
            if !show { system.processMonitor.isActive = false }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            if popoverManager.hasMoved {
                closeButton
            }
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.downloadColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "network").foregroundColor(.downloadColor).font(.system(size: 16))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("NetMonitor").font(.system(size: 14, weight: .semibold)).foregroundColor(theme.textPrimary)
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.statusActive)
                        .frame(width: 8, height: 8)
                        .shadow(color: .statusActive.opacity(0.6), radius: 4)
                    Text(L10n.tr("Monitoring"))
                        .font(.system(size: 11)).foregroundColor(theme.textSecondary)
                }
            }
            Spacer()
            pinButton
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
    }

    private var closeButton: some View {
        Button {
            PopoverManager.shared.panel?.orderOut(nil)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(theme.textMuted.opacity(0.6))
        }
        .buttonStyle(.plain)
        .help(L10n.tr("Close"))
        .accessibilityLabel(L10n.tr("Close"))
    }

    private var pinButton: some View {
        Button {
            popoverManager.togglePin()
        } label: {
            Image(systemName: popoverManager.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 14))
                .foregroundColor(popoverManager.isPinned ? .downloadColor : theme.textMuted.opacity(0.6))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(popoverManager.isPinned ? L10n.tr("Unpin") : L10n.tr("Pin"))
        .accessibilityLabel(popoverManager.isPinned ? L10n.tr("Unpin") : L10n.tr("Pin"))
    }

    // MARK: - Traffic Badges (separate row, aligned with speed columns)

    private var trafficBadgesRow: some View {
        HStack(spacing: Spacing.md) {
            trafficCard(
                color: .uploadColor,
                label: L10n.tr("Upload Total"),
                showSession: $uploadShowSession,
                sessionValue: engine.totalSessionUp,
                todayValue: engine.todayUp
            )
            trafficCard(
                color: .downloadColor,
                label: L10n.tr("Download Total"),
                showSession: $downloadShowSession,
                sessionValue: engine.totalSessionDown,
                todayValue: engine.todayDown
            )
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.xs)
    }

    private func trafficCard(color: Color, label: String, showSession: Binding<Bool>, sessionValue: UInt64, todayValue: UInt64) -> some View {
        VStack(spacing: 4) {
            // Line 1: toggle + label
            HStack(spacing: 6) {
                periodToggle(showSession: showSession, color: color)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(theme.textMuted)
            }
            // Line 2: value
            Text(formatBytes(showSession.wrappedValue ? sessionValue : todayValue, dataUnit: settings.dataUnit))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.15), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { openTrafficStatistics() }
        .contextMenu {
            Button {
                openTrafficStatistics()
            } label: {
                Label(L10n.tr("View Details"), systemImage: "chart.bar.fill")
            }
        }
        .help(L10n.tr("View Traffic Details"))
    }

    private func openTrafficStatistics() {
        openWindow(id: "trafficStats")
        NSApp.activate()
    }

    private func periodToggle(showSession: Binding<Bool>, color: Color = .accentPurple) -> some View {
        HStack(spacing: 0) {
            Button(L10n.tr("This Session")) { showSession.wrappedValue = true }
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(showSession.wrappedValue ? color.opacity(0.15) : Color.clear)
                .foregroundColor(showSession.wrappedValue ? color : theme.textMuted.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .accessibilityLabel(L10n.tr("This Session"))
                .accessibilityAddTraits(showSession.wrappedValue ? .isSelected : [])
            Button(L10n.tr("Today")) { showSession.wrappedValue = false }
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(!showSession.wrappedValue ? color.opacity(0.15) : Color.clear)
                .foregroundColor(!showSession.wrappedValue ? color : theme.textMuted.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .accessibilityLabel(L10n.tr("Today"))
                .accessibilityAddTraits(!showSession.wrappedValue ? .isSelected : [])
        }
        .buttonStyle(.plain)
    }

    // MARK: - Speeds

    private var speedsSection: some View {
        HStack(spacing: Spacing.md) {
            speedItem(icon: "arrow.up.circle.fill", speed: engine.currentUpSpeed, color: .uploadColor)
            speedItem(icon: "arrow.down.circle.fill", speed: engine.currentDownSpeed, color: .downloadColor)
        }
    }

    private func speedItem(icon: String, speed: Double, color: Color) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon).font(.system(size: 26)).foregroundColor(color)
            Text(formatSpeed(speed, unit: settings.displayUnit))
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
            Spacer()
        }
        .accessibilityLabel("\(icon.contains("up") ? L10n.tr("Upload Speed") : L10n.tr("Download Speed")) \(formatSpeed(speed, unit: settings.displayUnit))")
    }

    // MARK: - Traffic Section (header + speeds + badges + charts)

    private var trafficSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line").font(.system(size: 11)).foregroundColor(theme.textMuted)
                Text(L10n.tr("Real-time Traffic")).font(.system(size: 11)).foregroundColor(theme.textMuted)
                Spacer()
            }
            .padding(.horizontal, Spacing.md).padding(.top, Spacing.sm).padding(.bottom, 4)

            speedsSection
                .padding(.horizontal, Spacing.md)

            if settings.menuShowDailyTraffic {
                trafficBadgesRow
            }

            VStack(spacing: 16) {
                speedChartRow(label: L10n.tr("Upload Speed"), data: engine.upHistory, times: engine.upHistoryTimes, color: .uploadColor)
                speedChartRow(label: L10n.tr("Download Speed"), data: engine.downHistory, times: engine.downHistoryTimes, color: .downloadColor)
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
        }
    }

    private func speedChartRow(label: String, data: [Double], times: [Date], color: Color) -> some View {
        let chartMax = speedChartMax(peak: data.max() ?? 0)
        return VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(color)
            MiniSparkLine(data: data, times: times, color: color, showAxis: false, showPeak: true, fixedMax: chartMax, formatValue: { v in formatSpeed(v, unit: settings.displayUnit) })
                .frame(height: 60)
        }
        .accessibilityLabel(label)
    }

    // MARK: - System Section (header + cards + charts)

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.needle").font(.system(size: 11)).foregroundColor(theme.textMuted)
                Text(L10n.tr("System Resources")).font(.system(size: 11)).foregroundColor(theme.textMuted)
                Spacer()
            }
            .padding(.horizontal, Spacing.md).padding(.top, Spacing.sm).padding(.bottom, 4)

            groupedStatsSection
                .padding(.horizontal, Spacing.md)

            VStack(spacing: 16) {
                systemRow(label: "CPU", usage: String(format: "%.1f%%", system.cpuUsage),
                          color: .cpuColor, data: system.cpuHistory, temp: system.thermal.cpuTemperature)
                systemRow(label: "GPU", usage: String(format: "%.1f%%", system.gpuUsage),
                          color: .gpuColor, data: system.gpuHistory, temp: system.thermal.gpuTemperature)
                systemRow(label: "MEM", usage: String(format: "%.1f%%", system.memoryUsage),
                          color: .memoryColor, data: system.memoryHistory, temp: system.thermal.memoryTemperature)
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
        }
    }

    private var groupedStatsSection: some View {
        HStack(spacing: Spacing.sm) {
            statCard(icon: "cpu", label: "CPU", value: String(format: "%.1f%%", system.cpuUsage), color: .cpuColor)
            statCard(icon: "display", label: "GPU", value: String(format: "%.1f%%", system.gpuUsage), color: .gpuColor)
            statCard(icon: "memorychip", label: "MEM", value: String(format: "%.1f%%", system.memoryUsage), color: .memoryColor)
        }
        .padding(.vertical, 4)
    }

    private func statCard(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            // Line 1: icon + label
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.textSecondary)
            }
            // Line 2: value
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func systemRow(label: String, usage: String, color: Color, data: [Double], temp: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                tempThermometer(value: temp, color: color)
                Spacer()
                HStack(spacing: 4) {
                    Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(color)
                    Text(usage).font(.system(size: 11, design: .monospaced)).foregroundColor(color)
                }
            }
            MiniSparkLine(data: data, times: [], color: color, showAxis: false, showPeak: true, fixedMax: 100)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
        }
    }

    // MARK: - Top Processes

    private var sortedProcesses: [ProcessSnapshot] {
        let count = settings.menuTopProcessesCount
        switch processSortMode {
        case .cpuPerCore: return Array(system.processMonitor.topByCPU.prefix(count))
        case .cpuTotal: return Array(system.processMonitor.topByCPUTotal.prefix(count))
        case .memory: return Array(system.processMonitor.topByMemory.prefix(count))
        case .network: return Array(system.processMonitor.topByNetwork.prefix(count))
        }
    }

    private var topProcessesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().opacity(0.2).padding(.horizontal, Spacing.md)

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "app.badge").font(.system(size: 11))
                    Text(L10n.tr("Top Processes")).font(.system(size: 11))
                }
                .foregroundColor(theme.textMuted)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(theme.textMuted.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))

                activityMonitorButton

                Spacer()
                processSortToggle
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                appState.settingsTab = .general
                openWindow(id: "settings")
                NSApp.activate()
            }

            let processes = sortedProcesses
            VStack(spacing: 2) {
                ForEach(Array(processes.enumerated()), id: \.element.pid) { _, snap in
                    processRow(snap)
                }
                if let selfSnap = system.processMonitor.selfInfo {
                    Divider().opacity(0.15).padding(.vertical, 2)
                    selfProcessRow(selfSnap)
                }
            }
            .padding(.horizontal, Spacing.md).padding(.bottom, Spacing.sm)
        }
    }

    private var activityMonitorButton: some View {
        Button {
            let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 11))
                Text(L10n.tr("Activity Monitor"))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.downloadColor)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.downloadColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private var processSortToggle: some View {
        HStack(spacing: 0) {
            Button(L10n.tr("By CPU")) {
                withAnimation(.easeInOut(duration: 0.15)) { processSortMode = .cpuPerCore }
            }
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(processSortMode == .cpuPerCore ? Color.downloadColor.opacity(0.15) : Color.clear)
            .foregroundColor(processSortMode == .cpuPerCore ? .downloadColor : theme.textMuted.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            Button(L10n.tr("By CPU Total")) {
                withAnimation(.easeInOut(duration: 0.15)) { processSortMode = .cpuTotal }
            }
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(processSortMode == .cpuTotal ? Color.downloadColor.opacity(0.15) : Color.clear)
            .foregroundColor(processSortMode == .cpuTotal ? .downloadColor : theme.textMuted.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            Button(L10n.tr("By Memory")) {
                withAnimation(.easeInOut(duration: 0.15)) { processSortMode = .memory }
            }
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(processSortMode == .memory ? Color.downloadColor.opacity(0.15) : Color.clear)
            .foregroundColor(processSortMode == .memory ? .downloadColor : theme.textMuted.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            Button(L10n.tr("By Network")) {
                withAnimation(.easeInOut(duration: 0.15)) { processSortMode = .network }
            }
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(processSortMode == .network ? Color.downloadColor.opacity(0.15) : Color.clear)
            .foregroundColor(processSortMode == .network ? .downloadColor : theme.textMuted.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }

    private func processRow(_ snap: ProcessSnapshot) -> some View {
        HStack(spacing: 8) {
            if let icon = processIcon(for: snap.pid) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.textMuted.opacity(0.2))
                    .frame(width: 16, height: 16)
            }

            Text(processDisplayName(for: snap))
                .font(.system(size: 12))
                .foregroundColor(theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if processSortMode == .network {
                Text(formatNetworkSpeed(snap.downloadBytes, isDownload: true))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.downloadColor)
                    .frame(width: 72, alignment: .trailing)
                Text(formatNetworkSpeed(snap.uploadBytes, isDownload: false))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.uploadColor)
                    .frame(width: 72, alignment: .trailing)
            } else {
                let cpuValue = processSortMode == .cpuTotal
                    ? snap.cpuPercent / Double(system.processMonitor.processorCount)
                    : snap.cpuPercent
                Text(String(format: "%.1f%%", cpuValue))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(cpuPercentColor(cpuValue))

                Text(formatBytes(snap.rssBytes, dataUnit: settings.dataUnit))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.memoryColor)
                    .frame(width: 64, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(theme.appBg.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func formatNetworkSpeed(_ bytesPerSec: Double, isDownload: Bool) -> String {
        let prefix = isDownload ? "↓" : "↑"
        if bytesPerSec < 0 { return "\(prefix)0 KB/s" }
        let kb = bytesPerSec / 1024.0
        if kb < 1024.0 { return "\(prefix)\(String(format: "%.1f", kb)) KB/s" }
        return "\(prefix)\(String(format: "%.1f", kb / 1024.0)) MB/s"
    }

    private func selfProcessRow(_ snap: ProcessSnapshot) -> some View {
        HStack(spacing: 8) {
            if let icon = NSRunningApplication.current.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.downloadColor.opacity(0.3))
                    .frame(width: 16, height: 16)
            }

            Text("NetMonitor")
                .font(.system(size: 12))
                .foregroundColor(theme.textSecondary)

            Spacer()

            if processSortMode == .network {
                Text(formatNetworkSpeed(snap.downloadBytes, isDownload: true))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.downloadColor)
                    .frame(width: 72, alignment: .trailing)
                Text(formatNetworkSpeed(snap.uploadBytes, isDownload: false))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.uploadColor)
                    .frame(width: 72, alignment: .trailing)
            } else {
                let cpuValue = processSortMode == .cpuTotal
                    ? snap.cpuPercent / Double(system.processMonitor.processorCount)
                    : snap.cpuPercent
                Text(String(format: "%.1f%%", cpuValue))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(cpuPercentColor(cpuValue))

                Text(formatBytes(snap.rssBytes, dataUnit: settings.dataUnit))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.memoryColor)
                    .frame(width: 64, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.downloadColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func cpuPercentColor(_ pct: Double) -> Color {
        if pct < 10 { return .downloadColor }
        if pct < 40 { return .cpuColor }
        return .errorColor
    }

    private func processIcon(for pid: Int32) -> NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }

    private func processDisplayName(for snap: ProcessSnapshot) -> String {
        if let app = NSRunningApplication(processIdentifier: snap.pid), let name = app.localizedName, !name.isEmpty {
            return name
        }
        return snap.name
    }

    // MARK: - Actions

    private var actionsSection: some View {
        HStack(spacing: 2) {
            bottomActionRow(icon: "gearshape", text: L10n.tr("Settings")) {
                openWindow(id: "settings")
                NSApp.activate()
            }
            bottomActionRow(icon: "chart.bar.fill", text: L10n.tr("Traffic Stats")) {
                openWindow(id: "trafficStats")
                NSApp.activate()
            }
            Spacer(minLength: 16)
            bottomActionRow(icon: "xmark", text: L10n.tr("Exit"), destructive: true) {
                engine.stop(); system.stop()
                DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            }
            Spacer(minLength: 0)
        }
    }

    private func bottomActionRow(icon: String, text: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(destructive ? .errorColor : theme.textMuted)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(destructive ? .errorColor : theme.textSecondary)
            }
            .frame(width: 72)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.glass(.ghost))
        .accessibilityLabel(text)
    }

    @ViewBuilder
    private func tempThermometer(value: Double?, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "thermometer").font(.system(size: 9)).foregroundColor(theme.textMuted)
            if let t = value, t > 0 {
                Text("\(String(format: "%.0f", t))°C")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(t < 60 ? .memoryColor : t < 80 ? color : .temperatureColor)
            } else {
                Text("--°C").font(.system(size: 10, design: .monospaced)).foregroundColor(theme.textMuted)
            }
        }
    }
}
