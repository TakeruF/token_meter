import Foundation
import Observation
import AppKit
import WidgetKit
import TokenMeterCore

/// What the UI needs to know about one provider at one moment.
struct ProviderState: Identifiable {
    let id: UsageProviderID
    var availability: ProviderAvailability
    var snapshot: UsageSnapshot?
    var lastSuccessfulUpdate: Date?
    var lastError: String?
    /// Token totals for the last 7 days, oldest first.
    var weekSeries: [DailyUsage] = []

    var freshness: DataFreshness? {
        guard let lastSuccessfulUpdate else { return nil }
        return DataFreshness.evaluate(age: Date().timeIntervalSince(lastSuccessfulUpdate))
    }

    var displayName: String { id.displayName }
}

struct MenuBarProviderValue: Identifiable {
    let providerID: UsageProviderID
    let value: String
    let compactValue: String

    var id: UsageProviderID { providerID }
}

/// Owns the providers, the refresh schedule, the database and the widget snapshot.
///
/// Refresh paths, all funnelled through one serialized `refresh()`:
/// launch · manual · log change (FSEvents) · interval timer · wake from sleep · day change.
@Observable
@MainActor
final class UsageMonitor {
    /// One instance for the whole app: the delegate starts it, the views observe it.
    static let shared = UsageMonitor()

    private(set) var states: [UsageProviderID: ProviderState] = [:]
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    /// Set when the app cannot store history at all; the UI shows this instead of numbers.
    private(set) var fatalError: String?

    private var store: UsageStore?
    private var providers: [UsageProviderID: any UsageProvider] = [:]
    private var claudeProvider: ClaudeCodeUsageProvider?
    private let snapshotStore = SharedSnapshotStore(appGroupID: TokenMeterPaths.appGroupID)
    private let aggregator = UsageAggregator()
    private let notifications = NotificationManager()
    private let settings = AppSettings.shared

    private var refreshTimer: Timer?
    private var dayChangeObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    /// Guards against overlapping refreshes (a burst of file events plus a timer tick).
    private var refreshTask: Task<Void, Never>?
    /// Snapshot writes are small but asynchronous. Chaining them prevents an older
    /// write from finishing after a newer one and restoring a stale widget value.
    private var snapshotWriteTask: Task<Void, Never>?
    /// When the last WidgetKit reload actually fired, and any reload deferred to the
    /// tail of the current window. Used to rate-limit reloads (see `reloadWidgets`).
    private var lastWidgetReload: Date?
    private var pendingWidgetReload: Task<Void, Never>?
    /// The shortest gap between WidgetKit reloads. Snapshots are still written every
    /// time; only the reload is throttled. The first scan lands each provider
    /// separately and the refresh loop publishes per provider, so an unthrottled
    /// reload fired several times a second during launch. WidgetKit budgets reloads,
    /// and once that budget is spent a later reload — the one after the user resizes a
    /// widget — is dropped, leaving the widget stuck on its empty placeholder.
    private static let minWidgetReloadInterval: TimeInterval = 8

    /// Generous, because the very first scan legitimately reads every existing log
    /// (hundreds of MB here). Later refreshes only read what was appended.
    private static let refreshTimeout: Duration = .seconds(180)

    var usingAppGroup: Bool { snapshotStore.usingAppGroup }
    var snapshotPath: String { snapshotStore.fileURL.path }
    var databasePath: String { store?.path ?? "unavailable" }
    var storedEventCount: Int { store?.eventCount() ?? 0 }

    init() {
        do {
            let store = try UsageStore(path: TokenMeterPaths.databaseURL.path)
            self.store = store
            let claudeProvider = ClaudeCodeUsageProvider(store: store)
            self.claudeProvider = claudeProvider
            self.providers = [
                .claudeCode: claudeProvider,
                .codex: CodexUsageProvider(store: store),
                .copilotCli: CopilotUsageProvider(store: store),
            ]
        } catch {
            fatalError = AppLocalization.format(
                "Could not open the history database: %@",
                error.localizedDescription
            )
        }
    }

    // MARK: - Lifecycle

    func start() async {
        guard store != nil else { return }
        await claudeProvider?.setOAuthUsageEnabled(settings.claudeOAuthUsageEnabled)
        await notifications.requestAuthorizationIfNeeded()
        await detectDataSources()
        await refresh(reason: .launch)
        startWatching()
        scheduleTimer()
        observeSystemEvents()
        pruneHistory()
    }

