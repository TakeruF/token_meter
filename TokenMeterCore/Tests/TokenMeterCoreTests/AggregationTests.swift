import XCTest
@testable import TokenMeterCore

final class AggregationTests: XCTestCase {

    private var tokyo: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ iso: String) throws -> Date {
        try XCTUnwrap(LogDate.parse(iso))
    }

    /// Log timestamps are UTC; the user's "today" is local. 23:30Z on the 14th is
    /// already 08:30 on the 15th in Tokyo, and must be counted on the 15th.
    func testDayBucketsFollowTheUsersTimeZoneNotUTC() throws {
        let lateNightUTC = try date("2026-07-14T23:30:00.000Z")
        let events = [makeEvent(id: "a", at: lateNightUTC, output: 100)]

        let tokyoDays = UsageAggregator(calendar: tokyo).dailyUsage(
            events, provider: .claudeCode, days: 7,
            now: try date("2026-07-15T05:00:00.000Z")
        )
        let utcDays = UsageAggregator(calendar: utc).dailyUsage(
            events, provider: .claudeCode, days: 7,
            now: try date("2026-07-15T05:00:00.000Z")
        )

        var tokyoComponents = tokyo.dateComponents([.year, .month, .day], from: try XCTUnwrap(tokyoDays.first).day)
        XCTAssertEqual(tokyoComponents.day, 15, "in Tokyo this belongs to the 15th")

        var utcComponents = utc.dateComponents([.year, .month, .day], from: try XCTUnwrap(utcDays.first).day)
        XCTAssertEqual(utcComponents.day, 14, "the same instant is the 14th in UTC")

        _ = (tokyoComponents, utcComponents)
    }

    /// The rollover case: usage from before local midnight must drop out of "today".
    func testTodayExcludesUsageFromBeforeLocalMidnight() throws {
        let aggregator = UsageAggregator(calendar: tokyo)
        let now = try date("2026-07-15T01:00:00.000Z")   // 10:00 on the 15th in Tokyo

        let events = [
            // 20:00 on the 14th, Tokyo -> yesterday
            makeEvent(id: "yesterday", at: try date("2026-07-14T11:00:00.000Z"), output: 500),
            // 09:00 on the 15th, Tokyo -> today
            makeEvent(id: "today", at: try date("2026-07-15T00:00:00.000Z"), output: 70),
        ]

        let today = try XCTUnwrap(aggregator.todayTotals(events, provider: .claudeCode, now: now))
        XCTAssertEqual(today.totalTokens, 70, "yesterday's 500 must not leak into today")
    }

    /// A day with no usage is 0 in a chart series, but a provider that never reports
    /// reasoning tokens stays nil so the UI can say "no data" instead of "0".
    func testSeriesZeroFillsDaysButKeepsUnreportedMetricsNil() throws {
        let aggregator = UsageAggregator(calendar: tokyo)
        let now = try date("2026-07-15T05:00:00.000Z")

        let events = [makeEvent(id: "a", at: try date("2026-07-15T02:00:00.000Z"), output: 10)]
        let series = aggregator.dailySeries(events, provider: .claudeCode, days: 7, now: now)

        XCTAssertEqual(series.count, 7)
        XCTAssertEqual(series.map(\.totalTokens).reduce(0, +), 10)
        XCTAssertEqual(series.last?.totalTokens, 10, "series ends with today")
        XCTAssertEqual(series.first?.totalTokens, 0, "empty days really are zero usage")

        for day in series {
            XCTAssertNil(day.reasoningTokens, "Claude Code reports no reasoning tokens at all")
        }
    }

    func testReasoningTokensAreSummedWhenTheProviderReportsThem() throws {
        let aggregator = UsageAggregator(calendar: tokyo)
        let now = try date("2026-07-15T05:00:00.000Z")
        let events = [
            makeEvent(id: "a", provider: .codex, at: try date("2026-07-15T02:00:00.000Z"), output: 10, reasoning: 4),
            makeEvent(id: "b", provider: .codex, at: try date("2026-07-15T03:00:00.000Z"), output: 20, reasoning: 6),
        ]
        let today = try XCTUnwrap(aggregator.todayTotals(events, provider: .codex, now: now))
        XCTAssertEqual(today.reasoningTokens, 10)
    }

    func testModelBreakdownGroupsByModelAndSortsByUsage() throws {
        let events = [
            makeEvent(id: "a", at: Date(), model: "claude-opus-4-8", output: 100),
            makeEvent(id: "b", at: Date(), model: "claude-sonnet-5", output: 300),
            makeEvent(id: "c", at: Date(), model: "claude-opus-4-8", output: 50),
        ]
        let breakdown = UsageAggregator().modelBreakdown(events)

        XCTAssertEqual(breakdown.map(\.model), ["claude-sonnet-5", "claude-opus-4-8"])
        XCTAssertEqual(breakdown[0].totalTokens, 300)
        XCTAssertEqual(breakdown[1].totalTokens, 150)
    }

    func testStoreRetentionPrunesOldEventsOnly() throws {
        let store = try makeTempStore()
        try store.insert(events: [
            makeEvent(id: "old", at: Date().addingTimeInterval(-40 * 86_400), output: 1),
            makeEvent(id: "recent", at: Date().addingTimeInterval(-2 * 86_400), output: 1),
        ])

        let removed = try store.pruneEvents(olderThan: 30)
        XCTAssertEqual(removed, 1)

        let remaining = try store.events(since: .distantPast)
        XCTAssertEqual(remaining.map(\.id), ["recent"])
    }

    func testTokenAbbreviation() {
        XCTAssertEqual(1_840_230.abbreviatedTokens, "1.84M")
        XCTAssertEqual(12_500.abbreviatedTokens, "12.5K")
        XCTAssertEqual(842.abbreviatedTokens, "842")
    }
}
