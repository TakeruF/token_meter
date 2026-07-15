import XCTest
@testable import TokenMeterCore

final class SharedSnapshotTests: XCTestCase {

    func testWidgetJSONRoundTripsWithMissingValuesPreserved() throws {
        let store = SharedSnapshotStore(containerURL: makeTempDirectory())
        let snapshot = SharedSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_784_000_000),
            languageCode: "ja",
            claudeCode: .init(
                displayName: "Claude Code",
                // Claude publishes no quota: these must survive as nil, not 0.
                remainingRatio: nil,
                usedRatio: nil,
                resetsAt: nil,
                todayTokens: 1_840_230,
                modelName: "claude-opus-4-8",
                lastUpdated: Date(timeIntervalSince1970: 1_784_000_000),
                hasQuotaInformation: false
            ),
            codex: .init(
                displayName: "Codex",
                remainingRatio: 0.42,
                usedRatio: 0.58,
                resetsAt: Date(timeIntervalSince1970: 1_784_494_842),
                todayTokens: 2_471_020,
                modelName: "gpt-5.6-sol",
                lastUpdated: Date(timeIntervalSince1970: 1_784_000_000),
                hasQuotaInformation: true
            )
        )

        try store.write(snapshot)
        let decoded = try store.read()

        XCTAssertEqual(decoded, snapshot)
        XCTAssertNil(decoded.claudeCode?.remainingRatio, "a missing ratio must not decode as 0")
        XCTAssertFalse(try XCTUnwrap(decoded.claudeCode).hasQuotaInformation)
        XCTAssertEqual(decoded.codex?.remainingRatio, 0.42)
        XCTAssertEqual(decoded.languageCode, "ja")
    }

    /// The widget must be able to tell "nothing written yet" from "unreadable".
    func testReadIfPresentReturnsNilWhenNoSnapshotExists() {
        let store = SharedSnapshotStore(containerURL: makeTempDirectory())
        XCTAssertNil(store.readIfPresent())
    }

    /// Writes go via a temp file and an atomic replace, so a reader racing the
    /// writer sees either the old file or the new one — never a partial one.
    func testConcurrentWritesNeverLeaveAPartialFile() throws {
        let store = SharedSnapshotStore(containerURL: makeTempDirectory())
        try store.write(SharedSnapshot(updatedAt: Date()))

        let iterations = 50
        let group = DispatchGroup()

        DispatchQueue.global().async(group: group) {
            for i in 0..<iterations {
                let s = SharedSnapshot(
                    updatedAt: Date(timeIntervalSince1970: TimeInterval(i)),
                    codex: .init(displayName: "Codex", remainingRatio: Double(i) / Double(iterations), hasQuotaInformation: true)
                )
                try? store.write(s)
            }
        }
        DispatchQueue.global().async(group: group) {
            for _ in 0..<iterations {
                // Every read must yield a decodable document.
                XCTAssertNotNil(store.readIfPresent(), "reader observed a torn write")
            }
        }
        group.wait()

        XCTAssertNotNil(store.readIfPresent())
        // No temp files left behind.
        let leftovers = try FileManager.default
            .contentsOfDirectory(atPath: store.containerURL.path)
            .filter { $0.hasSuffix(".tmp") }
        XCTAssertTrue(leftovers.isEmpty, "temp files leaked: \(leftovers)")
    }

    func testTruncatedSnapshotFileIsReportedAsMissingRatherThanCrashing() throws {
        let store = SharedSnapshotStore(containerURL: makeTempDirectory())
        try store.write(SharedSnapshot(updatedAt: Date()))
        try Data("{ not json".utf8).write(to: store.fileURL)

        XCTAssertNil(store.readIfPresent())
        XCTAssertThrowsError(try store.read())
    }
}

final class IncrementalReadTests: XCTestCase {

