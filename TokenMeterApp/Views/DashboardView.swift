import SwiftUI
import Charts
import TokenMeterCore

struct DashboardView: View {
    let monitor: UsageMonitor
    @State private var settings = AppSettings.shared
    @State private var range: Range = .week

    enum Range: Int, CaseIterable, Identifiable {
        case today = 1
        case week = 7
        case month = 30
        case quarter = 90

        var id: Int { rawValue }
        var label: String {
            switch self {
            case .today: return AppLocalization.string("Today")
            case .week: return AppLocalization.string("7 days")
            case .month: return AppLocalization.string("30 days")
            case .quarter: return AppLocalization.string("90 days")
            }
        }

        /// Human phrase for the immediately-preceding period of the same length,
        /// used by the trend comparison.
        var previousPeriodLabel: String {
            switch self {
            case .today: return AppLocalization.string("vs yesterday")
            case .week: return AppLocalization.string("vs prev 7 days")
            case .month: return AppLocalization.string("vs prev 30 days")
            case .quarter: return AppLocalization.string("vs prev 90 days")
            }
        }
    }

    private var providers: [UsageProviderID] {
        UsageProviderID.allCases.filter { settings.enabledProviders().contains($0) }
    }

    private var aggregator: UsageAggregator { UsageAggregator() }

