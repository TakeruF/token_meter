import Foundation

/// Codex, read from `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
///
/// This is the only provider that can report a real usage percentage and reset
/// time, because `token_count` events carry a `rate_limits` block.
public actor CodexUsageProvider: UsageProvider {
    public nonisolated let id: UsageProviderID = .codex
    public nonisolated let displayName = "Codex"

    private let sessionsRoot: URL
    private let store: UsageStore
    private let parser = CodexLogParser()
    private var watcher: DirectoryWatcher?
    /// Recently modified files checked on every refresh. Older files with no
    /// persisted cursor are added once so existing history is fully backfilled.
    private let maxFilesPerRefresh: Int

    /// Windows persist between refreshes: a pass that appends no new events must
    /// not drop the quota we already know about.
    private var lastShortWindow: UsageWindow?
    private var lastWeeklyWindow: UsageWindow?
    private var lastSparkShortWindow: UsageWindow?
    private var lastSparkWeeklyWindow: UsageWindow?
    private var lastPlanType: String?
    private var lastContextWindow: Int?
    private var lastModel: String?
    private var lastContextTokens: Int?
    private var lastWindowUpdate: Date?
    private var didRecoverCanonicalRateLimits = false

    public init(sessionsRoot: URL = TokenMeterPaths.codexSessions, store: UsageStore, maxFilesPerRefresh: Int = 20) {
        self.sessionsRoot = sessionsRoot
        self.store = store
        self.maxFilesPerRefresh = maxFilesPerRefresh
    }

    /// The session id is the trailing UUID of `rollout-<ISO8601>-<uuid>.jsonl`.
    static func sessionID(from url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.split(separator: "-")
        // A UUID is 5 dash-separated groups; take them off the end.
        guard parts.count >= 5 else { return name }
        return parts.suffix(5).joined(separator: "-")
    }

    public func checkAvailability() async -> ProviderAvailability {
        let fm = FileManager.default

        guard fm.fileExists(atPath: TokenMeterPaths.codexHome.path) else {
            return .notInstalled(detail: "\(TokenMeterPaths.codexHome.path) not found")
        }
        // Presence only — the file holds credentials and is never opened.
        guard fm.fileExists(atPath: TokenMeterPaths.codexAuthMarker.path) else {
            return .notLoggedIn(detail: "Run `codex login`")
        }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sessionsRoot.path, isDirectory: &isDir), isDir.boolValue else {
            return .noData(detail: "No session logs in \(sessionsRoot.path)")
        }
        guard fm.isReadableFile(atPath: sessionsRoot.path) else {
            return .permissionDenied(path: sessionsRoot.path)
        }
        guard !TokenMeterPaths.jsonlFiles(under: sessionsRoot, limit: 1).isEmpty else {
            return .noData(detail: "No rollout logs yet")
        }
        return .available(detail: "Rollout logs — tokens, usage %, and reset time", hasQuota: true)
    }

    public func fetchCurrentUsage(forceRefresh: Bool = false) async throws -> UsageSnapshot {
        switch await checkAvailability() {
        case .notInstalled(let d): throw UsageProviderError.sourceNotFound(d)
        case .notLoggedIn(let d): throw UsageProviderError.sourceNotFound(d)
        case .permissionDenied(let p): throw UsageProviderError.permissionDenied(p)
        case .noData: throw UsageProviderError.noDataYet
        case .available: break
        }

        // Newest first, so the freshest rate_limits block wins. The recent subset
        // is checked on every refresh. Any older file without a cursor was never
        // imported (including files skipped by older Token Meter versions), so add
        // it for a one-time historical backfill.
        let allFiles = TokenMeterPaths.jsonlFiles(under: sessionsRoot)
        let recentFiles = Array(allFiles.prefix(maxFilesPerRefresh))
        let historicalBackfill = allFiles.dropFirst(recentFiles.count).filter {
            store.cursor(forPath: $0.path) == 0
        }
        let files = recentFiles + historicalBackfill
        var newestParsed: Date?

        // Older Token Meter builds treated model-specific buckets such as
        // `codex_bengalfox` as the general account limit. Re-read quota lines from
        // the newest applicable file once per launch so an already-persisted bad
        // sample is repaired even when every incremental cursor is at EOF.
        if !didRecoverCanonicalRateLimits {
            didRecoverCanonicalRateLimits = true
            recoverCanonicalRateLimits(from: files)
        }

        for file in files.reversed() {   // oldest -> newest, so later files overwrite windows
            // Safe cancellation point: cursors and session totals are committed per
            // file, so stopping here resumes cleanly on the next refresh.
            if Task.isCancelled { break }

            let path = file.path
            let sessionID = Self.sessionID(from: file)
            // Older releases stored one cumulative counter per session. Re-read
            // that session once so the new per-model counters can be reconstructed;
            // INSERT OR IGNORE keeps already persisted events idempotent.
            let storedModels = storedTotalsByModel(sessionID: sessionID)
            let needsModelMigration = storedModels.isEmpty
                && store.sessionTotals(sessionID: sessionID) != nil
            let offset = needsModelMigration ? 0 : store.cursor(forPath: path)

            let read: IncrementalReadResult
            do {
                read = try JSONLReader.readNewLines(at: path, from: offset)
            } catch {
                continue
            }
            guard !read.lines.isEmpty else { continue }

            // Resume from the cumulative totals we stored, so deltas stay correct
            // across app restarts and never double count.
            let previous = read.didReset || needsModelMigration ? [:] : storedModels
            let result = parser.parse(
                lines: read.lines,
                sessionID: sessionID,
                previousTotalsByModel: previous,
                // Carried over so a resumed chunk still knows which model it is using.
                previousModel: store.latestModel(sessionID: sessionID)
            )

            if needsModelMigration {
                // Old event ids were session-wide. Replace only this derived
                // session's rows before inserting model-aware ids; token history
                // is reconstructed from the immutable Codex log below.
                try store.deleteEvents(provider: .codex, sessionID: sessionID)
            }
            if !result.events.isEmpty {
                try store.insert(events: result.events)
            }
            for (model, totals) in result.totalsByModel {
                try store.setSessionTotals(sessionID: "\(sessionID)|\(model)", provider: .codex, totals: totals)
            }
            try store.setCursor(path: path, offset: read.newOffset)

            if let ts = result.latestTimestamp {
                if newestParsed == nil || ts >= newestParsed! {
                    newestParsed = ts
                    if let m = result.latestModel { lastModel = m }
                    if let c = result.latestContextTokens { lastContextTokens = c }
                    if let w = result.contextWindowTokens { lastContextWindow = w }
                }
            }
            if result.shortWindow != nil || result.weeklyWindow != nil
                || result.sparkShortWindow != nil || result.sparkWeeklyWindow != nil {
                if let s = result.shortWindow { lastShortWindow = s }
                if let w = result.weeklyWindow { lastWeeklyWindow = w }
                if let s = result.sparkShortWindow { lastSparkShortWindow = s }
                if let w = result.sparkWeeklyWindow { lastSparkWeeklyWindow = w }
                if let p = result.planType { lastPlanType = p }
                lastWindowUpdate = result.latestRateLimitTimestamp ?? result.latestTimestamp ?? Date()
            }
        }

        let aggregator = UsageAggregator()
        // One read covering the widest window we report on (the weekly quota window
        // is 7 days); today and the 5-hour window are sliced out of it.
        let weekEvents = try store.events(provider: .codex, since: aggregator.day(offsetFromToday: 6))
        let startOfToday = aggregator.startOfDay(Date())
        let todayEvents = weekEvents.filter { $0.timestamp >= startOfToday }
        let today = aggregator.todayTotals(todayEvents, provider: .codex)

        // Persist the quota reading for history.
        if let s = lastShortWindow {
            try store.insertLimitSample(provider: .codex, timestamp: lastWindowUpdate ?? Date(), kind: "short", window: s, source: .localLog)
        }
        if let w = lastWeeklyWindow {
            try store.insertLimitSample(provider: .codex, timestamp: lastWindowUpdate ?? Date(), kind: "weekly", window: w, source: .localLog)
        }
        if let s = lastSparkShortWindow {
            try store.insertLimitSample(provider: .codex, timestamp: lastWindowUpdate ?? Date(), kind: "spark_short", window: s, source: .localLog)
        }
        if let w = lastSparkWeeklyWindow {
            try store.insertLimitSample(provider: .codex, timestamp: lastWindowUpdate ?? Date(), kind: "spark_weekly", window: w, source: .localLog)
        }

        // Rate limits only appear on lines the log appends. After a restart, an
        // incremental pass usually reads nothing new — so recover the last reading
        // we stored instead of reporting "no quota info" for a quota we do know.
        if lastShortWindow == nil, let stored = store.latestLimitSample(provider: .codex, kind: "short") {
            lastShortWindow = stored.window
            lastWindowUpdate = lastWindowUpdate ?? stored.timestamp
        }
        if lastWeeklyWindow == nil, let stored = store.latestLimitSample(provider: .codex, kind: "weekly") {
            lastWeeklyWindow = stored.window
            lastWindowUpdate = lastWindowUpdate ?? stored.timestamp
        }
        if lastSparkShortWindow == nil, let stored = store.latestLimitSample(provider: .codex, kind: "spark_short") {
            lastSparkShortWindow = stored.window
            lastWindowUpdate = lastWindowUpdate ?? stored.timestamp
        }
        if lastSparkWeeklyWindow == nil, let stored = store.latestLimitSample(provider: .codex, kind: "spark_weekly") {
            lastSparkWeeklyWindow = stored.window
            lastWindowUpdate = lastWindowUpdate ?? stored.timestamp
        }
        if lastModel == nil {
            lastModel = store.latestModel(provider: .codex)
        }

        // A window whose reset time has passed is spent; showing the old percentage
        // would be showing stale data as if it were current.
        let now = Date()
        let short = expireIfReset(lastShortWindow, now: now)
        let weekly = expireIfReset(lastWeeklyWindow, now: now)

        // Codex states both `resets_at` and `window_minutes`, so the window's start is
        // known and the tokens spent inside it are a real count — not a derivation.
        let shortUsage = short.flatMap { aggregator.reportedWindowUsage(weekEvents, provider: .codex, window: $0) }
        let weeklyUsage = weekly.flatMap { aggregator.reportedWindowUsage(weekEvents, provider: .codex, window: $0) }

        return UsageSnapshot(
            provider: .codex,
            timestamp: Date(),
            modelName: lastModel,
            inputTokens: today?.inputTokens,
            cachedInputTokens: today?.cachedInputTokens,
            cacheCreationTokens: nil,      // Codex does not report cache creation
            outputTokens: today?.outputTokens,
            reasoningTokens: today?.reasoningTokens,
            totalTokens: today?.totalTokens,
            currentContextTokens: lastContextTokens,
            contextWindowTokens: lastContextWindow,
            shortWindow: short,
            weeklyWindow: weekly,
            sparkShortWindow: expireIfReset(lastSparkShortWindow, now: now),
            sparkWeeklyWindow: expireIfReset(lastSparkWeeklyWindow, now: now),
            shortWindowUsage: shortUsage,
            weeklyWindowUsage: weeklyUsage,
            planType: lastPlanType,
            source: .localLog
        )
    }

    /// After `resetsAt` the figure we hold is meaningless: the quota rolled over but
    /// Codex has not written a new reading yet. Report nil, not the old percentage.
    private func expireIfReset(_ window: UsageWindow?, now: Date) -> UsageWindow? {
        guard let window else { return nil }
        guard let resetsAt = window.resetsAt else { return window }
        return resetsAt > now ? window : nil
    }

    private func recoverCanonicalRateLimits(from files: [URL]) {
        // `files` is newest first. A recent rollout can contain only Spark or only
        // general Codex, so collect the newest reading for every distinct bucket
        // instead of allowing a Spark-only file to blank the general menu-bar value.
        var recovered = CodexLogParser.RateLimitResult()
        for file in files {
            guard let read = try? JSONLReader.readNewLines(at: file.path, from: 0),
                  !read.lines.isEmpty else { continue }

            let reading = parser.parseLatestRateLimits(lines: read.lines)
            if recovered.shortWindow == nil { recovered.shortWindow = reading.shortWindow }
            if recovered.weeklyWindow == nil { recovered.weeklyWindow = reading.weeklyWindow }
            if recovered.sparkShortWindow == nil { recovered.sparkShortWindow = reading.sparkShortWindow }
            if recovered.sparkWeeklyWindow == nil { recovered.sparkWeeklyWindow = reading.sparkWeeklyWindow }
            if recovered.planType == nil { recovered.planType = reading.planType }
        }

        guard recovered.hasQuota else { return }
        if let short = recovered.shortWindow { lastShortWindow = short }
        if let weekly = recovered.weeklyWindow { lastWeeklyWindow = weekly }
        if let sparkShort = recovered.sparkShortWindow { lastSparkShortWindow = sparkShort }
        if let sparkWeekly = recovered.sparkWeeklyWindow { lastSparkWeeklyWindow = sparkWeekly }
        if let planType = recovered.planType { lastPlanType = planType }
        // Timestamp the repair now so it supersedes a bad sample persisted by a
        // previous app version. The window's reset time remains provider data.
        lastWindowUpdate = Date()
    }

    private func storedTotalsByModel(sessionID: String) -> [String: CodexCumulativeTotals] {
        var out: [String: CodexCumulativeTotals] = [:]
        for model in store.sessionModels(provider: .codex, sessionPrefix: "\(sessionID)|") {
            if let totals = store.sessionTotals(sessionID: "\(sessionID)|\(model)") {
                out[model] = totals
            }
        }
        return out
    }

    public func startMonitoring(onUpdate: @escaping @Sendable (UsageSnapshot) -> Void) async throws {
        guard watcher == nil else { return }
        let w = DirectoryWatcher(paths: [sessionsRoot.path], debounce: 3.0) { [weak self] in
            guard let self else { return }
            Task {
                if let snapshot = try? await self.fetchCurrentUsage() {
                    onUpdate(snapshot)
                }
            }
        }
        w.start()
        watcher = w
    }

    public func stopMonitoring() async {
        watcher?.stop()
        watcher = nil
    }
}
