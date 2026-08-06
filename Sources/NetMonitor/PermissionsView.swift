import NetMonitorCore
import SwiftUI
import AppKit

struct PermissionsView: View {
    @State private var hardware: HardwareInfo?
    @State private var isMonitoring = true  // engine always active while app runs
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
                    icon: "pip", name: L10n.tr("Floating Window"),
                    description: L10n.tr("Floating Window Desc"),
                    granted: settings.showFloatingWindow
                )
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
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                let info = HardwareInfo.load()
                DispatchQueue.main.async {
                    hardware = info
                }
            }
        }
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
