import Foundation
import SwiftUI

enum AppLocalization {
    static func string(_ key: String, language: AppLanguage = AppSettings.shared.appLanguage) -> String {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key),
            locale: AppSettings.shared.appLanguage.locale,
            arguments: arguments
        )
    }

    /// The app-language locale, but honouring the user's system 12-/24-hour clock
    /// preference. `.formatted` otherwise falls back to the raw system locale
    /// (wrong language) rather than the app's chosen language.
    static var dateTimeLocale: Locale {
        var components = Locale.Components(locale: AppSettings.shared.appLanguage.locale)
        components.hourCycle = Locale.current.hourCycle
        return Locale(components: components)
    }

    /// An "updated N ago" phrase in the app language, with a friendlier "just now"
    /// for the most recent minute than the system formatter's bare "now" / "今".
    static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        if abs(now.timeIntervalSince(date)) < 60 { return string("Just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppSettings.shared.appLanguage.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func resetDescription(resetsAt: Date?, now: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        let interval = resetsAt.timeIntervalSince(now)
        guard interval > 0 else { return string("Resetting now") }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours >= 24 {
            return format("Resets in %dd %dh", hours / 24, hours % 24)
        }
        if hours > 0 { return format("Resets in %dh %dm", hours, minutes) }
        return format("Resets in %dm", minutes)
    }

    /// Full-sentence form of `resetDescription`, for notification bodies: it reads as
    /// a sentence and ends with a localized period. The short label form (no verb, no
    /// period) stays in `resetDescription` for compact clock labels.
    static func resetSentence(resetsAt: Date?, now: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        let interval = resetsAt.timeIntervalSince(now)
        guard interval > 0 else { return string("Resetting now") }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours >= 24 {
            return format("Resets in %dd %dh.", hours / 24, hours % 24)
        }
        if hours > 0 { return format("Resets in %dh %dm.", hours, minutes) }
        return format("Resets in %dm.", minutes)
    }

    static func providerDetail(_ detail: String) -> String {
        let replacements: [(prefix: String, key: String)] = [
            ("No session logs in ", "No session logs in %@"),
        ]
        for replacement in replacements where detail.hasPrefix(replacement.prefix) {
            let value = String(detail.dropFirst(replacement.prefix.count))
            return format(replacement.key, value)
        }
        if detail.hasSuffix(" not found") {
            return format("%@ not found", String(detail.dropLast(" not found".count)))
        }
        if detail.hasPrefix("Permission denied: ") {
            return format(
                "Permission denied: %@",
                String(detail.dropFirst("Permission denied: ".count))
            )
        }
        return string(detail)
    }
}

struct AppLanguagePicker: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        HStack {
            Text("Language")
            Spacer()
            Picker("Language", selection: $settings.appLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(verbatim: language.displayName).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityLabel(Text("App language"))
        }
    }
}
