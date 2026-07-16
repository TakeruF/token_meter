import Foundation

public enum UsageProviderID: String, Codable, Sendable, CaseIterable, Identifiable {
    case claudeCode
    case codex
    case copilotCli

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude"
        case .codex: return "Codex"
        case .copilotCli: return "Copilot"
        }
    }

    public var compactName: String {
        switch self {
        case .claudeCode: return "Claude"
        case .codex: return "Codex"
        case .copilotCli: return "Copilot"
        }
    }
}

/// Where a value came from. Both shipping providers read local logs; the other
/// cases exist because the investigation confirmed no other local interface
/// currently exposes usage (see docs/data-sources.md).
public enum UsageSource: String, Codable, Sendable {
    case command
    case localLog
    case localServer
    case statusLine
    case officialAPI

    public var displayName: String {
        switch self {
        case .command: return "CLI command"
        case .localLog: return "Local log"
        case .localServer: return "Local server"
        case .statusLine: return "Status line"
        case .officialAPI: return "Official API"
        }
    }
}

/// A quota window. Every field is optional because Claude Code publishes none of
/// them locally — a missing value must stay missing, never be filled with 0.
public struct UsageWindow: Codable, Sendable, Equatable {
    public let usedRatio: Double?
    public let remainingRatio: Double?
    public let resetsAt: Date?
    /// Length of the window as reported by the provider (Codex: `window_minutes`).
    public let windowMinutes: Int?

    public init(usedRatio: Double?, remainingRatio: Double?, resetsAt: Date?, windowMinutes: Int? = nil) {
        self.usedRatio = usedRatio
        self.remainingRatio = remainingRatio
        self.resetsAt = resetsAt
        self.windowMinutes = windowMinutes
    }

    /// Builds a window from a percentage in 0...100, deriving the remainder.
    public static func fromUsedPercent(_ percent: Double?, resetsAt: Date?, windowMinutes: Int?) -> UsageWindow? {
        guard let percent else { return nil }
        let used = min(max(percent / 100.0, 0), 1)
        return UsageWindow(
            usedRatio: used,
            remainingRatio: 1 - used,
            resetsAt: resetsAt,
            windowMinutes: windowMinutes
        )
    }
}

public struct UsageSnapshot: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let provider: UsageProviderID
    public let timestamp: Date

    public let modelName: String?

    public let inputTokens: Int?
    public let cachedInputTokens: Int?
    /// Claude Code only: `cache_creation_input_tokens`. Codex does not report it.
    public let cacheCreationTokens: Int?
    public let outputTokens: Int?
    public let reasoningTokens: Int?
    public let totalTokens: Int?

    public let currentContextTokens: Int?
    public let contextWindowTokens: Int?

    /// Quota windows — a *percentage*. Present only where the provider published one
    /// (Codex). Always nil for Claude Code.
    public let shortWindow: UsageWindow?
    public let weeklyWindow: UsageWindow?
    /// Claude Pro/Max only: a separate Sonnet weekly limit when Anthropic returns one.
    public let sonnetWeeklyWindow: UsageWindow?

    /// Metadata for quota data fetched through the Claude Code OAuth credential.
    public let quotaUpdatedAt: Date?
    public let quotaIsCached: Bool
    public let quotaError: ClaudeUsageError?
    public let quotaIntegrationEnabled: Bool

    /// Token counts over the same two windows — a *measurement*, available for both
    /// providers because it comes from the logs rather than from a published quota.
    /// For Claude Code the 5-hour boundary is derived (see `TokenWindowUsage`).
    public let shortWindowUsage: TokenWindowUsage?
    public let weeklyWindowUsage: TokenWindowUsage?

    /// Codex only: `rate_limits.plan_type`.
    public let planType: String?

    public let source: UsageSource

    public init(
        id: UUID = UUID(),
        provider: UsageProviderID,
        timestamp: Date,
        modelName: String? = nil,
        inputTokens: Int? = nil,
        cachedInputTokens: Int? = nil,
        cacheCreationTokens: Int? = nil,
        outputTokens: Int? = nil,
        reasoningTokens: Int? = nil,
        totalTokens: Int? = nil,
        currentContextTokens: Int? = nil,
        contextWindowTokens: Int? = nil,
        shortWindow: UsageWindow? = nil,
        weeklyWindow: UsageWindow? = nil,
        sonnetWeeklyWindow: UsageWindow? = nil,
        quotaUpdatedAt: Date? = nil,
        quotaIsCached: Bool = false,
        quotaError: ClaudeUsageError? = nil,
        quotaIntegrationEnabled: Bool = false,
        shortWindowUsage: TokenWindowUsage? = nil,
        weeklyWindowUsage: TokenWindowUsage? = nil,
        planType: String? = nil,
        source: UsageSource
    ) {
        self.id = id
        self.provider = provider
        self.timestamp = timestamp
        self.modelName = modelName
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.totalTokens = totalTokens
        self.currentContextTokens = currentContextTokens
        self.contextWindowTokens = contextWindowTokens
        self.shortWindow = shortWindow
        self.weeklyWindow = weeklyWindow
        self.sonnetWeeklyWindow = sonnetWeeklyWindow
        self.quotaUpdatedAt = quotaUpdatedAt
        self.quotaIsCached = quotaIsCached
        self.quotaError = quotaError
        self.quotaIntegrationEnabled = quotaIntegrationEnabled
        self.shortWindowUsage = shortWindowUsage
        self.weeklyWindowUsage = weeklyWindowUsage
        self.planType = planType
        self.source = source
    }

    /// See `UsageEvent.workingTokens`: today's counts minus the cached context that
    /// every turn re-sends. nil when the provider reported nothing for today at all,
    /// which is not the same as a counted zero.
    public var workingTokens: Int? {
        guard let totalTokens else { return nil }
        return totalTokens - (cachedInputTokens ?? 0)
    }

    /// The window the UI should lead with: the tightest one that actually exists.
    public var primaryWindow: UsageWindow? {
        [shortWindow, weeklyWindow, sonnetWeeklyWindow]
            .compactMap { $0 }
            .min { ($0.remainingRatio ?? 1) < ($1.remainingRatio ?? 1) }
    }

    public var hasQuotaInformation: Bool {
        shortWindow != nil || weeklyWindow != nil || sonnetWeeklyWindow != nil
    }
}

