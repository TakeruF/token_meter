import WidgetKit
import SwiftUI
import TokenMeterCore

/// Formats token counts the way the main app would.
///
/// Carried in the environment alongside `\.locale`, because the leaf views that show
/// a count hold a number and nothing else — and a widget has no AppSettings to
/// consult, only what the snapshot brought across.
struct TokenFormatter: Sendable {
    var notation: TokenNotation = .metric
    var locale: Locale = Locale(identifier: "en")

    func callAsFunction(_ count: Int) -> String {
        count.abbreviatedTokens(notation, locale: locale)
    }
}

private struct TokenFormatterKey: EnvironmentKey {
    static let defaultValue = TokenFormatter()
}

extension EnvironmentValues {
    var tokenFormatter: TokenFormatter {
        get { self[TokenFormatterKey.self] }
        set { self[TokenFormatterKey.self] = newValue }
    }
}

/// The widget never touches the CLI logs. It only reads the JSON snapshot the main
/// app writes into the App Group container.
struct Provider: TimelineProvider {
    private let store = SharedSnapshotStore(appGroupID: TokenMeterPaths.appGroupID)

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: nil, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snapshot: store.readResilient(), isPlaceholder: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: Date(), snapshot: store.readResilient(), isPlaceholder: false)
        // The app reloads timelines whenever it writes a new snapshot; this is the
        // fallback so a widget still ages out if the app is not running. Retry sooner
        // while empty so a newly installed widget does not cache "No data" for 15m.
        let retryInterval: TimeInterval = entry.snapshot == nil ? 60 : 15 * 60
        let next = Date().addingTimeInterval(retryInterval)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot?
    let isPlaceholder: Bool
}

// MARK: - Shared pieces

/// One provider row. Shows a percentage only when the provider really publishes
/// one; otherwise it shows tokens, or says there is no data.
struct ProviderRow: View {
    let provider: SharedSnapshot.Provider?
    let providerID: UsageProviderID
    var showProgress = true
    var showReset = false
    var showTokens = false

    @Environment(\.tokenFormatter) private var tokens

    private var name: String { providerID.displayName }

