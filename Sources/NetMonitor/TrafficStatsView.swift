import NetMonitorCore
import SwiftUI
import AppKit

// Thread-safe ISO8601 helpers
private func iso8601String(from date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: date)
}

private func iso8601Date(from string: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: string)
}

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
    @ObservedObject var engine: NetMonitorEngine
    @ObservedObject var settings: AppSettings
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme

    @State private var timeRange: TrafficTimeRange = .today
    @State private var page: BarChartPage?
    @State private var selectedDateStr: String = ""
    @State private var availableDateStrs: [String] = []
    @State private var refreshTimer: Timer?
    @State private var minutelyLoadedForToday = false

    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }
    private let cfg = BarChartConfig.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            controlBar
            scrollContent
        }
        .frame(minWidth: cfg.pW, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
        .background(theme.appBg)
        .onAppear {
            minutelyLoadedForToday = false
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                DatabaseManager.shared?.flushPendingTrafficSync()
                loadData()
            }
            DatabaseManager.shared?.flushPendingTrafficSync()
            loadAvailableDates()
            loadData()
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
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
        guard let ty = todayComp.year, let tm = todayComp.month, let td = todayComp.day else { return dateStr }
        let todayStr = String(format: "%04d-%02d-%02d", ty, tm, td)
        if dateStr == todayStr { return L10n.tr("Today") }
        guard let date = iso8601Date(from: dateStr + "T00:00:00.000Z") else { return dateStr }
        let fmt = DateFormatter()
        fmt.dateFormat = "MM/dd (E)"
        fmt.locale = Locale.current
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
            statItem(label: L10n.tr("Peak ↓"), value: barFormatBytes(peakDown), color: .downloadColor, small: true)
            statItem(label: L10n.tr("Peak ↑"), value: barFormatBytes(peakUp), color: .uploadColor, small: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: cfg.statsH)
            .background(theme.textMuted.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statItem(label: String, value: String, color: Color, small: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(theme.textMuted.opacity(0.53))
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
            .background(theme.textMuted.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Load Available Dates

    private func loadAvailableDates() {
        let db = DatabaseManager.shared
        guard let db else { return }
        let summary = db.dailyTrafficSummary(days: 730)

        let todayComp = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        guard let ty = todayComp.year, let tm = todayComp.month, let td = todayComp.day else { return }
        let todayStr = String(format: "%04d-%02d-%02d", ty, tm, td)

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

        let dateParts = dateStr.split(separator: "-")
        guard dateParts.count == 3,
              let year = Int(dateParts[0]), let month = Int(dateParts[1]), let day = Int(dateParts[2]) else {
            page = nil; return
        }
        var localCal = Calendar.current
        localCal.timeZone = TimeZone.current
        guard let localDate = localCal.date(from: DateComponents(year: year, month: month, day: day)) else {
            page = nil; return
        }
        let startLocal = localCal.startOfDay(for: localDate)
        guard let endLocal = localCal.date(byAdding: .day, value: 1, to: startLocal) else {
            page = nil; return
        }

        let nowLocal = localCal.component(.hour, from: Date())
        let todayLocal = localCal.dateComponents([.year, .month, .day], from: Date())
        guard let tly = todayLocal.year, let tlm = todayLocal.month, let tld = todayLocal.day else { return }
        let todayStr = String(format: "%04d-%02d-%02d", tly, tlm, tld)
        let isToday = (dateStr == todayStr)

        // Timezone offset in hours (local - UTC)
        let tzOffset = TimeZone.current.secondsFromGMT() / 3600

        if isToday {
            // 1) Instant render: hourly table (completed hours) + live delta for current hour
            let hourlyData = db.dailyHourlyTraffic(for: localDate)
            var dn = [UInt64](repeating: 0, count: 24)
            var up = [UInt64](repeating: 0, count: 24)
            var hasDataArr = [Bool](repeating: false, count: 24)

            // Convert hourly table UTC hours to local hours
            for (utcHour, down, upVal) in hourlyData {
                let localHour = (utcHour + tzOffset + 24) % 24
                if localHour >= 0 && localHour < 24 && localHour < nowLocal {
                    dn[localHour] = down
                    up[localHour] = upVal
                    hasDataArr[localHour] = down > 0 || upVal > 0
                }
            }
            // Live delta for current hour
            let barSumDn = dn.reduce(0, +)
            let barSumUp = up.reduce(0, +)
            if engine.todayDown > barSumDn {
                dn[nowLocal] += engine.todayDown - barSumDn
                hasDataArr[nowLocal] = true
            }
            if engine.todayUp > barSumUp {
                up[nowLocal] += engine.todayUp - barSumUp
                hasDataArr[nowLocal] = true
            }

            // First paint
            renderDayPage(dn: dn, up: up, hasData: hasDataArr, isToday: true, nowLocal: nowLocal)

            // 2) Background minutely aggregation (only once per session)
            if !minutelyLoadedForToday {
                minutelyLoadedForToday = true
                db.minutelyTrafficAsync(from: startLocal, to: endLocal) { minutelyData in
                    var newDn = [UInt64](repeating: 0, count: 24)
                    var newUp = [UInt64](repeating: 0, count: 24)
                    var newHas = [Bool](repeating: false, count: 24)
                    for record in minutelyData {
                        let h = localCal.component(.hour, from: record.time)  // LOCAL hour
                        if h >= 0 && h < 24 {
                            newDn[h] += record.down
                            newUp[h] += record.up
                            newHas[h] = true
                        }
                    }
                    // Live delta for current hour
                    let barSumDn = newDn.reduce(0, +)
                    let barSumUp = newUp.reduce(0, +)
                    if self.engine.todayDown > barSumDn {
                        newDn[nowLocal] += self.engine.todayDown - barSumDn
                        newHas[nowLocal] = true
                    }
                    if self.engine.todayUp > barSumUp {
                        newUp[nowLocal] += self.engine.todayUp - barSumUp
                        newHas[nowLocal] = true
                    }
                    DispatchQueue.main.async {
                        self.renderDayPage(dn: newDn, up: newUp, hasData: newHas, isToday: true, nowLocal: nowLocal)
                    }
                }
            }
        } else {
            // Past days: hourly table is complete, instant render
            let hourlyData = db.dailyHourlyTraffic(for: localDate)
            var dn = [UInt64](repeating: 0, count: 24)
            var up = [UInt64](repeating: 0, count: 24)
            var hasDataArr = [Bool](repeating: false, count: 24)
            for (utcHour, down, upVal) in hourlyData {
                let localHour = (utcHour + tzOffset + 24) % 24
                if localHour >= 0 && localHour < 24 {
                    dn[localHour] = down
                    up[localHour] = upVal
                    hasDataArr[localHour] = down > 0 || upVal > 0
                }
            }
            renderDayPage(dn: dn, up: up, hasData: hasDataArr, isToday: false, nowLocal: 99)
        }
    }

    private func renderDayPage(dn: [UInt64], up: [UInt64], hasData: [Bool], isToday: Bool, nowLocal: Int) {
        let l1 = (0..<24).map { String(format: "%02d:00", $0) }
        let l2 = [String](repeating: "", count: 24)
        let s1 = isToday ? engine.todayDown : dn.reduce(0, +)
        let s2 = isToday ? engine.todayUp : up.reduce(0, +)
        let hoursElapsed = isToday ? max(1, nowLocal + 1) : 24
        let a1 = Double(s1) / Double(hoursElapsed * 3600)
        let a2 = Double(s2) / Double(hoursElapsed * 3600)
        let futureHour = isToday ? nowLocal : 99
        page = BarChartPage(
            dn: dn, up: up, l1: l1, l2: l2,
            fut: { $0 > futureHour },
            hasData: { idx in idx < hasData.count && hasData[idx] },
            title: L10n.tr("Day"),
            s1: s1, s2: s2, a1: a1, a2: a2
        )
    }

    // MARK: - Week (从最早数据所在周的周一开始，24天)

    private func loadWeek(_ db: DatabaseManager) {
        let summary = db.dailyTrafficSummary(days: 730)
        let todayStr = currentDateStamp()

        let cal = Calendar.current
        var dataByDate: [String: (down: UInt64, up: UInt64)] = [:]
        for row in summary {
            dataByDate[row.date] = (row.totalDown, row.totalUp)
        }

        let sortedDates = dataByDate.keys.sorted()
        guard let earliestStr = sortedDates.first,
              let earliestDate = iso8601Date(from: earliestStr + "T00:00:00.000Z") else {
            page = nil; return
        }

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
            let isTodayBucket = (dateStr == todayStr)
            if isTodayBucket {
                dn.append(engine.todayDown)
                up.append(engine.todayUp)
                hasDataArr.append(true)
            } else {
                let data = dataByDate[dateStr]
                dn.append(data?.down ?? 0)
                up.append(data?.up ?? 0)
                hasDataArr.append(data != nil)
            }
            l1.append(weekdayNames[wd - 1])
            let parts = dateStr.split(separator: "-")
            l2.append(parts.count >= 3 ? "\(parts[1])/\(parts[2])" : "")
            dates.append(dateStr)
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

        let cal = Calendar.current
        let now = Date()
        var monthlyDict: [String: (down: UInt64, up: UInt64)] = [:]
        var monthKeysWithData = Set<String>()
        for row in summary {
            let monthKey = String(row.date.prefix(7))
            monthlyDict[monthKey, default: (0, 0)].down += row.totalDown
            monthlyDict[monthKey, default: (0, 0)].up += row.totalUp
            monthKeysWithData.insert(monthKey)
        }

// Patch current month with today's unaggregated traffic
        if let currentHourStart = cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: now)) {
            let hourMinutely = db.minutelyTraffic(from: currentHourStart, to: now)
            var extraDown: UInt64 = 0, extraUp: UInt64 = 0
            for m in hourMinutely { extraDown += m.down; extraUp += m.up }
            if extraDown > 0 || extraUp > 0 {
                let currentMonthKey = String(iso8601String(from: now).prefix(7))
                monthlyDict[currentMonthKey, default: (0, 0)].down += extraDown
                monthlyDict[currentMonthKey, default: (0, 0)].up += extraUp
                monthKeysWithData.insert(currentMonthKey)
            }
        }
        
        // 从当年1月开始
        let year = cal.component(.year, from: now)
        let isoJan = "\(year)-01-01T00:00:00.000Z"
        guard let january = iso8601Date(from: isoJan) else {
            page = nil; return
        }

        var months: [(key: String, date: Date)] = []
        for i in 0..<24 {
            guard let d = cal.date(byAdding: .month, value: i, to: january) else { continue }
            months.append((String(iso8601String(from: d).prefix(7)), d))
        }

        let dn = months.map { monthlyDict[$0.key]?.down ?? 0 }
        let up = months.map { monthlyDict[$0.key]?.up ?? 0 }
        let hasDataArr = months.map { monthKeysWithData.contains($0.key) }
        let l1 = months.map { "\(cal.component(.month, from: $0.date))月" }
        let l2 = months.map { "\(cal.component(.year, from: $0.date))" }

        let s1 = dn.reduce(0, +), s2 = up.reduce(0, +)
        let totalSec = Double(24 * 30 * 86400)
        let currentMonthKey = String(iso8601String(from: now).prefix(7))

        page = BarChartPage(
            dn: dn, up: up, l1: l1, l2: l2,
            fut: { idx in idx < months.count && months[idx].key > currentMonthKey },
            hasData: { idx in idx < hasDataArr.count && hasDataArr[idx] },
            title: L10n.tr("Year"),
            s1: s1, s2: s2, a1: Double(s1) / totalSec, a2: Double(s2) / totalSec
        )
    }
}
