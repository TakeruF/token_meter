import Foundation

/// The distinct states the UI must be able to tell apart (see README > Troubleshooting).
public enum ProviderAvailability: Sendable, Equatable {
    /// Logs found and readable. `hasQuota` records whether this provider can ever
    /// report a usage percentage, so the UI can say "no quota info" rather than 0%.
    case available(detail: String, hasQuota: Bool)
    /// The tool itself was never found on this machine.
    case notInstalled(detail: String)
    /// The tool is installed but has no credentials, so it has produced no usage.
    case notLoggedIn(detail: String)
    /// Tool present, but the directory we read has no data yet.
    case noData(detail: String)
    /// The path exists but the sandbox/permissions block reading it.
    case permissionDenied(path: String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    public var detail: String {
        switch self {
        case .available(let d, _): return d
        case .notInstalled(let d): return d
        case .notLoggedIn(let d): return d
        case .noData(let d): return d
        case .permissionDenied(let path): return "Permission denied: \(path)"
        }
    }

    public var headline: String {
        switch self {
        case .available: return "Connected"
        case .notInstalled: return "Not installed"
        case .notLoggedIn: return "Not signed in"
        case .noData: return "No data yet"
        case .permissionDenied: return "Permission denied"
        }
    }

    /// SF Symbol used alongside colour, so state is never conveyed by colour alone.
    public var symbolName: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .notInstalled: return "questionmark.circle"
        case .notLoggedIn: return "person.crop.circle.badge.exclamationmark"
        case .noData: return "tray"
        case .permissionDenied: return "lock.circle"
        }
    }
}

public enum UsageProviderError: Error, LocalizedError, Sendable, Equatable {
    case sourceNotFound(String)
    case permissionDenied(String)
    case commandTimedOut(String)
    case decodingFailed(String)
    case logFormatChanged(String)
    case noDataYet

    public var errorDescription: String? {
        switch self {
        case .sourceNotFound(let s): return "Data source not found: \(s)"
        case .permissionDenied(let s): return "Permission denied: \(s)"
        case .commandTimedOut(let s): return "Command timed out: \(s)"
        case .decodingFailed(let s): return "Could not parse data: \(s)"
        case .logFormatChanged(let s): return "Log format looks unfamiliar: \(s)"
        case .noDataYet: return "No usage data recorded yet"
        }
    }
}

/// Freshness of a snapshot. Stale data must never be presented as current.
public enum DataFreshness: Sendable, Equatable {
    case fresh
    case aging(TimeInterval)
    case stale(TimeInterval)

    public static func evaluate(age: TimeInterval, staleAfter: TimeInterval = 3600) -> DataFreshness {
        if age < 300 { return .fresh }
        if age < staleAfter { return .aging(age) }
        return .stale(age)
    }

    public var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}
