import Foundation

public protocol UsageProvider: Sendable {
    var id: UsageProviderID { get }
    var displayName: String { get }

    func checkAvailability() async -> ProviderAvailability
    func fetchCurrentUsage(forceRefresh: Bool) async throws -> UsageSnapshot
    func startMonitoring(
        onUpdate: @escaping @Sendable (UsageSnapshot) -> Void
    ) async throws
    func stopMonitoring() async
}

public extension UsageProvider {
    func fetchCurrentUsage() async throws -> UsageSnapshot {
        try await fetchCurrentUsage(forceRefresh: false)
    }
}

/// Providers hand freshly parsed events to this so the app can persist them
/// without the provider knowing about the database.
public protocol UsageEventSink: AnyObject, Sendable {
    func ingest(events: [UsageEvent], provider: UsageProviderID)
}
