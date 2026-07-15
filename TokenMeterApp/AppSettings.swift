import Foundation
import Observation
import ServiceManagement
import TokenMeterCore

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case full          // "Claude 68% · Codex 42%"
    case compact       // Brand marks followed by values
    case iconOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .full: return "Full (Claude 68% · Codex 42%)"
        case .compact: return "Compact (brand icons + values)"
        case .iconOnly: return "Icon only"
        }
    }
}

/// UserDefaults-backed preferences. No credentials are ever stored here — see
/// README > Security.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let showClaude = "showClaudeCode"
        static let claudeOAuthUsage = "claudeOAuthUsageEnabled"
        static let showCodex = "showCodex"
        static let refreshInterval = "refreshIntervalSeconds"
        static let menuBarStyle = "menuBarStyle"
        static let showMenuBarExtra = "showMenuBarExtra"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let menuBarShowPercentage = "menuBarShowPercentage"
        static let menuBarShowTokens = "menuBarShowTokens"
        static let menuBarShowReset = "menuBarShowReset"
        static let showFiveHourWindow = "showFiveHourWindow"
        static let showWeeklyWindow = "showWeeklyWindow"
        static let hasCompletedSetup = "hasCompletedSetup"
        static let notify20 = "notifyAt20"
        static let notify10 = "notifyAt10"
        static let notify5 = "notifyAt5"
        static let notifyReset = "notifyOnReset"
        static let notifyError = "notifyOnError"
        static let retentionDays = "retentionDays"
        static let widgetShowTokens = "widgetShowTokens"
        static let widgetShowReset = "widgetShowReset"
        static let launchAtLogin = "launchAtLogin"
    }

    var showClaudeCode: Bool { didSet { defaults.set(showClaudeCode, forKey: Key.showClaude) } }
    /// Explicit opt-in: enabling this permits reading Claude Code's Keychain item
    /// solely to request usage data from Anthropic.
    var claudeOAuthUsageEnabled: Bool {
        didSet { defaults.set(claudeOAuthUsageEnabled, forKey: Key.claudeOAuthUsage) }
    }
    var showCodex: Bool { didSet { defaults.set(showCodex, forKey: Key.showCodex) } }

    /// Seconds between periodic refreshes. The file watcher is the primary trigger;
    /// this is only a backstop, so the floor is deliberately high.
    var refreshInterval: TimeInterval { didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) } }
    static let refreshIntervalOptions: [TimeInterval] = [60, 300, 600, 1800]

    var menuBarStyle: MenuBarStyle { didSet { defaults.set(menuBarStyle.rawValue, forKey: Key.menuBarStyle) } }

    /// Whether to sit in the menu bar at all. When off, the app keeps a Dock icon
    /// instead — otherwise there would be no way left to open it.
    var showMenuBarExtra: Bool { didSet { defaults.set(showMenuBarExtra, forKey: Key.showMenuBarExtra) } }

    /// Whether the Meter glyph is shown beside the menu bar text. Icon-only mode
    /// always keeps the glyph so the menu bar item remains visible and clickable.
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) } }

    /// Which values the menu bar item is allowed to show.
    var menuBarShowPercentage: Bool { didSet { defaults.set(menuBarShowPercentage, forKey: Key.menuBarShowPercentage) } }
    var menuBarShowTokens: Bool { didSet { defaults.set(menuBarShowTokens, forKey: Key.menuBarShowTokens) } }
    /// Countdown to the next 5-hour reset, appended to the menu bar title.
    var menuBarShowReset: Bool { didSet { defaults.set(menuBarShowReset, forKey: Key.menuBarShowReset) } }

    /// The two time-window rows (5-hour and weekly). They are token *measurements*,
    /// not quota percentages, so some people will not want them — hence the toggles.
    var showFiveHourWindow: Bool { didSet { defaults.set(showFiveHourWindow, forKey: Key.showFiveHourWindow) } }
    var showWeeklyWindow: Bool { didSet { defaults.set(showWeeklyWindow, forKey: Key.showWeeklyWindow) } }

    /// Set once the user has seen Setup, so it only leads on first launch.
    var hasCompletedSetup: Bool { didSet { defaults.set(hasCompletedSetup, forKey: Key.hasCompletedSetup) } }

    var notifyAt20: Bool { didSet { defaults.set(notifyAt20, forKey: Key.notify20) } }
    var notifyAt10: Bool { didSet { defaults.set(notifyAt10, forKey: Key.notify10) } }
    var notifyAt5: Bool { didSet { defaults.set(notifyAt5, forKey: Key.notify5) } }
    var notifyOnReset: Bool { didSet { defaults.set(notifyOnReset, forKey: Key.notifyReset) } }
    var notifyOnError: Bool { didSet { defaults.set(notifyOnError, forKey: Key.notifyError) } }

    var retentionDays: Int { didSet { defaults.set(retentionDays, forKey: Key.retentionDays) } }
    static let retentionOptions = [30, 90, 180, 365]

    var widgetShowTokens: Bool { didSet { defaults.set(widgetShowTokens, forKey: Key.widgetShowTokens) } }
    var widgetShowReset: Bool { didSet { defaults.set(widgetShowReset, forKey: Key.widgetShowReset) } }

    var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
            applyLaunchAtLogin()
        }
    }

    private init() {
        defaults.register(defaults: [
            Key.showClaude: true,
            Key.claudeOAuthUsage: false,
            Key.showCodex: true,
            Key.refreshInterval: 300.0,
            Key.menuBarStyle: MenuBarStyle.full.rawValue,
            Key.showMenuBarExtra: true,
            Key.showMenuBarIcon: true,
            Key.menuBarShowPercentage: true,
            Key.menuBarShowTokens: true,
            Key.menuBarShowReset: false,
            Key.showFiveHourWindow: true,
            Key.showWeeklyWindow: true,
            Key.hasCompletedSetup: false,
            Key.notify20: true,
            Key.notify10: true,
            Key.notify5: true,
            Key.notifyReset: false,
            Key.notifyError: true,
            Key.retentionDays: 90,
            Key.widgetShowTokens: true,
            Key.widgetShowReset: true,
            Key.launchAtLogin: false,
        ])

        showClaudeCode = defaults.bool(forKey: Key.showClaude)
        claudeOAuthUsageEnabled = defaults.bool(forKey: Key.claudeOAuthUsage)
        showCodex = defaults.bool(forKey: Key.showCodex)
        refreshInterval = defaults.double(forKey: Key.refreshInterval)
        menuBarStyle = MenuBarStyle(rawValue: defaults.string(forKey: Key.menuBarStyle) ?? "") ?? .full
        showMenuBarExtra = defaults.bool(forKey: Key.showMenuBarExtra)
        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon)
        menuBarShowPercentage = defaults.bool(forKey: Key.menuBarShowPercentage)
        menuBarShowTokens = defaults.bool(forKey: Key.menuBarShowTokens)
        menuBarShowReset = defaults.bool(forKey: Key.menuBarShowReset)
        showFiveHourWindow = defaults.bool(forKey: Key.showFiveHourWindow)
        showWeeklyWindow = defaults.bool(forKey: Key.showWeeklyWindow)
        hasCompletedSetup = defaults.bool(forKey: Key.hasCompletedSetup)
        notifyAt20 = defaults.bool(forKey: Key.notify20)
        notifyAt10 = defaults.bool(forKey: Key.notify10)
        notifyAt5 = defaults.bool(forKey: Key.notify5)
        notifyOnReset = defaults.bool(forKey: Key.notifyReset)
        notifyOnError = defaults.bool(forKey: Key.notifyError)
        retentionDays = defaults.integer(forKey: Key.retentionDays)
        widgetShowTokens = defaults.bool(forKey: Key.widgetShowTokens)
        widgetShowReset = defaults.bool(forKey: Key.widgetShowReset)
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
    }

    func enabledProviders() -> Set<UsageProviderID> {
        var set: Set<UsageProviderID> = []
        if showClaudeCode { set.insert(.claudeCode) }
        if showCodex { set.insert(.codex) }
        return set
    }

    /// Thresholds the user has switched on, highest first.
    func enabledThresholds() -> [Double] {
        var out: [Double] = []
        if notifyAt20 { out.append(0.20) }
        if notifyAt10 { out.append(0.10) }
        if notifyAt5 { out.append(0.05) }
        return out
    }

    private func applyLaunchAtLogin() {
        // SMAppService needs a signed, installed app; failing here is not fatal, so
        // report it rather than crash an unsigned dev build.
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("TokenMeter: could not update Launch at Login: \(error.localizedDescription)")
        }
    }
}
