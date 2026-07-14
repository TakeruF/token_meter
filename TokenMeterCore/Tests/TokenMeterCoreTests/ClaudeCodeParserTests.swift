import XCTest
@testable import TokenMeterCore

final class ClaudeCodeParserTests: XCTestCase {

    private func lines(_ fixture: String) throws -> [String] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(fixture)", withExtension: "jsonl"))
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// The headline defect this whole design guards against. The fixture is a real
    /// transcript: 60 usage-bearing lines that represent only 33 messages, because
    /// Claude Code repeats one `usage` object across a message's content blocks.
    /// Summing lines gives 2,503,906 tokens; the truth is 1,402,353.
    func testDeduplicatesRepeatedUsagePerMessage() throws {
        let result = ClaudeCodeLogParser().parse(lines: try lines("claude-session"))

        XCTAssertEqual(result.totalLineCount, 60)
        XCTAssertEqual(result.events.count, 60, "parser emits one event per line; the ids are what dedupe")

        let uniqueIDs = Set(result.events.map(\.id))
        XCTAssertEqual(uniqueIDs.count, 33, "60 lines describe 33 distinct messages")

        let naive = result.events.reduce(0) { $0 + $1.totalTokens }
        XCTAssertEqual(naive, 2_503_906, "summing every line double counts")

        var deduped: [String: UsageEvent] = [:]
        for e in result.events { deduped[e.id] = e }
        let correct = deduped.values.reduce(0) { $0 + $1.totalTokens }
        XCTAssertEqual(correct, 1_402_353, "dedup by (message.id, requestId) gives the real total")
    }

    /// The store, not the parser, is what makes ingestion idempotent — verify the
    /// two work together, since that is the path the app actually takes.
    func testStoreCollapsesDuplicateEventsAndIsIdempotent() throws {
        let store = try makeTempStore()
        let result = ClaudeCodeLogParser().parse(lines: try lines("claude-session"))

        let firstInsert = try store.insert(events: result.events)
        XCTAssertEqual(firstInsert, 33, "only distinct messages land in the DB")

        // Re-ingesting the same log (an app restart, a re-scan) must add nothing.
        let secondInsert = try store.insert(events: result.events)
        XCTAssertEqual(secondInsert, 0)
        XCTAssertEqual(store.eventCount(), 33)

        let stored = try store.events(provider: .claudeCode, since: .distantPast)
        XCTAssertEqual(stored.reduce(0) { $0 + $1.totalTokens }, 1_402_353)
    }

    func testTokenBreakdownMatchesLoggedFields() throws {
        let result = ClaudeCodeLogParser().parse(lines: try lines("claude-broken"))
        let first = try XCTUnwrap(result.events.first)

        XCTAssertEqual(first.inputTokens, 10)
        XCTAssertEqual(first.cacheCreationTokens, 20)
        XCTAssertEqual(first.cachedInputTokens, 30)
        XCTAssertEqual(first.outputTokens, 40)
        XCTAssertEqual(first.totalTokens, 100)
        XCTAssertEqual(first.id, "msg_a|req_a")
        XCTAssertEqual(first.source, .localLog)
    }

    /// Claude Code folds thinking into output_tokens and never reports reasoning
    /// separately. It must stay nil — reporting 0 would claim we measured zero.
    func testReasoningTokensAreNilNotZero() throws {
        let result = ClaudeCodeLogParser().parse(lines: try lines("claude-session"))
        XCTAssertFalse(result.events.isEmpty)
        for event in result.events {
            XCTAssertNil(event.reasoningTokens)
        }
    }

    func testBrokenAndTruncatedLinesAreSkippedWithoutLosingGoodOnes() throws {
        let result = ClaudeCodeLogParser().parse(lines: try lines("claude-broken"))

        XCTAssertEqual(result.events.count, 2, "the two well-formed records survive")
        XCTAssertEqual(result.events.map(\.id), ["msg_a|req_a", "msg_b|req_b"])

        // Only the truncated *usage* line counts as malformed. The "not json at all"
        // and "{}" lines never claimed to be usage records, so they are simply not
        // candidates — treating them as parse failures would trip the
        // format-changed alarm on ordinary log noise.
        XCTAssertEqual(result.candidateLineCount, 3, "3 lines mention usage")
        XCTAssertEqual(result.malformedLineCount, 1, "the truncated usage line")
    }

    func testEmptyFileYieldsNothingAndDoesNotThrow() throws {
        let result = ClaudeCodeLogParser().parse(lines: try lines("empty"))
        XCTAssertTrue(result.events.isEmpty)
        XCTAssertEqual(result.malformedLineCount, 0)
        XCTAssertNil(result.latestModel)
    }

    /// A future Claude Code release adding fields must not break parsing, and
    /// records we do not understand must be ignored rather than guessed at.
    func testUnknownFieldsAreToleratedAndSyntheticModelsExcluded() throws {
        let result = ClaudeCodeLogParser().parse(lines: try lines("claude-unknown-fields"))

        // msg_c (unknown keys), msg_d (missing input fields) parse; the
        // "<synthetic>" model and the unknown record type do not.
        XCTAssertEqual(result.events.map(\.id), ["msg_c|req_c", "msg_d|req_d"])

        let c = result.events[0]
        XCTAssertEqual(c.totalTokens, 150)

        // Missing optional token fields default to 0 for that field only.
        let d = result.events[1]
        XCTAssertEqual(d.inputTokens, 0)
        XCTAssertEqual(d.outputTokens, 7)
        XCTAssertEqual(d.totalTokens, 7)

        XCTAssertFalse(result.events.contains { $0.model == "<synthetic>" })
    }

    func testCurrentContextIsTheLastRequestsInputFootprint() throws {
        let result = ClaudeCodeLogParser().parse(lines: try lines("claude-broken"))
        // last good record: 1 + 3 + 2 = 6 (input + cache_read + cache_creation)
        XCTAssertEqual(result.latestContextTokens, 6)
        XCTAssertEqual(result.latestModel, "claude-opus-4-8")
    }
}
