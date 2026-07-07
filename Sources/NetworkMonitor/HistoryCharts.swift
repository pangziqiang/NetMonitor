import SwiftUI
import Charts
import NetworkMonitorCore

// MARK: - Speed Trend Chart

struct SpeedTrendChart: View {
    let records: [DatabaseManager.HourlyRecord]
    let displayUnit: DisplayUnit
    @Environment(\.colorScheme) var colorScheme
    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }

    private var niceMax: Double {
        speedChartMax(peak: records.flatMap { [$0.avgDown, $0.avgUp] }.max() ?? 0)
    }

    var body: some View {
        if records.isEmpty {
            emptyView
        } else {
            chartContent
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.downtrend.xyaxis").font(.title2).foregroundColor(theme.textMuted.opacity(0.4))
            Text(L10n.tr("No Data")).font(.system(size: 12)).foregroundColor(theme.textMuted)
        }
        .frame(maxWidth: .infinity).frame(height: 200)
        .background(theme.textMuted.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var chartContent: some View {
        let totalWidth = CGFloat(records.count) * 36 + 8

        return VStack(alignment: .leading, spacing: 6) {
            Text(L10n.tr("Speed Trend"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(theme.textMuted)
                .padding(.horizontal, 4)

            GeometryReader { geo in
                ScrollView(.horizontal) {
                    VStack(spacing: 2) {
                        Chart {
                            ForEach(Array(records.enumerated()), id: \.offset) { _, r in
                                LineMark(x: .value("", r.hour), y: .value("", r.avgDown), series: .value("", "down"))
                                    .foregroundStyle(Color.downloadColor)
                                    .lineStyle(StrokeStyle(lineWidth: 2))
                                    .symbol(Circle().strokeBorder(lineWidth: 1.5))
                                    .symbolSize(16)
                                LineMark(x: .value("", r.hour), y: .value("", r.avgUp), series: .value("", "up"))
                                    .foregroundStyle(Color.uploadColor)
                                    .lineStyle(StrokeStyle(lineWidth: 2))
                                    .symbol(Circle().strokeBorder(lineWidth: 1.5))
                                    .symbolSize(16)
                            }
                        }
                        .chartYAxis(.hidden)
                        .chartYScale(domain: 0...niceMax)
                        .chartXAxis(.hidden)
                        .frame(width: max(totalWidth, geo.size.width), height: 180)

                        xAxisLabelsRow
                    }
                    .frame(width: max(totalWidth, geo.size.width))
                }
            }
            .frame(height: 200)

            HStack(spacing: 16) {
                legendDot(color: .downloadColor, label: L10n.tr("Download"))
                legendDot(color: .uploadColor, label: L10n.tr("Upload"))
            }
            .font(.system(size: 10))
            .padding(.horizontal, 4)
        }
        .padding(12)
        .background(theme.textMuted.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var xAxisLabelsRow: some View {
        let strideCount = max(1, records.count / 6)
        let labels = records.enumerated().compactMap { i, r -> (Int, String)? in
            guard i % strideCount == 0 else { return nil }
            return (i, xLabel(r.hour))
        }
        return HStack(spacing: 0) {
            ForEach(labels, id: \.0) { idx, label in
                Text(label)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(theme.textMuted)
                if idx < labels.count - 1 { Spacer() }
            }
        }
        .frame(height: 14)
    }

    private func xLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = records.count <= 24 ? "HH:mm" : "MM/dd"; return f.string(from: d)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 6, height: 6); Text(label).foregroundColor(theme.textSecondary) }
    }
}

// MARK: - Traffic Bar Chart (manual rendering)

struct TrafficBarChart: View {
    let records: [DatabaseManager.HourlyRecord]
    let dataUnit: DataUnit
    @Environment(\.colorScheme) var colorScheme
    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }

    private let barGroupWidth: CGFloat = 36
    private let barWidth: CGFloat = 12
    private let barGap: CGFloat = 4

    private var niceMax: Double {
        let peak = records.flatMap { [Double($0.totalDown), Double($0.totalUp)] }.max() ?? 0
        return speedChartMax(peak: peak)
    }

    var body: some View {
        if records.isEmpty {
            emptyView
        } else {
            chartContent
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar").font(.title2).foregroundColor(theme.textMuted.opacity(0.4))
            Text(L10n.tr("No Data")).font(.system(size: 12)).foregroundColor(theme.textMuted)
        }
        .frame(maxWidth: .infinity).frame(height: 240)
        .background(theme.textMuted.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var chartContent: some View {
        let totalWidth = CGFloat(records.count) * barGroupWidth + 8
        let h: CGFloat = 200

        return VStack(alignment: .leading, spacing: 6) {
            Text(L10n.tr("Traffic Volume"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(theme.textMuted)
                .padding(.horizontal, 4)

            GeometryReader { geo in
                ScrollView(.horizontal) {
                    VStack(spacing: 2) {
                        barCanvas.frame(width: max(totalWidth, geo.size.width), height: h)
                        xAxisLabels
                    }
                    .frame(width: max(totalWidth, geo.size.width), height: h + 16)
                }
            }
            .frame(height: h + 16)

            HStack(spacing: 16) {
                legendDot(color: .downloadColor, label: L10n.tr("Download"))
                legendDot(color: .uploadColor, label: L10n.tr("Upload"))
            }
            .font(.system(size: 10))
            .padding(.horizontal, 4)
        }
        .padding(12)
        .background(theme.textMuted.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var barCanvas: some View {
        let h: CGFloat = 200

        return ZStack(alignment: .bottomLeading) {
            Canvas { ctx, size in
                for pct in stride(from: 0.25, through: 1.0, by: 0.25) {
                    let y = size.height - CGFloat(pct) * size.height
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(path, with: .color(theme.textMuted.opacity(0.08)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: h)

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(records.enumerated()), id: \.offset) { i, r in
                    barGroup(record: r, chartHeight: h)
                    if i < records.count - 1 { Spacer().frame(width: barGap) }
                }
            }
            .padding(.leading, 4).padding(.trailing, 4)
        }
        .frame(height: h)
    }

    private func barGroup(record: DatabaseManager.HourlyRecord, chartHeight: CGFloat) -> some View {
        let top = niceMax > 0 ? niceMax : 1024
        let downH = CGFloat(Double(record.totalDown) / top) * chartHeight
        let upH = CGFloat(Double(record.totalUp) / top) * chartHeight

        return HStack(alignment: .bottom, spacing: 2) {
            VStack(spacing: 2) {
                if record.totalDown > 0 {
                    Text(shortBytes(record.totalDown))
                        .font(.system(size: 6, design: .monospaced))
                        .foregroundColor(.downloadColor.opacity(0.8))
                }
                Rectangle()
                    .fill(Color.downloadColor)
                    .frame(width: barWidth, height: max(2, downH))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            VStack(spacing: 2) {
                if record.totalUp > 0 {
                    Text(shortBytes(record.totalUp))
                        .font(.system(size: 6, design: .monospaced))
                        .foregroundColor(.uploadColor.opacity(0.8))
                }
                Rectangle()
                    .fill(Color.uploadColor)
                    .frame(width: barWidth, height: max(2, upH))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .frame(width: barGroupWidth - barGap)
    }

    private var xAxisLabels: some View {
        HStack(spacing: 0) {
            ForEach(Array(records.enumerated()), id: \.offset) { i, r in
                Text(xLabel(r.hour, index: i))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(theme.textMuted.opacity(0.7))
                    .frame(width: barGroupWidth, alignment: .center)
            }
        }
    }

    private func xLabel(_ d: Date, index: Int) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        if records.count <= 24 {
            let total = records.count
            if total <= 6 { return hourStr(d) }
            return index % max(1, total / 6) == 0 ? hourStr(d) : ""
        } else {
            f.dateFormat = "MM/dd"
            return index % 2 == 0 ? f.string(from: d) : ""
        }
    }
    private func hourStr(_ d: Date) -> String {
        let c = Calendar.current; return String(format: "%02d:00", c.component(.hour, from: d))
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 6, height: 6); Text(label).foregroundColor(theme.textSecondary) }
    }

    private func shortBytes(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0fK", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1fM", mb) }
        let gb = mb / 1024
        return String(format: "%.1fG", gb)
    }
}