/// One deduplicated, non-cumulative usage record extracted from a log.
public struct UsageEvent: Codable, Sendable, Equatable, Identifiable {
    /// Stable dedup key. Claude Code: `message.id|requestId`. Codex: `sessionID|eventIndex`.
    public let id: String
    public let provider: UsageProviderID
    public let timestamp: Date
    public let model: String?
    public let sessionID: String?

    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let cacheCreationTokens: Int
    public let outputTokens: Int
    public let reasoningTokens: Int?
    public let totalTokens: Int

    public let source: UsageSource

    public init(
        id: String,
        provider: UsageProviderID,
        timestamp: Date,
        model: String?,
        sessionID: String?,
        inputTokens: Int,
        cachedInputTokens: Int,
        cacheCreationTokens: Int,
        outputTokens: Int,
        reasoningTokens: Int?,
        totalTokens: Int,
        source: UsageSource
    ) {
        self.id = id
        self.provider = provider
        self.timestamp = timestamp
        self.model = model
        self.sessionID = sessionID
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.totalTokens = totalTokens
        self.source = source
    }

    /// Tokens that represent genuine new work: the provider's own total minus the
    /// cached context re-sent on every turn, which inflates `totalTokens` without
    /// reflecting real usage.
    ///
    /// Stated as a subtraction from `totalTokens` rather than a sum of the parts
    /// because the parts do not mean the same thing for every provider: Claude Code
    /// reports four disjoint counts, while Codex and Copilot fold the cached tokens
    /// into `inputTokens` (and Codex folds reasoning into `outputTokens`). Adding the
    /// parts up therefore double-counts on those two. Each parser already builds
    /// `totalTokens` to its own provider's semantics, and `cachedInputTokens` is
    /// always counted exactly once inside it — so this holds everywhere, and can
    /// never exceed the total.
    public var workingTokens: Int {
        totalTokens - cachedInputTokens
    }
}

/// Token totals for one calendar day, in the user's local time zone.
public struct DailyUsage: Codable, Sendable, Equatable, Identifiable {
    public let day: Date
    public let provider: UsageProviderID
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let cacheCreationTokens: Int
    public let outputTokens: Int
    /// nil when the provider does not report reasoning tokens at all (Claude Code).
    public let reasoningTokens: Int?
    public let totalTokens: Int

    /// See `UsageEvent.workingTokens`: usage minus re-sent cached context.
    public var workingTokens: Int {
        totalTokens - cachedInputTokens
    }

    public var id: String { "\(provider.rawValue)-\(day.timeIntervalSince1970)" }

    public init(
        day: Date,
        provider: UsageProviderID,
        inputTokens: Int,
        cachedInputTokens: Int,
        cacheCreationTokens: Int,
        outputTokens: Int,
        reasoningTokens: Int?,
        totalTokens: Int
    ) {
        self.day = day
        self.provider = provider
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.totalTokens = totalTokens
    }
}

/// One work session, rolled up from its individual events. Turns within a
/// session re-send the same cached context every time, so a raw per-event list
/// is mostly repetition; this collapses a session into what it actually did.
public struct SessionSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let provider: UsageProviderID
    public let start: Date
    public let end: Date
    /// Number of recorded events (turns) in the session.
    public let turns: Int
    /// The session's most-used model, if any event carried one.
    public let model: String?
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let cacheCreationTokens: Int
    public let outputTokens: Int
    public let reasoningTokens: Int?
    public let totalTokens: Int

    /// See `UsageEvent.workingTokens`: usage minus the cached context re-sent on
    /// every turn, which is what makes a raw per-turn list look like the same row
    /// over and over.
    public var workingTokens: Int {
        totalTokens - cachedInputTokens
    }

    public init(
        id: String,
        provider: UsageProviderID,
        start: Date,
        end: Date,
        turns: Int,
        model: String?,
        inputTokens: Int,
        cachedInputTokens: Int,
        cacheCreationTokens: Int,
        outputTokens: Int,
        reasoningTokens: Int?,
        totalTokens: Int
    ) {
        self.id = id
        self.provider = provider
        self.start = start
        self.end = end
        self.turns = turns
        self.model = model
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.totalTokens = totalTokens
    }
}

public struct ModelUsage: Codable, Sendable, Equatable, Identifiable {
    public let model: String
    public let provider: UsageProviderID
    /// Real processing per model, not cache-inflated totals — so the "By model"
    /// comparison reflects actual work. See `UsageEvent.workingTokens`.
    public let workingTokens: Int
    public var id: String { "\(provider.rawValue)-\(model)" }

    public init(model: String, provider: UsageProviderID, workingTokens: Int) {
        self.model = model
        self.provider = provider
        self.workingTokens = workingTokens
    }
}
