import Foundation

/// Tokens counted over one time window, from our own event history.
///
/// This is a **measurement, not a quota**. `tokens` is what we counted in the logs
/// on this machine; there is no denominator and no percentage here, because neither
/// provider publishes a token budget. Anything that needs a percentage must use
/// `UsageWindow`, which only ever carries a ratio the provider itself reported.
public struct TokenWindowUsage: Codable, Sendable, Equatable {
    /// Where the window's boundaries came from. The distinction is shown in the UI:
    /// a derived boundary must never be presented as if the provider stated it.
    public enum Boundary: String, Codable, Sendable {
        /// The provider published the reset time (Codex `rate_limits.*.resets_at`).
        case reported
        /// Derived from local activity using the documented rule (Claude Code's
        /// 5-hour session block begins with the first message). Claude Code does not
        /// publish the boundary anywhere local, and the same limit is also consumed
        /// by claude.ai and by other machines — so this is our view of the window,
        /// not necessarily Anthropic's.
        case inferred
        /// A plain rolling lookback (e.g. "the last 7 days"). It never resets, so
        /// `resetsAt` is nil.
        case rolling
    }

    public let start: Date
    /// nil for a rolling window, and for any window whose reset time is unknown.
    public let resetsAt: Date?
    /// Everything that crossed the wire inside the window, cache reads included.
    public let tokens: Int
    /// The part of `tokens` that was genuine new work — see `UsageEvent.workingTokens`.
    /// Carried alongside the total rather than derived by callers, so a window can
    /// never be rendered in one meaning while the count next to it uses the other.
    public let workingTokens: Int
    public let boundary: Boundary
    public let windowMinutes: Int?

    public init(
        start: Date,
        resetsAt: Date?,
        tokens: Int,
        workingTokens: Int,
        boundary: Boundary,
        windowMinutes: Int? = nil
    ) {
        self.start = start
        self.resetsAt = resetsAt
        self.tokens = tokens
        self.workingTokens = workingTokens
        self.boundary = boundary
        self.windowMinutes = windowMinutes
    }

    /// A widget payload written before work and total were split knows only the
    /// total. Reading it back as `workingTokens == tokens` reproduces exactly what
    /// that release displayed, and the next refresh overwrites it with both counts —
    /// whereas defaulting to 0 would flash "no work" for a window that had plenty.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(Date.self, forKey: .start)
        resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
        tokens = try container.decode(Int.self, forKey: .tokens)
        workingTokens = try container.decodeIfPresent(Int.self, forKey: .workingTokens) ?? tokens
        boundary = try container.decode(Boundary.self, forKey: .boundary)
        windowMinutes = try container.decodeIfPresent(Int.self, forKey: .windowMinutes)
    }

    /// True when the reset time is our own derivation rather than the provider's.
    public var isBoundaryInferred: Bool { boundary == .inferred }

    /// "Resets in 2h 14m", or nil when there is no reset to describe.
    public func resetDescription(now: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        let interval = resetsAt.timeIntervalSince(now)
        guard interval > 0 else { return "Resetting now" }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            return "Resets in \(days)d \(hours % 24)h"
        }
        if hours > 0 { return "Resets in \(hours)h \(minutes)m" }
        return "Resets in \(minutes)m"
    }
}
