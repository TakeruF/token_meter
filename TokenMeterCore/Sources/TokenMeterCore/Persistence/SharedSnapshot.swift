import Foundation

/// The payload the widget reads. It contains only what we actually have: every
/// field is optional, and the widget renders "—" rather than 0 for a missing one.
public struct SharedSnapshot: Codable, Sendable, Equatable {
    public struct Provider: Codable, Sendable, Equatable {
        public var displayName: String
        /// nil when no provider-reported quota is available.
        public var remainingRatio: Double?
        public var usedRatio: Double?
        public var resetsAt: Date?
        /// Today's real work, and the cache-inclusive total it ran against. Spelled
        /// out rather than left as a bare `todayTokens`, which said nothing about
        /// which of the two it held — and so got filled with the total here while the
        /// dashboard showed the work, leaving one "Today" with two values.
        public var todayWorkingTokens: Int?
        public var todayTotalTokens: Int?
        public var last7DaysWorkingTokens: Int?
        public var last7DaysTotalTokens: Int?
        public var modelName: String?
        public var lastUpdated: Date?
        /// Human-readable state when there is nothing to show ("Not installed", …).
        public var statusHeadline: String?
        public var hasQuotaInformation: Bool
        /// Real work per day over the last 7 days, oldest first, for the Large widget
        /// chart — the same series the dashboard plots, so both draw one shape.
        public var dailyTotals: [DayPoint]?

        /// Tokens counted in the 5-hour window and the weekly window, with their reset
        /// times. Available for both providers (unlike the ratios above), because these
        /// are measurements rather than a published quota. nil when the user has
        /// switched the window off in Settings.
        public var fiveHourWindow: TokenWindowUsage?
        public var weeklyWindow: TokenWindowUsage?
        /// Provider-reported quota windows. Kept separate from locally counted token
        /// windows so the widget never mixes a percentage with a token measurement.
        public var fiveHourQuota: UsageWindow?
        public var weeklyQuota: UsageWindow?
        public var sonnetWeeklyQuota: UsageWindow?
        public var quotaUpdatedAt: Date?
        public var quotaIsCached: Bool?
        public var quotaErrorMessage: String?

        public init(
            displayName: String,
            remainingRatio: Double? = nil,
            usedRatio: Double? = nil,
            resetsAt: Date? = nil,
            todayWorkingTokens: Int? = nil,
            todayTotalTokens: Int? = nil,
            last7DaysWorkingTokens: Int? = nil,
            last7DaysTotalTokens: Int? = nil,
            modelName: String? = nil,
            lastUpdated: Date? = nil,
            statusHeadline: String? = nil,
            hasQuotaInformation: Bool = false,
            dailyTotals: [DayPoint]? = nil,
            fiveHourWindow: TokenWindowUsage? = nil,
            weeklyWindow: TokenWindowUsage? = nil,
            fiveHourQuota: UsageWindow? = nil,
            weeklyQuota: UsageWindow? = nil,
            sonnetWeeklyQuota: UsageWindow? = nil,
            quotaUpdatedAt: Date? = nil,
            quotaIsCached: Bool? = nil,
            quotaErrorMessage: String? = nil
        ) {
            self.displayName = displayName
            self.remainingRatio = remainingRatio
            self.usedRatio = usedRatio
            self.resetsAt = resetsAt
            self.todayWorkingTokens = todayWorkingTokens
            self.todayTotalTokens = todayTotalTokens
            self.last7DaysWorkingTokens = last7DaysWorkingTokens
            self.last7DaysTotalTokens = last7DaysTotalTokens
            self.modelName = modelName
            self.lastUpdated = lastUpdated
            self.statusHeadline = statusHeadline
            self.hasQuotaInformation = hasQuotaInformation
            self.dailyTotals = dailyTotals
            self.fiveHourWindow = fiveHourWindow
            self.weeklyWindow = weeklyWindow
            self.fiveHourQuota = fiveHourQuota
            self.weeklyQuota = weeklyQuota
            self.sonnetWeeklyQuota = sonnetWeeklyQuota
            self.quotaUpdatedAt = quotaUpdatedAt
            self.quotaIsCached = quotaIsCached
            self.quotaErrorMessage = quotaErrorMessage
        }
    }

    public struct DayPoint: Codable, Sendable, Equatable, Identifiable {
        public var day: Date
        /// Real work that day — see `UsageEvent.workingTokens`.
        public var workingTokens: Int
        public var id: Date { day }

        public init(day: Date, workingTokens: Int) {
            self.day = day
            self.workingTokens = workingTokens
        }

        private enum CodingKeys: String, CodingKey {
            case day, workingTokens
            /// What this field was called while it still carried cache-inflated totals.
            case totalTokens
        }

