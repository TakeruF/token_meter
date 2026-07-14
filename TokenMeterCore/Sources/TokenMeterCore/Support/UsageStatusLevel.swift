import Foundation

/// Severity derived from how much of a quota is left.
///
/// Each level carries a symbol and a word as well as a colour, because colour
/// alone must never be the only way to tell states apart.
public enum UsageStatusLevel: String, Sendable, CaseIterable {
    case normal
    case caution
    case warning
    case critical
    /// The provider does not publish a quota at all (Claude Code). Distinct from
    /// "0% remaining" — we know nothing, rather than knowing it is empty.
    case unknown

    public static func from(remainingRatio: Double?) -> UsageStatusLevel {
        guard let remainingRatio else { return .unknown }
        switch remainingRatio {
        case ..<0.10: return .critical
        case ..<0.20: return .warning
        case ..<0.50: return .caution
        default: return .normal
        }
    }

    public var symbolName: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    /// Spoken by VoiceOver and shown as text, so the state survives without colour.
    public var label: String {
        switch self {
        case .normal: return "Normal"
        case .caution: return "Caution"
        case .warning: return "Low"
        case .critical: return "Critical"
        case .unknown: return "No quota data"
        }
    }

    /// Notification thresholds, in the order they should fire.
    public static let notificationThresholds: [Double] = [0.20, 0.10, 0.05]
}

public extension UsageWindow {
    var statusLevel: UsageStatusLevel {
        .from(remainingRatio: remainingRatio)
    }

    /// "Resets in 2h 14m", or nil when the provider gave no reset time.
    func resetDescription(now: Date = Date()) -> String? {
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
