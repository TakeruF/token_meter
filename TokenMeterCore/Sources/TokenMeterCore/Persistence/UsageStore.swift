import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite history.
///
/// Only counts, timestamps, model names and ratios are stored. No prompt text, no
/// response text, no credentials — see README > Security.
///
/// Double counting is prevented structurally: `usage_event.id` is the primary key
/// and every insert is `INSERT OR IGNORE`, so replaying a log is a no-op.
public final class UsageStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.tokenmeter.store")
    public let path: String

    public init(path: String) throws {
        self.path = path
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw UsageProviderError.decodingFailed("Could not open database at \(path)")
        }
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA busy_timeout=3000;")
        try createSchema()
    }

    deinit { if let db { sqlite3_close_v2(db) } }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            let message = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw UsageProviderError.decodingFailed("SQL failed: \(message)")
        }
    }

    private func createSchema() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS usage_event (
            id TEXT PRIMARY KEY,
            provider TEXT NOT NULL,
            timestamp REAL NOT NULL,
            model TEXT,
            session_id TEXT,
            input_tokens INTEGER NOT NULL,
            cached_input_tokens INTEGER NOT NULL,
            cache_creation_tokens INTEGER NOT NULL,
            output_tokens INTEGER NOT NULL,
            reasoning_tokens INTEGER,
            total_tokens INTEGER NOT NULL,
            source TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_event_time ON usage_event(timestamp);
        CREATE INDEX IF NOT EXISTS idx_event_provider_time ON usage_event(provider, timestamp);

        CREATE TABLE IF NOT EXISTS file_cursor (
            path TEXT PRIMARY KEY,
            offset INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS session_totals (
            session_id TEXT PRIMARY KEY,
            provider TEXT NOT NULL,
            input_tokens INTEGER NOT NULL,
            cached_input_tokens INTEGER NOT NULL,
            output_tokens INTEGER NOT NULL,
            reasoning_tokens INTEGER NOT NULL,
            total_tokens INTEGER NOT NULL,
            event_count INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS limit_sample (
            provider TEXT NOT NULL,
            timestamp REAL NOT NULL,
            window_kind TEXT NOT NULL,
            used_ratio REAL,
            remaining_ratio REAL,
            resets_at REAL,
            source TEXT NOT NULL,
            PRIMARY KEY (provider, window_kind, timestamp)
        );
        """)
    }

    // MARK: - Events

    /// Inserts events, ignoring ones already present. Returns how many were new.
    @discardableResult
    public func insert(events: [UsageEvent]) throws -> Int {
        guard !events.isEmpty else { return 0 }
        return try queue.sync {
            try exec("BEGIN IMMEDIATE;")
            var inserted = 0
            do {
                let sql = """
                INSERT OR IGNORE INTO usage_event
                (id, provider, timestamp, model, session_id, input_tokens, cached_input_tokens,
                 cache_creation_tokens, output_tokens, reasoning_tokens, total_tokens, source)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?);
                """
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    throw UsageProviderError.decodingFailed("prepare insert failed")
                }
                defer { sqlite3_finalize(stmt) }

                for e in events {
                    sqlite3_bind_text(stmt, 1, e.id, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 2, e.provider.rawValue, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_double(stmt, 3, e.timestamp.timeIntervalSince1970)
                    if let m = e.model { sqlite3_bind_text(stmt, 4, m, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 4) }
                    if let s = e.sessionID { sqlite3_bind_text(stmt, 5, s, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 5) }
                    sqlite3_bind_int64(stmt, 6, Int64(e.inputTokens))
                    sqlite3_bind_int64(stmt, 7, Int64(e.cachedInputTokens))
                    sqlite3_bind_int64(stmt, 8, Int64(e.cacheCreationTokens))
                    sqlite3_bind_int64(stmt, 9, Int64(e.outputTokens))
                    if let r = e.reasoningTokens { sqlite3_bind_int64(stmt, 10, Int64(r)) } else { sqlite3_bind_null(stmt, 10) }
                    sqlite3_bind_int64(stmt, 11, Int64(e.totalTokens))
                    sqlite3_bind_text(stmt, 12, e.source.rawValue, -1, SQLITE_TRANSIENT)

                    guard sqlite3_step(stmt) == SQLITE_DONE else {
                        throw UsageProviderError.decodingFailed("insert step failed")
                    }
                    if sqlite3_changes(db) > 0 { inserted += 1 }
                    sqlite3_reset(stmt)
                    sqlite3_clear_bindings(stmt)
                }
                try exec("COMMIT;")
            } catch {
                try? exec("ROLLBACK;")
                throw error
            }
            return inserted
        }
    }

    public func events(provider: UsageProviderID? = nil, since: Date, until: Date = .distantFuture) throws -> [UsageEvent] {
        try queue.sync {
            var sql = "SELECT id, provider, timestamp, model, session_id, input_tokens, cached_input_tokens, cache_creation_tokens, output_tokens, reasoning_tokens, total_tokens, source FROM usage_event WHERE timestamp >= ? AND timestamp < ?"
            if provider != nil { sql += " AND provider = ?" }
            sql += " ORDER BY timestamp ASC;"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw UsageProviderError.decodingFailed("prepare select failed")
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, since.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 2, until == .distantFuture ? Date.distantFuture.timeIntervalSince1970 : until.timeIntervalSince1970)
            if let provider { sqlite3_bind_text(stmt, 3, provider.rawValue, -1, SQLITE_TRANSIENT) }

            var out: [UsageEvent] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                func text(_ i: Int32) -> String? {
                    guard let c = sqlite3_column_text(stmt, i) else { return nil }
                    return String(cString: c)
                }
                guard let id = text(0),
                      let providerRaw = text(1),
                      let p = UsageProviderID(rawValue: providerRaw),
                      let sourceRaw = text(11),
                      let source = UsageSource(rawValue: sourceRaw) else { continue }

                out.append(
                    UsageEvent(
                        id: id,
                        provider: p,
                        timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                        model: text(3),
                        sessionID: text(4),
                        inputTokens: Int(sqlite3_column_int64(stmt, 5)),
                        cachedInputTokens: Int(sqlite3_column_int64(stmt, 6)),
                        cacheCreationTokens: Int(sqlite3_column_int64(stmt, 7)),
                        outputTokens: Int(sqlite3_column_int64(stmt, 8)),
                        reasoningTokens: sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, 9)),
                        totalTokens: Int(sqlite3_column_int64(stmt, 10)),
                        source: source
                    )
                )
            }
            return out
        }
    }

    // MARK: - Cursors

    public func cursor(forPath path: String) -> UInt64 {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT offset FROM file_cursor WHERE path = ?;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return UInt64(max(0, sqlite3_column_int64(stmt, 0)))
        }
    }

    public func setCursor(path: String, offset: UInt64) throws {
        try queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "INSERT INTO file_cursor (path, offset) VALUES (?,?) ON CONFLICT(path) DO UPDATE SET offset = excluded.offset;", -1, &stmt, nil) == SQLITE_OK else {
                throw UsageProviderError.decodingFailed("prepare cursor failed")
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, Int64(offset))
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw UsageProviderError.decodingFailed("cursor step failed")
            }
        }
    }

    // MARK: - Codex session totals

    public func sessionTotals(sessionID: String) -> CodexCumulativeTotals? {
        queue.sync {
            var stmt: OpaquePointer?
            let sql = "SELECT input_tokens, cached_input_tokens, output_tokens, reasoning_tokens, total_tokens, event_count FROM session_totals WHERE session_id = ?;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, sessionID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return CodexCumulativeTotals(
                inputTokens: Int(sqlite3_column_int64(stmt, 0)),
                cachedInputTokens: Int(sqlite3_column_int64(stmt, 1)),
                outputTokens: Int(sqlite3_column_int64(stmt, 2)),
                reasoningTokens: Int(sqlite3_column_int64(stmt, 3)),
                totalTokens: Int(sqlite3_column_int64(stmt, 4)),
                eventCount: Int(sqlite3_column_int64(stmt, 5))
            )
        }
    }

    public func setSessionTotals(sessionID: String, provider: UsageProviderID, totals: CodexCumulativeTotals) throws {
        try queue.sync {
            let sql = """
            INSERT INTO session_totals (session_id, provider, input_tokens, cached_input_tokens, output_tokens, reasoning_tokens, total_tokens, event_count)
            VALUES (?,?,?,?,?,?,?,?)
            ON CONFLICT(session_id) DO UPDATE SET
                input_tokens = excluded.input_tokens,
                cached_input_tokens = excluded.cached_input_tokens,
                output_tokens = excluded.output_tokens,
                reasoning_tokens = excluded.reasoning_tokens,
                total_tokens = excluded.total_tokens,
                event_count = excluded.event_count;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw UsageProviderError.decodingFailed("prepare totals failed")
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, sessionID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, provider.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 3, Int64(totals.inputTokens))
            sqlite3_bind_int64(stmt, 4, Int64(totals.cachedInputTokens))
            sqlite3_bind_int64(stmt, 5, Int64(totals.outputTokens))
            sqlite3_bind_int64(stmt, 6, Int64(totals.reasoningTokens))
            sqlite3_bind_int64(stmt, 7, Int64(totals.totalTokens))
            sqlite3_bind_int64(stmt, 8, Int64(totals.eventCount))
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw UsageProviderError.decodingFailed("totals step failed")
            }
        }
    }

    // MARK: - Limit samples

    public func insertLimitSample(provider: UsageProviderID, timestamp: Date, kind: String, window: UsageWindow, source: UsageSource) throws {
        try queue.sync {
            let sql = "INSERT OR REPLACE INTO limit_sample (provider, timestamp, window_kind, used_ratio, remaining_ratio, resets_at, source) VALUES (?,?,?,?,?,?,?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw UsageProviderError.decodingFailed("prepare limit failed")
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, provider.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, timestamp.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 3, kind, -1, SQLITE_TRANSIENT)
            if let u = window.usedRatio { sqlite3_bind_double(stmt, 4, u) } else { sqlite3_bind_null(stmt, 4) }
            if let r = window.remainingRatio { sqlite3_bind_double(stmt, 5, r) } else { sqlite3_bind_null(stmt, 5) }
            if let d = window.resetsAt { sqlite3_bind_double(stmt, 6, d.timeIntervalSince1970) } else { sqlite3_bind_null(stmt, 6) }
            sqlite3_bind_text(stmt, 7, source.rawValue, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw UsageProviderError.decodingFailed("limit step failed")
            }
        }
    }

    /// The most recent quota reading we stored for this provider and window.
    ///
    /// Needed because rate limits arrive only on lines the log appends. After a
    /// restart the incremental parser reads nothing new, so without this the app
    /// would report "no quota info" for a provider whose quota it actually knows.
    public func latestLimitSample(provider: UsageProviderID, kind: String) -> (window: UsageWindow, timestamp: Date)? {
        queue.sync {
            let sql = """
            SELECT timestamp, used_ratio, remaining_ratio, resets_at FROM limit_sample
            WHERE provider = ? AND window_kind = ?
            ORDER BY timestamp DESC LIMIT 1;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, provider.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, kind, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
            let window = UsageWindow(
                usedRatio: sqlite3_column_type(stmt, 1) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 1),
                remainingRatio: sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 2),
                resetsAt: sqlite3_column_type(stmt, 3) == SQLITE_NULL
                    ? nil
                    : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
                windowMinutes: kind == "short" ? nil : 10080
            )
            return (window, timestamp)
        }
    }

    /// Newest stored event for a provider, used to recover the current model name
    /// after a restart that parses no new lines.
    public func latestEvent(provider: UsageProviderID) -> UsageEvent? {
        let recent = try? events(provider: provider, since: Date().addingTimeInterval(-30 * 86_400))
        return recent?.last
    }

    /// The most recent model recorded for a provider, ignoring events whose model we
    /// never learned. Used for display, so a session whose `turn_context` line was
    /// consumed before we knew to keep it still shows the right model.
    public func latestModel(provider: UsageProviderID) -> String? {
        queue.sync {
            let sql = """
            SELECT model FROM usage_event
            WHERE provider = ? AND model IS NOT NULL
            ORDER BY timestamp DESC LIMIT 1;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, provider.rawValue, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else { return nil }
            return String(cString: c)
        }
    }

    /// The model last recorded for a session.
    ///
    /// Codex names the model on `turn_context` lines, not on the `token_count` lines
    /// that carry the usage. An incremental read resumes mid-file, past those lines,
    /// so the model has to be carried over from what we already stored.
    public func latestModel(sessionID: String) -> String? {
        queue.sync {
            let sql = """
            SELECT model FROM usage_event
            WHERE session_id = ? AND model IS NOT NULL
            ORDER BY timestamp DESC LIMIT 1;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, sessionID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else { return nil }
            return String(cString: c)
        }
    }

    // MARK: - Retention

    /// Deletes events older than `days`. Returns rows removed.
    @discardableResult
    public func pruneEvents(olderThan days: Int) throws -> Int {
        guard days > 0 else { return 0 }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return try queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM usage_event WHERE timestamp < ?;", -1, &stmt, nil) == SQLITE_OK else {
                throw UsageProviderError.decodingFailed("prepare prune failed")
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, cutoff.timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw UsageProviderError.decodingFailed("prune step failed")
            }
            return Int(sqlite3_changes(db))
        }
    }

    /// Wipes every table, including cursors, so the next refresh rebuilds from the logs.
    public func deleteAllData() throws {
        try queue.sync {
            try exec("DELETE FROM usage_event; DELETE FROM file_cursor; DELETE FROM session_totals; DELETE FROM limit_sample;")
            try exec("VACUUM;")
        }
    }

    public func eventCount() -> Int {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM usage_event;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }
}
