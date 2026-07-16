import Foundation

/// One of the provider-reported quota windows, named so a notification can say
/// which limit it is talking about.
public enum QuotaWindowKind: String, Sendable, CaseIterable {
    case short
    case weekly
    case sonnetWeekly

    /// Localization key naming this window, matching the UI's own row titles.
    public var label: String {
        switch self {
        case .short: return "5-hour"
        case .weekly: return "Weekly"
        case .sonnetWeekly: return "Sonnet weekly"
        }
    }
}

public extension UsageSnapshot {
    /// The reported quota window of a given kind, if the provider published one.
    func window(_ kind: QuotaWindowKind) -> UsageWindow? {
        switch kind {
        case .short: return shortWindow
        case .weekly: return weeklyWindow
        case .sonnetWeekly: return sonnetWeeklyWindow
        }
    }

    /// The quota windows that rolled over between `previous` and this snapshot — a
    /// window whose remaining share jumped back up by more than `minimumJump`.
    ///
    /// Each window is compared against *its own* previous value. Reading
    /// `primaryWindow` instead compares whichever window happened to be tightest at
    /// each refresh, and those need not be the same window: once a 5-hour window
    /// rolls over (20% -> 100%), the weekly window at 95% becomes the tightest, so
    /// the jump from 20% to 95% gets read — and announced — as the *weekly* limit
    /// resetting, when the weekly limit did not move at all.
    func windowsThatReset(since previous: UsageSnapshot?, minimumJump: Double = 0.05) -> [QuotaWindowKind] {
        guard let previous else { return [] }
        return QuotaWindowKind.allCases.filter { kind in
            guard let now = window(kind)?.remainingRatio,
                  let before = previous.window(kind)?.remainingRatio else { return false }
            return now > before + minimumJump
        }
    }
}
