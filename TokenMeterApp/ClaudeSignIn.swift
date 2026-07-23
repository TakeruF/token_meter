import AppKit
import Foundation
import SwiftUI

/// Launches the real `claude` CLI's own login flow for users who don't know how to
/// open a terminal — Token Meter never touches Claude's OAuth credentials itself
/// (see `ClaudeUsageService`), it only offers a shortcut to the same `claude`
/// command a terminal-comfortable user would type by hand.
///
/// `/login` is a slash command inside the interactive REPL, not a CLI flag, so this
/// can only get the user to the prompt — not complete the sign-in unattended.
enum ClaudeSignIn {
    /// True when `claude` resolves on the user's login-shell PATH. Run before
    /// showing the sign-in button: a login shell (`-l`) sources the same profile
    /// scripts (`.zprofile`, `.zshrc`, nvm, etc.) a user's own Terminal would, so
    /// this matches what actually happens when they type `claude` themselves —
    /// unlike checking a handful of guessed install paths.
    static func isCLIAvailable() async -> Bool {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", "command -v claude"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }

    enum LaunchError: Error {
        case scriptWriteFailed
    }

    /// Opens Terminal (or the user's default terminal app) running `claude`, via a
    /// throwaway `.command` file — the standard way to hand a shell command to
    /// Terminal without triggering an Automation ("Token Meter wants to control
    /// Terminal") permission prompt, which AppleScript's `tell application
    /// "Terminal"` would require.
    @MainActor
    static func openTerminalAndSignIn() throws {
        let script = "#!/bin/zsh\nexec claude\n"
        let directory = FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent("token-meter-claude-signin-\(UUID().uuidString).command")

        guard let data = script.data(using: .utf8) else { throw LaunchError.scriptWriteFailed }
        do {
            try data.write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            throw LaunchError.scriptWriteFailed
        }

        NSWorkspace.shared.open(url)
    }
}

/// "Sign in to Claude Code" — shown wherever the app tells the user their Claude
/// session expired. Hides itself until the PATH check confirms `claude` actually
/// resolves, so it never promises a shortcut that would just fail with "command
/// not found"; callers fall back to their own manual instructions in that case.
struct ClaudeSignInButton: View {
    @State private var cliAvailable: Bool?
    @State private var launchFailed = false

    var body: some View {
        Group {
            if cliAvailable == true {
                VStack(alignment: .leading, spacing: 3) {
                    Button {
                        do {
                            try ClaudeSignIn.openTerminalAndSignIn()
                            launchFailed = false
                        } catch {
                            launchFailed = true
                        }
                    } label: {
                        Label("Sign in to Claude Code", systemImage: "terminal")
                    }
                    .controlSize(.small)

                    if launchFailed {
                        Text("Could not open Terminal. Use the command below instead.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Opens Terminal and runs `claude` — type /login once it starts.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                EmptyView()
            }
        }
        .task { cliAvailable = await ClaudeSignIn.isCLIAvailable() }
    }
}
