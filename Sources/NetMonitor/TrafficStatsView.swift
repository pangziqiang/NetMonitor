import NetMonitorCore
import SwiftUI
import AppKit

// MARK: - Time Range

enum TrafficTimeRange: String, CaseIterable {
    case hour
    case day
    case month

    var displayName: String {
        switch self {
        case .hour: return L10n.tr("Hour")
        case .day: return L10n.tr("Day")
        case .month: return L10n.tr("Month")
        }
    }
}

// MARK: - Traffic Stats View

struct TrafficStatsView: View {
    private static let cachedDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM/dd (E)"
        fmt.locale = Locale.current
        return fmt
    }()
    @ObservedObject var engine: NetMonitorEngine
    @ObservedObject var settings: AppSettings
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme

    @State private var timeRange: TrafficTimeRange = .hour
    @State private var page: BarChartPage?
    @State private var selectedDateStr: String = ""
    @State private var availableDateStrs: [String] = []
    @State private var refreshTimer: Timer?
    @State private var todayDnBase: [UInt64] = []
    @State private var todayUpBase: [UInt64] = []
    @State private var todayBaseLoaded = false

    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }
    private let cfg = BarChartConfig.shared

    @State private var detailProcesses: [(name: String, down: UInt64, up: UInt64)] = []
    @State private var showDetailSheet = false
    @State private var detailLabel = ""
    @State private var detailType: BarType = .download
    @State private var detailBarDown: UInt64 = 0
    @State private var detailBarUp: UInt64 = 0

    /// Week-page date stamps (YYYY-MM-DD), index-aligned with bars
    @State private var dayDates: [String] = []

    /// Day view (24 days) window end date (YYYY-MM-DD); empty = today
    @State private var dayWindowEndStr = ""
    /// 日视图箭头步进：选"时间段"=24（整窗口翻页），选"单日结束日期"=1（滚动条逐日滑动）
    @State private var dayArrowStep = 24
    /// 月视图窗口起点（YYYY-MM）；空 = 当年 1 月
    @State private var monthWindowStartStr = ""
    /// 进程流量历史 sheet
    @State private var showProcessHistory = false
    @State private var processHistory: [(pid: Int32, name: String, down: UInt64, up: UInt64)] = []
    @State private var historyRangeLabel = ""
    @State private var selectedProcess: (pid: Int32, name: String)?
    @State private var processDaily: [(day: String, down: UInt64, up: UInt64)] = []
    /// 页面数据指纹：数据未变化时跳过整页重建/重绘（避免 3 秒定时器空转）
    @State private var lastPageFingerprint = -1
    /// 自定义日期下拉面板（替代系统 Picker 菜单，避免选中早期日期时菜单向上弹出被遮挡）
    @State private var showDateDropdown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            controlBar
            scrollContent
        }
        .frame(minWidth: cfg.pW, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
        .background(theme.appBg)
        .onAppear {
            refreshTimer?.invalidate()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                DatabaseManager.shared?.flushPendingTrafficSyncIfNeeded()
                refreshLiveData()
            }
            DatabaseManager.shared?.flushPendingTrafficSyncIfNeeded()
            loadAvailableDates()
            loadData()
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
        .onChange(of: timeRange) { _, _ in todayBaseLoaded = false; loadData() }
        .onChange(of: selectedDateStr) { _, _ in todayBaseLoaded = false; if timeRange == .hour { loadData() } }
        .onChange(of: dayWindowEndStr) { _, _ in if timeRange == .day { loadData() } }
        .onChange(of: monthWindowStartStr) { _, _ in if timeRange == .month { loadData() } }
        .sheet(isPresented: $showDetailSheet) {
            processDetailSheet
        }
        .sheet(isPresented: $showProcessHistory) {
            processHistorySheet
        }
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

            if timeRange == .hour && !availableDateStrs.isEmpty {
                Divider().frame(height: 16)
                hourDateControl
            }

            if timeRange == .day {
                Divider().frame(height: 16)
                dayRangeControl
            }

            if timeRange == .month {
                Divider().frame(height: 16)
                monthRangePager
            }

            if canReturnToToday {
                Button {
                    resetToToday()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 10))
                        Text(L10n.tr("Today")).font(.system(size: 11))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.textMuted.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .foregroundColor(.downloadColor)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                openProcessHistory()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "app.badge").font(.system(size: 11))
                    Text(L10n.tr("Process Traffic History")).font(.system(size: 11))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(theme.textMuted.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .foregroundColor(theme.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Date Dropdown

    // MARK: - 时视图: ◀ 日期下拉 ▶

    private var hourDateControl: some View {
        HStack(spacing: 6) {
            stepButton(systemImage: "chevron.left", enabled: canGoHourEarlier) {
                shiftHourDate(+1)
            }

            dateDropdown

            stepButton(systemImage: "chevron.right", enabled: canGoHourLater) {
                shiftHourDate(-1)
            }
        }
    }

    private var dateDropdown: some View {
        Button {
            showDateDropdown.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundColor(theme.textMuted)
                Text(formatDateStr(selectedDateStr))
                    .font(.system(size: 12))
                    .foregroundColor(theme.textSecondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundColor(theme.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(theme.textMuted.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDateDropdown, arrowEdge: .top) {
            dropdownPanel {
                ForEach(availableDateStrs, id: \.self) { dateStr in
                    pickerRow(label: formatDateStr(dateStr), value: dateStr, selected: selectedDateStr) {
                        selectedDateStr = dateStr
                        todayBaseLoaded = false
                        showDateDropdown = false
                    }
                }
            }
        }
    }

    private var canGoHourEarlier: Bool {
        guard let idx = availableDateStrs.firstIndex(of: selectedDateStr) else { return false }
        return idx < availableDateStrs.count - 1
    }

    private var canGoHourLater: Bool {
        guard let idx = availableDateStrs.firstIndex(of: selectedDateStr) else { return false }
        return idx > 0
    }

    private func shiftHourDate(_ delta: Int) {
        guard let idx = availableDateStrs.firstIndex(of: selectedDateStr) else { return }
        let newIdx = min(max(idx + delta, 0), availableDateStrs.count - 1)
        let newDate = availableDateStrs[newIdx]
        guard newDate != selectedDateStr else { return }
        selectedDateStr = newDate
        todayBaseLoaded = false
        loadData()
    }

    private func formatDateStr(_ dateStr: String) -> String {
        let todayComp = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        guard let ty = todayComp.year, let tm = todayComp.month, let td = todayComp.day else { return dateStr }
        let todayStr = String(format: "%04d-%02d-%02d", ty, tm, td)
        if dateStr == todayStr { return L10n.tr("Today") }
        guard let date = iso8601Date(from: dateStr + "T00:00:00.000Z") else { return dateStr }
        return Self.cachedDateFormatter.string(from: date)
    }

    // MARK: - 日视图: ◀ 窗口终点下拉 ▶（24天窗口）

    private var dayRangeControl: some View {
        HStack(spacing: 6) {
            stepButton(systemImage: "chevron.left", enabled: dayCanGoEarlier) {
                shiftDayWindow(-dayArrowStep)
            }

            Button {
                showDateDropdown.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                        .foregroundColor(theme.textMuted)
                    Text(dayDropdownLabel)
                        .font(.system(size: 12))
                        .foregroundColor(theme.textSecondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(theme.textMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(theme.textMuted.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showDateDropdown, arrowEdge: .top) {
                dropdownPanel {
                    ForEach(dayWindowOptions, id: \.end) { opt in
                        pickerRow(label: opt.label, value: opt.end, selected: dayEndDate) {
                            dayArrowStep = 24
                            dayWindowEndStr = opt.end
                            showDateDropdown = false
                        }
                    }
                    Divider().padding(.vertical, 4)
                    ForEach(daySingleDates, id: \.self) { dateStr in
                        pickerRow(label: formatDateStr(dateStr), value: dateStr, selected: dayEndDate) {
                            dayArrowStep = 1
                            dayWindowEndStr = dateStr
                            showDateDropdown = false
                        }
                    }
                }
            }

            stepButton(systemImage: "chevron.right", enabled: dayCanGoLater) {
                shiftDayWindow(+dayArrowStep)
            }
        }
    }

    private var dayDropdownLabel: String {
        if let opt = dayWindowOptions.first(where: { $0.end == dayEndDate }) {
            return opt.label
        }
        return formatDateStr(dayEndDate)
    }

    /// 自定义下拉面板：scrollable 列表，popover 自动保持在屏幕内，不会被边缘裁剪
    private func dropdownPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
        }
        .frame(width: 230, height: 340)
        .background(theme.appBg)
    }

    private func pickerRow(label: String, value: String, selected: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(value == selected ? .downloadColor : theme.textSecondary)
                Spacer()
                if value == selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10))
                        .foregroundColor(.downloadColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(value == selected ? Color.downloadColor.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var dayEndDate: String {
        dayWindowEndStr.isEmpty ? currentDateStamp() : dayWindowEndStr
    }

    private var dayCanGoEarlier: Bool {
        guard let earliest = availableDateStrs.last,
              let end = iso8601Date(from: dayEndDate + "T00:00:00.000Z"),
              let back = Calendar.current.date(byAdding: .day, value: -dayArrowStep, to: end) else { return false }
        return currentDateStamp(from: back) >= earliest
    }

    private var dayCanGoLater: Bool {
        dayEndDate < currentDateStamp()
    }

    private func shiftDayWindow(_ delta: Int) {
        guard let end = iso8601Date(from: dayEndDate + "T00:00:00.000Z"),
              let target = Calendar.current.date(byAdding: .day, value: delta, to: end) else { return }
        let targetStr = currentDateStamp(from: target)
        let todayStr = currentDateStamp()
        if delta > 0 {
            // 向右翻：不能超过今天；若 +24 天会越过今天，则直接落到今天窗口
            if targetStr > todayStr {
                guard todayStr != dayEndDate else { return }
                dayWindowEndStr = todayStr
                return
            }
        } else {
            guard let earliest = availableDateStrs.last, targetStr >= earliest else { return }
        }
        guard targetStr != dayEndDate else { return }
        dayWindowEndStr = targetStr
    }

    private func stepButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(enabled ? theme.textSecondary : theme.textMuted.opacity(0.2))
        .disabled(!enabled)
    }

    /// 日视图下拉项：按 24 天对齐的窗口列表（07/14 ~ 08/06、06/20 ~ 07/13 …），
    /// 与 ◀▶ 翻页完全一致；窗口终点 = 今天 - n*24。
    private var dayWindowOptions: [(label: String, end: String)] {
        let cal = Calendar.current
        let todayStr = currentDateStamp()
        guard let today = iso8601Date(from: todayStr + "T00:00:00.000Z") else { return [] }
        var options: [(String, String)] = []
        var n = 0
        while true {
            guard let end = cal.date(byAdding: .day, value: -n * 24, to: today),
                  let start = cal.date(byAdding: .day, value: -23, to: end) else { break }
            let endStr = currentDateStamp(from: end)
            if let earliest = availableDateStrs.last, endStr < earliest { break }
            options.append((label: dayRangeText(start: start, end: end), end: endStr))
            n += 1
        }
        return options
    }

    /// 单日列表：排除已出现在"时间段"里的终点日期，避免 Picker tag 重复
    private var daySingleDates: [String] {
        let alignedEnds = Set(dayWindowOptions.map { $0.end })
        return availableDateStrs.filter { !alignedEnds.contains($0) }
    }

    // MARK: - 月视图翻页（24 个月窗口，◀▶ 按 12 个月步进）

    private var monthRangePager: some View {
        HStack(spacing: 6) {
            stepButton(systemImage: "chevron.left", enabled: monthCanGoEarlier) {
                shiftMonthWindow(-12)
            }
            Text(monthRangeLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.textSecondary)
                .frame(minWidth: 150)
            stepButton(systemImage: "chevron.right", enabled: monthCanGoLater) {
                shiftMonthWindow(+12)
            }
        }
    }

    private var monthDefaultStartKey: String {
        "\(Calendar.current.component(.year, from: Date()))-01"
    }

    private var monthStartKey: String {
        monthWindowStartStr.isEmpty ? monthDefaultStartKey : monthWindowStartStr
    }

    private var monthCanGoEarlier: Bool {
        guard let start = iso8601Date(from: monthStartKey + "-01T00:00:00.000Z"),
              let back = Calendar.current.date(byAdding: .month, value: -12, to: start),
              let backEnd = Calendar.current.date(byAdding: .month, value: 23, to: back),
              let earliest = availableDateStrs.last,
              let earliestDate = iso8601Date(from: earliest + "T00:00:00.000Z") else { return false }
        return backEnd >= earliestDate
    }

    private var monthCanGoLater: Bool {
        monthStartKey < monthDefaultStartKey
    }

    private func shiftMonthWindow(_ delta: Int) {
        guard let start = iso8601Date(from: monthStartKey + "-01T00:00:00.000Z"),
              let target = Calendar.current.date(byAdding: .month, value: delta, to: start) else { return }
        let targetKey = String(iso8601String(from: target).prefix(7))
        if delta > 0 {
            // 右翻不能越过"当年 1 月"窗口；超出则直接落回默认
            if targetKey > monthDefaultStartKey {
                guard monthStartKey != monthDefaultStartKey else { return }
                monthWindowStartStr = monthDefaultStartKey
                return
            }
        } else {
            guard let earliest = availableDateStrs.last else { return }
            let earliestKey = String(earliest.prefix(7))
            guard let targetEnd = Calendar.current.date(byAdding: .month, value: 23, to: target),
                  String(iso8601String(from: targetEnd).prefix(7)) >= earliestKey else { return }
        }
        guard targetKey != monthStartKey else { return }
        monthWindowStartStr = targetKey
    }

    private var monthRangeLabel: String {
        guard let start = iso8601Date(from: monthStartKey + "-01T00:00:00.000Z"),
              let end = Calendar.current.date(byAdding: .month, value: 23, to: start) else { return "" }
        let endKey = String(iso8601String(from: end).prefix(7))
        return "\(monthStartKey) ~ \(endKey)"
    }

    private var canReturnToToday: Bool {
        switch timeRange {
        case .hour: return !selectedDateStr.isEmpty && selectedDateStr != currentDateStamp()
        case .day: return dayEndDate != currentDateStamp()
        case .month: return monthStartKey != monthDefaultStartKey
        }
    }

    private func resetToToday() {
        switch timeRange {
        case .hour:
            selectedDateStr = currentDateStamp()
            todayBaseLoaded = false
            loadData()
        case .day:
            dayWindowEndStr = ""
        case .month:
            monthWindowStartStr = ""
        }
    }

    private func dayRangeText(start: Date, end: Date) -> String {
        let f = { (d: Date) -> String in
            let c = Calendar.current.dateComponents([.month, .day], from: d)
            return String(format: "%02d/%02d", c.month ?? 0, c.day ?? 0)
        }
        return "\(f(start)) ~ \(f(end))"
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
            config: cfg,
            onBarDoubleTap: { index in
                onBarDoubleTapped(index: index, type: color == .downloadColor ? .download : .upload, value: data[index])
            }
        )
            .background(theme.textMuted.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private enum BarType { case download, upload }

    private func onBarDoubleTapped(index: Int, type: BarType, value: UInt64) {
        guard let db = DatabaseManager.shared else { return }
        guard index >= 0, index < 24 else { return }
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        var startDate: Date?
        var endDate: Date?
        var label = ""

        switch timeRange {
        case .hour:
            let dateParts = selectedDateStr.split(separator: "-")
            guard dateParts.count == 3,
                  let year = Int(dateParts[0]), let month = Int(dateParts[1]), let day = Int(dateParts[2])
            else { return }
            guard let dayStart = cal.date(from: DateComponents(year: year, month: month, day: day))
            else { return }
            startDate = cal.date(byAdding: .hour, value: index, to: dayStart)
            endDate = cal.date(byAdding: .hour, value: 1, to: startDate ?? dayStart)
            label = String(format: "%02d:00", index)

        case .day:
            guard index < dayDates.count else { return }
            let parts = dayDates[index].split(separator: "-")
            guard parts.count == 3,
                  let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
            else { return }
            startDate = cal.date(from: DateComponents(year: year, month: month, day: day))
            endDate = cal.date(byAdding: .day, value: 1, to: startDate ?? Date())
            label = dayDates[index]

        case .month:
            return  // month-level too broad for process detail
        }

        guard let s = startDate, let e = endDate else { return }
        detailLabel = label
        detailType = type
        // Use actual bar values for header totals (not process JSON sum)
        if index >= 0 && index < 24 {
            detailBarDown = page?.dn[index] ?? 0
            detailBarUp = page?.up[index] ?? 0
        }
        let processes = db.topProcessesFromMinutely(from: s, to: e, limit: 20)
        // Sort processes by the active type (download or upload)
        if type == .download {
            detailProcesses = processes.sorted { $0.down > $1.down }
        } else {
            detailProcesses = processes.sorted { $0.up > $1.up }
        }
        showDetailSheet = true
    }

    private var processDetailSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(detailLabel)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(L10n.tr("Close")) { showDetailSheet = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.downloadColor)
            }
            .padding(.bottom, 8)

            if detailProcesses.isEmpty {
                Text(L10n.tr("No Data"))
                    .foregroundColor(theme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        HStack {
                            Text(L10n.tr("Process")).frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(L10n.tr("Download"))（\(barFormatBytes(detailBarDown))）")
                                .frame(width: 150, alignment: .trailing)
                                .foregroundColor(detailType == .download ? .downloadColor : theme.textMuted)
                            Text("\(L10n.tr("Upload"))（\(barFormatBytes(detailBarUp))）")
                                .frame(width: 150, alignment: .trailing)
                                .foregroundColor(detailType == .upload ? .uploadColor : theme.textMuted)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.textMuted)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(theme.textMuted.opacity(0.05))

                        Divider()

                        ForEach(Array(detailProcesses.enumerated()), id: \.offset) { _, proc in
                            HStack {
                                Text(proc.name)
                                    .lineLimit(1).truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(barFormatBytes(proc.down))
                                    .foregroundColor(detailType == .download ? .downloadColor : theme.textPrimary)
                                    .fontWeight(detailType == .download ? .bold : .regular)
                                    .frame(width: 150, alignment: .trailing)
                                Text(barFormatBytes(proc.up))
                                    .foregroundColor(detailType == .upload ? .uploadColor : theme.textPrimary)
                                    .fontWeight(detailType == .upload ? .bold : .regular)
                                    .frame(width: 150, alignment: .trailing)
                            }
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(theme.textPrimary)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            Divider().opacity(0.1)
                        }
                    }
                    .background(theme.textMuted.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 520, height: 400)
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
        if dayWindowEndStr.isEmpty {
            dayWindowEndStr = todayStr
        }
    }

    // MARK: - 进程流量历史（process_traffic 明细）

    private var processHistorySheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.tr("Process Traffic History"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                Text(historyRangeLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.textMuted)
                Spacer()
                Button(L10n.tr("Close")) { showProcessHistory = false }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            if let sel = selectedProcess {
                HStack(spacing: 8) {
                    Text(sel.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.downloadColor)
                    Text(L10n.tr("Daily Breakdown"))
                        .font(.system(size: 10))
                        .foregroundColor(theme.textMuted)
                    Spacer()
                    Button {
                        selectedProcess = nil
                        processDaily = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(theme.textMuted.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(processDaily, id: \.day) { row in
                            HStack {
                                Text(row.day)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(theme.textSecondary)
                                    .frame(width: 90, alignment: .leading)
                                Text("↓ \(formatBytes(row.down, dataUnit: settings.dataUnit))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.downloadColor)
                                Spacer()
                                Text("↑ \(formatBytes(row.up, dataUnit: settings.dataUnit))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.uploadColor)
                            }
                        }
                        if processDaily.isEmpty {
                            Text(L10n.tr("No Data"))
                                .font(.system(size: 11))
                                .foregroundColor(theme.textMuted)
                                .padding(.vertical, 6)
                        }
                    }
                }
                .frame(maxHeight: 180)
                Divider()
            }

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(processHistory.enumerated()), id: \.offset) { _, row in
                        Button {
                            selectProcess(row)
                        } label: {
                            HStack(spacing: 8) {
                                Text(row.name)
                                    .font(.system(size: 11))
                                    .foregroundColor(theme.textSecondary)
                                    .lineLimit(1)
                                Spacer()
                                Text("↓ \(formatBytes(row.down, dataUnit: settings.dataUnit))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.downloadColor)
                                Text("↑ \(formatBytes(row.up, dataUnit: settings.dataUnit))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.uploadColor)
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if processHistory.isEmpty {
                        Text(L10n.tr("No Data"))
                            .font(.system(size: 11))
                            .foregroundColor(theme.textMuted)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 540, height: 480)
        .background(theme.appBg)
    }

    private func openProcessHistory() {
        guard let (from, to) = currentHistoryRange(),
              let db = DatabaseManager.shared else { return }
        processHistory = db.processTrafficSummary(from: from, to: to, limit: 30)
        selectedProcess = nil
        processDaily = []
        let f = Self.cachedDateFormatter.string(from: from)
        let t = Self.cachedDateFormatter.string(from: to)
        historyRangeLabel = "\(f) ~ \(t)"
        showProcessHistory = true
    }

    private func selectProcess(_ row: (pid: Int32, name: String, down: UInt64, up: UInt64)) {
        guard let (from, to) = currentHistoryRange(),
              let db = DatabaseManager.shared else { return }
        selectedProcess = (row.pid, row.name)
        processDaily = db.processTrafficDaily(pid: row.pid, name: row.name, from: from, to: to)
    }

    private func currentHistoryRange() -> (Date, Date)? {
        let cal = Calendar.current
        switch timeRange {
        case .hour:
            guard !selectedDateStr.isEmpty,
                  let d = iso8601Date(from: selectedDateStr + "T00:00:00.000Z"),
                  let end = cal.date(byAdding: .day, value: 1, to: d) else { return nil }
            return (d, end)
        case .day:
            guard let first = dayDates.first, let last = dayDates.last,
                  let f = iso8601Date(from: first + "T00:00:00.000Z"),
                  let l = iso8601Date(from: last + "T00:00:00.000Z"),
                  let end = cal.date(byAdding: .day, value: 1, to: l) else { return nil }
            return (f, end)
        case .month:
            guard let s = iso8601Date(from: monthStartKey + "-01T00:00:00.000Z"),
                  let e = cal.date(byAdding: .month, value: 24, to: s) else { return nil }
            return (s, e)
        }
    }

    // MARK: - Data Loading

    /// 3 秒定时刷新：只有当前可见数据会变化时才重载。
    /// 历史视图（过去的某天、翻页回看的日窗口）数据是静态的，跳过可省掉
    /// 每 3 秒一次的 DB 查询与整页重绘。
    private func refreshLiveData() {
        let todayStr = currentDateStamp()
        switch timeRange {
        case .hour:
            if selectedDateStr.isEmpty || selectedDateStr == todayStr { loadData() }
        case .day:
            if dayWindowEndStr.isEmpty || dayWindowEndStr == todayStr { loadData() }
        case .month:
            loadData()
        }
    }

    private func loadData() {
        let db = DatabaseManager.shared
        guard let db else { page = nil; return }
        switch timeRange {
        case .hour:
            loadHour(db)
        case .day:
            loadDay(db)
        case .month:
            loadMonth(db)
        }
    }

    // MARK: - Day (24h)

    private func loadHour(_ db: DatabaseManager) {
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
        guard localCal.date(byAdding: .day, value: 1, to: startLocal) != nil else {
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
            // First tick: aggregate ALL minutely data for today (sync, ~50ms once)
            if !todayBaseLoaded {
                let records = db.minutelyTrafficByHour(for: localDate)
                var dn = [UInt64](repeating: 0, count: 24)
                var up = [UInt64](repeating: 0, count: 24)
                var hasDataArr = [Bool](repeating: false, count: 24)
                for record in records {
                    let localHour = (record.hour + tzOffset + 24) % 24
                    guard localHour >= 0 && localHour < 24 else { continue }
                    dn[localHour] = record.down
                    up[localHour] = record.up
                    hasDataArr[localHour] = true
                }
                // Engine delta for current hour
                let sumDn = dn.reduce(0, +)
                if engine.todayDown > sumDn {
                    dn[nowLocal] += engine.todayDown - sumDn
                    hasDataArr[nowLocal] = true
                }
                let sumUp = up.reduce(0, +)
                if engine.todayUp > sumUp {
                    up[nowLocal] += engine.todayUp - sumUp
                    hasDataArr[nowLocal] = true
                }
                todayDnBase = dn
                todayUpBase = up
                todayBaseLoaded = true
                renderDayPage(dn: dn, up: up, hasData: hasDataArr, isToday: true, nowLocal: nowLocal)
            } else {
                // Subsequent ticks: re-aggregate from SQL (fast, ~5ms) + engine delta
                var dn = [UInt64](repeating: 0, count: 24)
                var up = [UInt64](repeating: 0, count: 24)
                var hasDataArr = [Bool](repeating: false, count: 24)
                let freshRecords = db.minutelyTrafficByHour(for: localDate)
                for record in freshRecords {
                    let localHour = (record.hour + tzOffset + 24) % 24
                    guard localHour >= 0 && localHour < 24 else { continue }
                    dn[localHour] = record.down
                    up[localHour] = record.up
                    hasDataArr[localHour] = true
                }
                // Engine delta on top of refreshed data
                let sumAfterRefresh = dn.reduce(0, +)
                if engine.todayDown > sumAfterRefresh {
                    dn[nowLocal] += engine.todayDown - sumAfterRefresh
                    hasDataArr[nowLocal] = true
                }
                let upSumAfterRefresh = up.reduce(0, +)
                if engine.todayUp > upSumAfterRefresh {
                    up[nowLocal] += engine.todayUp - upSumAfterRefresh
                    hasDataArr[nowLocal] = true
                }
                renderDayPage(dn: dn, up: up, hasData: hasDataArr, isToday: true, nowLocal: nowLocal)
            }
        } else {
            // Past days: hourly table as base, fallback to minutely for missing hours
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
            // Fallback: fill missing hours from traffic_minutely
            
            if !hasDataArr.allSatisfy({ $0 }) {
                let minutelyRecords = db.minutelyTrafficByHour(for: localDate)
                for record in minutelyRecords {
                    let localHour = (record.hour + tzOffset + 24) % 24
                    guard localHour >= 0 && localHour < 24 else { continue }
                    if !hasDataArr[localHour] {
                        dn[localHour] = record.down
                        up[localHour] = record.up
                        hasDataArr[localHour] = record.down > 0 || record.up > 0
                    }
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
        publishPage(BarChartPage(
            dn: dn, up: up, l1: l1, l2: l2,
            fut: { $0 > futureHour },
            hasData: { idx in idx < hasData.count && hasData[idx] },
            title: L10n.tr("Hour"),
            s1: s1, s2: s2, a1: a1, a2: a2
        ), dn: dn, up: up, window: l2)
    }

    // MARK: - Week (从最早数据所在周的周一开始，24天)

    private func loadDay(_ db: DatabaseManager) {
        let summary = db.dailyTrafficSummary(days: 730)
        let todayStr = currentDateStamp()

        let cal = Calendar.current
        var dataByDate: [String: (down: UInt64, up: UInt64)] = [:]
        for row in summary {
            dataByDate[row.date] = (row.totalDown, row.totalUp)
        }

        // 锚定窗口终点：默认今天；下拉/翻页可改终点（每页 24 天）。
        guard let endDate = iso8601Date(from: dayEndDate + "T00:00:00.000Z"),
              let startDate = cal.date(byAdding: .day, value: -23, to: endDate) else {
            page = nil; return
        }

        let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        var dn = [UInt64](), up = [UInt64](), l1 = [String](), l2 = [String]()
        var dates = [String](), hasDataArr = [Bool]()

        for i in 0..<24 {
            guard let d = cal.date(byAdding: .day, value: i, to: startDate) else { continue }
            let dateStr = currentDateStamp(from: d)
            let wd = cal.component(.weekday, from: d)
            // 实时今日桶只在窗口锚定今天时生效；历史窗口用数据库数据
            let isTodayBucket = (dateStr == todayStr && dayEndDate == todayStr)
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

        dayDates = dates

        let s1 = dn.reduce(0, +), s2 = up.reduce(0, +)
        let totalSec = Double(24 * 86400)

        publishPage(BarChartPage(
            dn: dn, up: up, l1: l1, l2: l2,
            fut: { idx in idx < dates.count && dates[idx] > todayStr },
            hasData: { idx in idx < hasDataArr.count && hasDataArr[idx] },
            title: L10n.tr("Day"),
            s1: s1, s2: s2, a1: Double(s1) / totalSec, a2: Double(s2) / totalSec
        ), dn: dn, up: up, window: dates)
    }

    // MARK: - Year (从最早数据所在月开始，24个月)

    private func loadMonth(_ db: DatabaseManager) {
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
        
        // 窗口起点：默认当年 1 月；可翻页回看往年（每页 24 个月，◀▶ 按 12 个月步进）
        let year = cal.component(.year, from: now)
        let defaultStartKey = "\(year)-01"
        let startKey = monthWindowStartStr.isEmpty ? defaultStartKey : monthWindowStartStr
        guard let january = iso8601Date(from: startKey + "-01T00:00:00.000Z") else {
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

        publishPage(BarChartPage(
            dn: dn, up: up, l1: l1, l2: l2,
            fut: { idx in idx < months.count && months[idx].key > currentMonthKey },
            hasData: { idx in idx < hasDataArr.count && hasDataArr[idx] },
            title: L10n.tr("Month"),
            s1: s1, s2: s2, a1: Double(s1) / totalSec, a2: Double(s2) / totalSec
        ), dn: dn, up: up, window: months.map { $0.key })
    }

    /// 只有页面数据真正变化时才重建/重绘图表；数据未变（如空闲）时跳过，
    /// 避免 3 秒定时器每轮都触发整页 SwiftUI 重算与 CG 重绘。
    private func publishPage(_ newPage: BarChartPage, dn: [UInt64], up: [UInt64], window: [String]) {
        var fp = window.joined().hashValue
        for v in dn { fp = fp &* 31 &+ Int(v) }
        for v in up { fp = fp &* 31 &+ Int(v) }
        if fp != lastPageFingerprint {
            page = newPage
            lastPageFingerprint = fp
        }
    }
}
