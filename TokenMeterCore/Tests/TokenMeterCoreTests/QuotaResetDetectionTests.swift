import XCTest
@testable import TokenMeterCore

final class QuotaResetDetectionTests: XCTestCase {

    /// A Claude snapshot carrying only the two reported quota windows.
    private func snapshot(fiveHour: Double?, weekly: Double?) -> UsageSnapshot {
        UsageSnapshot(
            provider: .claudeCode,
            timestamp: Date(),
            shortWindow: fiveHour.map { UsageWindow(usedRatio: 1 - $0, remainingRatio: $0, resetsAt: nil) },
            weeklyWindow: weekly.map { UsageWindow(usedRatio: 1 - $0, remainingRatio: $0, resetsAt: nil) },
            source: .officialAPI
        )
    }

    /// The regression this whole type exists for. The 5-hour window rolls over while
    /// the weekly barely moves; because the weekly (95%) is now the tightest window,
    /// reading `primaryWindow` would compare it against the old 5-hour reading (20%),
    /// see a jump, and announce the *weekly* quota as reset.
    func testFiveHourRolloverIsNotReportedAsAWeeklyReset() {
        let before = snapshot(fiveHour: 0.20, weekly: 0.96)
        let after = snapshot(fiveHour: 1.00, weekly: 0.95)

        XCTAssertEqual(after.windowsThatReset(since: before), [.short])
        XCTAssertEqual(
            after.primaryWindow?.remainingRatio, 0.95,
            "the weekly is now the tightest window — the trap the old check fell into"
        )
    }

    func testWeeklyRolloverIsReportedAsWeekly() {
        let before = snapshot(fiveHour: 1.00, weekly: 0.04)
        let after = snapshot(fiveHour: 1.00, weekly: 1.00)
        XCTAssertEqual(after.windowsThatReset(since: before), [.weekly])
    }

    /// Both limits can roll over in the same refresh; neither notice may be dropped.
    func testBothWindowsResettingAreBothReported() {
        let before = snapshot(fiveHour: 0.10, weekly: 0.05)
        let after = snapshot(fiveHour: 1.00, weekly: 1.00)
        XCTAssertEqual(after.windowsThatReset(since: before), [.short, .weekly])
    }

    func testSpendingQuotaIsNotAReset() {
        let before = snapshot(fiveHour: 0.80, weekly: 0.96)
        let after = snapshot(fiveHour: 0.30, weekly: 0.92)
        XCTAssertEqual(after.windowsThatReset(since: before), [])
    }

    /// Reported percentages wobble by a fraction between refreshes; that is noise,
    /// not a rollover.
    func testTinyUpwardDriftIsNotAReset() {
        let before = snapshot(fiveHour: 0.50, weekly: 0.90)
        let after = snapshot(fiveHour: 0.52, weekly: 0.91)
        XCTAssertEqual(after.windowsThatReset(since: before), [])
    }

    func testNoPreviousSnapshotReportsNothing() {
        XCTAssertEqual(snapshot(fiveHour: 1.00, weekly: 1.00).windowsThatReset(since: nil), [])
    }

    /// A window the provider stopped reporting cannot be said to have reset.
    func testWindowAppearingForTheFirstTimeIsNotAReset() {
        let before = snapshot(fiveHour: nil, weekly: 0.96)
        let after = snapshot(fiveHour: 1.00, weekly: 0.96)
        XCTAssertEqual(after.windowsThatReset(since: before), [])
    }
}