    func testOnlyNewlyAppendedLinesAreReturned() throws {
        let dir = makeTempDirectory()
        let file = dir.appendingPathComponent("log.jsonl")
        try Data("{\"a\":1}\n{\"a\":2}\n".utf8).write(to: file)

        let first = try JSONLReader.readNewLines(at: file.path, from: 0)
        XCTAssertEqual(first.lines.count, 2)

        // Nothing new: the second pass must return nothing, which is what keeps
        // repeated refreshes from re-counting the same usage.
        let second = try JSONLReader.readNewLines(at: file.path, from: first.newOffset)
        XCTAssertEqual(second.lines.count, 0)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"a\":3}\n".utf8))
        try handle.close()

        let third = try JSONLReader.readNewLines(at: file.path, from: second.newOffset)
        XCTAssertEqual(third.lines, ["{\"a\":3}"])
    }

    /// A live log is often mid-append. The partial tail must not be consumed, or we
    /// would parse half a record and then never see the whole one.
    func testPartialTrailingLineIsLeftForTheNextPass() throws {
        let dir = makeTempDirectory()
        let file = dir.appendingPathComponent("log.jsonl")
        try Data("{\"a\":1}\n{\"a\":2".utf8).write(to: file)   // no trailing newline

        let first = try JSONLReader.readNewLines(at: file.path, from: 0)
        XCTAssertEqual(first.lines, ["{\"a\":1}"])
        XCTAssertEqual(first.newOffset, 8, "offset stops at the last newline")

        // The writer finishes the line.
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("}\n".utf8))
        try handle.close()

        let second = try JSONLReader.readNewLines(at: file.path, from: first.newOffset)
        XCTAssertEqual(second.lines, ["{\"a\":2}"], "the completed line is read exactly once")
    }

    func testTruncatedFileRestartsFromZero() throws {
        let dir = makeTempDirectory()
        let file = dir.appendingPathComponent("log.jsonl")
        try Data("{\"a\":1}\n{\"a\":2}\n".utf8).write(to: file)
        let first = try JSONLReader.readNewLines(at: file.path, from: 0)

        try Data("{\"b\":1}\n".utf8).write(to: file)   // rotated: now shorter

        let second = try JSONLReader.readNewLines(at: file.path, from: first.newOffset)
        XCTAssertTrue(second.didReset)
        XCTAssertEqual(second.lines, ["{\"b\":1}"])
    }

    func testMissingFileThrowsSourceNotFound() {
        XCTAssertThrowsError(try JSONLReader.readNewLines(at: "/nonexistent/nope.jsonl", from: 0)) { error in
            XCTAssertEqual(error as? UsageProviderError, .sourceNotFound("/nonexistent/nope.jsonl"))
        }
    }
}

final class ProviderAvailabilityTests: XCTestCase {

    /// Data source missing: the provider must say so rather than report zeros.
    func testClaudeProviderReportsNotInstalledWhenNothingIsThere() async throws {
        let store = try makeTempStore()
        let provider = ClaudeCodeUsageProvider(
            projectsRoot: makeTempDirectory().appendingPathComponent("absent/projects"),
            store: store
        )

        let availability = await provider.checkAvailability()
        guard case .notInstalled = availability else {
            return XCTFail("expected .notInstalled, got \(availability)")
        }

        do {
            _ = try await provider.fetchCurrentUsage()
            XCTFail("fetch must fail when the source is absent")
        } catch {
            XCTAssertNotNil(error as? UsageProviderError)
        }
    }

    func testCodexProviderReportsNoDataWhenSessionsDirectoryIsEmpty() async throws {
        let store = try makeTempStore()
        let root = makeTempDirectory().appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let provider = CodexUsageProvider(sessionsRoot: root, store: store)
        let availability = await provider.checkAvailability()

        // ~/.codex exists on this machine, so the empty-directory case is what we get.
        switch availability {
        case .noData, .notInstalled, .notLoggedIn:
            break
        default:
            XCTFail("empty sessions dir must not read as .available, got \(availability)")
        }
    }

