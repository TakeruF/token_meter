import Foundation
import Security

// MARK: - API models

public struct ClaudeUsageWindow: Decodable, Sendable, Equatable {
    public let utilization: Double?
    public let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    public init(utilization: Double?, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        utilization = try? container.decodeIfPresent(Double.self, forKey: .utilization)

        if let raw = try? container.decodeIfPresent(String.self, forKey: .resetsAt) {
            resetsAt = Self.parseISO8601(raw)
        } else {
            resetsAt = nil
        }
    }

    public func asUsageWindow(windowMinutes: Int) -> UsageWindow? {
        guard utilization != nil || resetsAt != nil else { return nil }
        guard let utilization else {
            return UsageWindow(usedRatio: nil, remainingRatio: nil, resetsAt: resetsAt, windowMinutes: windowMinutes)
        }
        let used = min(1, max(0, utilization / 100))
        return UsageWindow(
            usedRatio: used,
            remainingRatio: max(0, min(1, 1 - used)),
            resetsAt: resetsAt,
            windowMinutes: windowMinutes
        )
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let regular = ISO8601DateFormatter()
        regular.formatOptions = [.withInternetDateTime]
        return regular.date(from: value)
    }
}

public struct ClaudeUsageResponse: Decodable, Sendable, Equatable {
    public let fiveHour: ClaudeUsageWindow?
    public let sevenDay: ClaudeUsageWindow?
    public let sevenDaySonnet: ClaudeUsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
    }

    public init(
        fiveHour: ClaudeUsageWindow? = nil,
        sevenDay: ClaudeUsageWindow? = nil,
        sevenDaySonnet: ClaudeUsageWindow? = nil
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDaySonnet = sevenDaySonnet
    }

    public var hasAnyWindow: Bool {
        fiveHour != nil || sevenDay != nil || sevenDaySonnet != nil
    }
}

// MARK: - Credentials

public enum ClaudeCredentialError: Error, LocalizedError, Sendable, Equatable {
    case notFound
    case accessDenied
    case malformedData
    case oauthSectionMissing
    case accessTokenMissing
    case keychainFailure(Int32)

    public var errorDescription: String? {
        switch self {
        case .notFound, .oauthSectionMissing, .accessTokenMissing:
            return "Claude Code credentials were not found. Sign in with Claude Code, then try again."
        case .accessDenied:
            return "Token Meter could not access Claude Code credentials. Check the macOS Keychain permission and try again."
        case .malformedData:
            return "Claude Code credentials use an unfamiliar format. Sign in again, then try once more."
        case .keychainFailure:
            return "The Claude Code credential could not be read from Keychain."
        }
    }
}

/// A Claude Code OAuth access token together with the moment it stops being valid,
/// so callers can tell "expired sign-in" apart from a transient network failure
/// without first spending a request that would only come back 401 (or, worse, be
/// masked by a 429 from retrying an already-dead token).
public struct ClaudeCredential: Sendable, Equatable {
    public let accessToken: String
    /// When the access token expires, if the credential records it. `nil` means the
    /// field was absent and expiry cannot be judged locally.
    public let expiresAt: Date?

    public init(accessToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    /// True only when we positively know the token is past its expiry. An unknown
    /// (`nil`) expiry is never treated as expired.
    public func isExpired(now: Date = Date(), skew: TimeInterval = 30) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.addingTimeInterval(-skew) <= now
    }
}

public protocol ClaudeCredentialProviding: Sendable {
    func accessToken() throws -> String
    /// The token plus its expiry. Defaults to wrapping `accessToken()` with an
    /// unknown expiry, so existing conformances keep working unchanged.
    func credential() throws -> ClaudeCredential
}

public extension ClaudeCredentialProviding {
    func credential() throws -> ClaudeCredential {
        ClaudeCredential(accessToken: try accessToken(), expiresAt: nil)
    }
}

public enum ClaudeCredentialJSONDecoder {
    public static func accessToken(from data: Data) throws -> String {
        try credential(from: data).accessToken
    }

    public static func credential(from data: Data) throws -> ClaudeCredential {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ClaudeCredentialError.malformedData
        }

