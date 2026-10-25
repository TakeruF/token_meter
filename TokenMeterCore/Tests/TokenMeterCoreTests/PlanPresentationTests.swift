import XCTest
@testable import TokenMeterCore

final class PlanPresentationTests: XCTestCase {
    private let short = UsageWindow(usedRatio: 0.1, remainingRatio: 0.9, resetsAt: nil, windowMinutes: 300)
    private let weekly = UsageWindow(usedRatio: 0.4, remainingRatio: 0.6, resetsAt: nil, windowMinutes: 10_080)

    func testEveryCodexProTierUsesWeeklyAccountQuotaForEitherSelection() {
        for plan in ["prolite", "pro", "promax", "PROLITE"] {
            let snapshot = snapshot(plan: plan)
            XCTAssertEqual(snapshot.displayQuotaWindow(preferWeekly: false), weekly, plan)
            XCTAssertEqual(snapshot.displayQuotaWindow(preferWeekly: true), weekly, plan)
        }
    }

    func testModelShortWindowIsNotPresentedAsMissingProAccountQuota() {
        let snapshot = UsageSnapshot(provider: .codex, timestamp: Date(), shortWindow: short, planType: "prolite", source: .localLog)
        XCTAssertNil(snapshot.displayQuotaWindow(preferWeekly: false))
        XCTAssertNil(snapshot.displayQuotaWindow(preferWeekly: true))
    }

    func testOtherPlansAndProvidersRetainSelectedWindowAndFallback() {
        for provider in UsageProviderID.allCases {
            let snapshot = snapshot(plan: "plus", provider: provider)
            XCTAssertEqual(snapshot.displayQuotaWindow(preferWeekly: false), short)
            XCTAssertEqual(snapshot.displayQuotaWindow(preferWeekly: true), weekly)
        }
        let claude = snapshot(plan: "pro", provider: .claudeCode)
        XCTAssertEqual(claude.displayQuotaWindow(preferWeekly: false), short)
        let weeklyOnly = UsageSnapshot(provider: .codex, timestamp: Date(), weeklyWindow: weekly, planType: "plus", source: .localLog)
        XCTAssertEqual(weeklyOnly.displayQuotaWindow(preferWeekly: false), weekly)
    }

    private func snapshot(plan: String, provider: UsageProviderID = .codex) -> UsageSnapshot {
        UsageSnapshot(provider: provider, timestamp: Date(), shortWindow: short, weeklyWindow: weekly, planType: plan, source: .localLog)
    }
}
