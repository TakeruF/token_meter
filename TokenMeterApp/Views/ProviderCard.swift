import SwiftUI
import TokenMeterCore

/// One provider, as shown in the menu bar popover.
///
/// The card's job is to never lie: it shows a percentage only where the provider
/// actually publishes one, marks ageing data as ageing, and names its own source.
struct ProviderCard: View {
    let state: ProviderState?
    let providerID: UsageProviderID
    let onRefresh: () -> Void

    @State private var settings = AppSettings.shared

    private var snapshot: UsageSnapshot? { state?.snapshot }
    private var window: UsageWindow? { snapshot?.primaryWindow }

    private var isAvailable: Bool { state?.availability.isAvailable == true }
    private var fiveHour: TokenWindowUsage? {
        settings.showFiveHourWindow ? snapshot?.shortWindowUsage : nil
    }
    private var weekly: TokenWindowUsage? {
        settings.showWeeklyWindow ? snapshot?.weeklyWindowUsage : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow

            if let state, !state.availability.isAvailable, snapshot == nil {
                unavailable(state.availability)
            } else if providerID == .claudeCode {
                claudeQuotaSection
            } else if let window, let remaining = window.remainingRatio {
                quotaSection(window: window, remaining: remaining)
            } else {
                noQuotaSection
            }

            windowsSection
            tokensRow
            metadataRow
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Rows

    private var titleRow: some View {
        HStack(spacing: 6) {
            ProviderLabel(providerID: providerID, font: .headline, iconSize: 18)

            if let plan = snapshot?.planType {
                Text(plan.uppercased())
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.secondary.opacity(0.2), in: Capsule())
            }

            Spacer()

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Refresh \(providerID.displayName)")
            .accessibilityLabel("Refresh \(providerID.displayName)")
        }
    }

