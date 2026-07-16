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

    /// The metric scale is spelled the same in every language: a Japanese reader who
    /// left the notation on K/M/B must not be handed "1.84百万".
    func testMetricAbbreviationIgnoresLocale() {
        for id in ["en", "ja", "zh-Hans", "ko"] {
            XCTAssertEqual(
                1_840_230.abbreviatedTokens(.metric, locale: Locale(identifier: id)),
                "1.84M",
                "metric changed shape in \(id)"
            )
        }
    }

    func testMyriadAbbreviationGroupsEveryFourDigits() {
        let ja = Locale(identifier: "ja")
        XCTAssertEqual(1_840_230.abbreviatedTokens(.myriad, locale: ja), "184万")
        XCTAssertEqual(600_000_000.abbreviatedTokens(.myriad, locale: ja), "6億")
        XCTAssertEqual(12_500.abbreviatedTokens(.myriad, locale: ja), "1.25万")
        // Below 万 there is no unit to name, so the count reads out in full.
        XCTAssertEqual(842.abbreviatedTokens(.myriad, locale: ja), "842")
    }

    func testMyriadAbbreviationNamesUnitsPerLanguage() {
        XCTAssertEqual(600_000_000.abbreviatedTokens(.myriad, locale: Locale(identifier: "zh-Hans")), "6亿")
        XCTAssertEqual(600_000_000.abbreviatedTokens(.myriad, locale: Locale(identifier: "ko")), "6억")
    }

    func testRecentSessionsGroupBySessionAndSeparateWorkFromCache() throws {
        let aggregator = UsageAggregator(calendar: tokyo)
        let events = [
            // Session A: two turns, each re-sending the same cached context.
            makeEvent(id: "a1", at: try date("2026-07-15T01:00:00.000Z"),
                      session: "A", cached: 100_000, output: 500),
            makeEvent(id: "a2", at: try date("2026-07-15T01:05:00.000Z"),
                      session: "A", input: 40, cached: 101_000, output: 700),
            // Session B: one turn, later — should sort first.
            makeEvent(id: "b1", at: try date("2026-07-15T02:00:00.000Z"),
                      session: "B", output: 300),
        ]

        let sessions = aggregator.recentSessions(events)
        XCTAssertEqual(sessions.count, 2, "three events, two sessions")
        XCTAssertEqual(sessions.first?.id, "claudeCode|B", "newest last-activity sorts first")

        let a = try XCTUnwrap(sessions.first { $0.id == "claudeCode|A" })
        XCTAssertEqual(a.turns, 2)
        XCTAssertEqual(a.start, try date("2026-07-15T01:00:00.000Z"))
        XCTAssertEqual(a.end, try date("2026-07-15T01:05:00.000Z"))
        // Work excludes the re-sent cached context (201_000), leaving input+output.
        XCTAssertEqual(a.workingTokens, 40 + 500 + 700)
        XCTAssertEqual(a.cachedInputTokens, 201_000)
        XCTAssertEqual(a.totalTokens, 100_500 + 101_740)
    }

    func testRecentSessionsWithoutSessionIDStayDistinct() throws {
        let aggregator = UsageAggregator(calendar: tokyo)
        let events = [
            makeEvent(id: "x", at: try date("2026-07-15T01:00:00.000Z"), session: nil, output: 1),
            makeEvent(id: "y", at: try date("2026-07-15T01:01:00.000Z"), session: nil, output: 1),
        ]
        XCTAssertEqual(aggregator.recentSessions(events).count, 2,
                       "events with no session id are not merged together")
    }

    func testHourlySeriesZeroFillsUpToTheCurrentHour() throws {
        let aggregator = UsageAggregator(calendar: tokyo)
        // 12:30 in Tokyo on the 15th.
        let now = try date("2026-07-15T03:30:00.000Z")
        let events = [
            // 09:00 Tokyo
            makeEvent(id: "a", at: try date("2026-07-15T00:00:00.000Z"), output: 100),
            // 12:10 Tokyo
            makeEvent(id: "b", at: try date("2026-07-15T03:10:00.000Z"), output: 50),
        ]

        let series = aggregator.hourlySeries(events, provider: .claudeCode, now: now)
        XCTAssertEqual(series.count, 13, "hours 0…12 inclusive, no future hours")
        XCTAssertEqual(series[9].totalTokens, 100)
        XCTAssertEqual(series[12].totalTokens, 50)
        XCTAssertEqual(series[10].totalTokens, 0, "idle hours are a real zero")
    }
}
