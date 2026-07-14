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
    public let tokens: Int
    public let boundary: Boundary
    public let windowMinutes: Int?

    public init(
        start: Date,
        resetsAt: Date?,
        tokens: Int,
        boundary: Boundary,
        windowMinutes: Int? = nil
    ) {
        self.start = start
        self.resetsAt = resetsAt
        self.tokens = tokens
        self.boundary = boundary
        self.windowMinutes = windowMinutes
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
