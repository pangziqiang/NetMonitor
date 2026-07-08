import NetworkMonitorCore
import SwiftUI
import AppKit

struct TrafficStatsView: View {
    @ObservedObject var engine: NetworkMonitorEngine
    @ObservedObject var settings: AppSettings
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme

    @State private var page: BarChartPage?

    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }
    private let cfg = BarChartConfig.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            scrollContent
        }
        .frame(minWidth: cfg.pW, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
        .background(Color(red: 0x1a / 255, green: 0x1a / 255, blue: 0x1e / 255))
        .onAppear { loadData() }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.downloadColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.downloadColor)
                    .font(.system(size: 14))
            }
            Text(L10n.tr("Traffic Statistics"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            if let page {
                VStack(alignment: .leading, spacing: 16) {
                    // stats
                    statsBar(page)

                    // chart: 下载流量
                    chartSection(data: page.dn, color: .downloadColor, page: page)

                    // chart: 上传流量
                    chartSection(data: page.up, color: .uploadColor, page: page)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            } else {
                VStack {
                    Spacer()
                    Text(L10n.tr("No Data"))
                        .font(.system(size: 14))
                        .foregroundColor(theme.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Stats Bar

    private func statsBar(_ page: BarChartPage) -> some View {
        let peakDown = page.dn.max() ?? 0
        let peakUp = page.up.max() ?? 0
        return HStack(spacing: 20) {
            statItem(label: L10n.tr("Download"), value: barFormatBytes(page.s1), color: .downloadColor)
            statItem(label: L10n.tr("Upload"), value: barFormatBytes(page.s2), color: .uploadColor)
            statItem(label: "峰值↓", value: barFormatBytes(peakDown), color: .downloadColor, small: true)
            statItem(label: "峰值↑", value: barFormatBytes(peakUp), color: .uploadColor, small: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: cfg.statsH)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statItem(label: String, value: String, color: Color, small: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color.white.opacity(0.53))
            Text(value)
                .font(.system(size: small ? 13 : 16, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }

    // MARK: - Chart Section

    private func chartSection(data: [UInt64], color: Color, page: BarChartPage) -> some View {
        BarChartRenderer(
            data: data,
            color: color,
            labels1: page.l1,
            labels2: page.l2,
            isFuture: page.fut,
            sharedMax: barNiceMax([page.dn, page.up].flatMap { $0 }),
            config: cfg
        )
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Data Loading (今日 24 根柱子)

    private func loadData() {
        let db = DatabaseManager.shared
        guard let db else { page = nil; return }

        let records = db.hourlyTrafficToday()
        let now = Calendar.current.component(.hour, from: Date())

        var dn = [UInt64](repeating: 0, count: 24)
        var up = [UInt64](repeating: 0, count: 24)
        for r in records {
            let h = Calendar.current.component(.hour, from: r.hour)
            dn[h] = r.totalDown
            up[h] = r.totalUp
        }

        let l1 = (0..<24).map { String(format: "%02d:00", $0) }
        let l2 = [String](repeating: "", count: 24)
        let s1 = dn.reduce(0, +)
        let s2 = up.reduce(0, +)
        let hoursElapsed = max(1, now + 1)
        let a1 = Double(s1) / Double(hoursElapsed * 3600)
        let a2 = Double(s2) / Double(hoursElapsed * 3600)

        page = BarChartPage(
            dn: dn, up: up, l1: l1, l2: l2,
            fut: { $0 > now },
            title: L10n.tr("Today"),
            s1: s1, s2: s2, a1: a1, a2: a2
        )
    }
}