    /// An availability state must never claim quota data that the provider cannot
    /// produce — this is what stops the UI inventing a percentage for Claude.
    func testClaudeAvailabilityNeverAdvertisesQuota() async throws {
        let store = try makeTempStore()
        let root = makeTempDirectory()
        let session = root.appendingPathComponent("proj", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try Data("{}\n".utf8).write(to: session.appendingPathComponent("s.jsonl"))

        let provider = ClaudeCodeUsageProvider(projectsRoot: root, store: store)
        guard case .available(_, let hasQuota) = await provider.checkAvailability() else {
            return XCTFail("expected .available")
        }
        XCTAssertFalse(hasQuota, "Claude Code publishes no quota locally")
    }

    /// End to end on real fixture data: ingest a Claude log through the provider and
    /// confirm the snapshot carries tokens but no invented percentages.
    func testClaudeSnapshotHasTokensButNilQuota() async throws {
        let store = try makeTempStore()
        let root = makeTempDirectory()
        let projectDir = root.appendingPathComponent("-Users-example-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // A record dated now, so it lands in "today" whatever the test clock says.
        let now = ISO8601DateFormatter().string(from: Date())
        let line = """
        {"type":"assistant","timestamp":"\(now)","sessionId":"s1","requestId":"r1","message":{"id":"m1","model":"claude-opus-4-8","role":"assistant","usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30,"output_tokens":40}}}
        """
        try Data((line + "\n").utf8).write(to: projectDir.appendingPathComponent("s1.jsonl"))

        let provider = ClaudeCodeUsageProvider(projectsRoot: root, store: store)
        let snapshot = try await provider.fetchCurrentUsage()

        XCTAssertEqual(snapshot.totalTokens, 100)
        XCTAssertEqual(snapshot.modelName, "claude-opus-4-8")
        XCTAssertEqual(snapshot.currentContextTokens, 60)

        XCTAssertNil(snapshot.shortWindow)
        XCTAssertNil(snapshot.weeklyWindow)
        XCTAssertNil(snapshot.reasoningTokens)
        XCTAssertNil(snapshot.contextWindowTokens)
        XCTAssertFalse(snapshot.hasQuotaInformation)
    }
}

final class QuotaRecoveryTests: XCTestCase {

    func testCodexBackfillsUnseenSessionsBeyondTheRefreshLimit() async throws {
        let store = try makeTempStore()
        let root = makeTempDirectory()
        let dayDir = root.appendingPathComponent("2026/07/15", isDirectory: true)
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())

        for index in 0..<21 {
            let sessionID = String(format: "00000000-0000-0000-0000-%012d", index)
            let line = """
            {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":10}},"rate_limits":null}}
            """
            let file = dayDir.appendingPathComponent("rollout-2026-07-15T10-00-00-\(sessionID).jsonl")
            try Data((line + "\n").utf8).write(to: file)
        }

        let provider = CodexUsageProvider(
            sessionsRoot: root,
            store: store,
            maxFilesPerRefresh: 20
        )

        let first = try await provider.fetchCurrentUsage()
        XCTAssertEqual(first.totalTokens, 210)
        XCTAssertEqual(try store.events(provider: .codex, since: .distantPast).count, 21)

        _ = try await provider.fetchCurrentUsage()
        XCTAssertEqual(
            try store.events(provider: .codex, since: .distantPast).count,
            21,
            "backfilled sessions must remain idempotent"
        )
    }

    func testCanonicalQuotaRepairsPersistedModelSpecificLimitAfterUpgrade() async throws {
        let store = try makeTempStore()
        let root = makeTempDirectory()
        let dayDir = root.appendingPathComponent("2026/07/15", isDirectory: true)
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        let reset = Int(Date().addingTimeInterval(6 * 86_400).timeIntervalSince1970)
        let lines = [
            """
            {"timestamp":"2026-07-15T01:45:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","primary":{"used_percent":8.0,"window_minutes":10080,"resets_at":\(reset)},"secondary":null,"plan_type":"pro"}}}
            """,
            """
            {"timestamp":"2026-07-15T02:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex_bengalfox","primary":{"used_percent":0.0,"window_minutes":10080,"resets_at":\(reset)},"secondary":null,"plan_type":"pro"}}}
            """,
        ]
        let file = dayDir.appendingPathComponent("rollout-2026-07-15T01-00-00-019f5f87-eeb1-7493-96fc-7dbf947babbb.jsonl")
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        try data.write(to: file)

        // Simulate an older build: it consumed the whole file and persisted the
        // model-specific 100%-remaining bucket as the account quota.
        let enumeratedPath = try XCTUnwrap(TokenMeterPaths.jsonlFiles(under: root).first?.path)
        try store.setCursor(path: enumeratedPath, offset: UInt64(data.count))
        try store.insertLimitSample(
            provider: .codex,
            timestamp: Date().addingTimeInterval(-60),
            kind: "weekly",
            window: UsageWindow(
                usedRatio: 0,
                remainingRatio: 1,
                resetsAt: Date(timeIntervalSince1970: Double(reset)),
                windowMinutes: 10080
            ),
            source: .localLog
        )

        let provider = CodexUsageProvider(sessionsRoot: root, store: store)
        let snapshot = try await provider.fetchCurrentUsage()

        XCTAssertEqual(try XCTUnwrap(snapshot.weeklyWindow?.usedRatio), 0.08, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(snapshot.weeklyWindow?.remainingRatio), 0.92, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(store.latestLimitSample(provider: .codex, kind: "weekly")?.window.usedRatio), 0.08, accuracy: 0.001)
    }

    /// Regression: rate limits arrive only on newly appended log lines. On the second
    /// launch the incremental parser reads nothing, and the provider used to report
    /// "no quota info" for a quota it had already recorded. It must recover the last
    /// stored reading instead.
    func testQuotaSurvivesRestartWhenNoNewLogLinesAreAppended() async throws {
        let store = try makeTempStore()
        let root = makeTempDirectory()
        let dayDir = root.appendingPathComponent("2026/07/14", isDirectory: true)
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)

        let line = """
        {"timestamp":"2026-07-14T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":5,"total_tokens":110}},"rate_limits":{"primary":{"used_percent":26.0,"window_minutes":10080,"resets_at":\(Int(Date().addingTimeInterval(86_400).timeIntervalSince1970))},"secondary":null,"plan_type":"pro"}}}
        """
        let file = dayDir.appendingPathComponent("rollout-2026-07-14T10-00-00-019f5f87-eeb1-7493-96fc-7dbf947babbb.jsonl")
        try Data((line + "\n").utf8).write(to: file)

        // First launch: parses the log, sees the quota.
        let first = CodexUsageProvider(sessionsRoot: root, store: store)
        let firstSnapshot = try await first.fetchCurrentUsage()
        XCTAssertEqual(try XCTUnwrap(firstSnapshot.weeklyWindow?.usedRatio), 0.26, accuracy: 0.001)

        // Second launch: a brand new provider (empty in-memory state) over the same
        // store and an unchanged log — the cursor is already at EOF, so nothing parses.
        let second = CodexUsageProvider(sessionsRoot: root, store: store)
        let secondSnapshot = try await second.fetchCurrentUsage()

        XCTAssertTrue(secondSnapshot.hasQuotaInformation, "the quota must survive a restart")
        XCTAssertEqual(try XCTUnwrap(secondSnapshot.weeklyWindow?.usedRatio), 0.26, accuracy: 0.001)
        XCTAssertEqual(secondSnapshot.weeklyWindow?.remainingRatio, 0.74)
    }

