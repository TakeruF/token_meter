import Foundation
import UserNotifications
import TokenMeterCore

/// Sends threshold / reset / error notifications, and — the fiddly part — refuses
/// to send the same one twice for the same condition.
actor NotificationManager {

    /// The lowest threshold already announced for a provider. Cleared when the quota
    /// recovers (a reset), so the next cycle can warn again.
    private var announcedThreshold: [UsageProviderID: Double] = [:]
    /// Keyed by window as well as provider: the 5-hour and weekly limits roll over on
    /// their own schedules, and one must never suppress the other's notice.
    private var announcedResetAt: [UsageProviderID: [QuotaWindowKind: Date]] = [:]
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

        // Each window is checked against its own previous reading, so the notice names
        // the limit that actually rolled over rather than whichever one is now tightest.
        for kind in snapshot.windowsThatReset(since: previous) {
            announcedThreshold[provider] = nil
            guard notifyOnReset, let resetWindow = snapshot.window(kind) else { continue }

            // Guard against announcing the same reset twice — per window, since the
            // next 5-hour rollover must not be swallowed by the weekly's reset time.
            let resetsAt = resetWindow.resetsAt ?? Date()
            guard announcedResetAt[provider]?[kind] != resetsAt else { continue }
            announcedResetAt[provider, default: [:]][kind] = resetsAt

            // Name which window rolled over ("5-hour" / "Weekly"), so the one
            // sentence says everything — no separate "N% available again" line.
            await send(
                title: AppLocalization.format(
                    "%@ %@ quota reset",
                    provider.displayName,
                    AppLocalization.string(kind.label)
                ),
                body: ""
            )
        }

        // No provider-reported quota -> nothing to threshold on.
        guard let window = snapshot.primaryWindow, let remaining = window.remainingRatio else { return }

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
        var body = AppLocalization.format(
            "%d%% remaining.",
            Int((remaining * 100).rounded())
        )
        if let reset = AppLocalization.resetSentence(resetsAt: window.resetsAt) {
            body += " \(reset)"
        }

        await send(
            title: AppLocalization.format(
                "%@: %@",
                provider.displayName,
                AppLocalization.string(level.label)
            ),
            body: body
        )
    }

    func notifyError(provider: UsageProviderID, message: String) async {
        // Repeating the same error every refresh would be noise.
        guard lastErrorMessage[provider] != message else { return }
        lastErrorMessage[provider] = message
        await send(
            title: AppLocalization.format("%@: data error", provider.displayName),
            body: message
        )
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
