import NetMonitorCore
import SwiftUI

struct SystemGraphDetailView: View {
    @ObservedObject var system: SystemMonitor
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }

    private var title: String {
        switch appState.systemGraphType {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return L10n.tr("Memory")
        }
    }

    private var chartColor: Color {
        switch appState.systemGraphType {
        case .cpu: return .cpuColor
        case .gpu: return .gpuColor
        case .memory: return .memoryColor
        }
    }

    private var chartData: [Double] {
        switch appState.systemGraphType {
        case .cpu: return system.cpuHistory
        case .gpu: return system.gpuHistory
        case .memory: return system.memoryHistory
        }
    }

    private var chartTempData: [Double] {
        switch appState.systemGraphType {
        case .cpu: return system.cpuTemperatureHistory
        case .gpu: return system.gpuTemperatureHistory
        case .memory: return system.memoryTemperatureHistory
        }
    }

    private var iconName: String {
        switch appState.systemGraphType {
        case .cpu: return "cpu"
        case .gpu: return "display"
        case .memory: return "memorychip"
        }
    }

    var body: some View {
        ZStack {
            theme.appBg.edgesIgnoringSafeArea(.all)
            VStack(spacing: Spacing.md) {
                HStack {
                    Image(systemName: iconName).font(.subheadline).holographicTitle()
                    Text("\(title) \(L10n.tr("Usage"))").font(.subheadline).holographicTitle()
                    Spacer()
                    if let last = chartData.last {
                        Text(String(format: "%.1f%%", last))
                            .font(.system(.title2, design: .monospaced)).fontWeight(.semibold)
                    }
                }

                if chartData.isEmpty {
                    Spacer()
                    Text(L10n.tr("No Data Available")).font(.system(size: 14)).foregroundColor(theme.textMuted)
                    Spacer()
                } else {
                    DualSeriesChart(
                        title: title,
                        series1: SeriesConfig(
                            data: chartData,
                            color: chartColor,
                            yMax: 100,
                            label: L10n.tr("Usage"),
                            formatValue: { String(format: "%.1f%%", $0) },
                            formatYLabel: { "\(Int($0))%" }
                        ),
                        series2: SeriesConfig(
                            data: chartTempData,
                            color: .temperatureColor,
                            yMax: 100,
                            label: L10n.tr("Temperature"),
                            formatValue: { String(format: "%.0f°C", $0) },
                            formatYLabel: { "\(Int($0))°" }
                        ),
                        showCard: false
                    )
                }
            }
            .padding(Spacing.md)
            .frame(minWidth: 400, minHeight: 300)
            .card(.tone(chartColor))
            .padding(Spacing.md)
        }
    }
}
