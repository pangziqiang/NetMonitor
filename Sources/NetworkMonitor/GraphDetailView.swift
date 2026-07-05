import NetworkMonitorCore
import SwiftUI

struct GraphDetailView: View {
    @ObservedObject var engine: NetworkMonitorEngine
    let unit: DisplayUnit
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }

    var body: some View {
        let isDown = appState.graphType == .down
        let title = isDown ? L10n.tr("Download") : L10n.tr("Upload")
        let color = isDown ? Color.downloadColor : Color.uploadColor
        let data = isDown ? engine.downHistory : engine.upHistory
        let times = isDown ? engine.downHistoryTimes : engine.upHistoryTimes

        return ZStack {
            theme.appBg.edgesIgnoringSafeArea(.all)
            VStack(spacing: Spacing.md) {
                HStack {
                    Image(systemName: isDown ? "arrow.down.circle.fill" : "arrow.up.circle.fill").font(.subheadline).holographicTitle()
                    Text("\(title) \(L10n.tr("Real-time Traffic Chart"))").font(.subheadline).holographicTitle()
                    Spacer()
                    if let last = data.last {
                        Text(formatSpeed(last, unit: unit))
                            .font(.system(.title2, design: .monospaced)).fontWeight(.semibold)
                    }
                }
                if data.isEmpty {
                    Spacer()
                    Text(L10n.tr("No Data Available")).font(.system(size: 14)).foregroundColor(theme.textMuted)
                    Spacer()
                } else {
                    GraphCanvas(data: data, color: color, showLabels: true, yUnit: unit, times: times)
                }
            }
            .padding(Spacing.md)
            .frame(minWidth: 400, minHeight: 300)
            .card(.tone(color))
            .padding(Spacing.md)
        }
    }
}