    /// All events in the selected range, per provider.
    private func events(_ id: UsageProviderID) -> [UsageEvent] {
        monitor.events(provider: id, days: range.rawValue)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                rangePicker
                summaryCards
                usageWindowsSection
                dailyChart
                breakdownSection
                modelSection
                historySection
            }
            .padding(20)
        }
        .background(.background)
        .navigationTitle("Token Meter")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await monitor.refresh(reason: .manual) }
                } label: {
                    if monitor.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(monitor.isRefreshing)
            }
        }
    }

    // MARK: Sections

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(Range.allCases) { r in Text(r.label).tag(r) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 280)
        .accessibilityLabel("Time range")
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            ForEach(providers) { id in
                let all = events(id)
                // Headline is real work; total (cache-inflated) is the context.
                let work = all.reduce(0) { $0 + $1.workingTokens }
                let total = all.reduce(0) { $0 + $1.totalTokens }
                SummaryCard(
                    providerID: id,
                    value: work > 0 ? work.displayTokens : nil,
                    total: total > 0 ? total.displayTokens : nil,
                    caption: AppLocalization.format("tokens · %@", range.label),
                    trend: trend(id, currentWork: work)
                )
            }
            if providers.isEmpty {
                NoDataCard(message: "No providers enabled")
            }
        }
    }

    /// Working-token change versus the immediately-preceding period of the same
    /// length. Both halves come from one fetch of twice the range, split at the
    /// current period's start, so the comparison is apples-to-apples.
    private func trend(_ id: UsageProviderID, currentWork: Int) -> UsageTrend? {
        guard currentWork > 0 else { return nil }
        let both = monitor.events(provider: id, days: range.rawValue * 2)
        let periodStart = aggregator.day(offsetFromToday: range.rawValue - 1)
        let previousWork = both
            .filter { $0.timestamp < periodStart }
            .reduce(0) { $0 + $1.workingTokens }
        guard previousWork > 0 else { return nil }
        let change = Double(currentWork - previousWork) / Double(previousWork)
        return UsageTrend(changeRatio: change, caption: range.previousPeriodLabel)
    }

    /// The live 5-hour and weekly windows, one row each per provider, combining the
    /// provider-reported quota % and the locally-counted token total. The 5-hour /
    /// weekly visibility toggles gate the whole row here (they previously hid only
    /// the token counts, leaving the percentages on screen — a visible mismatch).
    /// Ignores the range picker on purpose: a 5-hour window over 30 days is a lie.
    @ViewBuilder
    private var usageWindowsSection: some View {
        let showFive = settings.showFiveHourWindow
        let showWeekly = settings.showWeeklyWindow
        let showing = providers.filter { id in
            let s = monitor.states[id]?.snapshot
            let hasFive = showFive && (s?.shortWindowUsage != nil || s?.shortWindow != nil)
            let hasWeekly = showWeekly
                && (s?.weeklyWindowUsage != nil || s?.weeklyWindow != nil || s?.sonnetWeeklyWindow != nil)
            return hasFive || hasWeekly
        }

        if !showing.isEmpty {
            SectionBox("Usage windows") {
                HStack(alignment: .top, spacing: 24) {
                    ForEach(showing) { id in
                        let s = monitor.states[id]?.snapshot
                        VStack(alignment: .leading, spacing: 10) {
                            ProviderLabel(providerID: id)

                            if showFive, s?.shortWindowUsage != nil || s?.shortWindow != nil {
                                WindowSummaryRow(
                                    title: "5-hour",
                                    usage: s?.shortWindowUsage,
                                    quota: s?.shortWindow
                                )
                            }
                            if showWeekly {
                                if s?.weeklyWindowUsage != nil || s?.weeklyWindow != nil {
                                    let rolling = s?.weeklyWindow == nil
                                        && s?.weeklyWindowUsage?.boundary == .rolling
                                    WindowSummaryRow(
                                        title: rolling ? "Last 7 days" : "Weekly",
                                        usage: s?.weeklyWindowUsage,
                                        quota: s?.weeklyWindow
                                    )
                                }
                                if let sonnet = s?.sonnetWeeklyWindow {
                                    WindowSummaryRow(title: "Sonnet weekly", usage: nil, quota: sonnet)
                                }
                            }

                            QuotaProvenanceFootnote(snapshot: s)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Text("Percentages are provider-reported; token counts come from local logs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if settings.claudeOAuthUsageEnabled,
                  providers.contains(.claudeCode),
                  let message = monitor.states[.claudeCode]?.snapshot?.quotaError?.errorDescription {
            SectionBox("Usage windows") {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var dailyChart: some View {
        // A single day has one daily point per provider, which no line or bar can
        // convey. Show the day's intraday shape by the hour instead.
        if range == .today {
            SectionBox("Today by hour") {
                let rows: [HourlyRow] = providers.flatMap { id in
                    aggregator.hourlySeries(events(id), provider: id)
                        .map { HourlyRow(hour: $0.day, provider: id, tokens: $0.workingTokens) }
                }
                if rows.allSatisfy({ $0.tokens == 0 }) {
                    NoDataInline()
                } else {
                    HourlyChart(rows: rows)
                }
            }
        } else {
            SectionBox("Daily tokens") {
                let rows: [DailyRow] = providers.flatMap { id in
                    aggregator.dailySeries(events(id), provider: id, days: range.rawValue)
                        .map { DailyRow(day: $0.day, provider: id, tokens: $0.workingTokens) }
                }
                if rows.allSatisfy({ $0.tokens == 0 }) {
                    NoDataInline()
                } else {
                    DailyChart(rows: rows)
                }
            }
        }
    }

    @ViewBuilder
    private var breakdownSection: some View {
        SectionBox("Token breakdown") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(providers) { id in
                    let all = events(id)
                    let input = all.reduce(0) { $0 + $1.inputTokens }
                    let cached = all.reduce(0) { $0 + $1.cachedInputTokens }
                    let cacheCreation = all.reduce(0) { $0 + $1.cacheCreationTokens }
                    let output = all.reduce(0) { $0 + $1.outputTokens }
                    // nil (not 0) when the provider never reports reasoning tokens.
                    let reasoning: Int? = all.compactMap(\.reasoningTokens).isEmpty
                        ? nil
                        : all.compactMap(\.reasoningTokens).reduce(0, +)

                    VStack(alignment: .leading, spacing: 6) {
                        ProviderLabel(providerID: id)
                        if all.isEmpty {
                            NoDataInline()
                        } else {
                            HStack(spacing: 18) {
                                BreakdownStat(label: "Input", value: input)
                                BreakdownStat(label: "Cache read", value: cached)
                                if id == .claudeCode {
                                    BreakdownStat(label: "Cache write", value: cacheCreation)
                                }
                                BreakdownStat(label: "Output", value: output)
                                BreakdownStat(label: "Reasoning", value: reasoning)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var modelSection: some View {
        SectionBox("By model") {
            let models = aggregator.modelBreakdown(providers.flatMap { events($0) })
            if models.isEmpty {
                NoDataInline()
            } else {
                ModelChart(models: models)
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        SectionBox("Recent activity") {
            // Grouped by session, not per message: consecutive turns re-send the
            // same cached context, so a raw event log is mostly repeated rows.
            let sessions = aggregator.recentSessions(
                providers.flatMap { events($0) },
                limit: 20
            )

            if sessions.isEmpty {
                NoDataInline()
            } else {
                Table(sessions) {
                    TableColumn("Session") { s in
                        Text(sessionInterval(s))
                            .monospacedDigit()
                    }
                    TableColumn("Provider") { s in
                        ProviderLabel(providerID: s.provider, font: .body, iconSize: 13)
                    }
                    TableColumn("Model") { s in
                        Text(s.model ?? "—").font(.caption).monospaced()
                    }
                    TableColumn("Turns") { s in
                        Text(s.turns, format: .number).monospacedDigit()
                    }
                    TableColumn("Work") { s in
                        // The real work this session did; total is shown as the
                        // context it ran against, since most of it is cached reuse.
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.workingTokens.displayTokens)
                                .monospacedDigit()
                            Text("\(Text("of")) \(s.totalTokens.displayTokens)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .frame(height: 260)
            }
        }
    }

    /// "Jul 15, 3:58–4:07 PM" — start with date, end as time only when same day.
    private func sessionInterval(_ s: SessionSummary) -> String {
        let cal = Calendar.current
        let locale = AppLocalization.dateTimeLocale
        let startText = s.start.formatted(.dateTime.month().day().hour().minute().locale(locale))
        if cal.isDate(s.start, inSameDayAs: s.end) {
            return "\(startText) – \(s.end.formatted(.dateTime.hour().minute().locale(locale)))"
        }
        return "\(startText) – \(s.end.formatted(.dateTime.month().day().hour().minute().locale(locale)))"
    }
}

// MARK: - Charts

/// Axis labels as "1.2M" rather than "1,200,000" — or "184万", for a reader who
/// picked myriad notation. Spelled out because `.number.notation(...)` is ambiguous
/// without the concrete format style.
///
/// The locale is bound explicitly: chart axis labels ignore `\.locale` from the
/// environment, so an unlocalized style would name the units off the *system*
/// language ("6億" under an English UI on a Japanese Mac). Computed rather than
/// stored, or it would freeze whichever language was current when first touched.
var compactCount: IntegerFormatStyle<Int> {
    .number.notation(.compactName).locale(AppSettings.shared.tokenFormattingLocale)
}

/// Date axis labels and tooltips, in the app language rather than the system one —
/// same reason as `compactCount` ("16日" under an English UI, otherwise).
var chartHour: Date.FormatStyle { Date.FormatStyle().hour().locale(AppLocalization.dateTimeLocale) }
var chartDay: Date.FormatStyle { Date.FormatStyle().day().locale(AppLocalization.dateTimeLocale) }
var chartMonthDay: Date.FormatStyle {
    Date.FormatStyle().month().day().locale(AppLocalization.dateTimeLocale)
}

struct DailyRow: Identifiable {
    let day: Date
    let provider: UsageProviderID
    let tokens: Int
    var id: String { "\(provider.rawValue)-\(day.timeIntervalSince1970)" }
}

struct HourlyRow: Identifiable {
    let hour: Date
    let provider: UsageProviderID
    let tokens: Int
    var id: String { "\(provider.rawValue)-\(hour.timeIntervalSince1970)" }
}

/// Today's usage split by hour, drawn as a line so the shape of the day reads at a
/// glance. The series is zero-filled from midnight to the current hour, so the line
/// is continuous and a genuinely idle hour shows as a real 0 rather than a gap.
struct HourlyChart: View {
    let rows: [HourlyRow]

    /// The hour the cursor is currently hovering over, if any.
    @State private var selectedHour: Date?

    /// Rows for the hovered hour, ordered by provider.
    private var selectedRows: [HourlyRow] {
        guard let selectedHour else { return [] }
        return rows
            .filter { Calendar.current.isDate($0.hour, equalTo: selectedHour, toGranularity: .hour) }
            .sorted { $0.provider.rawValue < $1.provider.rawValue }
    }

    /// Midnight of the day being charted, taken from the data so it matches the rows.
    private var dayStart: Date {
        Calendar.current.startOfDay(for: rows.map(\.hour).min() ?? Date())
    }

    /// The full day, 00:00–24:00, padded slightly so the 0h and 24h labels don't clip
    /// at the plot edges. The axis is always the whole day; the line only reaches the
    /// current hour (rows stop there), so the chart fills in as the day progresses.
    private var xDomain: ClosedRange<Date> {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        let pad: TimeInterval = 30 * 60
        return dayStart.addingTimeInterval(-pad)...end.addingTimeInterval(pad)
    }

    var body: some View {
        Chart(rows) { row in
            LineMark(
                x: .value("Hour", row.hour),
                y: .value("Tokens", row.tokens)
            )
            .foregroundStyle(by: .value("Provider", row.provider.displayName))
            .symbol(by: .value("Provider", row.provider.displayName))
            .interpolationMethod(.linear)

            if let selectedHour, Calendar.current.isDate(row.hour, equalTo: selectedHour, toGranularity: .hour) {
                PointMark(
                    x: .value("Hour", row.hour),
                    y: .value("Tokens", row.tokens)
                )
                .foregroundStyle(by: .value("Provider", row.provider.displayName))
                .symbolSize(90)
            }
        }
        .chartXSelection(value: $selectedHour)
        .chartOverlay { proxy in
            // `chartXSelection` covers clicks/drags; add hover for the pointer.
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let origin = geo[proxy.plotFrame!].origin
                            let x = location.x - origin.x
                            selectedHour = proxy.value(atX: x, as: Date.self)
                        case .ended:
                            selectedHour = nil
                        }
                    }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYAxis { AxisMarks(format: compactCount) }
        .chartXAxis {
            // Every 3 hours across the whole day. These ticks land on plotted hours,
            // and `centered: false` keeps each label directly under its point.
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine()
                // `anchor: .top` attaches the label's top-centre to the tick — which
                // sits on the point — so the time reads directly under its plotted
                // value instead of hanging off to the right (most visible on wide,
                // two-digit labels).
                AxisValueLabel(format: chartHour, anchor: .top)
            }
        }
        .frame(height: 220)
        .overlay(alignment: .topLeading) {
            if !selectedRows.isEmpty {
                selectionLabel
            }
        }
        .accessibilityLabel("Hourly token usage by provider today")
    }

    /// A floating tooltip listing each provider's usage in the hovered hour.
    private var selectionLabel: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
            GridRow {
                Text(selectedHour ?? .now, format: chartHour)
                    .font(.caption2.bold())
                    .gridCellColumns(2)
            }
            ForEach(selectedRows) { row in
                GridRow {
                    Text(row.provider.displayName)
                        .foregroundStyle(.secondary)
                    Text(row.tokens, format: compactCount)
                        .monospacedDigit()
                        .gridColumnAlignment(.trailing)
                }
                .font(.caption2)
            }
        }
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .windowBackgroundColor))
                .stroke(.quaternary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        .padding(8)
        .allowsHitTesting(false)
    }
}

/// Horizontal "By model" bar chart. Split out so it can carry its own hover state.
struct ModelChart: View {
    let models: [ModelUsage]

    /// The model whose bar the cursor is currently over, if any.
    @State private var selectedModel: String?

    /// The hovered model's row, if any.
    private var selectedRow: ModelUsage? {
        guard let selectedModel else { return nil }
        return models.first { $0.model == selectedModel }
    }

    var body: some View {
        Chart(models) { m in
            BarMark(
                x: .value("Tokens", m.workingTokens),
                y: .value("Model", m.model)
            )
            .foregroundStyle(by: .value("Provider", m.provider.displayName))
            .opacity(selectedModel == nil || selectedModel == m.model ? 1 : 0.4)
        }
        .chartYSelection(value: $selectedModel)
        .chartOverlay { proxy in
            // `chartYSelection` covers clicks/drags; add hover for the pointer.
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let origin = geo[proxy.plotFrame!].origin
                            let y = location.y - origin.y
                            selectedModel = proxy.value(atY: y, as: String.self)
                        case .ended:
                            selectedModel = nil
                        }
                    }
            }
        }
        .chartXAxis { AxisMarks(format: compactCount) }
        .frame(height: CGFloat(max(120, models.count * 32)))
        .overlay(alignment: .topTrailing) {
            if let selectedRow {
                selectionLabel(selectedRow)
            }
        }
        .accessibilityLabel("Tokens by model")
    }

    /// A floating tooltip showing the hovered model's token usage.
    private func selectionLabel(_ row: ModelUsage) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
            GridRow {
                Text(row.model)
                    .font(.caption2.bold())
                    .monospaced()
                    .gridCellColumns(2)
            }
            GridRow {
                Text(row.provider.displayName)
                    .foregroundStyle(.secondary)
                Text(row.workingTokens, format: compactCount)
                    .monospacedDigit()
                    .gridColumnAlignment(.trailing)
            }
            .font(.caption2)
        }
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .windowBackgroundColor))
                .stroke(.quaternary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        .padding(8)
        .allowsHitTesting(false)
    }
}

/// Split out of DashboardView: as one inline expression the type-checker gave up.
struct DailyChart: View {
    let rows: [DailyRow]

    /// The day the cursor is currently hovering over, if any.
    @State private var selectedDay: Date?

    /// The distinct plotted days, ascending. Axis marks land on these exact dates
    /// so each label centers on its gridline — and thus under its plotted point —
    /// instead of drifting off a generic day-stride.
    private var dayValues: [Date] {
        Array(Set(rows.map { Calendar.current.startOfDay(for: $0.day) })).sorted()
    }

    /// Days between axis labels. One per day suits a week or a month, but over the
    /// 90-day range they collide into an unreadable smear.
    private var labelStride: Int { dayValues.count >= 90 ? 10 : 1 }

    /// Ten-day marks span roughly three months, where a bare day number repeats —
    /// "6", "16", "26", "6" — with nothing to say which month each belongs to. Name
    /// the month there. A week or a month of consecutive days needs no such help,
    /// and the shorter label keeps those denser axes readable.
    private var dayLabelFormat: Date.FormatStyle { labelStride > 1 ? chartMonthDay : chartDay }

    /// The days that get an axis mark. The stride counts back from the most recent
    /// day, so the latest date always keeps its label; it is the one worth reading.
    /// The series is zero-filled and contiguous, so striding by index strides by
    /// exactly `labelStride` days.
    private var labelledDays: [Date] {
        let days = dayValues
        guard labelStride > 1 else { return days }
        return days.enumerated()
            .filter { (days.count - 1 - $0.offset).isMultiple(of: labelStride) }
            .map(\.element)
    }

    /// The plotted days padded by half a label interval on each side. Without this the
    /// first and last points sit exactly on the plot edges, so their axis labels — the
    /// latest date in particular — overflow the plot and get clipped to "…". Half an
    /// interval is the room a centred label needs; scaling it with the stride keeps
    /// that room constant on screen, since a fixed half-day shrinks to a few clipped
    /// pixels once the range stretches to 90 days.
    private var xDomain: ClosedRange<Date> {
        let days = dayValues
        guard let first = days.first, let last = days.last else {
            let now = Calendar.current.startOfDay(for: Date())
            return now...now.addingTimeInterval(86_400)
        }
        let pad = TimeInterval(labelStride) * 12 * 3600
        return first.addingTimeInterval(-pad)...last.addingTimeInterval(pad)
    }

    /// Rows for the hovered day, ordered by provider, with a non-zero total.
    private var selectedRows: [DailyRow] {
        guard let selectedDay else { return [] }
        return rows
            .filter { Calendar.current.isDate($0.day, inSameDayAs: selectedDay) }
            .sorted { $0.provider.rawValue < $1.provider.rawValue }
    }

    var body: some View {
        Chart(rows) { row in
            // No `unit: .day`: that plots each point at the day-band's centre while the
            // gridline/label sit at the band's start, so labels drift left of the
            // points. `row.day` is already midnight, so a plain value puts the point
            // exactly on its gridline — label centred directly under it.
            LineMark(
                x: .value("Day", row.day),
                y: .value("Tokens", row.tokens)
            )
            .foregroundStyle(by: .value("Provider", row.provider.displayName))
            .symbol(by: .value("Provider", row.provider.displayName))
            .interpolationMethod(.linear)

            if let selectedDay, Calendar.current.isDate(row.day, inSameDayAs: selectedDay) {
                PointMark(
                    x: .value("Day", row.day),
                    y: .value("Tokens", row.tokens)
                )
                .foregroundStyle(by: .value("Provider", row.provider.displayName))
                .symbolSize(90)
            }
        }
        .chartXSelection(value: $selectedDay)
        .chartOverlay { proxy in
            // `chartXSelection` covers clicks/drags; add hover for the pointer.
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let origin = geo[proxy.plotFrame!].origin
                            let x = location.x - origin.x
                            selectedDay = proxy.value(atX: x, as: Date.self)
                        case .ended:
                            selectedDay = nil
                        }
                    }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYAxis { AxisMarks(format: compactCount) }
        .chartXAxis {
            AxisMarks(values: labelledDays) { _ in
                AxisGridLine()
                // `anchor: .top` attaches the label's top-centre to the tick, which
                // sits on the point — so each date reads directly under its plotted
                // value instead of hanging off to the right (most visible on two-digit
                // days).
                AxisValueLabel(format: dayLabelFormat, anchor: .top)
            }
        }
        .frame(height: 220)
        .overlay(alignment: .topLeading) {
            if !selectedRows.isEmpty {
                selectionLabel
            }
        }
        .accessibilityLabel("Daily token usage by provider")
    }

    /// A floating tooltip listing each provider's usage on the hovered day.
    private var selectionLabel: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
            GridRow {
                Text(selectedDay ?? .now, format: chartMonthDay)
                    .font(.caption2.bold())
                    .gridCellColumns(2)
            }
            ForEach(selectedRows) { row in
                GridRow {
                    Text(row.provider.displayName)
                        .foregroundStyle(.secondary)
                    Text(row.tokens, format: compactCount)
                        .monospacedDigit()
                        .gridColumnAlignment(.trailing)
                }
                .font(.caption2)
            }
        }
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .windowBackgroundColor))
                .stroke(.quaternary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        .padding(8)
        .allowsHitTesting(false)
    }
}

// MARK: - Small pieces

struct SectionBox<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(title)).font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Period-over-period change in working tokens, shown as a small chip on a card.
struct UsageTrend {
    /// Signed fractional change, e.g. 0.12 for +12%.
    let changeRatio: Double
    /// Localized phrase naming the comparison period ("vs prev 7 days").
    let caption: String

    /// Rising usage is not "good" or "bad", so the chip stays colour-neutral and
    /// leans on the arrow direction rather than red/green.
    var symbol: String {
        if changeRatio > 0.005 { return "arrow.up.right" }
        if changeRatio < -0.005 { return "arrow.down.right" }
        return "arrow.right"
    }

    var text: String {
        let pct = Int((abs(changeRatio) * 100).rounded())
        let sign = changeRatio > 0.005 ? "+" : (changeRatio < -0.005 ? "−" : "±")
        return "\(sign)\(pct)%"
    }
}

struct SummaryCard: View {
    let providerID: UsageProviderID
    /// Working tokens (real processing) — the headline figure.
    let value: String?
    /// Cache-inclusive total, shown small as context for `value`.
    let total: String?
    let caption: String
    var trend: UsageTrend? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProviderLabel(providerID: providerID)

            if let value {
                Text(value)
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            } else {
                Text("No data")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text(LocalizedStringKey(caption)).font(.caption).foregroundStyle(.secondary)

            if let total, value != nil {
                Text("\(Text("of")) \(total) \(Text("total"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let trend, value != nil {
                HStack(spacing: 3) {
                    Image(systemName: trend.symbol)
                    Text(trend.text).monospacedDigit()
                    Text(LocalizedStringKey(trend.caption)).foregroundStyle(.secondary)
                }
                .font(.caption2.weight(.medium))
                .padding(.top, 1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// One window row that combines both facts about a limit: the provider-reported
/// quota % (with a bar) and the locally-counted token total, plus a single reset
/// line. Reported reset times win over locally-estimated ones.
struct WindowSummaryRow: View {
    let title: String
    let usage: TokenWindowUsage?
    let quota: UsageWindow?

    private var level: UsageStatusLevel { quota?.statusLevel ?? .unknown }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(LocalizedStringKey(title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let usage {
                    // Work first, total as context — matching the summary cards above,
                    // which is the only way the two sections can be read together.
                    Text("\(usage.workingTokens.displayTokens) \(Text("tokens"))")
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                    Text("\(Text("of")) \(usage.tokens.displayTokens)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let remaining = quota?.remainingRatio {
                    Text(AppLocalization.format("%@%% left", "\(Int((remaining * 100).rounded()))"))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(level.tint)
                }
            }

            if let remaining = quota?.remainingRatio {
                ProgressView(value: max(0, min(1, remaining)))
                    .progressViewStyle(.linear)
                    .tint(level.tint)
            }

            resetLine
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var resetLine: some View {
        if let resetsAt = quota?.resetsAt {
            resetLabel(resetsAt, estimated: false)
        } else if let resetsAt = usage?.resetsAt {
            resetLabel(resetsAt, estimated: usage?.isBoundaryInferred == true)
        }
    }

    private func resetLabel(_ resetsAt: Date, estimated: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "clock.arrow.circlepath")
            Text("Resets \(resetsAt, style: .relative)")
            if estimated {
                Text("· \(Text("estimated"))").italic()
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

/// The cached / last-updated / error notes for provider-reported quota. Shown
/// only when the provider actually publishes quota data.
struct QuotaProvenanceFootnote: View {
    let snapshot: UsageSnapshot?

    var body: some View {
        if let snapshot, snapshot.hasQuotaInformation {
            VStack(alignment: .leading, spacing: 4) {
                if snapshot.quotaIsCached == true {
                    Label(
                        AppLocalization.string(
                            snapshot.quotaError == nil ? "Showing cached value" : "Showing last successful value"
                        ),
                        systemImage: snapshot.quotaError == nil ? "clock" : "clock.badge.exclamationmark"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        snapshot.quotaError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange)
                    )
                }
                if let updated = snapshot.quotaUpdatedAt {
                    Text(AppLocalization.format("Last updated %@", updated.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLocalization.dateTimeLocale))))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let error = snapshot.quotaError?.errorDescription {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct BreakdownStat: View {
    let label: String
    let value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(.secondary)
            if let value {
                Text(value.displayTokens)
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
            } else {
                // The provider does not report this at all — not the same as zero.
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct NoDataInline: View {
    var body: some View {
        Label("No data", systemImage: "tray")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }
}

struct NoDataCard: View {
    let message: String
    var body: some View {
        Label(AppLocalization.string(message), systemImage: "tray")
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}