        guard let oauth = findDictionary(named: "claudeAiOauth", in: object) else {
            throw ClaudeCredentialError.oauthSectionMissing
        }
        guard let token = oauth["accessToken"] as? String,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClaudeCredentialError.accessTokenMissing
        }
        return ClaudeCredential(accessToken: token, expiresAt: expiryDate(from: oauth["expiresAt"]))
    }

    /// Claude Code stores `expiresAt` as epoch milliseconds. Accept a couple of
    /// encodings defensively; an unrecognised value just yields an unknown expiry.
    private static func expiryDate(from value: Any?) -> Date? {
        let millis: Double?
        switch value {
        case let n as Double: millis = n
        case let n as Int: millis = Double(n)
        case let s as String: millis = Double(s)
        default: millis = nil
        }
        guard let millis, millis > 0 else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }

    private static func findDictionary(named key: String, in value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            if let match = dictionary[key] as? [String: Any] { return match }
            for child in dictionary.values {
                if let match = findDictionary(named: key, in: child) { return match }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let match = findDictionary(named: key, in: child) { return match }
            }
        }
        return nil
    }
}

public struct KeychainClaudeCredentialProvider: ClaudeCredentialProviding {
    public static let service = "Claude Code-credentials"

    public init() {}

    public func accessToken() throws -> String {
        try credential().accessToken
    }

    public func credential() throws -> ClaudeCredential {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw ClaudeCredentialError.malformedData }
            return try ClaudeCredentialJSONDecoder.credential(from: data)
        case errSecItemNotFound:
            throw ClaudeCredentialError.notFound
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed, errSecMissingEntitlement:
            throw ClaudeCredentialError.accessDenied
        default:
            throw ClaudeCredentialError.keychainFailure(status)
        }
    }
}

// MARK: - HTTP client

public enum ClaudeUsageError: Error, LocalizedError, Codable, Sendable, Equatable {
    case credentialsNotFound
    case keychainAccessDenied
    case invalidCredentials
    /// The stored access token is past its expiry. Detected locally, before any
    /// request, so it is never hidden behind a 429 from retrying a dead token.
    case sessionExpired
    case unauthorized
    case forbidden
    case rateLimited(retryAfter: String?)
    case serverError(status: Int)
    case networkUnavailable
    case invalidResponse
    case requestFailed

    public var errorDescription: String? {
        switch self {
        case .credentialsNotFound, .invalidCredentials:
            return "Claude usage is unavailable. Sign in with Claude Code, then refresh."
        case .keychainAccessDenied:
            return "Claude usage is unavailable because macOS denied Keychain access. Check Keychain permissions and try again."
        case .sessionExpired:
            return "Claude Code sign-in has expired. Open Claude Code, run /login to sign in again, then re-check."
        case .unauthorized, .forbidden:
            return "Claude Code sign-in has expired or is not authorized. Open Claude Code, run /login to sign in again, then re-check."
        case .rateLimited:
            return "Claude usage is temporarily rate limited. The last successful value is still shown when available."
        case .serverError:
            return "Anthropic usage data is temporarily unavailable. The last successful value is still shown when available."
        case .networkUnavailable:
            return "Claude usage could not be updated while offline. The last successful value is still shown when available."
        case .invalidResponse:
            return "Claude usage data uses an unfamiliar format and cannot currently be displayed."
        case .requestFailed:
            return "Claude usage could not be updated. Try again in a moment."
        }
    }
}

public protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

public protocol ClaudeUsageAPIClientProtocol: Sendable {
    func fetchUsage(accessToken: String) async throws -> ClaudeUsageResponse
}

public struct ClaudeUsageAPIClient: ClaudeUsageAPIClientProtocol, Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let session: any URLSessionProtocol
    private let timeout: TimeInterval

    public init(session: any URLSessionProtocol = ClaudeUsageAPIClient.makeSession(), timeout: TimeInterval = 15) {
        self.session = session
        self.timeout = timeout
    }

    public func fetchUsage(accessToken: String) async throws -> ClaudeUsageResponse {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .timedOut:
                throw ClaudeUsageError.networkUnavailable
            default:
                throw ClaudeUsageError.requestFailed
            }
        } catch {
            throw ClaudeUsageError.requestFailed
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeUsageError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            // Decode only the documented error envelope, then discard it. Response
            // bodies are never logged or surfaced because they may be sensitive.
            _ = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            switch http.statusCode {
            case 401: throw ClaudeUsageError.unauthorized
            case 403: throw ClaudeUsageError.forbidden
            case 429: throw ClaudeUsageError.rateLimited(retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
            case 500...599: throw ClaudeUsageError.serverError(status: http.statusCode)
            default: throw ClaudeUsageError.requestFailed
            }
        }

        let decoded: ClaudeUsageResponse
        do {
            decoded = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
        } catch {
            throw ClaudeUsageError.invalidResponse
        }
        guard decoded.hasAnyWindow else { throw ClaudeUsageError.invalidResponse }
        return decoded
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }

    private struct APIErrorEnvelope: Decodable {
        struct Detail: Decodable { let type: String?; let message: String? }
        let type: String?
        let message: String?
        let error: Detail?
    }
}

