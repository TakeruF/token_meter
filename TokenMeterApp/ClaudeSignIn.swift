import AppKit
import Foundation
import Security
import SwiftUI
import TokenMeterCore

/// Getting Claude usage flowing again — installing Claude Code, signing back in,
/// and letting macOS ask about the Keychain item — as one-click actions.
///
/// Two rules shape this file:
///
/// - Nothing visible happens unbidden. Every step that opens Terminal, opens a
///   browser, or makes macOS raise its own Keychain dialog is preceded by a popup
///   that says exactly what is about to happen. A permission dialog that appears
///   out of a background refresh reads as something going wrong; the same dialog
///   one click after "Continue" reads as the app doing what it was asked to.
/// - Token Meter never handles Claude's credentials beyond the single read the
///   usage request already needs (see `ClaudeUsageService`), and never types,
///   sees, or stores a password. `/login` is a slash command inside the
///   interactive REPL, not a CLI flag, so the sign-in can only ever be *started*
///   for the user — never completed on their behalf.
///
/// Anyone who would rather do all of this by hand is one link away from the
/// written steps: `ClaudeSignIn.manualStepsURL`.
enum ClaudeSignIn {
    /// The written instructions for doing every step here by hand.
    static let manualStepsURL = URL(string: "https://github.com/TakeruF/token_meter/blob/main/docs/claude-sign-in.md")!

    /// Where Claude Code is downloaded from.
    static let installURL = URL(string: "https://claude.com/claude-code")!

    /// True when `claude` resolves on the user's login-shell PATH. A login shell
    /// (`-l`) sources the same profile scripts (`.zprofile`, `.zshrc`, nvm, etc.) a
    /// user's own Terminal would, so this matches what actually happens when they
    /// type `claude` themselves — unlike checking a handful of guessed install paths.
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

    /// What a single, deliberate read of the Claude Code Keychain item found. This
    /// is the same read the usage request makes — performed now, on a click, so
    /// macOS raises its approval dialog while the user is looking at it.
    enum CredentialProbe: Equatable, Sendable {
        case granted
        /// Readable, but the token is past its expiry: signing in again is the fix,
        /// not a Keychain permission.
        case expired
        /// No usable credential stored — Claude Code was never signed in here, or
        /// the item is in a format we cannot read. Both are fixed by signing in.
        case signedOut
        case denied
        case failed(OSStatus)
    }

    /// Reads the credential once, off the main thread: the macOS approval dialog is
    /// raised by this call and would otherwise block the UI it appears over.
    static func probeCredential() async -> CredentialProbe {
        await Task.detached(priority: .userInitiated) {
            do {
                let credential = try KeychainClaudeCredentialProvider().credential()
                return credential.isExpired() ? .expired : .granted
            } catch let error as ClaudeCredentialError {
                switch error {
                case .accessDenied:
                    return .denied
                case .notFound, .oauthSectionMissing, .accessTokenMissing, .malformedData:
                    return .signedOut
                case .keychainFailure(let status):
                    return .failed(status)
                }
            } catch {
                return .failed(errSecInternalError)
            }
        }.value
    }

    /// Opens Keychain Access at the user's request, for the one case the app cannot
    /// fix itself: a previously denied item, whose access control only Keychain
    /// Access can change.
    ///
    /// Located by bundle identifier rather than by path — the app has moved between
    /// `/System/Applications/Utilities` and `/System/Library/CoreServices/Applications`
    /// across macOS versions, and the hard-coded path silently does nothing on the
    /// versions it is wrong for.
    @MainActor
    static func openKeychainAccess() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.keychainaccess") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Confirmation popups

/// The popup that precedes every visible step.
///
/// Deliberately AppKit rather than SwiftUI's `.alert`: this runs from the menu bar
/// popover as well as from real windows, and an `NSAlert` is the one form that is
/// certain to be presented — and stay presented — in both.
@MainActor
enum ClaudeConnectPrompt {
    enum Choice {
        case confirm
        case cancel
        /// "I'll do it myself" — opens the written steps instead.
        case manual
    }

    static func ask(title: String, message: String, confirm: String) -> Choice {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = AppLocalization.string(title)
        alert.informativeText = AppLocalization.string(message)
        alert.addButton(withTitle: AppLocalization.string(confirm))
        alert.addButton(withTitle: AppLocalization.string("Cancel"))
        alert.addButton(withTitle: AppLocalization.string("Manual steps…"))

        switch alert.runModal() {
        case .alertFirstButtonReturn: return .confirm
        case .alertThirdButtonReturn: return .manual
        default: return .cancel
        }
    }

