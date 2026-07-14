import Foundation
import XCTest
@testable import TokenMeterCore

extension XCTestCase {
    /// A store in a unique temp dir, torn down with the test.
    func makeTempStore(file: StaticString = #filePath, line: UInt = #line) throws -> UsageStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmeter-tests-\(UUID().uuidString)", isDirectory: true)
        let store = try UsageStore(path: dir.appendingPathComponent("history.sqlite").path)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return store
    }

    func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmeter-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }
}

func makeEvent(
    id: String,
    provider: UsageProviderID = .claudeCode,
    at timestamp: Date,
    model: String? = "m",
    input: Int = 0,
    cached: Int = 0,
    cacheCreation: Int = 0,
    output: Int = 0,
    reasoning: Int? = nil,
    total: Int? = nil
) -> UsageEvent {
    UsageEvent(
        id: id,
        provider: provider,
        timestamp: timestamp,
        model: model,
        sessionID: "s",
        inputTokens: input,
        cachedInputTokens: cached,
        cacheCreationTokens: cacheCreation,
        outputTokens: output,
        reasoningTokens: reasoning,
        totalTokens: total ?? (input + cached + cacheCreation + output),
        source: .localLog
    )
}