    private var level: UsageStatusLevel {
        .from(remainingRatio: provider?.remainingRatio)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                WidgetProviderIcon(providerID: providerID, size: 12)
                Text(name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                valueLabel
            }

            if showProgress {
                if let remaining = provider?.remainingRatio {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule()
                                .fill(level.tint)
                                .frame(width: geo.size.width * max(0, min(1, remaining)))
                        }
                    }
                    .frame(height: 4)
                } else {
                    // No quota to draw. A full or empty bar would both be a lie.
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: 4)
                }
            }

            if showReset { resetLine }

            if showTokens {
                if let tokens = provider?.todayTokens, tokens > 0 {
                    Text("\(self.tokens(tokens)) \(Text("today"))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if provider != nil {
                    Text("No usage today")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(accessibilityValue)")
    }

    /// The next 5-hour reset, which both providers now have — Codex because it
    /// reports one, Claude Code because we derive it. A derived time is marked
    /// "est." so it cannot be read as something Anthropic stated.
    @ViewBuilder
    private var resetLine: some View {
        if let resetsAt = provider?.fiveHourQuota?.resetsAt {
            HStack(spacing: 3) {
                Image(systemName: "clock.arrow.circlepath")
                Text("\(Text("5h limit")) \(resetsAt, style: .relative)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else if let five = provider?.fiveHourWindow, let resetsAt = five.resetsAt {
            HStack(spacing: 3) {
                Image(systemName: "clock.arrow.circlepath")
                Text("\(Text("5h limit")) \(resetsAt, style: .relative)")
                if five.boundary == .inferred {
                    Text("est.").italic()
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else if let reset = provider?.resetsAt {
            Text(reset, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var valueLabel: some View {
        if let headline = provider?.statusHeadline {
            Text(headline)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if let remaining = provider?.remainingRatio {
            HStack(spacing: 2) {
                Image(systemName: level.symbolName)
                    .font(.caption2)
                    .foregroundStyle(level.tint)
                Text("\(Int((remaining * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
        } else if let tokens = provider?.todayTokens, tokens > 0 {
            Text(self.tokens(tokens))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        } else {
            Text("—")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var accessibilityValue: String {
        if let headline = provider?.statusHeadline { return headline }
        if let remaining = provider?.remainingRatio {
            return "\(Int((remaining * 100).rounded())) percent remaining, \(level.label)"
        }
        if let tokens = provider?.todayTokens, tokens > 0 {
            return "\(self.tokens(tokens)) tokens today, no quota information"
        }
        return "No data"
    }
}

struct WidgetProviderIcon: View {
    let providerID: UsageProviderID
    var size: CGFloat = 12

    var body: some View {
        Image(providerID == .claudeCode ? "ClaudeLogo" : "CodexLogo")
            .renderingMode(providerID == .claudeCode ? .template : .original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(.primary)
            .accessibilityHidden(true)
    }
}

struct UpdatedFooter: View {
    let updatedAt: Date?

    var body: some View {
        if let updatedAt {
            let isStale = Date().timeIntervalSince(updatedAt) > 3600
            HStack(spacing: 3) {
                if isStale {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8))
                }
                Text(updatedAt, style: .relative)
                    .lineLimit(1)
            }
            .font(.system(size: 9))
            .foregroundStyle(isStale ? .orange : .secondary)
        } else {
            Text("Open the app to load data")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No data yet")
                .font(.caption.weight(.medium))
            Text("Open Token Meter")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sizes

struct SmallWidgetView: View {
    let entry: Entry

    var body: some View {
        if entry.snapshot == nil {
            EmptyStateView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ProviderRow(
                    provider: entry.snapshot?.claudeCode,
                    providerID: .claudeCode,
                    showProgress: false,
                    showReset: true
                )
                ProviderRow(provider: entry.snapshot?.codex, providerID: .codex, showProgress: false)
                Spacer(minLength: 0)
                UpdatedFooter(updatedAt: entry.snapshot?.updatedAt)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct MediumWidgetView: View {
    let entry: Entry

    var body: some View {
        if entry.snapshot == nil {
            EmptyStateView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 12) {
                    ProviderRow(
                        provider: entry.snapshot?.claudeCode,
                        providerID: .claudeCode,
                        showProgress: true,
                        showReset: true,
                        showTokens: true
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    Divider()

                    ProviderRow(
                        provider: entry.snapshot?.codex,
                        providerID: .codex,
                        showProgress: true,
                        showReset: true,
                        showTokens: true
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                Spacer(minLength: 0)
                UpdatedFooter(updatedAt: entry.snapshot?.updatedAt)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct LargeWidgetView: View {
    let entry: Entry

    var body: some View {
        if entry.snapshot == nil {
            EmptyStateView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(UsageProviderID.allCases) { providerID in
                    if let provider = entry.snapshot?.provider(providerID) {
                        VStack(alignment: .leading, spacing: 5) {
                            // Reset time is shown by CompactQuotaStrip below, so the
                            // row omits it here to keep the large widget within bounds.
                            ProviderRow(
                                provider: provider, providerID: providerID,
                                showProgress: true, showReset: false
                            )
                            if provider.hasQuotaInformation {
                                CompactQuotaStrip(provider: provider, showReset: true)
                            }
                            HStack(spacing: 12) {
                                Stat(label: "5h", tokens: provider.fiveHourWindow?.tokens)
                                Stat(label: "Today", tokens: provider.todayTokens)
                                // Codex's weekly figure is its real quota window; Claude
                                // Code has no weekly anchor, so it is a 7-day lookback.
                                Stat(
                                    label: provider.weeklyWindow?.boundary == .reported ? "Week" : "7 days",
                                    tokens: provider.weeklyWindow?.tokens ?? provider.last7DaysTokens
                                )
                            }
                            UsageLineChart(points: provider.dailyTotals ?? [])
                        }
                    }
                }
                Spacer(minLength: 0)
                UpdatedFooter(updatedAt: entry.snapshot?.updatedAt)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    struct Stat: View {
        let label: String
        let tokens: Int?

        @Environment(\.tokenFormatter) private var formatted

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                if let tokens, tokens > 0 {
                    Text(formatted(tokens))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                } else {
                    Text("No data")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct CompactQuotaStrip: View {
    let provider: SharedSnapshot.Provider
    var showReset = false

    var body: some View {
        HStack(spacing: 10) {
            quota("5h", provider.fiveHourQuota)
            quota("7d", provider.weeklyQuota)
            if provider.sonnetWeeklyQuota != nil {
                quota("Sonnet", provider.sonnetWeeklyQuota)
            }
            Spacer(minLength: 0)
            if provider.quotaIsCached == true {
                HStack(spacing: 2) {
                    Image(systemName: "clock.badge.exclamationmark")
                    if let updated = provider.quotaUpdatedAt {
                        Text(updated, style: .relative)
                    } else {
                        Text("Cached")
                    }
                }
                .foregroundStyle(
                    provider.quotaErrorMessage == nil
                        ? AnyShapeStyle(.secondary)
                        : AnyShapeStyle(.orange)
                )
                .help("Cached usage")
            }
        }
        .font(.caption2)
    }

    @ViewBuilder
    private func quota(_ label: String, _ window: UsageWindow?) -> some View {
        if let window, let remaining = window.remainingRatio {
            VStack(alignment: .leading, spacing: 0) {
                // Percent as a String so the key stays "%@%% left" (localized, order-aware)
                // rather than a bare "%lld%% left" that ships only in English.
                Text(verbatim: "\(label) ") + Text("\("\(Int((remaining * 100).rounded()))")% left")
                    .monospacedDigit()
                if showReset, let reset = window.resetsAt {
                    Text(reset, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Line chart for the last 7 days with labelled axes. Used only in the large
/// widget, where there is room for the axis text without crowding the plot.
/// Points are joined with straight lines and sit above their weekday labels.
struct UsageLineChart: View {
    let points: [SharedSnapshot.DayPoint]

    // Set at the widget root from the snapshot's language; `.formatted` otherwise
    // uses the system locale, so weekday letters would ignore the app language.
    @Environment(\.locale) private var locale
    @Environment(\.tokenFormatter) private var tokens

    /// Height of the plot area (the line). The axis labels live outside this.
    private let plotHeight: CGFloat = 30

    var body: some View {
        let maxValue = points.map(\.totalTokens).max() ?? 0
        if points.isEmpty || maxValue == 0 {
            Text("No usage in the last 7 days")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: 5) {
                // Y axis: max at the top, zero on the baseline. Fixed to the plot
                // height so "0" lines up with the bottom of the plot.
                VStack(alignment: .trailing, spacing: 0) {
                    Text(tokens(maxValue))
                    Spacer(minLength: 0)
                    Text(verbatim: "0")
                }
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(height: plotHeight)

                VStack(spacing: 2) {
                    GeometryReader { geo in
                        // One slot per point; place each point at its slot centre
                        // so it lines up with the weekday label below it.
                        let coordinates = points.enumerated().map { index, point -> CGPoint in
                            let slot = geo.size.width / CGFloat(points.count)
                            let ratio = CGFloat(point.totalTokens) / CGFloat(maxValue)
                            return CGPoint(
                                x: slot * (CGFloat(index) + 0.5),
                                y: plotHeight * (1 - ratio)
                            )
                        }
                        ZStack {
                            Path { path in
                                guard let first = coordinates.first else { return }
                                path.move(to: first)
                                coordinates.dropFirst().forEach { path.addLine(to: $0) }
                            }
                            .stroke(
                                .tint,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                            )

                            ForEach(Array(coordinates.enumerated()), id: \.offset) { _, point in
                                Circle()
                                    .fill(.tint)
                                    .frame(width: 4, height: 4)
                                    .position(point)
                            }
                        }
                    }
                    .frame(height: plotHeight)

                    // X axis line, then one narrow weekday label per point. The
                    // narrow symbol is a single letter, so labels never collide.
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 1)

                    HStack(spacing: 3) {
                        ForEach(points) { point in
                            Text(point.day.formatted(.dateTime.weekday(.narrow).locale(locale)))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                }
            }
            .accessibilityLabel("Token usage for the last 7 days")
        }
    }
}

// MARK: - Widget

struct TokenMeterWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    private var locale: Locale {
        Locale(identifier: entry.snapshot?.languageCode ?? Locale.preferredLanguages.first ?? "en")
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallWidgetView(entry: entry)
            case .systemLarge: LargeWidgetView(entry: entry)
            default: MediumWidgetView(entry: entry)
            }
        }
        .environment(\.locale, locale)
        .environment(
            \.tokenFormatter,
            TokenFormatter(notation: entry.snapshot?.tokenNotation ?? .metric, locale: locale)
        )
        // Tapping anywhere opens the dashboard.
        .widgetURL(URL(string: "tokenmeter://dashboard"))
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct TokenMeterWidget: Widget {
    let kind = "TokenMeterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TokenMeterWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Token Meter")
        .description("Claude and Codex usage at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

extension UsageStatusLevel {
    var tint: Color {
        switch self {
        case .normal: return .green
        case .caution: return .yellow
        case .warning: return .orange
        case .critical: return .red
        case .unknown: return .secondary
        }
    }
}