    func stop() async {
        refreshTimer?.invalidate()
        for provider in providers.values { await provider.stopMonitoring() }
        if let dayChangeObserver { NotificationCenter.default.removeObserver(dayChangeObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    enum RefreshReason: String {
        case launch, manual, logChange, interval, wake, dayChange
    }

    /// Re-runs availability detection for every provider (Settings > "Re-detect").
    func detectDataSources() async {
        await claudeProvider?.setOAuthUsageEnabled(settings.claudeOAuthUsageEnabled)
        for (id, provider) in providers {
            let availability = await provider.checkAvailability()
            var state = states[id] ?? ProviderState(id: id, availability: availability)
            state.availability = availability
            states[id] = state
        }
    }

    // MARK: - Refresh

    /// Serialized: a refresh already in flight is awaited rather than duplicated, so
    /// a burst of file-system events cannot stack up parallel scans of the same logs.
    func refresh(reason: RefreshReason) async {
        if let existing = refreshTask {
            await existing.value
            // A manual tap should still produce a fresh read after the in-flight one.
            guard reason == .manual else { return }
        }

        let task = Task { @MainActor in
            isRefreshing = true
            defer { isRefreshing = false }

            await claudeProvider?.setOAuthUsageEnabled(settings.claudeOAuthUsageEnabled)

            await withTaskGroup(of: (UsageProviderID, Result<UsageSnapshot, Error>).self) { group in
                for (id, provider) in providers where settings.enabledProviders().contains(id) {
                    group.addTask {
                        do {
                            // Reading a large tree should never wedge the app.
                            let snapshot = try await withTimeout(Self.refreshTimeout) {
                                try await provider.fetchCurrentUsage(forceRefresh: reason == .manual)
                            }
                            return (id, .success(snapshot))
                        } catch {
                            return (id, .failure(error))
                        }
                    }
                }
                for await (id, result) in group {
                    await apply(result: result, for: id)
                    // Publish as each provider lands: the first run has to chew
                    // through hundreds of MB of logs, and there is no reason to make
                    // the menu bar and widget wait for the slower provider.
                    publishSnapshot()
                }
            }

            lastRefresh = Date()
            publishSnapshot()
        }

        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func apply(result: Result<UsageSnapshot, Error>, for id: UsageProviderID) async {
        guard let provider = providers[id] else { return }
        let availability = await provider.checkAvailability()
        var state = states[id] ?? ProviderState(id: id, availability: availability)

        switch result {
        case .success(let snapshot):
            let previous = state.snapshot
            state.snapshot = snapshot
            state.lastSuccessfulUpdate = Date()
            state.lastError = snapshot.quotaError?.errorDescription
            state.availability = availability
            state.weekSeries = loadWeekSeries(for: id)
            states[id] = state

            // Plain values only: the settings object is not Sendable.
            await notifications.evaluate(
                snapshot: snapshot,
                previous: previous,
                thresholds: settings.enabledThresholds(),
                notifyOnReset: settings.notifyOnReset
            )

        case .failure(let error):
            state.availability = availability
            state.lastError = (error as? UsageProviderError)?.errorDescription ?? error.localizedDescription
            // The previous snapshot is deliberately kept, but `lastSuccessfulUpdate`
            // is not advanced — the UI shows it as ageing, not as current.
            states[id] = state

            if settings.notifyOnError, case .available = state.availability {
                await notifications.notifyError(provider: id, message: state.lastError ?? "Unknown error")
            }
        }
    }

    private func loadWeekSeries(for id: UsageProviderID) -> [DailyUsage] {
        guard let store else { return [] }
        let since = aggregator.day(offsetFromToday: 6)
        let events = (try? store.events(provider: id, since: since)) ?? []
        return aggregator.dailySeries(events, provider: id, days: 7)
    }

    func events(provider: UsageProviderID, days: Int) -> [UsageEvent] {
        guard let store else { return [] }
        let since = aggregator.day(offsetFromToday: days - 1)
        return (try? store.events(provider: provider, since: since)) ?? []
    }

    // MARK: - Widget snapshot

    /// Writes the App Group JSON and nudges WidgetKit. Only values we actually have
    /// are written; a provider with no quota gets nulls, not zeros.
    func publishSnapshot() {
        var snapshot = SharedSnapshot(
            updatedAt: Date(),
            languageCode: settings.appLanguage.rawValue,
            tokenNotation: settings.effectiveTokenNotation,
            widgetBackgroundStyle: settings.widgetBackgroundStyle
        )

        for id in UsageProviderID.allCases {
            guard settings.enabledProviders().contains(id), let state = states[id] else { continue }

            let window = state.snapshot?.primaryWindow
            let weekTotal = state.weekSeries.reduce(0) { $0 + $1.totalTokens }
            let weekWorking = state.weekSeries.reduce(0) { $0 + $1.workingTokens }

            let provider = SharedSnapshot.Provider(
                displayName: id.displayName,
                remainingRatio: window?.remainingRatio,
                usedRatio: window?.usedRatio,
                resetsAt: settings.widgetShowReset ? window?.resetsAt : nil,
                todayWorkingTokens: settings.widgetShowTokens ? state.snapshot?.workingTokens : nil,
                todayTotalTokens: settings.widgetShowTokens ? state.snapshot?.totalTokens : nil,
                last7DaysWorkingTokens: settings.widgetShowTokens ? weekWorking : nil,
                last7DaysTotalTokens: settings.widgetShowTokens ? weekTotal : nil,
                modelName: state.snapshot?.modelName,
                lastUpdated: state.lastSuccessfulUpdate,
                statusHeadline: state.availability.isAvailable || state.snapshot?.hasQuotaInformation == true
                    ? nil
                    : AppLocalization.string(state.availability.headline),
                hasQuotaInformation: state.snapshot?.hasQuotaInformation ?? false,
                dailyTotals: state.weekSeries.map { .init(day: $0.day, workingTokens: $0.workingTokens) },
                fiveHourWindow: settings.showFiveHourWindow ? state.snapshot?.shortWindowUsage : nil,
                weeklyWindow: settings.showWeeklyWindow ? state.snapshot?.weeklyWindowUsage : nil,
                fiveHourQuota: state.snapshot?.shortWindow,
                weeklyQuota: state.snapshot?.weeklyWindow,
                sonnetWeeklyQuota: state.snapshot?.sonnetWeeklyWindow,
                quotaUpdatedAt: state.snapshot?.quotaUpdatedAt,
                quotaIsCached: state.snapshot?.quotaIsCached,
                quotaErrorMessage: state.snapshot?.quotaError?.errorDescription
            )

            switch id {
            case .claudeCode: snapshot.claudeCode = provider
            case .codex: snapshot.codex = provider
            case .copilotCli: snapshot.copilotCli = provider
            }
        }

        // Off the main actor: this is disk I/O, and the UI must never wait on it.
        // Awaiting the previous write preserves the same order in which snapshots
        // were produced on the main actor.
        let store = snapshotStore
        let previousWrite = snapshotWriteTask
        snapshotWriteTask = Task.detached(priority: .utility) {
            await previousWrite?.value
            do {
                try store.write(snapshot)
                await MainActor.run { self.reloadWidgets() }
            } catch {
                NSLog("TokenMeter: could not write widget snapshot: \(error.localizedDescription)")
            }
        }
    }

    /// Asks WidgetKit to reload, but no more than once per `minWidgetReloadInterval`.
    /// A reload inside the window is coalesced into a single trailing reload so the
    /// final state is always picked up, while a burst of writes costs one reload.
    private func reloadWidgets() {
        pendingWidgetReload?.cancel()
        let now = Date()
        if let last = lastWidgetReload, now.timeIntervalSince(last) < Self.minWidgetReloadInterval {
            let delay = Self.minWidgetReloadInterval - now.timeIntervalSince(last)
            pendingWidgetReload = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.lastWidgetReload = Date()
                WidgetCenter.shared.reloadTimelines(ofKind: "TokenMeterWidget")
            }
        } else {
            lastWidgetReload = now
            WidgetCenter.shared.reloadTimelines(ofKind: "TokenMeterWidget")
        }
    }

    // MARK: - Triggers

    private func startWatching() {
        for (_, provider) in providers {
            Task {
                try? await provider.startMonitoring { [weak self] _ in
                    Task { @MainActor in
                        await self?.refresh(reason: .logChange)
                    }
                }
            }
        }
    }

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        let interval = max(60, settings.refreshInterval)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh(reason: .interval) }
        }
    }