    private func quotaSection(window: UsageWindow, remaining: Double) -> some View {
        let level = window.statusLevel
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // Symbol + word + number: the state survives without colour.
                Image(systemName: level.symbolName)
                    .foregroundStyle(level.tint)
                Text(AppLocalization.format("%@%% remaining", "\(Int((remaining * 100).rounded()))"))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text(AppLocalization.string(level.label))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ProgressView(value: max(0, min(1, remaining)))
                .progressViewStyle(.linear)
                .tint(level.tint)
                .accessibilityLabel("\(providerID.displayName) quota remaining")
                .accessibilityValue("\(Int((remaining * 100).rounded())) percent, \(level.label)")

            // The window rows below repeat this countdown when they cover the same
            // window, so only show it here when nothing else will.
            if !resetIsShownBelow,
               let reset = AppLocalization.resetDescription(resetsAt: window.resetsAt) {
                Label(reset, systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var claudeQuotaSection: some View {
        if snapshot?.quotaIntegrationEnabled != true {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude plan usage is off").font(.callout.weight(.medium))
                    Text("Enable it in Settings to read Claude Code credentials from Keychain for Anthropic usage checks.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "lock.shield")
            }
        } else if snapshot?.hasQuotaInformation == true {
            VStack(alignment: .leading, spacing: 7) {
                if let fiveHour = snapshot?.shortWindow {
                    QuotaWindowRow(title: "5-hour", window: fiveHour)
                }
                if let weekly = snapshot?.weeklyWindow {
                    QuotaWindowRow(title: "Weekly", window: weekly)
                }
                if let sonnet = snapshot?.sonnetWeeklyWindow {
                    QuotaWindowRow(title: "Sonnet weekly", window: sonnet)
                }

                HStack(spacing: 4) {
                    if snapshot?.quotaIsCached == true {
                        Label(
                            AppLocalization.string(snapshot?.quotaError == nil ? "Cached" : "Last successful value"),
                            systemImage: snapshot?.quotaError == nil ? "clock" : "clock.badge.exclamationmark"
                        )
                    } else {
                        Label("Anthropic OAuth usage", systemImage: "checkmark.shield")
                    }
                    Spacer()
                    if let updated = snapshot?.quotaUpdatedAt {
                        Text(AppLocalization.format("Updated %@", AppLocalization.relativeTime(updated)))
                    }
                }
                .font(.caption2)
                .foregroundStyle(
                    snapshot?.quotaError != nil
                        ? AnyShapeStyle(.orange)
                        : AnyShapeStyle(.tertiary)
                )
            }
        } else {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Unavailable").font(.callout.weight(.medium))
                    Text(AppLocalization.string(
                        snapshot?.quotaError?.errorDescription ?? "Claude usage has not been loaded yet."
                    ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var resetIsShownBelow: Bool {
        guard let resetsAt = window?.resetsAt else { return false }
        return fiveHour?.resetsAt == resetsAt || weekly?.resetsAt == resetsAt
    }

    /// Claude Code path: it publishes no quota locally, so we say exactly that
    /// rather than showing 0% or a guess. The token windows below are still real
    /// counts — the sentence has to keep those two things apart.
    private var noQuotaSection: some View {
        HStack(spacing: 6) {
            Image(systemName: UsageStatusLevel.unknown.symbolName)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("No quota info")
                    .font(.callout.weight(.medium))
                Text("\(providerID.displayName) publishes no usage limit locally, so there is no percentage to show. The token counts below are real.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The 5-hour and weekly windows. Both are token counts; only Codex can also
    /// state where the window's edges are, so a derived edge is labelled as derived.
    @ViewBuilder
    private var windowsSection: some View {
        if isAvailable, fiveHour != nil || weekly != nil {
            Divider()

            if let fiveHour {
                WindowRow(title: "5-hour window", usage: fiveHour)
            }
            if let weekly {
                WindowRow(
                    title: weekly.boundary == .rolling ? "Last 7 days" : "Weekly window",
                    usage: weekly
                )
            }

            // Said once, under the numbers it qualifies: the same Claude limit is also
            // spent by claude.ai and by other machines, which these logs cannot see.
            if fiveHour?.isBoundaryInferred == true || weekly?.isBoundaryInferred == true {
                Text("Counted from this Mac's \(providerID.displayName) logs only.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func unavailable(_ availability: ProviderAvailability) -> some View {
        HStack(spacing: 6) {
            Image(systemName: availability.symbolName)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(AppLocalization.string(availability.headline)).font(.callout.weight(.medium))
                Text(AppLocalization.string(availability.detail))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var tokensRow: some View {
        Divider()
        HStack(alignment: .firstTextBaseline) {
            Text("Today")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let today = snapshot?.totalTokens, today > 0 {
                Text("\(today.abbreviatedTokens) tokens")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
            } else {
                // No usage recorded today is different from "we don't know".
                Text(AppLocalization.string(
                    state?.availability.isAvailable == true ? "No usage today" : "No data"
                ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }

        if let model = snapshot?.modelName {
            HStack {
                Text("Model").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(model).font(.caption).monospaced()
                    .lineLimit(1).truncationMode(.middle)
            }
        }

        if let context = snapshot?.currentContextTokens {
            HStack {
                Text("Context").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let capacity = snapshot?.contextWindowTokens, capacity > 0 {
                    Text("\(context.abbreviatedTokens) / \(capacity.abbreviatedTokens)")
                        .font(.caption).monospacedDigit()
                } else {
                    Text(context.abbreviatedTokens).font(.caption).monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private var metadataRow: some View {
        HStack(spacing: 4) {
            if let source = snapshot?.source {
                Text(AppLocalization.string(source.displayName))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            FreshnessLabel(state: state)
        }

        if providerID != .claudeCode, let error = state?.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One provider-reported quota window. The dominant value is what remains; the
/// reset is shown both relatively and as an absolute local date/time.
struct QuotaWindowRow: View {
    let title: String
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let remaining = window.remainingRatio {
                    Text(AppLocalization.format("%@%% remaining", "\(Int((remaining * 100).rounded()))"))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                } else {
                    Text("Unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let remaining = window.remainingRatio {
                ProgressView(value: max(0, min(1, remaining)))
                    .progressViewStyle(.linear)
                    .tint(window.statusLevel.tint)
            }

            if let resetsAt = window.resetsAt {
                HStack(spacing: 3) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Resets \(resetsAt, style: .relative)")
                    Text(verbatim: "· \(resetsAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLocalization.dateTimeLocale)))")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One time window: tokens counted inside it, and when it resets.
///
/// There is deliberately no bar and no percentage here — we have a numerator and no
/// denominator, and drawing a bar would imply one.
struct WindowRow: View {
    let title: String
    let usage: TokenWindowUsage

    private var accessibilityText: String {
        var parts = [AppLocalization.format("%@: %d tokens", AppLocalization.string(title), usage.tokens)]
        if let reset = AppLocalization.resetDescription(resetsAt: usage.resetsAt) { parts.append(reset) }
        if usage.isBoundaryInferred {
            parts.append(AppLocalization.string("reset time estimated from local activity"))
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(usage.tokens.abbreviatedTokens) tokens")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
            }

            if let reset = AppLocalization.resetDescription(resetsAt: usage.resetsAt) {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text(reset)
                    if usage.isBoundaryInferred {
                        // The provider never told us this time; say so rather than
                        // letting it read like a published reset.
                        Text("· estimated")
                            .italic()
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

/// "Updated 2m ago", or a warning once the data is old enough to mislead.
struct FreshnessLabel: View {
    let state: ProviderState?

    var body: some View {
        if let updated = state?.lastSuccessfulUpdate, let freshness = state?.freshness {
            VStack(alignment: .trailing, spacing: 0) {
                Text(AppLocalization.format("Updated %@", AppLocalization.relativeTime(updated)))
                    .font(.caption2)
                    .foregroundStyle(freshness.isStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                if freshness.isStale {
                    Text("Data may be outdated")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
        } else {
            Text("Never updated")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

extension UsageStatusLevel {
    /// Colour is a redundant cue only; every use is paired with a symbol and a word.
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