    /// A plain result popup. Used where the outcome would otherwise be invisible:
    /// the menu bar popover closes as soon as the alert takes focus, so an inline
    /// status line alone could go unread.
    static func inform(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = AppLocalization.string(title)
        alert.informativeText = AppLocalization.string(message)
        alert.addButton(withTitle: AppLocalization.string("OK"))
        alert.runModal()
    }
}

// MARK: - Flow

/// What is standing between the user and Claude plan usage, as far as the app can
/// tell from the failure it actually saw.
enum ClaudeConnectionBlocker: Equatable {
    /// The sign-in expired, was revoked, or was never made here.
    case signedOut
    /// macOS has not been asked yet, or said no, to the Keychain item.
    case keychainAccess
    /// Claude Code is not on this Mac.
    case notInstalled

    var actionLabel: LocalizedStringKey {
        switch self {
        case .signedOut: return "Sign in to Claude Code"
        case .keychainAccess: return "Allow Keychain access"
        case .notInstalled: return "Get Claude Code"
        }
    }

    var actionSymbol: String {
        switch self {
        case .signedOut: return "terminal"
        case .keychainAccess: return "key.fill"
        case .notInstalled: return "arrow.down.circle"
        }
    }

    /// One line under the button, so the click is never a leap of faith.
    var caption: LocalizedStringKey {
        switch self {
        case .signedOut:
            return "Token Meter asks first, then opens Terminal and runs `claude` — type /login there."
        case .keychainAccess:
            return "Token Meter asks first, then macOS shows its own approval dialog. Choose Always Allow to stop the prompts."
        case .notInstalled:
            return "Token Meter asks first, then opens the Claude Code download page in your browser."
        }
    }
}

/// Runs the one-click flow: confirm, act, and — when the act reveals a different
/// problem than expected — offer the next step rather than dead-ending.
@MainActor
enum ClaudeConnectFlow {
    enum Outcome: Equatable {
        case cancelled
        /// The credential was read: usage can be fetched from now on.
        case connected
        case signInStarted
        case installPageOpened
        case manualStepsOpened
        case keychainDenied
        case terminalLaunchFailed
        case failed(OSStatus)

        /// Whether the host should re-check the provider now.
        var shouldRecheck: Bool {
            switch self {
            case .connected, .signInStarted: return true
            default: return false
            }
        }

        /// The line shown under the button afterwards. `nil` leaves the button's own
        /// caption in place, which is what a cancelled flow should do.
        var message: String? {
            switch self {
            case .cancelled:
                return nil
            case .connected:
                return AppLocalization.string("Keychain access granted. Claude plan usage will appear on the next refresh.")
            case .signInStarted:
                return AppLocalization.string("Terminal is open. Type /login in Claude Code, then re-check here.")
            case .installPageOpened:
                return AppLocalization.string("The download page is open in your browser. Install Claude Code, sign in once, then re-check here.")
            case .manualStepsOpened:
                return AppLocalization.string("The manual steps are open in your browser.")
            case .keychainDenied:
                return AppLocalization.string("macOS denied access to the Claude Code sign-in. Allow Token Meter in Keychain Access, then try again.")
            case .terminalLaunchFailed:
                return AppLocalization.string("Could not open Terminal. Follow the manual steps instead.")
            case .failed(let status):
                return AppLocalization.format("Could not read the Claude Code sign-in (Keychain error %d).", Int(status))
            }
        }

        var isProblem: Bool {
            switch self {
            case .keychainDenied, .terminalLaunchFailed, .failed: return true
            default: return false
            }
        }
    }

    static func run(_ blocker: ClaudeConnectionBlocker) async -> Outcome {
        switch blocker {
        case .signedOut: return await offerSignIn(expired: false)
        case .keychainAccess: return await offerKeychainAccess()
        case .notInstalled: return await offerInstall()
        }
    }

    // MARK: Steps

    /// The Keychain step. The read is the point: macOS decides whether to ask, and
    /// its answer tells us which of the other problems we actually have.
    private static func offerKeychainAccess() async -> Outcome {
        switch ClaudeConnectPrompt.ask(
            title: "Let macOS ask about the Claude Code sign-in?",
            message: "Token Meter will read the “Claude Code-credentials” Keychain item once, right now. macOS shows its own approval dialog — choose Always Allow so it stops asking on every refresh. The token is only used to ask Anthropic for your plan usage, and is never stored, logged, or put in the widget.",
            confirm: "Continue"
        ) {
        case .cancel:
            return .cancelled
        case .manual:
            return openManualSteps()
        case .confirm:
            break
        }

        switch await ClaudeSignIn.probeCredential() {
        case .granted:
            AppSettings.shared.claudeKeychainGranted = true
            ClaudeConnectPrompt.inform(
                title: "Keychain access granted",
                message: "Token Meter can read the Claude Code sign-in and will show your plan usage from the next refresh."
            )
            return .connected

        // Both of these are Keychain successes that reveal a sign-in problem, so
        // the flow continues into the sign-in step instead of reporting "done".
        case .expired:
            return await offerSignIn(expired: true)
        case .signedOut:
            return await offerSignIn(expired: false)

        case .denied:
            return offerKeychainAccessRepair()
        case .failed(let status):
            return .failed(status)
        }
    }

