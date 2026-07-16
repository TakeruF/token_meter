import Foundation

/// Every path this app is allowed to touch. Credential files are deliberately absent:
/// `~/.codex/auth.json` and `~/.claude.json` are never opened.
public enum TokenMeterPaths {
    public static let appGroupID = "group.com.tokenmeter.b97m43j5tt.shared"

    public static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    // MARK: Claude Code

    public static var claudeHome: URL { home.appendingPathComponent(".claude", isDirectory: true) }
    public static var claudeProjects: URL { claudeHome.appendingPathComponent("projects", isDirectory: true) }

    // MARK: Codex

    public static var codexHome: URL { home.appendingPathComponent(".codex", isDirectory: true) }
    public static var codexSessions: URL { codexHome.appendingPathComponent("sessions", isDirectory: true) }
    /// Existence is checked to infer sign-in state. The file is never read.
    public static var codexAuthMarker: URL { codexHome.appendingPathComponent("auth.json") }

    // MARK: GitHub Copilot CLI

    public static var copilotHome: URL { home.appendingPathComponent(".copilot", isDirectory: true) }
    /// One directory per session, each holding an `events.jsonl` transcript.
    public static var copilotSessionState: URL { copilotHome.appendingPathComponent("session-state", isDirectory: true) }

    /// All `events.jsonl` transcripts under `~/.copilot/session-state/`, newest first.
    public static func copilotEventFiles(limit: Int? = nil) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: copilotSessionState,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [(URL, Date)] = []
        for dir in entries {
            let events = dir.appendingPathComponent("events.jsonl")
            guard fm.fileExists(atPath: events.path) else { continue }
            let mod = (try? events.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            files.append((events, mod))
        }
        files.sort { $0.1 > $1.1 }
        let urls = files.map(\.0)
        if let limit { return Array(urls.prefix(limit)) }
        return urls
    }

    // MARK: App storage

    public static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenMeter", isDirectory: true)
    }

    public static var databaseURL: URL {
        applicationSupport.appendingPathComponent("history.sqlite")
    }

    /// All `*.jsonl` under a directory tree, newest first.
    public static func jsonlFiles(under root: URL, limit: Int? = nil) -> [URL] {
        let fm = FileManager.default
        guard let e = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [(URL, Date)] = []
        for case let url as URL in e {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            files.append((url, values?.contentModificationDate ?? .distantPast))
        }
        files.sort { $0.1 > $1.1 }
        let urls = files.map(\.0)
        if let limit { return Array(urls.prefix(limit)) }
        return urls
    }
}
