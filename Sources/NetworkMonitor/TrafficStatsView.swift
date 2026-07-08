import NetworkMonitorCore
import SwiftUI
import AppKit

// MARK: - Time Range

enum TrafficTimeRange: String, CaseIterable {
    case today
    case week
    case year

    var displayName: String {
        switch self {
        case .today: return L10n.tr("Day")
        case .week: return L10n.tr("Week")
        case .year: return L10n.tr("Year")
        }
    }
}

// MARK: - Traffic Stats View

struct TrafficStatsView: View {
    @ObservedObject var engine: NetworkMonitorEngine
    @ObservedObject var settings: AppSettings
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme

    @State private var timeRange: TrafficTimeRange = .today
    @State private var page: BarChartPage?
    @State private var selectedDateStr: String = ""
    @State private var availableDateStrs: [String] = []

    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }
    private let cfg = BarChartConfig.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            controlBar
            scrollContent
        }
        .frame(minWidth: cfg.pW, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
        .background(Color(red: 0x1a / 255, green: 0x1a / 255, blue: 0x1e / 255))
        .onAppear {
            loadAvailableDates()
            loadData()
        }
        .onChange(of: timeRange) { _, _ in loadData() }
        .onChange(of: selectedDateStr) { _, _ in if timeRange == .today { loadData() } }
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

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            ForEach(TrafficTimeRange.allCases, id: \.self) { range in
                let isSelected = timeRange == range
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { timeRange = range }
                } label: {
                    Text(range.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(isSelected ? Color.downloadColor.opacity(0.15) : Color.clear)
                        .foregroundColor(isSelected ? .downloadColor : theme.textMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            if timeRange == .today && !availableDateStrs.isEmpty {
                Divider().frame(height: 16)
                dateDropdown
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Date Dropdown

    private var dateDropdown: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 11))
                .foregroundColor(theme.textMuted)
            Picker("", selection: $selectedDateStr) {
                ForEach(availableDateStrs, id: \.self) { dateStr in
                    Text(formatDateStr(dateStr)).tag(dateStr)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)
        }
    }

    private func formatDateStr(_ dateStr: String) -> String {
        let todayComp = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let todayStr = String(format: "%04d-%02d-%02d", todayComp.year!, todayComp.month!, todayComp.day!)
        if dateStr == todayStr { return L10n.tr("Today") }
        guard let date = ISO8601Formatter.date(from: dateStr + "T00:00:00.000Z") else { return dateStr }
        let fmt = DateFormatter()
        fmt.dateFormat = "MM/dd (E)"
        fmt.locale = Locale(identifier: "zh_CN")
        return fmt.string(from: date)
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            if let page {
                VStack(alignment: .leading, spacing: 16) {
                    statsBar(page)
                    chartSection(data: page.dn, color: .downloadColor, page: page)
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
            hasData: page.hasData,
            sharedMax: barNiceMax([page.dn, page.up].flatMap { $0 }),
            config: cfg
        )
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Load Available Dates

    private func loadAvailableDates() {
        let db = DatabaseManager.shared
        guard let db else { return }
        let summary = db.dailyTrafficSummary(days: 730)

        // 本地今天的日期字符串
        let todayComp = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let todayStr = String(format: "%04d-%02d-%02d", todayComp.year!, todayComp.month!, todayComp.day!)

        // 数据库返回 UTC 日期，转换为本地日期字符串
        // UTC 的 "2026-07-05" 在 UTC+8 对应本地 "2026-07-05" 08:00 ~ "2026-07-06" 08:00
        // 简化处理：直接用 UTC 日期字符串作为本地日期（仅在跨日边界有1-2小时偏差）
        let dateStrs = Array(Set(summary.map { $0.date })).sorted(by: >)

        if dateStrs.first != todayStr {
            availableDateStrs = [todayStr] + dateStrs
        } else {
            availableDateStrs = dateStrs
        }
        if selectedDateStr.isEmpty || !availableDateStrs.contains(selectedDateStr) {
            selectedDateStr = todayStr
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        let db = DatabaseManager.shared
        guard let db else { page = nil; return }
        switch timeRange {
        case .today:
            loadDay(db)
        case .week:
            loadWeek(db)
        case .year:
            loadYear(db)
        }
    }

    // MARK: - Day (24h)

    private func loadDay(_ db: DatabaseManager) {
        let dateStr = selectedDateStr

        // 查询范围：选中日期的本地时间 00:00 ~ 次日 00:00，转为 UTC
        var localCal = Calendar.current
        localCal.timeZone = TimeZone.current
        let dateParts = dateStr.split(separator: "-")
        guard dateParts.count == 3,
              let year = Int(dateParts[0]), let month = Int(dateParts[1]), let day = Int(dateParts[2]),
              let localDate = localCal.date(from: DateComponents(year: year, month: month, day: day)) else {
            page = nil; return
        }
        let startLocal = localCal.startOfDay(for: localDate)
        let endLocal = localCal.date(byAdding: .day, value: 1, to: startLocal)!

        let records = db.hourlyTrafficRange(from: startLocal, to: endLocal)

        // 本地时间判断
        let nowLocal = localCal.component(.hour, from: Date())
        let todayLocal = localCal.dateComponents([.year, .month, .day], from: Date())
        let todayStr = String(format: "%04d-%02d-%02d", todayLocal.year!, todayLocal.month!, todayLocal.day!)
        let isToday = (dateStr == todayStr)

        // 按本地小时填充数据
        var dn = [UInt64](repeating: 0, count: 24)
        var up = [UInt64](repeating: 0, count: 24)
        var hasDataArr = [Bool](repeating: false, count: 24)
        for r in records {
            let h = localCal.component(.hour, from: r.hour)
            if h >= 0 && h < 24 {
                dn[h] = r.totalDown
                up[h] = r.totalUp
                hasDataArr[h] = true
            }
        }

        let l1 = (0..<24).map { String(format: "%02d:00", $0) }
        let l2 = [String](repeating: "", count: 24)
        let s1 = dn.reduce(0, +)
        let s2 = up.reduce(0, +)
        let hoursElapsed = isToday ? max(1, nowLocal + 1) : 24
        let a1 = Double(s1) / Double(hoursElapsed * 3600)
        let a2 = Double(s2) / Double(hoursElapsed * 3600)
        let futureHour = isToday ? (nowLocal - 1) : 99

        page = BarChartPage(
            dn: dn, up: up, l1: l1, l2: l2,
            fut: { $0 > futureHour },
            hasData: { idx in idx < hasDataArr.count && hasDataArr[idx] },
            title: L10n.tr("Day"),
            s1: s1, s2: s2, a1: a1, a2: a2
        )
    }

    // MARK: - Week (从最早数据所在周的周一开始，24天)

    private func loadWeek(_ db: DatabaseManager) {
        let summary = db.dailyTrafficSummary(days: 730)
        let todayStr = currentDateStamp()

        var dataByDate: [String: (down: UInt64, up: UInt64)] = [:]
        for row in summary {
            dataByDate[row.date] = (row.totalDown, row.totalUp)
        }
        let sortedDates = dataByDate.keys.sorted()
        guard let earliestStr = sortedDates.first,
              let earliestDate = ISO8601Formatter.date(from: earliestStr + "T00:00:00.000Z") else {
            page = nil; return
        }

        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: earliestDate)
        let daysBackToMonday = (weekday + 5) % 7
        guard let mondayDate = cal.date(byAdding: .day, value: -daysBackToMonday, to: earliestDate) else {
            page = nil; return
        }

        let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        var dn = [UInt64](), up = [UInt64](), l1 = [String](), l2 = [String]()
        var dates = [String](), hasDataArr = [Bool]()

        for i in 0..<24 {
            guard let d = cal.date(byAdding: .day, value: i, to: mondayDate) else { continue }
            let dateStr = currentDateStamp(from: d)
            let wd = cal.component(.weekday, from: d)
            let data = dataByDate[dateStr]
            dn.append(data?.down ?? 0)
            up.append(data?.up ?? 0)
            l1.append(weekdayNames[wd - 1])
            let parts = dateStr.split(separator: "-")
            l2.append(parts.count >= 3 ? "\(parts[1])/\(parts[2])" : "")
            dates.append(dateStr)
            hasDataArr.append(data != nil)
        }

        let s1 = dn.reduce(0, +), s2 = up.reduce(0, +)
        let totalSec = Double(24 * 86400)

        page = BarChartPage(
            dn: dn, up: up, l1: l1, l2: l2,
            fut: { idx in idx < dates.count && dates[idx] > todayStr },
            hasData: { idx in idx < hasDataArr.count && hasDataArr[idx] },
            title: L10n.tr("Week"),
            s1: s1, s2: s2, a1: Double(s1) / totalSec, a2: Double(s2) / totalSec
        )
    }

    // MARK: - Year (从最早数据所在月开始，24个月)

    private func loadYear(_ db: DatabaseManager) {
        let summary = db.dailyTrafficSummary(days: 730)

        var monthlyDict: [String: (down: UInt64, up: UInt64)] = [:]
        var monthKeysWithData = Set<String>()
        for row in summary {
            let monthKey = String(row.date.prefix(7))
            monthlyDict[monthKey, default: (0, 0)].down += row.totalDown
            monthlyDict[monthKey, default: (0, 0)].up += row.totalUp
            monthKeysWithData.insert(monthKey)
        }

        // 从当年1月开始
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        guard let january = ISO8601Formatter.date(from: "\(year)-01-01T00:00:00.000Z") else {
            page = nil; return
        }

        var months: [(key: String, date: Date)] = []
        for i in 0..<24 {
            guard let d = cal.date(byAdding: .month, value: i, to: january) else { continue }
            months.append((String(ISO8601Formatter.string(from: d).prefix(7)), d))
        }

        let dn = months.map { monthlyDict[$0.key]?.down ?? 0 }
        let up = months.map { monthlyDict[$0.key]?.up ?? 0 }
        let hasDataArr = months.map { monthKeysWithData.contains($0.key) }
        let l1 = months.map { "\(cal.component(.month, from: $0.date))月" }
        let l2 = months.map { "\(cal.component(.year, from: $0.date))" }

        let s1 = dn.reduce(0, +), s2 = up.reduce(0, +)
        let totalSec = Double(24 * 30 * 86400)
        let currentMonthKey = String(ISO8601Formatter.string(from: now).prefix(7))

        page = BarChartPage(
            dn: dn, up: up, l1: l1, l2: l2,
            fut: { idx in idx < months.count && months[idx].key > currentMonthKey },
            hasData: { idx in idx < hasDataArr.count && hasDataArr[idx] },
            title: L10n.tr("Year"),
            s1: s1, s2: s2, a1: Double(s1) / totalSec, a2: Double(s2) / totalSec
        )
    }
}
