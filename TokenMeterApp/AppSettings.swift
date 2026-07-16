import Foundation
import Observation
import ServiceManagement
import TokenMeterCore

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"
    case korean = "ko"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    /// Whether "184万" reads as a number in this language. English has no myriad
    /// words, so offering the choice there would only be a way to break the UI.
    var supportsMyriadNotation: Bool {
        switch self {
        case .english: return false
        case .japanese, .simplifiedChinese, .korean: return true
        }
    }

    /// Language names stay in their own language so the picker remains usable
    /// even when the currently selected language is unfamiliar.
    var displayName: String {
        switch self {
        case .english: return "English"
        case .japanese: return "日本語"
        case .simplifiedChinese: return "简体中文"
        case .korean: return "한국어"
        }
    }

    static var preferred: AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("ja") { return .japanese }
        if preferred.hasPrefix("zh") { return .simplifiedChinese }
        if preferred.hasPrefix("ko") { return .korean }
        return .english
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case full          // "Claude 68% · Codex 42%"
    case compact       // Brand marks followed by values
    case iconOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .full: return AppLocalization.string("Full (Claude 68% · Codex 42%)")
        case .compact: return AppLocalization.string("Compact (brand icons + values)")
        case .iconOnly: return AppLocalization.string("Icon only")
        }
    }
}

enum MenuBarLimitWindow: String, CaseIterable, Identifiable {
    case fiveHour
    case weekly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fiveHour: return AppLocalization.string("5-hour limit")
        case .weekly: return AppLocalization.string("Weekly limit")
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
        static let appLanguage = "appLanguage"
        static let showClaude = "showClaudeCode"
        static let claudeOAuthUsage = "claudeOAuthUsageEnabled"
        static let showCodex = "showCodex"
        static let showCopilotCli = "showCopilotCli"
        static let refreshInterval = "refreshIntervalSeconds"
        static let menuBarStyle = "menuBarStyle"
        static let showMenuBarExtra = "showMenuBarExtra"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let menuBarShowPercentage = "menuBarShowPercentage"
        static let menuBarShowTokens = "menuBarShowTokens"
        static let menuBarShowReset = "menuBarShowReset"
        static let menuBarLimitWindow = "menuBarLimitWindow"
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
        static let tokenNotation = "tokenNotation"
    }

    var appLanguage: AppLanguage { didSet { defaults.set(appLanguage.rawValue, forKey: Key.appLanguage) } }
    /// The notation the user picked. Only meaningful in a language that has myriad
    /// words — read `effectiveTokenNotation` to display a count, never this.
    var tokenNotation: TokenNotation { didSet { defaults.set(tokenNotation.rawValue, forKey: Key.tokenNotation) } }

    /// The notation to actually format with. A stored `.myriad` is ignored in a
    /// language that has no myriad words, so an English UI cannot end up reading
    /// "6億" — whether because the user switched language after choosing, or
    /// because the preference outlived the language it was chosen for.
    var effectiveTokenNotation: TokenNotation {
        appLanguage.supportsMyriadNotation ? tokenNotation : .metric
    }

    /// The locale to format token counts with. Metric is spelled by formatting in
    /// English, whose compact names *are* the K/M/B scale — so a single format style
    /// can render either notation, which is what the chart axes need.
    var tokenFormattingLocale: Locale {
        effectiveTokenNotation == .myriad ? appLanguage.locale : Locale(identifier: "en")
    }
    var showClaudeCode: Bool { didSet { defaults.set(showClaudeCode, forKey: Key.showClaude) } }
    /// Explicit opt-in: enabling this permits reading Claude Code's Keychain item
    /// solely to request usage data from Anthropic.
    var claudeOAuthUsageEnabled: Bool {
        didSet { defaults.set(claudeOAuthUsageEnabled, forKey: Key.claudeOAuthUsage) }
    }
    var showCodex: Bool { didSet { defaults.set(showCodex, forKey: Key.showCodex) } }
    /// Opt-in: GitHub Copilot CLI is off by default. It is a secondary provider
    /// (smaller audience) and its models overlap Claude Code, so it stays hidden
    /// until the user explicitly enables it.
    var showCopilotCli: Bool { didSet { defaults.set(showCopilotCli, forKey: Key.showCopilotCli) } }

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
    /// Countdown to the selected (or fallback) quota reset, appended to the menu bar title.
    var menuBarShowReset: Bool { didSet { defaults.set(menuBarShowReset, forKey: Key.menuBarShowReset) } }
    var menuBarLimitWindow: MenuBarLimitWindow {
        didSet { defaults.set(menuBarLimitWindow.rawValue, forKey: Key.menuBarLimitWindow) }
    }

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
            Key.appLanguage: AppLanguage.preferred.rawValue,
            // K/M/B by default even in Japanese: it is what every token count in the
            // app has always shown, and tokens are read as an engineering quantity.
            // Myriad is there for those who want it, not imposed on those who don't.
            Key.tokenNotation: TokenNotation.metric.rawValue,
            Key.showClaude: true,
            Key.claudeOAuthUsage: false,
            Key.showCodex: true,
            Key.showCopilotCli: false,
            Key.refreshInterval: 300.0,
            Key.menuBarStyle: MenuBarStyle.full.rawValue,
            Key.showMenuBarExtra: true,
            Key.showMenuBarIcon: true,
            Key.menuBarShowPercentage: true,
            Key.menuBarShowTokens: true,
            Key.menuBarShowReset: false,
            Key.menuBarLimitWindow: MenuBarLimitWindow.fiveHour.rawValue,
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

        appLanguage = AppLanguage(rawValue: defaults.string(forKey: Key.appLanguage) ?? "") ?? .preferred
        tokenNotation = TokenNotation(rawValue: defaults.string(forKey: Key.tokenNotation) ?? "") ?? .metric
        showClaudeCode = defaults.bool(forKey: Key.showClaude)
        claudeOAuthUsageEnabled = defaults.bool(forKey: Key.claudeOAuthUsage)
        showCodex = defaults.bool(forKey: Key.showCodex)
        showCopilotCli = defaults.bool(forKey: Key.showCopilotCli)
        refreshInterval = defaults.double(forKey: Key.refreshInterval)
        menuBarStyle = MenuBarStyle(rawValue: defaults.string(forKey: Key.menuBarStyle) ?? "") ?? .full
        showMenuBarExtra = defaults.bool(forKey: Key.showMenuBarExtra)
        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon)
        menuBarShowPercentage = defaults.bool(forKey: Key.menuBarShowPercentage)
        menuBarShowTokens = defaults.bool(forKey: Key.menuBarShowTokens)
        menuBarShowReset = defaults.bool(forKey: Key.menuBarShowReset)
        menuBarLimitWindow = MenuBarLimitWindow(
            rawValue: defaults.string(forKey: Key.menuBarLimitWindow) ?? ""
        ) ?? .fiveHour
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
        if showCopilotCli { set.insert(.copilotCli) }
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
