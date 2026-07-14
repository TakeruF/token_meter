import Foundation
import UserNotifications
import TokenMeterCore

/// Sends threshold / reset / error notifications, and — the fiddly part — refuses
/// to send the same one twice for the same condition.
actor NotificationManager {

    /// The lowest threshold already announced for a provider. Cleared when the quota
    /// recovers (a reset), so the next cycle can warn again.
    private var announcedThreshold: [UsageProviderID: Double] = [:]
    private var announcedResetAt: [UsageProviderID: Date] = [:]
    private var lastErrorMessage: [UsageProviderID: String] = [:]
    private var authorized = false

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            authorized = true
        case .notDetermined:
            authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            authorized = false
        }
    }

    /// `thresholds` are the enabled remaining-ratio levels, e.g. [0.20, 0.10, 0.05].
    func evaluate(
        snapshot: UsageSnapshot,
        previous: UsageSnapshot?,
        thresholds: [Double],
        notifyOnReset: Bool
    ) async {
        let provider = snapshot.provider

        // No provider-reported quota -> nothing to threshold on.
        guard let window = snapshot.primaryWindow, let remaining = window.remainingRatio else { return }

        // A quota reset: the remaining ratio jumped back up.
        if let previousRemaining = previous?.primaryWindow?.remainingRatio, remaining > previousRemaining + 0.05 {
            announcedThreshold[provider] = nil
            if notifyOnReset {
                let resetsAt = window.resetsAt ?? Date()
                // Guard against announcing the same reset twice.
                if announcedResetAt[provider] != resetsAt {
                    announcedResetAt[provider] = resetsAt
                    await send(
                        title: "\(provider.displayName) quota reset",
                        body: "\(Int((remaining * 100).rounded()))% available again."
                    )
                }
            }
        }

        // Fire only for the lowest threshold now crossed, and only if we have not
        // already announced that one (or a lower one) for this cycle.
        guard let crossed = thresholds.filter({ remaining <= $0 }).min() else {
            // Back above every threshold: allow future warnings again.
            announcedThreshold[provider] = nil
            return
        }
        if let already = announcedThreshold[provider], already <= crossed { return }

        announcedThreshold[provider] = crossed
        let level = UsageStatusLevel.from(remainingRatio: remaining)
        var body = "\(Int((remaining * 100).rounded()))% remaining."
        if let reset = window.resetDescription() { body += " \(reset)." }

        await send(title: "\(provider.displayName): \(level.label)", body: body)
    }

    func notifyError(provider: UsageProviderID, message: String) async {
        // Repeating the same error every refresh would be noise.
        guard lastErrorMessage[provider] != message else { return }
        lastErrorMessage[provider] = message
        await send(title: "\(provider.displayName): data error", body: message)
    }

    private func send(title: String, body: String) async {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
