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

        var id: Int { rawValue }
        var label: String {
            switch self {
            case .today: return AppLocalization.string("Today")
            case .week: return AppLocalization.string("7 days")
            case .month: return AppLocalization.string("30 days")
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
                    value: work > 0 ? work.abbreviatedTokens : nil,
                    total: total > 0 ? total.abbreviatedTokens : nil,
                    caption: AppLocalization.format("tokens · %@", range.label)
                )
            }
            if providers.isEmpty {
                NoDataCard(message: "No providers enabled")
            }
        }
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
                Chart(models) { m in
                    BarMark(
                        x: .value("Tokens", m.totalTokens),
                        y: .value("Model", m.model)
                    )
                    .foregroundStyle(by: .value("Provider", m.provider.displayName))
                }
                .chartXAxis { AxisMarks(format: compactCount) }
                .frame(height: CGFloat(max(120, models.count * 32)))
                .accessibilityLabel("Tokens by model")
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
                            Text(s.workingTokens.abbreviatedTokens)
                                .monospacedDigit()
                            Text("\(Text("of")) \(s.totalTokens.abbreviatedTokens)")
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

/// Axis labels as "1.2M" rather than "1,200,000". Spelled out because
/// `.number.notation(...)` is ambiguous without the concrete format style.
let compactCount: IntegerFormatStyle<Int> = .number.notation(.compactName)

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
        .chartYAxis { AxisMarks(format: compactCount) }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: Date.FormatStyle().hour())
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
                Text(selectedHour ?? .now, format: Date.FormatStyle().hour())
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
        .chartYAxis { AxisMarks(format: compactCount) }
        .chartXAxis {
            AxisMarks(values: dayValues) { _ in
                AxisGridLine()
                AxisValueLabel(format: Date.FormatStyle().day(), centered: false)
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
                Text(selectedDay ?? .now, format: Date.FormatStyle().month().day())
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

struct SummaryCard: View {
    let providerID: UsageProviderID
    /// Working tokens (real processing) — the headline figure.
    let value: String?
    /// Cache-inclusive total, shown small as context for `value`.
    let total: String?
    let caption: String

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
                if let tokens = usage?.tokens {
                    Text("\(tokens.abbreviatedTokens) \(Text("tokens"))")
                        .font(.callout.weight(.medium))
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
                Text(value.abbreviatedTokens)
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