        /// Unlike the optional fields around it, a missing count here would throw and
        /// take the whole snapshot — and with it the widget — down. So an older
        /// payload's `totalTokens` is read rather than rejected; the next refresh
        /// replaces it with the work figure.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            day = try container.decode(Date.self, forKey: .day)
            workingTokens = try container.decodeIfPresent(Int.self, forKey: .workingTokens)
                ?? container.decode(Int.self, forKey: .totalTokens)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(day, forKey: .day)
            try container.encode(workingTokens, forKey: .workingTokens)
        }
    }

    public var updatedAt: Date
    /// The language selected in the main app. Optional for compatibility with
    /// snapshots written by older releases.
    public var languageCode: String?
    /// The token notation selected in the main app. Optional for compatibility with
    /// snapshots written by older releases, which predate the choice.
    public var tokenNotation: TokenNotation?
    public var claudeCode: Provider?
    public var codex: Provider?
    /// Optional for compatibility with snapshots written by older releases.
    public var copilotCli: Provider?

    public init(
        updatedAt: Date,
        languageCode: String? = nil,
        tokenNotation: TokenNotation? = nil,
        claudeCode: Provider? = nil,
        codex: Provider? = nil,
        copilotCli: Provider? = nil
    ) {
        self.updatedAt = updatedAt
        self.languageCode = languageCode
        self.tokenNotation = tokenNotation
        self.claudeCode = claudeCode
        self.codex = codex
        self.copilotCli = copilotCli
    }

    /// Formats a token count exactly as the main app would. Falls back to the metric
    /// scale for a snapshot written before the notation existed — the notation those
    /// releases always used.
    public func tokens(_ count: Int) -> String {
        count.abbreviatedTokens(
            tokenNotation ?? .metric,
            locale: Locale(identifier: languageCode ?? "en")
        )
    }

    public func provider(_ id: UsageProviderID) -> Provider? {
        switch id {
        case .claudeCode: return claudeCode
        case .codex: return codex
        case .copilotCli: return copilotCli
        }
    }

    /// True when at least one provider carries data worth showing. A snapshot
    /// without this renders as the widget's empty state, so we neither cache it
    /// nor let it replace a good one on screen.
    public var hasData: Bool { claudeCode != nil || codex != nil || copilotCli != nil }
}

/// Reads and writes the snapshot JSON in the App Group container.
///
/// Writes go to a temp file in the same directory and are then moved into place,
/// so the widget can never observe a half-written file.
public struct SharedSnapshotStore: Sendable {
    public static let fileName = "snapshot.json"

    public let containerURL: URL
    /// True when we are using the real App Group container rather than the fallback.
    public let usingAppGroup: Bool

    public static let cacheFileName = "snapshot.cache.json"

    public var fileURL: URL { containerURL.appendingPathComponent(Self.fileName) }

    /// The last snapshot that actually had data. The widget falls back to this
    /// when the primary is transiently empty or unreadable.
    public var cacheFileURL: URL { containerURL.appendingPathComponent(Self.cacheFileName) }

    public init(appGroupID: String) {
        // The widget only reads this directory. `isWritableFile(atPath:)` can return
        // false for an extension even when its App Group entitlement grants access,
        // which incorrectly sent the widget to its private, empty fallback directory.
        // A properly entitled build gets a provisioned, existing container; using
        // that is sufficient, and actual read/write errors are handled by the caller.
        let fm = FileManager.default
        if let url = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID),
           fm.fileExists(atPath: url.path) {
            self.containerURL = url
            self.usingAppGroup = true
        } else {
            // Fall back to a local directory so an unsigned dev build still works.
            // The widget cannot read this; Diagnostics says so in as many words.
            self.containerURL = fm
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TokenMeter", isDirectory: true)
            self.usingAppGroup = false
        }
    }

    public init(containerURL: URL, usingAppGroup: Bool = false) {
        self.containerURL = containerURL
        self.usingAppGroup = usingAppGroup
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func write(_ snapshot: SharedSnapshot) throws {
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        let data = try Self.encoder().encode(snapshot)
        // Foundation creates and renames a sibling temporary file. This is atomic and
        // also works when snapshot.json does not exist yet (the first app launch).
        try data.write(to: fileURL, options: .atomic)
        // Preserve the last snapshot with real data. The app can write an empty
        // snapshot mid-launch (before the first parse, or while providers are
        // still resolving); without this cache the widget would blank out until
        // the next good write. An empty write never overwrites the cache.
        if snapshot.hasData {
            try? data.write(to: cacheFileURL, options: .atomic)
        }
    }

    public func read() throws -> SharedSnapshot {
        let data = try Data(contentsOf: fileURL)
        return try Self.decoder().decode(SharedSnapshot.self, from: data)
    }

    /// Returns nil rather than throwing when there is simply nothing yet — the
    /// widget needs to tell "no data" apart from "broken".
    public func readIfPresent() -> SharedSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try read()
        } catch {
            NSLog("TokenMeter: could not read widget snapshot at %@: %@", fileURL.path, error.localizedDescription)
            return nil
        }
    }

    /// The freshest usable snapshot for the widget: the primary when it has data,
    /// otherwise the last cached snapshot that did. This keeps the widget from
    /// dropping to its empty state on a transient empty or unreadable primary.
    /// Returns the (possibly empty) primary when there is nothing cached, so a
    /// genuine first run still shows "no data".
    public func readResilient() -> SharedSnapshot? {
        let primary = readIfPresent()
        if let primary, primary.hasData { return primary }

        if FileManager.default.fileExists(atPath: cacheFileURL.path),
           let data = try? Data(contentsOf: cacheFileURL),
           let cached = try? Self.decoder().decode(SharedSnapshot.self, from: data) {
            return cached
        }
        return primary
    }
}
