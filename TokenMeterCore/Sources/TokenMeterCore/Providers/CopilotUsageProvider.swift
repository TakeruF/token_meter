import Foundation

/// GitHub Copilot CLI, read from `~/.copilot/session-state/<uuid>/events.jsonl`.
///
/// Copilot publishes no usage quota locally, so this provider reports token
/// measurements only — never a percentage or reset time. Complete per-model
/// counts appear in each session's `session.shutdown` event, so usage lands
/// when a session ends (see `CopilotLogParser`).
public actor CopilotUsageProvider: UsageProvider {
    public nonisolated let id: UsageProviderID = .copilotCli
    public nonisolated let displayName = "Copilot"

    private let sessionStateRoot: URL
    private let store: UsageStore
    private let parser = CopilotLogParser()
    private var watcher: DirectoryWatcher?
    private let maxFilesPerRefresh: Int

    private var lastModel: String?

    public init(
        sessionStateRoot: URL = TokenMeterPaths.copilotSessionState,
        store: UsageStore,
        maxFilesPerRefresh: Int = 20
    ) {
        self.sessionStateRoot = sessionStateRoot
        self.store = store
        self.maxFilesPerRefresh = maxFilesPerRefresh
    }

    /// The session id is the name of the directory holding the transcript.
    static func sessionID(from eventsFile: URL) -> String {
        eventsFile.deletingLastPathComponent().lastPathComponent
    }

    public func checkAvailability() async -> ProviderAvailability {
        let fm = FileManager.default

        guard fm.fileExists(atPath: TokenMeterPaths.copilotHome.path) else {
            return .notInstalled(detail: "\(TokenMeterPaths.copilotHome.path) not found")
        }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sessionStateRoot.path, isDirectory: &isDir), isDir.boolValue else {
            return .noData(detail: "No Copilot CLI sessions in \(sessionStateRoot.path)")
        }
        guard fm.isReadableFile(atPath: sessionStateRoot.path) else {
            return .permissionDenied(path: sessionStateRoot.path)
        }
        guard !TokenMeterPaths.copilotEventFiles(limit: 1).isEmpty else {
            return .noData(detail: "No Copilot CLI session logs yet")
        }
        return .available(detail: "Copilot CLI session logs — token counts only", hasQuota: false)
    }

    public func fetchCurrentUsage(forceRefresh: Bool = false) async throws -> UsageSnapshot {
        switch await checkAvailability() {
        case .notInstalled(let d): throw UsageProviderError.sourceNotFound(d)
        case .notLoggedIn(let d): throw UsageProviderError.sourceNotFound(d)
        case .permissionDenied(let p): throw UsageProviderError.permissionDenied(p)
        case .noData: throw UsageProviderError.noDataYet
        case .available: break
        }

        // Newest first for freshness; older files without a cursor were never
        // imported, so add them once for a historical backfill.
        let allFiles = TokenMeterPaths.copilotEventFiles()
        let recentFiles = Array(allFiles.prefix(maxFilesPerRefresh))
        let historicalBackfill = allFiles.dropFirst(recentFiles.count).filter {
            store.cursor(forPath: $0.path) == 0
        }
        let files = recentFiles + historicalBackfill

        for file in files.reversed() {   // oldest -> newest
            if Task.isCancelled { break }

            let path = file.path
            let sessionID = Self.sessionID(from: file)
            let offset = store.cursor(forPath: path)

            let read: IncrementalReadResult
            do {
                read = try JSONLReader.readNewLines(at: path, from: offset)
            } catch {
                continue
            }
            guard !read.lines.isEmpty else { continue }

            let previous = read.didReset ? [:] : storedTotalsByModel(sessionID: sessionID)
            let result = parser.parse(
                lines: read.lines,
                sessionID: sessionID,
                previousTotalsByModel: previous
            )

            if !result.events.isEmpty {
                try store.insert(events: result.events)
            }
            for (model, totals) in result.totalsByModel {
                try store.setSessionTotals(sessionID: "\(sessionID)|\(model)", provider: .copilotCli, totals: totals)
            }
            try store.setCursor(path: path, offset: read.newOffset)

            if let m = result.latestModel { lastModel = m }
        }

        let aggregator = UsageAggregator()
        let weekEvents = try store.events(provider: .copilotCli, since: aggregator.day(offsetFromToday: 6))
        let startOfToday = aggregator.startOfDay(Date())
        let todayEvents = weekEvents.filter { $0.timestamp >= startOfToday }
        let today = aggregator.todayTotals(todayEvents, provider: .copilotCli)

        if lastModel == nil {
            lastModel = store.latestModel(provider: .copilotCli)
        }

        return UsageSnapshot(
            provider: .copilotCli,
            timestamp: Date(),
            modelName: lastModel,
            inputTokens: today?.inputTokens,
            cachedInputTokens: today?.cachedInputTokens,
            cacheCreationTokens: today?.cacheCreationTokens,
            outputTokens: today?.outputTokens,
            reasoningTokens: nil,           // Copilot does not report reasoning tokens
            totalTokens: today?.totalTokens,
            source: .localLog
        )
    }

    /// Recovers the per-model cumulative counters stored for this session so a
    /// resumed transcript keeps producing correct deltas after a restart.
    private func storedTotalsByModel(sessionID: String) -> [String: CodexCumulativeTotals] {
        var out: [String: CodexCumulativeTotals] = [:]
        for model in store.sessionModels(provider: .copilotCli, sessionPrefix: "\(sessionID)|") {
            if let totals = store.sessionTotals(sessionID: "\(sessionID)|\(model)") {
                out[model] = totals
            }
        }
        return out
    }

    public func startMonitoring(onUpdate: @escaping @Sendable (UsageSnapshot) -> Void) async throws {
        guard watcher == nil else { return }
        let w = DirectoryWatcher(paths: [sessionStateRoot.path], debounce: 3.0) { [weak self] in
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
