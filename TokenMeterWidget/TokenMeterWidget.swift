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
    /// When set alongside `showReset`, the row shows the weekly reset stacked under
    /// the 5-hour one (each on its own compact line so neither is truncated). Used by
    /// the small widget, which has no room for progress bars but wants both limits.
    var showWeeklyReset = false
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
                            // In tinted (accented) mode the fill joins the accent
                            // group so the bar keeps contrast against the dimmed
                            // track; the status colour only shows in full-colour mode.
                            Capsule()
                                .fill(level.tint)
                                .frame(width: geo.size.width * max(0, min(1, remaining)))
                                .widgetAccentable()
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

            if showReset {
                if showWeeklyReset {
                    dualResetLine
                } else {
                    resetLine
                }
            }

            if showTokens {
                if let tokens = provider?.todayWorkingTokens, tokens > 0 {
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

    /// The 5-hour reset time, and whether it is our own derivation. Prefers the
    /// provider-reported quota window; falls back to the locally counted 5-hour
    /// window (which is `.inferred` for Claude Code and must be flagged "est.").
    private var fiveHourReset: (date: Date, isEstimate: Bool)? {
        if let resetsAt = provider?.fiveHourQuota?.resetsAt { return (resetsAt, false) }
        if let five = provider?.fiveHourWindow, let resetsAt = five.resetsAt {
            return (resetsAt, five.boundary == .inferred)
        }
        return nil
    }

    /// The weekly reset time. Prefers the reported quota window; the locally counted
    /// weekly window is a rolling lookback with no reset (`resetsAt == nil`), so it
    /// only ever contributes a time when the provider actually anchored one.
    private var weeklyReset: (date: Date, isEstimate: Bool)? {
        if let resetsAt = provider?.weeklyQuota?.resetsAt { return (resetsAt, false) }
        if let weekly = provider?.weeklyWindow, let resetsAt = weekly.resetsAt {
            return (resetsAt, weekly.boundary == .inferred)
        }
        return nil
    }

    /// 5-hour and weekly resets stacked, one compact line each. Kept vertical (not
    /// joined on one line) so that on the narrow small widget neither reset is
    /// truncated away. Renders nothing when the provider anchors no reset at all.
    @ViewBuilder
    private var dualResetLine: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let five = fiveHourReset {
                resetChip(label: "5h", resetsAt: five.date, isEstimate: five.isEstimate)
            }
            if let weekly = weeklyReset {
                resetChip(label: "7d", resetsAt: weekly.date, isEstimate: weekly.isEstimate)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    /// One "5h in 12m" / "7d in 3d" reset line. `label` is a short unit shown
    /// verbatim (as in `CompactQuotaStrip`), so no per-language string is needed.
    @ViewBuilder
    private func resetChip(label: String, resetsAt: Date, isEstimate: Bool) -> some View {
        HStack(spacing: 3) {
            Text(verbatim: label).foregroundStyle(.tertiary)
            Text(resetsAt, style: .relative)
            if isEstimate { Text("est.").italic() }
        }
        .lineLimit(1)
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
            // The headline figure carries the accent colour in tinted mode.
            .widgetAccentable()
        } else if let tokens = provider?.todayWorkingTokens, tokens > 0 {
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
        if let tokens = provider?.todayWorkingTokens, tokens > 0 {
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
            // The brand mark reads as an accent element in tinted mode.
            .widgetAccentable()
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
            VStack(alignment: .leading, spacing: 6) {
                ProviderRow(
                    provider: entry.snapshot?.claudeCode,
                    providerID: .claudeCode,
                    showProgress: false,
                    showReset: true,
                    showWeeklyReset: true
                )
                ProviderRow(
                    provider: entry.snapshot?.codex,
                    providerID: .codex,
                    showProgress: false,
                    showReset: true,
                    showWeeklyReset: true
                )
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
                                Stat(label: "Today", tokens: provider.todayWorkingTokens)
                                // Codex's weekly figure is its real quota window; Claude
                                // Code has no weekly anchor, so it is a 7-day lookback.
                                Stat(
                                    label: provider.weeklyWindow?.boundary == .reported ? "Week" : "7 days",
                                    tokens: provider.weeklyWindow?.tokens ?? provider.last7DaysWorkingTokens
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
        let maxValue = points.map(\.workingTokens).max() ?? 0
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
                            let ratio = CGFloat(point.workingTokens) / CGFloat(maxValue)
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
                        // The plotted line and points take the accent colour in
                        // tinted mode; the axes and labels stay in the dimmed group.
                        .widgetAccentable()
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
        .widgetContainerBackground(style: entry.snapshot?.widgetBackgroundStyle ?? .solid)
    }
}

private extension View {
    /// Fills the widget container per the user's chosen style. Clear renders as
    /// Liquid Glass, which only exists on macOS 26+; on anything older — and for
    /// `.solid` — it falls back to the opaque `.fill.tertiary` the widget has
    /// always used, so the widget looks right on every system it can run on.
    @ViewBuilder
    func widgetContainerBackground(style: WidgetBackgroundStyle) -> some View {
        if style == .clear, #available(macOS 26.0, *) {
            containerBackground(for: .widget) {
                Rectangle().fill(.clear).glassEffect(.regular, in: .rect)
            }
        } else {
            containerBackground(.fill.tertiary, for: .widget)
        }
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

// MARK: - Previews

// Canvas previews with realistic data, so the widget can be checked without the
// main app writing a snapshot. Use the canvas's rendering-mode control to see the
// tinted (accented) appearance, and the Solid/Clear variants below to compare the
// two background styles. Clear renders as Liquid Glass only on macOS 26+.
#if DEBUG
private extension SharedSnapshot {
    static func previewSample(background: WidgetBackgroundStyle) -> SharedSnapshot {
        let now = Date()
        let cal = Calendar.current
        func days(_ delta: Int) -> Date { cal.date(byAdding: .day, value: delta, to: now) ?? now }
        func hours(_ delta: Double) -> Date { now.addingTimeInterval(delta * 3600) }
        func series(_ values: [Int]) -> [DayPoint] {
            values.enumerated().map { index, value in
                DayPoint(day: days(-(values.count - 1 - index)), workingTokens: value)
            }
        }

        let claude = Provider(
            displayName: "Claude Code",
            todayWorkingTokens: 184_000,
            hasQuotaInformation: true,
            dailyTotals: series([120_000, 340_000, 90_000, 510_000, 260_000, 430_000, 184_000]),
            fiveHourWindow: TokenWindowUsage(
                start: hours(-2), resetsAt: hours(3),
                tokens: 420_000, workingTokens: 384_000, boundary: .inferred
            ),
            weeklyWindow: TokenWindowUsage(
                start: days(-4), resetsAt: days(3),
                tokens: 5_800_000, workingTokens: 5_200_000, boundary: .reported
            ),
            fiveHourQuota: UsageWindow(usedRatio: 0.32, remainingRatio: 0.68, resetsAt: hours(3)),
            weeklyQuota: UsageWindow(usedRatio: 0.55, remainingRatio: 0.45, resetsAt: days(3))
        )

        let codex = Provider(
            displayName: "Codex",
            todayWorkingTokens: 92_000,
            hasQuotaInformation: true,
            dailyTotals: series([80_000, 60_000, 210_000, 140_000, 60_000, 120_000, 92_000]),
            fiveHourWindow: TokenWindowUsage(
                start: hours(-1), resetsAt: hours(4),
                tokens: 150_000, workingTokens: 138_000, boundary: .reported, windowMinutes: 300
            ),
            weeklyWindow: TokenWindowUsage(
                start: days(-3), resetsAt: days(4),
                tokens: 2_100_000, workingTokens: 1_900_000, boundary: .reported
            ),
            fiveHourQuota: UsageWindow(usedRatio: 0.58, remainingRatio: 0.42, resetsAt: hours(4), windowMinutes: 300),
            weeklyQuota: UsageWindow(usedRatio: 0.30, remainingRatio: 0.70, resetsAt: days(4))
        )

        return SharedSnapshot(
            updatedAt: now.addingTimeInterval(-180),
            languageCode: "en",
            tokenNotation: .metric,
            widgetBackgroundStyle: background,
            claudeCode: claude,
            codex: codex
        )
    }
}

private extension Entry {
    static func preview(_ background: WidgetBackgroundStyle) -> Entry {
        Entry(date: Date(), snapshot: .previewSample(background: background), isPlaceholder: false)
    }
}

/// Sizes in points that macOS uses for each desktop widget family, so the preview
/// frame matches the real proportions closely enough to judge layout and fit.
private enum PreviewSize {
    static let small = CGSize(width: 170, height: 170)
    static let medium = CGSize(width: 364, height: 170)
    static let large = CGSize(width: 364, height: 382)
}

/// Hosts a widget size view in a simulated desktop-widget frame.
///
/// The macOS canvas cannot launch a widget extension ("This platform does not
/// support previewing widgets"), so instead of `#Preview(as:)` these render the
/// plain SwiftUI views the widget is built from — which the canvas handles fine.
/// A stand-in wallpaper sits behind the frame so a clear (Liquid Glass) background
/// has something to reveal. True tinted/accented rendering only happens on a real
/// desktop widget: run the app, add the widget, and pick Tinted in Edit Widget.
private struct WidgetFramePreview<Content: View>: View {
    let size: CGSize
    let background: WidgetBackgroundStyle
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.locale, Locale(identifier: "en"))
            .environment(
                \.tokenFormatter,
                TokenFormatter(notation: .metric, locale: Locale(identifier: "en"))
            )
            .padding(14)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background {
                if background == .clear, #available(macOS 26.0, *) {
                    Rectangle().fill(.clear).glassEffect(.regular, in: .rect(cornerRadius: 22))
                } else {
                    Rectangle().fill(.fill.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .padding(28)
            .background {
                LinearGradient(
                    colors: [.blue, .indigo, .purple],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
    }
}

#Preview("Small · Solid") {
    WidgetFramePreview(size: PreviewSize.small, background: .solid) {
        SmallWidgetView(entry: .preview(.solid))
    }
}

#Preview("Medium · Solid") {
    WidgetFramePreview(size: PreviewSize.medium, background: .solid) {
        MediumWidgetView(entry: .preview(.solid))
    }
}

#Preview("Medium · Clear (Liquid Glass)") {
    WidgetFramePreview(size: PreviewSize.medium, background: .clear) {
        MediumWidgetView(entry: .preview(.clear))
    }
}

#Preview("Large · Solid") {
    WidgetFramePreview(size: PreviewSize.large, background: .solid) {
        LargeWidgetView(entry: .preview(.solid))
    }
}

#Preview("Large · Clear (Liquid Glass)") {
    WidgetFramePreview(size: PreviewSize.large, background: .clear) {
        LargeWidgetView(entry: .preview(.clear))
    }
}
#endif
