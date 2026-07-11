import NetMonitorCore
import SwiftUI

struct PermissionsView: View {
    @State private var isAppleSilicon = false
    @Environment(\.colorScheme) var colorScheme
    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }

    var body: some View {
        VStack(spacing: Spacing.lg) {
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
