import XCTest
@testable import TokenMeterCore

/// The 5-hour and weekly windows. The rule these tests are really protecting: a
/// window may report a token *count*, and may report a reset time only when it can
/// say where that time came from. No percentage is ever derived here.
final class TimeWindowTests: XCTestCase {

    private let aggregator = UsageAggregator()

    private func date(_ iso: String) throws -> Date {
        try XCTUnwrap(LogDate.parse(iso))
    }

    // MARK: - Claude Code: the derived 5-hour session block

    /// A block opens with the first message and lasts five hours. Usage from the
    /// *previous* block must not be added to the current one.
    func testSessionBlockCountsOnlyTheBlockThatIsStillOpen() throws {
        let events = [
            // Old block: opens 02:00, so it closed at 07:00.
            makeEvent(id: "a", at: try date("2026-07-15T02:00:00.000Z"), output: 500),
            makeEvent(id: "b", at: try date("2026-07-15T04:00:00.000Z"), output: 500),
            // 09:00 is past 07:00, so it opens a new block that runs to 14:00.
            makeEvent(id: "c", at: try date("2026-07-15T09:00:00.000Z"), output: 100),
            makeEvent(id: "d", at: try date("2026-07-15T11:30:00.000Z"), output: 200),
        ]

        let block = try XCTUnwrap(aggregator.sessionBlock(
            events, provider: .claudeCode,
            now: try date("2026-07-15T12:00:00.000Z")
        ))

        XCTAssertEqual(block.tokens, 300, "the 1000 tokens from the closed block are not carried over")
        XCTAssertEqual(block.start, try date("2026-07-15T09:00:00.000Z"))
        XCTAssertEqual(block.resetsAt, try date("2026-07-15T14:00:00.000Z"))
        XCTAssertEqual(block.windowMinutes, 300)
    }

    /// The boundary is our derivation, not Anthropic's. If this ever came back as
    /// `.reported` the UI would stop labelling it "estimated" and start lying.
    func testSessionBlockBoundaryIsMarkedInferred() throws {
        let block = try XCTUnwrap(aggregator.sessionBlock(
            [makeEvent(id: "a", at: try date("2026-07-15T09:00:00.000Z"), output: 1)],
            provider: .claudeCode,
            now: try date("2026-07-15T10:00:00.000Z")
        ))
        XCTAssertEqual(block.boundary, .inferred)
        XCTAssertTrue(block.isBoundaryInferred)
    }

    /// Once the block has lapsed there is no active window. Reporting the lapsed one
    /// would show spent usage as if it were current.
    func testSessionBlockIsNilOnceTheWindowHasLapsed() throws {
        let events = [makeEvent(id: "a", at: try date("2026-07-15T02:00:00.000Z"), output: 500)]
        XCTAssertNil(aggregator.sessionBlock(
            events, provider: .claudeCode,
            now: try date("2026-07-15T08:00:00.000Z")   // block closed at 07:00
        ))
    }

    func testSessionBlockIgnoresOtherProviders() throws {
        let events = [
            makeEvent(id: "a", provider: .codex, at: try date("2026-07-15T09:00:00.000Z"), output: 900),
            makeEvent(id: "b", provider: .claudeCode, at: try date("2026-07-15T09:30:00.000Z"), output: 42),
        ]
        let block = try XCTUnwrap(aggregator.sessionBlock(
            events, provider: .claudeCode,
            now: try date("2026-07-15T10:00:00.000Z")
        ))
        XCTAssertEqual(block.tokens, 42)
    }

    func testSessionBlockIsNilWithNoEvents() {
        XCTAssertNil(aggregator.sessionBlock([], provider: .claudeCode))
    }

    // MARK: - Codex: windows the provider actually stated

    /// Codex gives both `resets_at` and `window_minutes`, so the window's start is
    /// known — and the tokens inside it are a count, not an estimate.
    func testReportedWindowUsageDerivesItsStartFromResetMinusDuration() throws {
        let resetsAt = try date("2026-07-15T14:00:00.000Z")
        let window = UsageWindow(usedRatio: 0.4, remainingRatio: 0.6, resetsAt: resetsAt, windowMinutes: 300)

        let events = [
            // 08:59 is one minute before the window opened at 09:00.
            makeEvent(id: "before", provider: .codex, at: try date("2026-07-15T08:59:00.000Z"), output: 1_000),
            makeEvent(id: "in-1", provider: .codex, at: try date("2026-07-15T09:01:00.000Z"), output: 30),
            makeEvent(id: "in-2", provider: .codex, at: try date("2026-07-15T13:59:00.000Z"), output: 12),
        ]

        let usage = try XCTUnwrap(aggregator.reportedWindowUsage(events, provider: .codex, window: window))
        XCTAssertEqual(usage.start, try date("2026-07-15T09:00:00.000Z"))
        XCTAssertEqual(usage.resetsAt, resetsAt)
        XCTAssertEqual(usage.tokens, 42, "the event before the window opened is excluded")
        XCTAssertEqual(usage.boundary, .reported)
        XCTAssertFalse(usage.isBoundaryInferred)
    }

