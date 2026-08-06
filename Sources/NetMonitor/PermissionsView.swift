import NetMonitorCore
import SwiftUI
import AppKit

struct PermissionsView: View {
    @State private var hardware: HardwareInfo?
    @State private var isMonitoring = true  // engine always active while app runs
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var logs: [(timestamp: String, category: String, event: String, detail: String?)] = []
    @EnvironmentObject var settings: AppSettings
    @Environment(\.colorScheme) var colorScheme
    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            settingsSection(L10n.tr("Current Device"), textColor: theme.textMuted) {
                if let hw = hardware {
                    hardwareRow(icon: "desktopcomputer", name: L10n.tr("Machine Model"), value: hw.machineModel)
                    hardwareRow(icon: "cpu", name: L10n.tr("Processor"), value: hw.cpuBrand)
                    hardwareRow(icon: "cpu.fill", name: L10n.tr("Cores"), value: "\(hw.physicalCores) \(L10n.tr("Cores")) / \(hw.logicalCores) \(L10n.tr("Threads"))")
                    hardwareRow(icon: "display", name: L10n.tr("Graphics"), value: hw.gpuName.isEmpty ? "—" : "\(hw.gpuName) · \(hw.gpuVRAM)")
                    hardwareRow(icon: "memorychip", name: L10n.tr("Memory"), value: "\(hw.ramBytes / 1_073_741_824) GB")
                    hardwareRow(icon: "apple.logo", name: L10n.tr("System"), value: hw.osVersion)
                } else {
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }

            settingsSection(L10n.tr("System Status"), textColor: theme.textMuted) {
                permissionRow(
                    icon: "network", name: L10n.tr("Network Monitor"),
                    description: L10n.tr("Network Monitor Desc"),
                    granted: isMonitoring
                )
                permissionRow(
                    icon: "app.badge", name: L10n.tr("Process Monitor"),
                    description: L10n.tr("Process Monitor Desc"),
                    granted: true
                )
                permissionRow(
                    icon: "thermometer", name: L10n.tr("Temperature"),
                    description: L10n.tr("Temperature Desc"),
                    granted: true
                )
                accessibilityRow
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

            settingsSection(L10n.tr("Logs"), textColor: theme.textMuted) {
                HStack {
                    Text("\(L10n.tr("Recent Logs")) · \(logs.count)")
                        .font(.system(size: 10))
                        .foregroundColor(theme.textMuted)
                    Spacer()
                    Button(L10n.tr("Refresh")) {
                        loadLogs()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.bottom, 4)

                if logs.isEmpty {
                    Text(L10n.tr("No Logs"))
                        .font(.system(size: 11))
                        .foregroundColor(theme.textMuted)
                        .padding(.vertical, 6)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logs.enumerated()), id: \.offset) { _, log in
                            HStack(alignment: .top, spacing: 6) {
                                Text(logTimestamp(log.timestamp))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(theme.textMuted)
                                    .frame(width: 92, alignment: .leading)
                                Text(log.category)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(categoryColor(log.category))
                                    .frame(width: 52, alignment: .leading)
                                Text(log.detail.map { "\(log.event) · \($0)" } ?? log.event)
                                    .font(.system(size: 10))
                                    .foregroundColor(theme.textSecondary)
                                    .lineLimit(1)
                                    .help(log.detail ?? log.event)
                                Spacer()
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }
        }
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
            loadLogs()
            DispatchQueue.global(qos: .userInitiated).async {
                let info = HardwareInfo.load()
                DispatchQueue.main.async {
                    hardware = info
                }
            }
        }
    }

    private var accessibilityRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "accessibility")
                .font(.system(size: 12))
                .foregroundColor(accessibilityGranted ? .statusActive : theme.textMuted)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.tr("Accessibility")).font(.system(size: 12)).foregroundColor(theme.textSecondary)
                Text(L10n.tr("Accessibility Desc")).font(.system(size: 10)).foregroundColor(theme.textMuted)
            }
            Spacer()
            if accessibilityGranted {
                HStack(spacing: 6) {
                    Circle().fill(Color.statusActive).frame(width: 7, height: 7)
                    Text(L10n.tr("Authorized")).font(.system(size: 10, design: .monospaced)).foregroundColor(.statusActive)
                }
            } else {
                Button(L10n.tr("Grant")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func hardwareRow(icon: String, name: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(theme.textMuted)
                .frame(width: 20)
            Text(name).font(.system(size: 12)).foregroundColor(theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
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

    private func loadLogs() {
        logs = DatabaseManager.shared?.recentEvents(limit: 200) ?? []
    }

    private func logTimestamp(_ iso: String) -> String {
        guard let date = iso8601Date(from: iso) else { return String(iso.suffix(12)) }
        return Self.logTimeFormatter.string(from: date)
    }

    private static let logTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "lifecycle": return .downloadColor
        case "userAction": return .cpuColor
        case "error": return .errorColor
        default: return theme.textMuted
        }
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
}
