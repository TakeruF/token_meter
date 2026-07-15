import XCTest
@testable import TokenMeterCore

final class CodexParserTests: XCTestCase {

    private func lines(_ fixture: String) throws -> [String] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(fixture)", withExtension: "jsonl"))
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// `total_token_usage` is cumulative for the session, so consecutive events
    /// must be differenced or every turn re-counts the whole session.
    func testCumulativeTotalsAreConvertedToDeltas() throws {
        let result = CodexLogParser().parse(lines: try lines("codex-two-windows"), sessionID: "sess-1")

        // Three token_count events: 1100 cumulative, then 3300, then 3300 again.
        // Deltas: 1100, 2200, and 0 (dropped).
        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(result.events[0].totalTokens, 1100)
        XCTAssertEqual(result.events[1].totalTokens, 2200)

        // The delta must decompose correctly across every token kind.
        let second = result.events[1]
        XCTAssertEqual(second.inputTokens, 2000)
        XCTAssertEqual(second.cachedInputTokens, 1600)
        XCTAssertEqual(second.outputTokens, 200)
        XCTAssertEqual(second.reasoningTokens, 100)

        XCTAssertEqual(result.totals.totalTokens, 3300, "final cumulative is carried forward")
    }

    /// A repeated event (same cumulative value) is a duplicate, not new usage.
    func testRepeatedCumulativeValueProducesNoEvent() throws {
        let result = CodexLogParser().parse(lines: try lines("codex-two-windows"), sessionID: "sess-1")
        XCTAssertEqual(result.events.count, 2, "the third event repeats 3300 and contributes nothing")
        XCTAssertEqual(result.events.reduce(0) { $0 + $1.totalTokens }, 3300)
    }

    /// Resuming a session must not re-count what was already counted. This is the
    /// app-restart path: the store hands back the cumulative totals it saved.
    func testResumingWithPreviousTotalsDoesNotDoubleCount() throws {
        let all = try lines("codex-two-windows")
        let parser = CodexLogParser()

        // First pass over the head of the file.
        let firstPass = parser.parse(lines: Array(all[0...1]), sessionID: "sess-1")
        XCTAssertEqual(firstPass.events.reduce(0) { $0 + $1.totalTokens }, 1100)

        // Second pass over the rest, resuming from the saved cumulative totals.
        let secondPass = parser.parse(
            lines: Array(all[2...]),
            sessionID: "sess-1",
            previousTotals: firstPass.totals
        )
        XCTAssertEqual(secondPass.events.reduce(0) { $0 + $1.totalTokens }, 2200,
                       "only the new 2200 is counted, not the 3300 cumulative")

        // Event ids continue from the previous count, so nothing collides.
        XCTAssertEqual(Set(firstPass.events.map(\.id)).intersection(secondPass.events.map(\.id)), [])
    }

    /// Regression: Codex names the model on `turn_context`, which appears once, near
    /// the start of a turn. An incremental read that resumes *after* that line used to
    /// record every event with a nil model. The known model must be carried in.
    func testResumedChunkKeepsTheModelFromEarlierInTheSession() throws {
        let all = try lines("codex-two-windows")
        let parser = CodexLogParser()

        // First pass sees turn_context and learns the model.
        let firstPass = parser.parse(lines: Array(all[0...1]), sessionID: "s")
        XCTAssertEqual(firstPass.events.first?.model, "gpt-5.6-sol")

        // Second pass starts after it: without the carry-over the model would be nil.
        let resumedBlind = parser.parse(lines: Array(all[2...]), sessionID: "s", previousTotals: firstPass.totals)
        XCTAssertNil(resumedBlind.events.first?.model, "no turn_context in this chunk")

        let resumed = parser.parse(
            lines: Array(all[2...]),
            sessionID: "s",
            previousTotals: firstPass.totals,
            previousModel: "gpt-5.6-sol"
        )
        XCTAssertEqual(resumed.events.first?.model, "gpt-5.6-sol")
    }

