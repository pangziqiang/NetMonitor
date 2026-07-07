import SwiftUI
import Charts
import NetworkMonitorCore

// MARK: - Speed Trend Chart

struct SpeedTrendChart: View {
    let records: [DatabaseManager.HourlyRecord]
    let displayUnit: DisplayUnit
    @Environment(\.colorScheme) var colorScheme
    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }
    @State private var hoverIndex: Int? = nil

    private var niceMax: Double {
        speedChartMax(peak: records.flatMap { [$0.avgDown, $0.avgUp] }.max() ?? 0)
    }

    private var peakIndex: Int? {
        guard let maxVal = records.map(\.avgDown).max(), maxVal > 0 else { return nil }
        return records.firstIndex(where: { $0.avgDown == maxVal })
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
        let gridColor: Color = colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06)

        return VStack(alignment: .leading, spacing: 6) {
            Text(L10n.tr("Speed Trend"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(theme.textMuted)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 4) {
                    yAxisLabels
                        .frame(width: 42)

                    GeometryReader { geo in
                        let chartW = geo.size.width
                        let chartH: CGFloat = 180
                        let stepX = chartW / CGFloat(max(records.count - 1, 1))

                        ZStack(alignment: .topLeading) {
                            // Grid lines
                            Canvas { ctx, size in
                                for pct in stride(from: 0.25, through: 1.0, by: 0.25) {
                                    let y = chartH - CGFloat(pct) * chartH
                                    var path = Path()
                                    path.move(to: CGPoint(x: 0, y: y))
                                    path.addLine(to: CGPoint(x: size.width, y: y))
                                    ctx.stroke(path, with: .color(gridColor), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                                }
                            }
                            .frame(height: chartH)

                            // Chart
                            Chart {
                                ForEach(Array(records.enumerated()), id: \.offset) { _, r in
                                    LineMark(x: .value("", r.hour), y: .value("", r.avgDown), series: .value("", "down"))
                                        .foregroundStyle(Color.downloadColor)
                                        .lineStyle(StrokeStyle(lineWidth: 2))
                                    LineMark(x: .value("", r.hour), y: .value("", r.avgUp), series: .value("", "up"))
                                        .foregroundStyle(Color.uploadColor)
                                        .lineStyle(StrokeStyle(lineWidth: 2))
                                }
                            }
                            .chartYAxis(.hidden)
                            .chartYScale(domain: 0...niceMax)
                            .chartXAxis(.hidden)
                            .frame(height: chartH)

                            // Peak marker
                            if let peakIdx = peakIndex, peakIdx < records.count {
                                let peakVal = records[peakIdx].avgDown
                                let px = stepX * CGFloat(peakIdx)
                                let py = chartH - CGFloat(peakVal / niceMax) * chartH
                                peakMarker(value: peakVal, x: px, y: py, color: .downloadColor)
                            }

                            // Hover crosshair
                            if let idx = hoverIndex, idx < records.count {
                                let r = records[idx]
                                let px = stepX * CGFloat(idx)
                                let downY = chartH - CGFloat(r.avgDown / niceMax) * chartH

                                Path { path in
                                    path.move(to: CGPoint(x: px, y: 0))
                                    path.addLine(to: CGPoint(x: px, y: chartH))
                                }
                                .stroke(style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                                .foregroundStyle(Color.downloadColor.opacity(0.35))

                                Circle()
                                    .fill(Color.downloadColor)
                                    .frame(width: 6, height: 6)
                                    .position(x: px, y: downY)

                                hoverTooltip(idx: idx, x: px, chartSize: CGSize(width: chartW, height: chartH))
                            }
                        }
                        .frame(height: chartH)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                let idx = Int(round(loc.x / stepX))
                                hoverIndex = max(0, min(idx, records.count - 1))
                            case .ended:
                                hoverIndex = nil
                            }
                        }
                    }
                    .frame(height: 194)
                }

                // X-axis labels below chart
                HStack(spacing: 4) {
                    Spacer().frame(width: 42)
                    xAxisLabelsRow(availableWidth: CGFloat(records.count) * 50)
                }
            }
            .frame(maxHeight: 200)

            HStack(spacing: 16) {
                legendDot(color: .downloadColor, label: L10n.tr("Download"))
                legendDot(color: .uploadColor, label: L10n.tr("Upload"))
            }
            .font(.system(size: 10))
            .padding(.leading, 46)
        }
        .padding(12)
        .background(theme.textMuted.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func peakMarker(value: Double, x: CGFloat, y: CGFloat, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 4, height: 4)
            Text(shortSpeed(value, unit: displayUnit))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(color.opacity(0.9))
                .position(x: x, y: max(10, y - 10))
        }
        .position(x: x, y: y)
    }

    private func hoverTooltip(idx: Int, x: CGFloat, chartSize: CGSize) -> some View {
        let r = records[idx]
        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "en_US_POSIX")
        timeFmt.dateFormat = records.count <= 24 ? "HH:mm" : "MM/dd"
        let timeStr = timeFmt.string(from: r.hour)

        let tooltipW: CGFloat = 100
        let tooltipH: CGFloat = 44
        let tipX = min(max(tooltipW / 2 + 4, x), chartSize.width - tooltipW / 2 - 4)
        let tipY: CGFloat = max(tooltipH / 2 + 4, 40)

        return VStack(alignment: .leading, spacing: 2) {
            Text(shortSpeed(r.avgDown, unit: displayUnit))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.downloadColor)
            Text(timeStr)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.downloadColor.opacity(0.7))
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .frame(width: tooltipW, height: tooltipH)
        .position(x: tipX, y: tipY)
    }

    private var yAxisLabels: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(Array(stride(from: 1.0, through: 0.0, by: -0.25)), id: \.self) { p in
                Text(shortSpeed(niceMax * p, unit: displayUnit))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.textMuted.opacity(0.6))
                    .frame(height: p > 0 ? 180 / 4 : nil, alignment: .top)
                if p > 0 { Spacer(minLength: 0) }
            }
        }
        .frame(height: 180)
    }

    private func xAxisLabelsRow(availableWidth: CGFloat) -> some View {
        let stride = max(1, Int(ceil(50 / (availableWidth / CGFloat(records.count)))))
        let labels = records.enumerated().compactMap { i, r -> (Int, String)? in
            guard i % stride == 0 else { return nil }
            return (i, xLabel(r.hour))
        }
        return HStack(spacing: 0) {
            ForEach(labels, id: \.0) { idx, label in
                Text(label)
                    .font(.system(size: 10, design: .monospaced))
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

// MARK: - Traffic Bar Chart

struct TrafficBarChart: View {
    let records: [DatabaseManager.HourlyRecord]
    let dataUnit: DataUnit
    @Environment(\.colorScheme) var colorScheme
    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }
    @State private var hoverIndex: Int? = nil

    private let barW: CGFloat = 22
    private let barGap: CGFloat = 6
    private let groupGap: CGFloat = 12
    private var colWidth: CGFloat { barW * 2 + barGap + groupGap }
    private let totalColumns = 24

    private var niceMax: Double {
        let peak = records.flatMap { [Double($0.totalDown), Double($0.totalUp)] }.max() ?? 0
        return speedChartMax(peak: peak)
    }

    private var peakHourIndex: Int? {
        guard let maxVal = records.map(\.totalDown).max(), maxVal > 0 else { return nil }
        let cal = Calendar.current
        guard let peakRecord = records.first(where: { $0.totalDown == maxVal }) else { return nil }
        return cal.component(.hour, from: peakRecord.hour)
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

    private var recordsByHour: [Int: DatabaseManager.HourlyRecord] {
        var dict: [Int: DatabaseManager.HourlyRecord] = [:]
        let cal = Calendar.current
        for r in records {
            let hour = cal.component(.hour, from: r.hour)
            dict[hour] = r
        }
        return dict
    }

    private var chartContent: some View {
        let h: CGFloat = 200
        let chartW = CGFloat(totalColumns) * colWidth
        let gridColor: Color = colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06)
        let hourMap = recordsByHour

        return VStack(alignment: .leading, spacing: 6) {
            Text(L10n.tr("Traffic Volume"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(theme.textMuted)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 4) {
                    yAxisLabels
                        .frame(width: 42)

                    ZStack(alignment: .topLeading) {
                        // Grid lines
                        Canvas { ctx, size in
                            for pct in stride(from: 0.25, through: 1.0, by: 0.25) {
                                let y = h - CGFloat(pct) * h
                                var path = Path()
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: size.width, y: y))
                                ctx.stroke(path, with: .color(gridColor), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            }
                        }
                        .frame(width: chartW, height: h)

                        // Bars
                        HStack(alignment: .bottom, spacing: 0) {
                            ForEach(0..<totalColumns, id: \.self) { hour in
                                if let record = hourMap[hour] {
                                    barGroup(record: record, chartHeight: h)
                                } else {
                                    Color.clear.frame(width: colWidth, height: h)
                                }
                            }
                        }
                        .frame(width: chartW, height: h, alignment: .bottomLeading)

                        // Peak marker
                        if let peakHour = peakHourIndex, let peakRecord = hourMap[peakHour] {
                            let peakVal = peakRecord.totalDown
                            let top = niceMax > 0 ? niceMax : 1024
                            let px = colWidth * CGFloat(peakHour) + colWidth / 2
                            let py = h - CGFloat(Double(peakVal) / top) * h
                            peakMarker(value: peakVal, x: px, y: py, color: .downloadColor)
                        }

                        // Hover crosshair
                        if let hour = hoverIndex, let record = hourMap[hour] {
                            let px = colWidth * CGFloat(hour) + colWidth / 2
                            let top = niceMax > 0 ? niceMax : 1024
                            let downY = h - CGFloat(Double(record.totalDown) / top) * h

                            Path { path in
                                path.move(to: CGPoint(x: px, y: 0))
                                path.addLine(to: CGPoint(x: px, y: h))
                            }
                            .stroke(style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                            .foregroundStyle(Color.downloadColor.opacity(0.35))

                            Circle()
                                .fill(Color.downloadColor)
                                .frame(width: 6, height: 6)
                                .position(x: px, y: downY)

                            hoverTooltip(hour: hour, x: px, chartSize: CGSize(width: chartW, height: h))
                        }
                    }
                    .frame(width: chartW, height: h)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            let hour = Int(floor(loc.x / colWidth))
                            hoverIndex = max(0, min(hour, totalColumns - 1))
                        case .ended:
                            hoverIndex = nil
                        }
                    }
                }

                // X-axis labels below chart
                HStack(spacing: 4) {
                    Spacer().frame(width: 42)
                    xAxisLabels(chartWidth: chartW)
                }
            }
            .frame(maxHeight: h + 16)

            HStack(spacing: 16) {
                legendDot(color: .downloadColor, label: L10n.tr("Download"))
                legendDot(color: .uploadColor, label: L10n.tr("Upload"))
            }
            .font(.system(size: 10))
            .padding(.leading, 46)
        }
        .padding(12)
        .background(theme.textMuted.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func peakMarker(value: UInt64, x: CGFloat, y: CGFloat, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 4, height: 4)
            Text(formatBytes(value))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(color.opacity(0.9))
                .position(x: x, y: max(10, y - 10))
        }
        .position(x: x, y: y)
    }

    private func hoverTooltip(hour: Int, x: CGFloat, chartSize: CGSize) -> some View {
        let timeStr = String(format: "%02d:00", hour)
        let record = recordsByHour[hour]

        let tooltipW: CGFloat = 100
        let tooltipH: CGFloat = 44
        let tipX = min(max(tooltipW / 2 + 4, x), chartSize.width - tooltipW / 2 - 4)
        let tipY: CGFloat = max(tooltipH / 2 + 4, 40)

        return VStack(alignment: .leading, spacing: 2) {
            Text(record.map { formatBytes($0.totalDown) } ?? "--")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.downloadColor)
            Text(timeStr)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.downloadColor.opacity(0.7))
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .frame(width: tooltipW, height: tooltipH)
        .position(x: tipX, y: tipY)
    }

    private func barGroup(record: DatabaseManager.HourlyRecord, chartHeight: CGFloat) -> some View {
        let top = niceMax > 0 ? niceMax : 1024
        let downH = CGFloat(Double(record.totalDown) / top) * chartHeight
        let upH = CGFloat(Double(record.totalUp) / top) * chartHeight

        return VStack(spacing: 2) {
            // Values above bars
            HStack(spacing: barGap) {
                if record.totalDown > 0 {
                    Text(formatBytes(record.totalDown))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.downloadColor.opacity(0.8))
                } else {
                    Color.clear.frame(width: barW, height: 1)
                }
                if record.totalUp > 0 {
                    Text(formatBytes(record.totalUp))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.uploadColor.opacity(0.8))
                } else {
                    Color.clear.frame(width: barW, height: 1)
                }
            }
            .frame(width: colWidth)

            // Bars
            HStack(alignment: .bottom, spacing: barGap) {
                Rectangle()
                    .fill(Color.downloadColor)
                    .frame(width: barW, height: max(2, downH))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                Rectangle()
                    .fill(Color.uploadColor)
                    .frame(width: barW, height: max(2, upH))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(width: colWidth)
        }
    }

    private func xAxisLabels(chartWidth: CGFloat) -> some View {
        let stride = max(1, Int(ceil(50 / colWidth)))
        return HStack(spacing: 0) {
            ForEach(0..<totalColumns, id: \.self) { i in
                if i % stride == 0 {
                    Text(hourStr(i))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.textMuted.opacity(0.7))
                        .frame(width: colWidth, alignment: .center)
                } else {
                    Color.clear.frame(width: colWidth)
                }
            }
        }
        .frame(width: chartWidth)
    }

    private func hourStr(_ hour: Int) -> String {
        return String(format: "%02d:00", hour)
    }

    private var yAxisLabels: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(Array(stride(from: 1.0, through: 0.0, by: -0.25)), id: \.self) { p in
                Text(formatBytes(UInt64(niceMax * p)))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.textMuted.opacity(0.6))
                    .frame(height: p > 0 ? 200 / 4 : nil, alignment: .top)
                if p > 0 { Spacer(minLength: 0) }
            }
        }
        .frame(height: 200)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 6, height: 6); Text(label).foregroundColor(theme.textSecondary) }
    }
}