    /// Only reachable once macOS has recorded a denial: the item's access control
    /// now has to be changed in Keychain Access, which no API of ours can do.
    private static func offerKeychainAccessRepair() -> Outcome {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppLocalization.string("macOS denied access to the Claude Code sign-in")
        alert.informativeText = AppLocalization.string("Open Keychain Access, search for “Claude Code-credentials”, open it, and allow Token Meter under Access Control. Then try again. You can also turn the Claude usage check off in Settings and keep using local token counts.")
        alert.addButton(withTitle: AppLocalization.string("Open Keychain Access"))
        alert.addButton(withTitle: AppLocalization.string("Cancel"))
        alert.addButton(withTitle: AppLocalization.string("Manual steps…"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            ClaudeSignIn.openKeychainAccess()
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(ClaudeSignIn.manualStepsURL)
        default:
            break
        }
        return .keychainDenied
    }

    /// The sign-in step. Checked against the real PATH first, so the app never
    /// promises a Terminal command that would only come back "command not found" —
    /// in that case the install step is offered instead.
    private static func offerSignIn(expired: Bool) async -> Outcome {
        guard await ClaudeSignIn.isCLIAvailable() else { return await offerInstall() }

        switch ClaudeConnectPrompt.ask(
            title: expired
                ? "Your Claude Code sign-in has expired — open Terminal to sign in again?"
                : "Open Terminal and sign in to Claude Code?",
            message: "Token Meter will open Terminal and run `claude`. Type /login once it starts and finish the sign-in in your browser. Token Meter never sees or types your password, and cannot complete the sign-in for you.",
            confirm: "Open Terminal"
        ) {
        case .cancel:
            return .cancelled
        case .manual:
            return openManualSteps()
        case .confirm:
            break
        }

        do {
            try ClaudeSignIn.openTerminalAndSignIn()
            return .signInStarted
        } catch {
            return .terminalLaunchFailed
        }
    }

    private static func offerInstall() async -> Outcome {
        switch ClaudeConnectPrompt.ask(
            title: "Open the Claude Code download page?",
            message: "Claude Code was not found on this Mac. Token Meter will open claude.com/claude-code in your browser. Install Claude Code, run it once and sign in, then come back and re-check.",
            confirm: "Open browser"
        ) {
        case .cancel:
            return .cancelled
        case .manual:
            return openManualSteps()
        case .confirm:
            NSWorkspace.shared.open(ClaudeSignIn.installURL)
            return .installPageOpened
        }
    }

    private static func openManualSteps() -> Outcome {
        NSWorkspace.shared.open(ClaudeSignIn.manualStepsURL)
        return .manualStepsOpened
    }
}

// MARK: - Button

/// The one-click way out of whatever is blocking Claude usage, shown wherever the
/// app reports the problem: the menu bar card, Setup, and onboarding.
///
/// It states what the click will do before it is clicked, keeps the written steps
/// one link away for people who would rather not be driven, and reports the result
/// in place afterwards.
struct ClaudeConnectButton: View {
    let blocker: ClaudeConnectionBlocker
    /// Called when the flow got far enough that the provider is worth re-checking.
    var onCompleted: () -> Void = {}

    @State private var outcome: ClaudeConnectFlow.Outcome?
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Button {
                    run()
                } label: {
                    Label(blocker.actionLabel, systemImage: blocker.actionSymbol)
                }
                .controlSize(.small)
                .disabled(isRunning)

                if isRunning {
                    ProgressView().controlSize(.small)
                }
            }

            if let message = outcome?.message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(outcome?.isProblem == true ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(blocker.caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Link(destination: ClaudeSignIn.manualStepsURL) {
                Text("Rather do it yourself? Manual steps")
            }
            .font(.caption2)
        }
    }

    private func run() {
        isRunning = true
        Task {
            let result = await ClaudeConnectFlow.run(blocker)
            isRunning = false
            outcome = result
            if result.shouldRecheck { onCompleted() }
        }
    }
}