    func refreshIntervalChanged() {
        scheduleTimer()
    }

    private func observeSystemEvents() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh(reason: .wake) }
        }

        // Recomputes "today" at local midnight so the day totals roll over.
        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh(reason: .dayChange)
                self?.pruneHistory()
            }
        }
    }

    private func pruneHistory() {
        guard let store else { return }
        Task.detached(priority: .background) { [days = settings.retentionDays] in
            _ = try? store.pruneEvents(olderThan: days)
        }
    }

    func deleteAllHistory() {
        guard let store else { return }
        try? store.deleteAllData()
        for id in states.keys {
            states[id]?.snapshot = nil
            states[id]?.weekSeries = []
            states[id]?.lastSuccessfulUpdate = nil
        }
        Task { await refresh(reason: .manual) }
    }

    // MARK: - Menu bar title

    /// Values are kept separate from provider names so Compact mode can use the
    /// real brand marks instead of textual C / X abbreviations.
    var menuBarProviderValues: [MenuBarProviderValue] {
        let visible = UsageProviderID.allCases.filter { settings.enabledProviders().contains($0) }
        return visible.compactMap { id in
            guard let state = states[id] else { return nil }

            guard state.availability.isAvailable else {
                return MenuBarProviderValue(providerID: id, value: "—", compactValue: "—")
            }

            if settings.menuBarShowPercentage,
               let remaining = menuBarWindow(for: state.snapshot)?.remainingRatio {
                let percentage = "\(Int((remaining * 100).rounded()))%"
                return MenuBarProviderValue(
                    providerID: id,
                    value: AppLocalization.format("%@ left", percentage),
                    compactValue: percentage
                )
            }
            // No quota published (or percentages switched off): show today's work.
            // The total belongs to the popover, where there is room to caption it;
            // alone in the menu bar it would just read as a wildly larger "Today".
            if settings.menuBarShowTokens, let tokens = state.snapshot?.workingTokens, tokens > 0 {
                let tokenValue = tokens.displayTokens
                return MenuBarProviderValue(providerID: id, value: tokenValue, compactValue: tokenValue)
            }
            return MenuBarProviderValue(providerID: id, value: "—", compactValue: "—")
        }
    }

    var menuBarResetTitle: String? {
        settings.menuBarShowReset ? nextResetCountdown() : nil
    }

    /// A text-only equivalent used by Full mode and VoiceOver. A provider with no
    /// quota shows its token count instead of a fabricated percentage.
    var menuBarTitle: String {
        guard settings.menuBarStyle != .iconOnly else { return "" }

        let parts = menuBarProviderValues.map { item in
            "\(item.providerID.compactName) \(item.value)"
        }

        var title = parts.joined(separator: " · ")
        if let countdown = menuBarResetTitle {
            title += title.isEmpty ? countdown : " · \(countdown)"
        }
        return title
    }

    /// "↻1h20m" for the soonest selected-limit reset across the visible providers.
    /// Menu bar width is scarce, so this is the countdown only.
    private func nextResetCountdown(now: Date = Date()) -> String? {
        let resets = UsageProviderID.allCases
            .filter { settings.enabledProviders().contains($0) }
            .compactMap {
                guard let snapshot = states[$0]?.snapshot else { return nil }
                return menuBarWindow(for: snapshot)?.resetsAt
            }
            .filter { $0 > now }

        guard let soonest = resets.min() else { return nil }
        let interval = Int(soonest.timeIntervalSince(now))
        let hours = interval / 3600
        let minutes = (interval % 3600) / 60
        return hours > 0 ? "↻\(hours)h\(minutes)m" : "↻\(minutes)m"
    }

    /// The preferred window wins when present. A provider that temporarily omits
    /// it falls back to the other reported quota instead of showing a false 100% or
    /// dropping to token counts. This currently covers Codex's missing 5-hour limit.
    private func menuBarWindow(for snapshot: UsageSnapshot?) -> UsageWindow? {
        guard let snapshot else { return nil }
        switch settings.menuBarLimitWindow {
        case .fiveHour:
            return snapshot.shortWindow ?? snapshot.weeklyWindow
        case .weekly:
            return snapshot.weeklyWindow ?? snapshot.shortWindow
        }
    }
}

/// Runs `operation`, throwing if it outruns `timeout`. Used so a slow filesystem
/// cannot leave a refresh (and the UI's spinner) hanging forever.
func withTimeout<T: Sendable>(
    _ timeout: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw UsageProviderError.commandTimedOut("timed out after \(timeout)")
        }
        guard let result = try await group.next() else {
            throw UsageProviderError.commandTimedOut("no result")
        }
        group.cancelAll()
        return result
    }
}
