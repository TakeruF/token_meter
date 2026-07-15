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
            case .today: return "Today"
            case .week: return "7 days"
            case .month: return "30 days"
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
                quotaSection
                windowsSection
                comparisonChart
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
                let total = events(id).reduce(0) { $0 + $1.totalTokens }
                SummaryCard(
                    providerID: id,
                    value: total > 0 ? total.abbreviatedTokens : nil,
                    caption: "tokens · \(range.label.lowercased())",
                    window: monitor.states[id]?.snapshot?.primaryWindow
                )
            }
            if providers.isEmpty {
                NoDataCard(message: "No providers enabled")
            }
        }
    }

    @ViewBuilder
    private var quotaSection: some View {
        let showing = providers.filter { monitor.states[$0]?.snapshot?.hasQuotaInformation == true }
        if !showing.isEmpty {
            SectionBox("Plan usage remaining") {
                HStack(alignment: .top, spacing: 24) {
                    ForEach(showing) { id in
                        let snapshot = monitor.states[id]?.snapshot
                        VStack(alignment: .leading, spacing: 8) {
                            ProviderLabel(providerID: id)
                            if let five = snapshot?.shortWindow {
                                QuotaWindowRow(title: "5-hour", window: five)
                            }
                            if let weekly = snapshot?.weeklyWindow {
                                QuotaWindowRow(title: "Weekly", window: weekly)
                            }
                            if let sonnet = snapshot?.sonnetWeeklyWindow {
                                QuotaWindowRow(title: "Sonnet weekly", window: sonnet)
                            }
                            if snapshot?.quotaIsCached == true {
                                Label(
                                    snapshot?.quotaError == nil ? "Showing cached value" : "Showing last successful value",
                                    systemImage: snapshot?.quotaError == nil ? "clock" : "clock.badge.exclamationmark"
                                )
                                    .font(.caption)
                                    .foregroundStyle(
                                        snapshot?.quotaError == nil
                                            ? AnyShapeStyle(.secondary)
                                            : AnyShapeStyle(.orange)
                                    )
                            }
                            if let updated = snapshot?.quotaUpdatedAt {
                                Text("Last updated \(updated.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let error = snapshot?.quotaError?.errorDescription {
                                Label(error, systemImage: "exclamationmark.triangle")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } else if settings.claudeOAuthUsageEnabled,
                  providers.contains(.claudeCode),
                  let message = monitor.states[.claudeCode]?.snapshot?.quotaError?.errorDescription {
            SectionBox("Claude plan usage") {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    /// The two live windows, side by side per provider. These ignore the range picker
    /// on purpose: a "5-hour window" that honoured a 30-day range would be a lie.
    @ViewBuilder
    private var windowsSection: some View {
        let showing = providers.filter {
            monitor.states[$0]?.snapshot?.shortWindowUsage != nil
                || monitor.states[$0]?.snapshot?.weeklyWindowUsage != nil
        }
        if !showing.isEmpty, settings.showFiveHourWindow || settings.showWeeklyWindow {
            SectionBox("Current windows") {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(showing) { id in
                        VStack(alignment: .leading, spacing: 8) {
                            ProviderLabel(providerID: id)

                            if settings.showFiveHourWindow,
                               let five = monitor.states[id]?.snapshot?.shortWindowUsage {
                                WindowRow(title: "5-hour window", usage: five)
                            }
                            if settings.showWeeklyWindow,
                               let weekly = monitor.states[id]?.snapshot?.weeklyWindowUsage {
                                WindowRow(
                                    title: weekly.boundary == .rolling ? "Last 7 days" : "Weekly window",
                                    usage: weekly
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Text("These are token counts from local logs. Provider-reported quota percentages are displayed separately above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var comparisonChart: some View {
        SectionBox("Claude vs Codex") {
            let totals = providers.map { id in
                (id, events(id).reduce(0) { $0 + $1.totalTokens })
            }
            if totals.allSatisfy({ $0.1 == 0 }) {
                NoDataInline()
            } else {
                Chart(totals, id: \.0) { item in
                    BarMark(
                        x: .value("Tokens", item.1),
                        y: .value("Provider", item.0.displayName)
                    )
                    .foregroundStyle(by: .value("Provider", item.0.displayName))
                    .annotation(position: .trailing) {
                        Text(item.1.abbreviatedTokens)
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis { AxisMarks(format: compactCount) }
                .frame(height: 120)
                .accessibilityLabel("Total tokens by provider")
            }
        }
    }

    @ViewBuilder
    private var dailyChart: some View {
        SectionBox("Daily tokens") {
            let rows: [DailyRow] = providers.flatMap { id in
                aggregator.dailySeries(events(id), provider: id, days: range.rawValue)
                    .map { DailyRow(day: $0.day, provider: id, tokens: $0.totalTokens) }
            }
            if rows.allSatisfy({ $0.tokens == 0 }) {
                NoDataInline()
            } else {
                DailyChart(rows: rows)
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
            let recent = providers
                .flatMap { events($0) }
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(20)

            if recent.isEmpty {
                NoDataInline()
            } else {
                Table(Array(recent)) {
                    TableColumn("Time") { e in
                        Text(e.timestamp, format: .dateTime.month().day().hour().minute())
                            .monospacedDigit()
                    }
                    TableColumn("Provider") { e in
                        ProviderLabel(providerID: e.provider, font: .body, iconSize: 13)
                    }
                    TableColumn("Model") { e in
                        Text(e.model ?? "—").font(.caption).monospaced()
                    }
                    TableColumn("Tokens") { e in
                        Text(e.totalTokens.abbreviatedTokens).monospacedDigit()
                    }
                }
                .frame(height: 260)
            }
        }
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

/// Split out of DashboardView: as one inline expression the type-checker gave up.
struct DailyChart: View {
    let rows: [DailyRow]

    var body: some View {
        Chart(rows) { row in
            BarMark(
                x: .value("Day", row.day, unit: .day),
                y: .value("Tokens", row.tokens)
            )
            .foregroundStyle(by: .value("Provider", row.provider.displayName))
        }
        .chartYAxis { AxisMarks(format: compactCount) }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine()
                AxisValueLabel(format: Date.FormatStyle().day())
            }
        }
        .frame(height: 220)
        .accessibilityLabel("Daily token usage by provider")
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
            Text(title).font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SummaryCard: View {
    let providerID: UsageProviderID
    let value: String?
    let caption: String
    let window: UsageWindow?

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
            Text(caption).font(.caption).foregroundStyle(.secondary)

            if let window, let remaining = window.remainingRatio {
                let level = window.statusLevel
                HStack(spacing: 4) {
                    Image(systemName: level.symbolName).foregroundStyle(level.tint)
                    Text("\(Int((remaining * 100).rounded()))% quota left")
                        .font(.caption).monospacedDigit()
                }
            } else {
                Label("No quota info", systemImage: UsageStatusLevel.unknown.symbolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct BreakdownStat: View {
    let label: String
    let value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
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
        Label(message, systemImage: "tray")
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}