    /// Without a duration we cannot say where the window began, so we say nothing
    /// rather than guessing a start.
    func testReportedWindowUsageIsNilWithoutADuration() throws {
        let window = UsageWindow(
            usedRatio: 0.4, remainingRatio: 0.6,
            resetsAt: try date("2026-07-15T14:00:00.000Z"),
            windowMinutes: nil
        )
        XCTAssertNil(aggregator.reportedWindowUsage(
            [makeEvent(id: "a", provider: .codex, at: try date("2026-07-15T10:00:00.000Z"), output: 5)],
            provider: .codex, window: window
        ))
    }

    // MARK: - The rolling lookback (Claude Code's "week")

    /// Claude Code publishes no weekly anchor, so this window must not claim a reset.
    func testRollingWindowHasNoResetTime() throws {
        let now = try date("2026-07-15T10:00:00.000Z")
        let events = [
            makeEvent(id: "a", at: try date("2026-07-14T10:00:00.000Z"), output: 10),
            makeEvent(id: "b", at: now, output: 5),
        ]
        let usage = try XCTUnwrap(aggregator.rollingWindowUsage(events, provider: .claudeCode, days: 7, now: now))

        XCTAssertNil(usage.resetsAt)
        XCTAssertEqual(usage.boundary, .rolling)
        XCTAssertNil(usage.resetDescription(now: now), "nothing to count down to")
        XCTAssertEqual(usage.tokens, 15)
    }

    func testRollingWindowIsNilWhenNothingFallsInIt() throws {
        XCTAssertNil(aggregator.rollingWindowUsage([], provider: .claudeCode, days: 7))
    }

    // MARK: - Reset countdown

    func testResetDescriptionCountsDownAndThenStops() throws {
        let now = try date("2026-07-15T10:00:00.000Z")
        let usage = TokenWindowUsage(
            start: now,
            resetsAt: try date("2026-07-15T12:30:00.000Z"),
            tokens: 1,
            boundary: .reported
        )
        XCTAssertEqual(usage.resetDescription(now: now), "Resets in 2h 30m")

        let lapsed = TokenWindowUsage(
            start: now, resetsAt: try date("2026-07-15T09:00:00.000Z"),
            tokens: 1, boundary: .reported
        )
        XCTAssertEqual(lapsed.resetDescription(now: now), "Resetting now")
    }

    // MARK: - Widget payload

    /// The widget reads these across a process boundary; a reset time that arrives as
    /// `.reported` when it left as `.inferred` would lose the "estimated" label.
    func testWidgetSnapshotPreservesWindowsAndTheirOrigin() throws {
        let dir = makeTempDirectory()
        let store = SharedSnapshotStore(containerURL: dir)

        let snapshot = SharedSnapshot(
            updatedAt: Date(),
            claudeCode: .init(
                displayName: "Claude Code",
                hasQuotaInformation: false,
                fiveHourWindow: TokenWindowUsage(
                    start: try date("2026-07-15T09:00:00.000Z"),
                    resetsAt: try date("2026-07-15T14:00:00.000Z"),
                    tokens: 300, boundary: .inferred, windowMinutes: 300
                ),
                weeklyWindow: TokenWindowUsage(
                    start: try date("2026-07-09T00:00:00.000Z"),
                    resetsAt: nil, tokens: 9_000, boundary: .rolling, windowMinutes: 10080
                )
            )
        )
        try store.write(snapshot)

        let read = try XCTUnwrap(store.readIfPresent()?.claudeCode)
        XCTAssertEqual(read.fiveHourWindow?.tokens, 300)
        XCTAssertEqual(read.fiveHourWindow?.boundary, .inferred)
        XCTAssertEqual(read.fiveHourWindow?.resetsAt, try date("2026-07-15T14:00:00.000Z"))
        XCTAssertNil(read.weeklyWindow?.resetsAt)
        XCTAssertEqual(read.weeklyWindow?.boundary, .rolling)
        XCTAssertFalse(read.hasQuotaInformation, "token windows are not quota information")
    }

    /// A snapshot written by an older build has none of these keys. It must decode to
    /// nil windows rather than failing and blanking the widget.
    func testWidgetSnapshotWithoutWindowKeysStillDecodes() throws {
        let dir = makeTempDirectory()
        let url = dir.appendingPathComponent(SharedSnapshotStore.fileName)
        let legacy = """
        {
          "updatedAt": "2026-07-15T10:00:00Z",
          "claudeCode": { "displayName": "Claude Code", "hasQuotaInformation": false, "todayTokens": 1234 }
        }
        """
        try legacy.write(to: url, atomically: true, encoding: .utf8)

        let read = try XCTUnwrap(SharedSnapshotStore(containerURL: dir).readIfPresent()?.claudeCode)
        XCTAssertEqual(read.todayTokens, 1234)
        XCTAssertNil(read.fiveHourWindow)
        XCTAssertNil(read.weeklyWindow)
    }
}
