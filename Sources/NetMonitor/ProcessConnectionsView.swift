import NetMonitorCore
import SwiftUI

struct ProcessConnectionsView: View {
    @ObservedObject var system: SystemMonitor
    @EnvironmentObject var settings: AppSettings
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var connectionReader = ConnectionReader()
    @State private var tab: Tab = .processes
    @State private var searchText = ""

    private enum Tab: String, CaseIterable {
        case processes
        case connections
    }

    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("", selection: $tab) {
                    Text(L10n.tr("Processes")).tag(Tab.processes)
                    Text(L10n.tr("Connections")).tag(Tab.connections)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(theme.textMuted)
                    TextField("", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(theme.textPrimary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(theme.textMuted.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                if tab == .connections, let updated = connectionReader.lastUpdated {
                    Text(Self.timeFormatter.string(from: updated))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.textMuted)
                }
            }
            .padding(12)

            Divider()

            switch tab {
            case .processes: processList
            case .connections: connectionList
            }
        }
        .frame(width: 760, height: 540)
        .background(theme.appBg)
        .onAppear {
            system.processMonitor.isWindowActive = true
            connectionReader.start()
        }
        .onDisappear {
            system.processMonitor.isWindowActive = false
            connectionReader.stop()
        }
    }

    // MARK: - 进程页签

    private var processList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.tr("Process")).frame(width: 260, alignment: .leading)
                Spacer()
                Text("↓").frame(width: 100, alignment: .trailing)
                Text("↑").frame(width: 100, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(theme.textMuted)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredProcesses, id: \.pid) { p in
                        HStack {
                            Text(p.name)
                                .font(.system(size: 12))
                                .foregroundColor(theme.textSecondary)
                                .lineLimit(1)
                                .frame(width: 260, alignment: .leading)
                            Spacer()
                            Text(formatSpeed(p.downloadBytes, unit: settings.displayUnit))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.downloadColor)
                                .frame(width: 100, alignment: .trailing)
                            Text(formatSpeed(p.uploadBytes, unit: settings.displayUnit))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.uploadColor)
                                .frame(width: 100, alignment: .trailing)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                        Divider().opacity(0.4)
                    }
                    if filteredProcesses.isEmpty {
                        Text(L10n.tr("No Data"))
                            .font(.system(size: 12))
                            .foregroundColor(theme.textMuted)
                            .padding(.top, 40)
                    }
                }
            }
        }
    }

    private var filteredProcesses: [ProcessSnapshot] {
        let list = system.processMonitor.topByNetwork
        let sorted = list.sorted { ($0.downloadBytes + $0.uploadBytes) > ($1.downloadBytes + $1.uploadBytes) }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - 链接页签

    private var connectionList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.tr("Process")).frame(width: 130, alignment: .leading)
                Text(L10n.tr("Protocol")).frame(width: 42, alignment: .leading)
                Text(L10n.tr("Local")).frame(width: 180, alignment: .leading)
                Text(L10n.tr("Remote")).frame(width: 180, alignment: .leading)
                Text(L10n.tr("State")).frame(width: 100, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(theme.textMuted)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredConnections) { c in
                        HStack {
                            Text(c.process)
                                .font(.system(size: 11))
                                .foregroundColor(theme.textSecondary)
                                .lineLimit(1)
                                .frame(width: 130, alignment: .leading)
                            Text(c.protocolName)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(theme.textMuted)
                                .frame(width: 42, alignment: .leading)
                            Text(c.local)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(theme.textMuted)
                                .lineLimit(1)
                                .frame(width: 180, alignment: .leading)
                            Text(c.remote)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(theme.textMuted)
                                .lineLimit(1)
                                .frame(width: 180, alignment: .leading)
                            Text(c.state)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(c.state == "ESTABLISHED" ? .downloadColor : theme.textMuted)
                                .frame(width: 100, alignment: .trailing)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 3)
                        Divider().opacity(0.4)
                    }
                    if filteredConnections.isEmpty {
                        Text(L10n.tr("No Data"))
                            .font(.system(size: 12))
                            .foregroundColor(theme.textMuted)
                            .padding(.top, 40)
                    }
                }
            }
        }
    }

    private var filteredConnections: [NetworkConnection] {
        guard !searchText.isEmpty else { return connectionReader.connections }
        return connectionReader.connections.filter {
            $0.process.localizedCaseInsensitiveContains(searchText)
                || $0.local.localizedCaseInsensitiveContains(searchText)
                || $0.remote.localizedCaseInsensitiveContains(searchText)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