    /// But a quota whose reset time has passed is spent: reporting the old percentage
    /// would be presenting stale data as current.
    func testStoredQuotaIsDroppedOnceItsResetTimeHasPassed() async throws {
        let store = try makeTempStore()
        let root = makeTempDirectory()
        let dayDir = root.appendingPathComponent("2026/07/14", isDirectory: true)
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)

        // resets_at is in the past.
        let line = """
        {"timestamp":"2026-07-14T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":5,"total_tokens":110}},"rate_limits":{"primary":{"used_percent":26.0,"window_minutes":10080,"resets_at":\(Int(Date().addingTimeInterval(-3600).timeIntervalSince1970))},"secondary":null,"plan_type":"pro"}}}
        """
        try Data((line + "\n").utf8)
            .write(to: dayDir.appendingPathComponent("rollout-2026-07-14T10-00-00-019f5f87-eeb1-7493-96fc-7dbf947babbb.jsonl"))

        let provider = CodexUsageProvider(sessionsRoot: root, store: store)
        let snapshot = try await provider.fetchCurrentUsage()

        XCTAssertNil(snapshot.weeklyWindow, "an expired quota reading must not be shown as current")
        XCTAssertFalse(snapshot.hasQuotaInformation)
    }
}

final class FreshnessTests: XCTestCase {

    func testStaleDataIsFlagged() {
        XCTAssertEqual(DataFreshness.evaluate(age: 60), .fresh)
        if case .aging = DataFreshness.evaluate(age: 600) {} else { XCTFail("10 min should be aging") }

        let twoHours = DataFreshness.evaluate(age: 7_200)
        XCTAssertTrue(twoHours.isStale, "two-hour-old data must be marked stale, not shown as current")
    }
}
