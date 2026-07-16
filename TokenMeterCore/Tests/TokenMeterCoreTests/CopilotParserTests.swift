import Foundation
import XCTest
@testable import TokenMeterCore

final class CopilotParserTests: XCTestCase {
    private let parser = CopilotLogParser()

    private func shutdownLine(
        timestamp: String = "2026-07-15T10:00:00.000Z",
        metrics: [String: (input: Int, output: Int, cacheRead: Int, cacheWrite: Int)]
    ) -> String {
        var models: [String: Any] = [:]
        for (model, u) in metrics {
            models[model] = [
                "usage": [
                    "inputTokens": u.input,
                    "outputTokens": u.output,
                    "cacheReadTokens": u.cacheRead,
                    "cacheWriteTokens": u.cacheWrite,
                ]
            ]
        }
        let obj: [String: Any] = [
            "type": "session.shutdown",
            "timestamp": timestamp,
            "data": ["modelMetrics": models],
        ]
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return String(data: data, encoding: .utf8)!
    }

    func testEmitsPerModelWorkingTokensFromShutdown() {
        let line = shutdownLine(metrics: [
            "claude-opus-4.5": (input: 600_000, output: 7_000, cacheRead: 550_000, cacheWrite: 100),
            "claude-haiku-4.5": (input: 250_000, output: 6_000, cacheRead: 210_000, cacheWrite: 0),
        ])
        let result = parser.parse(lines: [line], sessionID: "sess-1")

        XCTAssertEqual(result.events.count, 2)
        let opus = result.events.first { $0.model == "claude-opus-4.5" }
        XCTAssertNotNil(opus)
        XCTAssertEqual(opus?.inputTokens, 600_000)
        XCTAssertEqual(opus?.outputTokens, 7_000)
        XCTAssertEqual(opus?.cachedInputTokens, 550_000)
        XCTAssertEqual(opus?.cacheCreationTokens, 100)   // cacheWrite → cacheCreation
        XCTAssertNil(opus?.reasoningTokens)              // Copilot reports none
        XCTAssertEqual(opus?.provider, .copilotCli)
    }

    func testCumulativeShutdownsProduceDeltasNotDoubleCounts() {
        // A resumed session writes a second shutdown with cumulative totals.
        let first = shutdownLine(
            timestamp: "2026-07-15T10:00:00.000Z",
            metrics: ["claude-opus-4.5": (input: 100, output: 10, cacheRead: 0, cacheWrite: 0)]
        )
        let firstResult = parser.parse(lines: [first], sessionID: "sess-1")
        XCTAssertEqual(firstResult.events.first?.totalTokens, 110)

        let second = shutdownLine(
            timestamp: "2026-07-15T11:00:00.000Z",
            metrics: ["claude-opus-4.5": (input: 300, output: 40, cacheRead: 0, cacheWrite: 0)]
        )
        let secondResult = parser.parse(
            lines: [second],
            sessionID: "sess-1",
            previousTotalsByModel: firstResult.totalsByModel
        )
        // Delta only: (300-100) input + (40-10) output = 230, not 340.
        XCTAssertEqual(secondResult.events.count, 1)
        XCTAssertEqual(secondResult.events.first?.inputTokens, 200)
        XCTAssertEqual(secondResult.events.first?.outputTokens, 30)
        XCTAssertEqual(secondResult.events.first?.totalTokens, 230)
    }

    func testCounterRestartTakesCurrentValueWhole() {
        let previous: [String: CodexCumulativeTotals] = [
            "claude-opus-4.5": CodexCumulativeTotals(
                inputTokens: 1_000, outputTokens: 100, totalTokens: 1_100, eventCount: 1
            )
        ]
        // A smaller cumulative than stored means the session counter restarted.
        let line = shutdownLine(
            metrics: ["claude-opus-4.5": (input: 50, output: 5, cacheRead: 0, cacheWrite: 0)]
        )
        let result = parser.parse(lines: [line], sessionID: "sess-1", previousTotalsByModel: previous)
        XCTAssertEqual(result.events.first?.inputTokens, 50)
        XCTAssertEqual(result.events.first?.totalTokens, 55)
    }

    func testIgnoresNonShutdownLines() {
        let noise = #"{"type":"assistant.message","data":{"outputTokens":348}}"#
        let result = parser.parse(lines: [noise], sessionID: "sess-1")
        XCTAssertTrue(result.events.isEmpty)
    }

    func testZeroDeltaProducesNoEvent() {
        let line = shutdownLine(metrics: ["m": (input: 0, output: 0, cacheRead: 0, cacheWrite: 0)])
        let result = parser.parse(lines: [line], sessionID: "sess-1")
        XCTAssertTrue(result.events.isEmpty)
    }
}