    /// If the counter ever restarts, the current value *is* the new consumption.
    func testCounterRestartIsTreatedAsFreshUsage() throws {
        let restart = """
        {"timestamp":"2026-07-14T12:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":15}}}}
        """
        let previous = CodexCumulativeTotals(
            inputTokens: 9999, cachedInputTokens: 0, outputTokens: 9999,
            reasoningTokens: 0, totalTokens: 99999, eventCount: 5
        )
        let result = CodexLogParser().parse(lines: [restart], sessionID: "s", previousTotals: previous)

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events[0].totalTokens, 15, "not a negative delta")
    }

    /// The rule that would be easiest to get wrong: on this machine `primary` was
    /// the 5h window in some sessions and the weekly window in others. Classify by
    /// window_minutes, never by slot name.
    func testWindowsAreClassifiedByDurationNotBySlotName() throws {
        let result = CodexLogParser().parse(lines: try lines("codex-two-windows"), sessionID: "sess-1")

        let short = try XCTUnwrap(result.shortWindow)
        XCTAssertEqual(short.windowMinutes, 300)
        XCTAssertEqual(try XCTUnwrap(short.usedRatio), 0.125, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(short.remainingRatio), 0.875, accuracy: 0.0001)

        let weekly = try XCTUnwrap(result.weeklyWindow)
        XCTAssertEqual(weekly.windowMinutes, 10080)
        XCTAssertEqual(try XCTUnwrap(weekly.usedRatio), 0.41, accuracy: 0.0001)

        XCTAssertEqual(result.planType, "pro")
    }

    /// The shape actually seen most often on this machine: the weekly window sits
    /// in `primary` and `secondary` is null. It must land in weeklyWindow.
    func testWeeklyWindowInPrimarySlotIsNotMistakenForShortWindow() throws {
        let result = CodexLogParser().parse(lines: try lines("codex-partial"), sessionID: "sess-2")

        XCTAssertNil(result.shortWindow, "there is no 5h window in this session")
        let weekly = try XCTUnwrap(result.weeklyWindow)
        XCTAssertEqual(weekly.windowMinutes, 10080)
        XCTAssertEqual(try XCTUnwrap(weekly.usedRatio), 0.07, accuracy: 0.0001)
    }

    func testModelSpecificLimitDoesNotReplaceGeneralCodexLimit() throws {
        let lines = [
            """
            {"timestamp":"2026-07-15T01:45:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","primary":{"used_percent":8.0,"window_minutes":10080,"resets_at":1784668980},"secondary":null,"plan_type":"pro"}}}
            """,
            """
            {"timestamp":"2026-07-15T02:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex_bengalfox","primary":{"used_percent":0.0,"window_minutes":10080,"resets_at":1784685660},"secondary":null,"plan_type":"pro"}}}
            """,
        ]

        let result = CodexLogParser().parse(lines: lines, sessionID: "s")

        XCTAssertEqual(try XCTUnwrap(result.weeklyWindow?.usedRatio), 0.08, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.weeklyWindow?.remainingRatio), 0.92, accuracy: 0.001)
    }

    func testModelSpecificLimitAloneIsNotAccountQuota() {
        let line = """
        {"timestamp":"2026-07-15T02:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex_bengalfox","primary":{"used_percent":0.0,"window_minutes":10080,"resets_at":1784685660},"secondary":null,"plan_type":"pro"}}}
        """

        let result = CodexLogParser().parse(lines: [line], sessionID: "s")

        XCTAssertNil(result.shortWindow)
        XCTAssertNil(result.weeklyWindow)
    }

    func testResetsAtIsDecodedAsUnixEpochSeconds() throws {
        let result = CodexLogParser().parse(lines: try lines("codex-two-windows"), sessionID: "sess-1")
        let resetsAt = try XCTUnwrap(result.shortWindow?.resetsAt)
        XCTAssertEqual(resetsAt.timeIntervalSince1970, 1_784_494_842, accuracy: 1)
    }

    func testNullInfoAndUnknownEventsAreSurvivable() throws {
        let result = CodexLogParser().parse(lines: try lines("codex-partial"), sessionID: "sess-2")

        // null info -> no event; unknown event type -> ignored.
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events[0].totalTokens, 60)
        XCTAssertEqual(result.events[0].reasoningTokens, 5)
        XCTAssertEqual(result.contextWindowTokens, 400_000)

        // The trailing "broken line {{{" mentions neither token_count nor
        // turn_context, so it is not a candidate at all — not a parse failure.
        XCTAssertEqual(result.malformedLineCount, 0)
    }

    func testEmptyFileYieldsNothing() throws {
        let result = CodexLogParser().parse(lines: try lines("empty"), sessionID: "s")
        XCTAssertTrue(result.events.isEmpty)
        XCTAssertNil(result.shortWindow)
        XCTAssertNil(result.weeklyWindow)
    }

    /// Sanity check against a real (sanitized) 372-event session.
    func testRealSessionFixtureParsesToItsFinalCumulativeTotal() throws {
        let result = CodexLogParser().parse(lines: try lines("codex-session"), sessionID: "real")

        XCTAssertFalse(result.events.isEmpty)
        // Deltas over a session must sum back to the final cumulative reading.
        XCTAssertEqual(result.events.reduce(0) { $0 + $1.totalTokens }, 44_920_896)
        XCTAssertEqual(result.totals.totalTokens, 44_920_896)
        XCTAssertNotNil(result.weeklyWindow)
        XCTAssertEqual(result.latestModel, "gpt-5.6-sol")
        XCTAssertEqual(result.contextWindowTokens, 258_400)
    }

    func testSessionIDIsExtractedFromRolloutFilename() {
        let url = URL(fileURLWithPath: "/x/rollout-2026-07-14T16-29-31-019f5f87-eeb1-7493-96fc-7dbf947babbb.jsonl")
        XCTAssertEqual(CodexUsageProvider.sessionID(from: url), "019f5f87-eeb1-7493-96fc-7dbf947babbb")
    }
}