// MARK: - Cache and request coalescing

public struct ClaudeUsageFetchResult: Sendable, Equatable {
    public let usage: ClaudeUsageResponse?
    public let fetchedAt: Date?
    public let isCached: Bool
    public let error: ClaudeUsageError?

    public init(usage: ClaudeUsageResponse?, fetchedAt: Date?, isCached: Bool, error: ClaudeUsageError?) {
        self.usage = usage
        self.fetchedAt = fetchedAt
        self.isCached = isCached
        self.error = error
    }
}

public protocol ClaudeUsageServicing: Sendable {
    func usage(forceRefresh: Bool) async -> ClaudeUsageFetchResult
}

public actor ClaudeUsageService: ClaudeUsageServicing {
    private let credentials: any ClaudeCredentialProviding
    private let client: any ClaudeUsageAPIClientProtocol
    private let refreshInterval: TimeInterval
    private let now: @Sendable () -> Date

    private var cachedUsage: ClaudeUsageResponse?
    private var cachedAt: Date?
    private var inFlight: Task<ClaudeUsageResponse, Error>?

    public init(
        credentials: any ClaudeCredentialProviding = KeychainClaudeCredentialProvider(),
        client: any ClaudeUsageAPIClientProtocol = ClaudeUsageAPIClient(),
        refreshInterval: TimeInterval = 5 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.client = client
        self.refreshInterval = refreshInterval
        self.now = now
    }

    public func usage(forceRefresh: Bool) async -> ClaudeUsageFetchResult {
        let current = now()
        if !forceRefresh, let cachedUsage, let cachedAt,
           current.timeIntervalSince(cachedAt) < refreshInterval {
            return ClaudeUsageFetchResult(usage: cachedUsage, fetchedAt: cachedAt, isCached: true, error: nil)
        }

        if let inFlight {
            return await result(of: inFlight)
        }

        let credentials = self.credentials
        let client = self.client
        let clock = self.now
        let task = Task<ClaudeUsageResponse, Error> {
            let credential = try credentials.credential()
            // A token we already know is expired will only ever come back 401 — and
            // hammering it invites a 429 that hides the real cause. Fail fast with a
            // precise, actionable error instead of spending the request.
            if credential.isExpired(now: clock()) {
                throw ClaudeUsageError.sessionExpired
            }
            return try await client.fetchUsage(accessToken: credential.accessToken)
        }
        inFlight = task
        let result = await result(of: task)
        inFlight = nil
        return result
    }

    private func result(of task: Task<ClaudeUsageResponse, Error>) async -> ClaudeUsageFetchResult {
        do {
            let usage = try await task.value
            let fetchedAt = now()
            cachedUsage = usage
            cachedAt = fetchedAt
            return ClaudeUsageFetchResult(usage: usage, fetchedAt: fetchedAt, isCached: false, error: nil)
        } catch {
            let mapped = Self.map(error)
            return ClaudeUsageFetchResult(
                usage: cachedUsage,
                fetchedAt: cachedAt,
                isCached: cachedUsage != nil,
                error: mapped
            )
        }
    }

    private static func map(_ error: Error) -> ClaudeUsageError {
        if let error = error as? ClaudeUsageError { return error }
        guard let error = error as? ClaudeCredentialError else { return .requestFailed }
        switch error {
        case .notFound, .oauthSectionMissing, .accessTokenMissing: return .credentialsNotFound
        case .accessDenied: return .keychainAccessDenied
        case .malformedData: return .invalidCredentials
        case .keychainFailure: return .keychainAccessDenied
        }
    }
}
