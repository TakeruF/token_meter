import Foundation

/// Claude Code, read from `~/.claude/projects/*/*.jsonl`.
///
/// Local transcripts provide token counts. When the user explicitly enables the
/// integration, the Claude Code Keychain credential is used to fetch Pro/Max quota
/// windows from Anthropic; credentials are never persisted by Token Meter.
public actor ClaudeCodeUsageProvider: UsageProvider {
    public nonisolated let id: UsageProviderID = .claudeCode
    public nonisolated let displayName = "Claude"

    private let projectsRoot: URL
    private let store: UsageStore
    private let parser = ClaudeCodeLogParser()
    private let quotaService: any ClaudeUsageServicing
    private var watcher: DirectoryWatcher?
    private var oauthUsageEnabled = false
    private var lastQuotaError: ClaudeUsageError?

    /// Bounds a refresh: only the most recently touched sessions are considered,
    /// since older files cannot have changed since the last cursor.
    private let maxFilesPerRefresh: Int

    public init(
        projectsRoot: URL = TokenMeterPaths.claudeProjects,
        store: UsageStore,
        maxFilesPerRefresh: Int = 40,
        quotaService: any ClaudeUsageServicing = ClaudeUsageService()
    ) {
        self.projectsRoot = projectsRoot
        self.store = store
        self.maxFilesPerRefresh = maxFilesPerRefresh
        self.quotaService = quotaService
    }

    public func setOAuthUsageEnabled(_ enabled: Bool) {
        oauthUsageEnabled = enabled
        if !enabled { lastQuotaError = nil }
    }

    public func checkAvailability() async -> ProviderAvailability {
        let fm = FileManager.default
        var isDir: ObjCBool = false

        // OAuth usage is independent of transcript history. Its precise credential
        // state is reported by `quotaError` after a refresh without exposing secrets.
        if oauthUsageEnabled {
            switch lastQuotaError {
            case .credentialsNotFound, .invalidCredentials, .unauthorized, .forbidden:
                return .notLoggedIn(detail: "Sign in again with Claude Code to load plan usage")
            case .keychainAccessDenied:
                return .permissionDenied(path: "macOS Keychain item \(KeychainClaudeCredentialProvider.service)")
            default:
                break
            }
            return .available(detail: "Claude usage via OAuth; local logs add token history when available", hasQuota: true)
        }

        guard fm.fileExists(atPath: projectsRoot.path, isDirectory: &isDir), isDir.boolValue else {
            // Judge the configured root on its own terms, not the real ~/.claude:
            // if its parent (the Claude home) is missing too, Claude Code has never
            // run here; if the home exists but has no projects dir, it just has no
            // sessions yet.
            let claudeHome = projectsRoot.deletingLastPathComponent().path
            if fm.fileExists(atPath: claudeHome) {
                return .noData(detail: "No session logs in \(projectsRoot.path)")
            }
            return .notInstalled(detail: "\(claudeHome) not found")
        }

        guard fm.isReadableFile(atPath: projectsRoot.path) else {
            return .permissionDenied(path: projectsRoot.path)
        }

        let files = TokenMeterPaths.jsonlFiles(under: projectsRoot, limit: 1)
        guard !files.isEmpty else {
            return .noData(detail: "No .jsonl transcripts yet")
        }
        return .available(
            detail: "Session logs — token counts only, no quota published locally",
            hasQuota: false
        )
    }

    /// Parses everything appended since the last run, persists it, and reports the
    /// current state. OAuth quota failures do not discard previously parsed local
    /// usage, and the quota service itself keeps the last successful response.
    public func fetchCurrentUsage(forceRefresh: Bool = false) async throws -> UsageSnapshot {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        let hasReadableLogs = fm.fileExists(atPath: projectsRoot.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && fm.isReadableFile(atPath: projectsRoot.path)
            && !TokenMeterPaths.jsonlFiles(under: projectsRoot, limit: 1).isEmpty

        if !hasReadableLogs && !oauthUsageEnabled {
            let availability = await checkAvailability()
            switch availability {
            case .notInstalled(let detail): throw UsageProviderError.sourceNotFound(detail)
            case .permissionDenied(let path): throw UsageProviderError.permissionDenied(path)
            case .noData: throw UsageProviderError.noDataYet
            case .notLoggedIn(let detail): throw UsageProviderError.sourceNotFound(detail)
            case .available: break
            }
        }

        let files = hasReadableLogs
            ? TokenMeterPaths.jsonlFiles(under: projectsRoot, limit: maxFilesPerRefresh)
            : []

        var latestModel: String?
        var latestContext: Int?
        var latestTimestamp: Date?
        var malformed = 0
        var candidates = 0

        for file in files {
            // Cooperative cancellation, checked between files so a timeout can
            // actually stop the work. It is safe here and only here: a file's cursor
            // is advanced only after that file is fully parsed and stored, so
            // stopping between files loses nothing — the next refresh resumes.
            if Task.isCancelled { break }

            let path = file.path
            let offset = store.cursor(forPath: path)
            let read: IncrementalReadResult
            do {
                read = try JSONLReader.readNewLines(at: path, from: offset)
            } catch {
                continue  // a session file can vanish mid-scan; that is not fatal
            }
            guard !read.lines.isEmpty else { continue }

            let result = parser.parse(lines: read.lines)
            malformed += result.malformedLineCount
            candidates += result.candidateLineCount

            if !result.events.isEmpty {
                try store.insert(events: result.events)
            }
            try store.setCursor(path: path, offset: read.newOffset)

            if let ts = result.latestTimestamp, latestTimestamp == nil || ts > latestTimestamp! {
                latestTimestamp = ts
                latestModel = result.latestModel
                latestContext = result.latestContextTokens
            }
        }

        // If nothing was appended this pass, describe the newest event we have
        // rather than pretending there was no usage.
        let aggregator = UsageAggregator()
        // One read covering the widest window we report on; the narrower ones are
        // sliced out of it rather than re-queried.
        let weekEvents = try store.events(provider: .claudeCode, since: aggregator.day(offsetFromToday: 6))
        let startOfToday = aggregator.startOfDay(Date())
        let todayEvents = weekEvents.filter { $0.timestamp >= startOfToday }
        let today = aggregator.todayTotals(todayEvents, provider: .claudeCode)

        // Local token counts only. Claude Code publishes no quota in these logs, so the 5-hour boundary
        // is replayed from the documented session rule and marked as inferred, and
        // the weekly figure is a plain 7-day lookback with no reset implied.
        let shortUsage = aggregator.sessionBlock(weekEvents, provider: .claudeCode)
        let weeklyUsage = aggregator.rollingWindowUsage(weekEvents, provider: .claudeCode, days: 7)

        // A pass that appended nothing still has to report the current model, so fall
        // back to the newest event we already stored rather than showing nothing.
        if latestModel == nil {
            latestModel = todayEvents.last?.model ?? store.latestModel(provider: .claudeCode)
        }

        // Every line that looked like a usage record failed to decode: the format moved.
        if candidates > 20 && malformed == candidates {
            throw UsageProviderError.logFormatChanged("Claude Code transcript: \(malformed) unparseable usage lines")
        }

        let quota = oauthUsageEnabled
            ? await quotaService.usage(forceRefresh: forceRefresh)
            : ClaudeUsageFetchResult(usage: nil, fetchedAt: nil, isCached: false, error: nil)
        lastQuotaError = quota.error

        return UsageSnapshot(
            provider: .claudeCode,
            timestamp: Date(),
            modelName: latestModel,
            inputTokens: today?.inputTokens,
            cachedInputTokens: today?.cachedInputTokens,
            cacheCreationTokens: today?.cacheCreationTokens,
            outputTokens: today?.outputTokens,
            reasoningTokens: nil,          // not reported by Claude Code
            totalTokens: today?.totalTokens,
            currentContextTokens: latestContext,
            contextWindowTokens: nil,      // not published locally
            shortWindow: quota.usage?.fiveHour?.asUsageWindow(windowMinutes: 5 * 60),
            weeklyWindow: quota.usage?.sevenDay?.asUsageWindow(windowMinutes: 7 * 24 * 60),
            sonnetWeeklyWindow: quota.usage?.sevenDaySonnet?.asUsageWindow(windowMinutes: 7 * 24 * 60),
            quotaUpdatedAt: quota.fetchedAt,
            quotaIsCached: quota.isCached,
            quotaError: quota.error,
            quotaIntegrationEnabled: oauthUsageEnabled,
            shortWindowUsage: shortUsage,  // tokens only, boundary inferred
            weeklyWindowUsage: weeklyUsage,// tokens only, rolling 7 days
            planType: nil,
            source: hasReadableLogs ? .localLog : .officialAPI
        )
    }

    public func startMonitoring(onUpdate: @escaping @Sendable (UsageSnapshot) -> Void) async throws {
        guard watcher == nil else { return }
        let w = DirectoryWatcher(paths: [projectsRoot.path], debounce: 3.0) { [weak self] in
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
