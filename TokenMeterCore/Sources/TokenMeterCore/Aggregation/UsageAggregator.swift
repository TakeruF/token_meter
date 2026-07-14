import Foundation

/// Rolls events up into calendar days.
///
/// Days are boundaries in the *user's* time zone, while log timestamps are UTC, so
/// bucketing goes through `Calendar` rather than dividing epochs by 86400. A
/// message at 2026-07-14T23:30Z is 08:30 on the 15th in Asia/Tokyo and must land
/// on the 15th.
public struct UsageAggregator: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Start of the day `daysAgo` before today (0 = today).
    public func day(offsetFromToday daysAgo: Int, now: Date = Date()) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: startOfDay(now)) ?? startOfDay(now)
    }

    public func totalTokens(_ events: [UsageEvent]) -> Int {
        events.reduce(0) { $0 + $1.totalTokens }
    }

    /// Totals for a single day.
    public func todayTotals(_ events: [UsageEvent], provider: UsageProviderID, now: Date = Date()) -> DailyUsage? {
        let start = startOfDay(now)
        let today = events.filter { $0.provider == provider && $0.timestamp >= start }
        guard !today.isEmpty else { return nil }
        return combine(today, day: start, provider: provider)
    }

    /// One `DailyUsage` per day in the range, oldest first. Days with no events are
    /// omitted, not zero-filled — callers decide whether a gap means "0" or "no data".
    public func dailyUsage(
        _ events: [UsageEvent],
        provider: UsageProviderID,
        days: Int,
        now: Date = Date()
    ) -> [DailyUsage] {
        let cutoff = day(offsetFromToday: days - 1, now: now)
        var buckets: [Date: [UsageEvent]] = [:]
        for event in events where event.provider == provider && event.timestamp >= cutoff {
            buckets[startOfDay(event.timestamp), default: []].append(event)
        }
        return buckets
            .map { combine($0.value, day: $0.key, provider: provider) }
            .sorted { $0.day < $1.day }
    }

    /// Zero-filled series for charts, where a day with genuinely no usage is a real 0.
    public func dailySeries(
        _ events: [UsageEvent],
        provider: UsageProviderID,
        days: Int,
        now: Date = Date()
    ) -> [DailyUsage] {
        let existing = Dictionary(
            dailyUsage(events, provider: provider, days: days, now: now).map { ($0.day, $0) },
            uniquingKeysWith: { a, _ in a }
        )
        return (0..<days).reversed().map { offset in
            let d = day(offsetFromToday: offset, now: now)
            return existing[d] ?? DailyUsage(
                day: d,
                provider: provider,
                inputTokens: 0,
                cachedInputTokens: 0,
                cacheCreationTokens: 0,
                outputTokens: 0,
                reasoningTokens: nil,
                totalTokens: 0
            )
        }
    }

    // MARK: - Time windows

    /// Claude Code's 5-hour session block, derived from local activity.
    ///
    /// Anthropic documents the rule — a session begins with your first message and
    /// lasts five hours — but publishes the boundary nowhere we can read. So we
    /// replay it: walk the events forward, and every event that falls outside the
    /// running block opens a new one. The result is flagged `.inferred` and carries
    /// **no percentage**, because the same limit is also spent by claude.ai and by
    /// other machines, which these logs cannot see.
    ///
    /// Returns nil when the last block has already expired — there is no active
    /// session, and inventing one would be worse than saying nothing.
    public func sessionBlock(
        _ events: [UsageEvent],
        provider: UsageProviderID,
        length: TimeInterval = 5 * 3600,
        now: Date = Date()
    ) -> TokenWindowUsage? {
        let sorted = events
            .filter { $0.provider == provider }
            .sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return nil }

        var blockStart = sorted[0].timestamp
        var blockTokens = 0
        for event in sorted {
            if event.timestamp >= blockStart.addingTimeInterval(length) {
                blockStart = event.timestamp
                blockTokens = 0
            }
            blockTokens += event.totalTokens
        }

        let resetsAt = blockStart.addingTimeInterval(length)
        guard resetsAt > now else { return nil }   // the block already lapsed

        return TokenWindowUsage(
            start: blockStart,
            resetsAt: resetsAt,
            tokens: blockTokens,
            boundary: .inferred,
            windowMinutes: Int(length / 60)
        )
    }

    /// Tokens counted inside a window whose boundaries the provider gave us.
    ///
    /// Used for Codex, where `resets_at` and `window_minutes` are real: the start is
    /// `resetsAt - windowMinutes`, so both the reset time and the token count are
    /// reported data, not a derivation.
    public func reportedWindowUsage(
        _ events: [UsageEvent],
        provider: UsageProviderID,
        window: UsageWindow
    ) -> TokenWindowUsage? {
        guard let resetsAt = window.resetsAt, let minutes = window.windowMinutes else { return nil }
        let start = resetsAt.addingTimeInterval(-Double(minutes) * 60)
        let tokens = events
            .filter { $0.provider == provider && $0.timestamp >= start && $0.timestamp <= resetsAt }
            .reduce(0) { $0 + $1.totalTokens }

        return TokenWindowUsage(
            start: start,
            resetsAt: resetsAt,
            tokens: tokens,
            boundary: .reported,
            windowMinutes: minutes
        )
    }

    /// A plain lookback with no reset — "the last 7 days". Used where the provider
    /// gives no weekly anchor (Claude Code), so we must not imply one.
    public func rollingWindowUsage(
        _ events: [UsageEvent],
        provider: UsageProviderID,
        days: Int,
        now: Date = Date()
    ) -> TokenWindowUsage? {
        let start = day(offsetFromToday: days - 1, now: now)
        let matching = events.filter { $0.provider == provider && $0.timestamp >= start }
        guard !matching.isEmpty else { return nil }

        return TokenWindowUsage(
            start: start,
            resetsAt: nil,
            tokens: matching.reduce(0) { $0 + $1.totalTokens },
            boundary: .rolling,
            windowMinutes: days * 24 * 60
        )
    }

    public func modelBreakdown(
        _ events: [UsageEvent],
        provider: UsageProviderID? = nil
    ) -> [ModelUsage] {
        var buckets: [String: (UsageProviderID, Int)] = [:]
        for event in events {
            if let provider, event.provider != provider { continue }
            guard let model = event.model, !model.isEmpty else { continue }
            let key = "\(event.provider.rawValue)|\(model)"
            buckets[key, default: (event.provider, 0)].1 += event.totalTokens
        }
        return buckets
            .map { key, value in
                ModelUsage(
                    model: String(key.split(separator: "|", maxSplits: 1)[1]),
                    provider: value.0,
                    totalTokens: value.1
                )
            }
            .sorted { $0.totalTokens > $1.totalTokens }
    }

    private func combine(_ events: [UsageEvent], day: Date, provider: UsageProviderID) -> DailyUsage {
        var input = 0, cached = 0, cacheCreation = 0, output = 0, total = 0
        // Stays nil unless at least one event actually reported reasoning tokens,
        // so "provider doesn't report it" never renders as 0.
        var reasoning: Int?

        for e in events {
            input += e.inputTokens
            cached += e.cachedInputTokens
            cacheCreation += e.cacheCreationTokens
            output += e.outputTokens
            total += e.totalTokens
            if let r = e.reasoningTokens {
                reasoning = (reasoning ?? 0) + r
            }
        }
        return DailyUsage(
            day: day,
            provider: provider,
            inputTokens: input,
            cachedInputTokens: cached,
            cacheCreationTokens: cacheCreation,
            outputTokens: output,
            reasoningTokens: reasoning,
            totalTokens: total
        )
    }
}

public extension Int {
    /// 1_840_230 -> "1.84M". Used everywhere token counts are shown.
    var abbreviatedTokens: String {
        let n = Double(self)
        switch abs(n) {
        case 1_000_000_000...:
            return String(format: "%.2fB", n / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.2fM", n / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", n / 1_000)
        default:
            return "\(self)"
        }
    }
}
