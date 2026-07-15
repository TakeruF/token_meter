import SwiftUI
import TokenMeterCore

/// The first screen of the main window: what is connected, what is missing, what to
/// do about it, and how the menu bar should look.
///
/// Every instruction here is something that was verified on a real machine — the
/// commands exist and the paths are the ones the app actually reads. Nothing is
/// invented, and no step ever asks for a token or a password.
struct SetupView: View {
    let monitor: UsageMonitor
    @State private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                intro

                ForEach(UsageProviderID.allCases) { id in
                    ConnectionCard(
                        providerID: id,
                        state: monitor.states[id],
                        onRecheck: {
                            Task {
                                await monitor.detectDataSources()
                                await monitor.refresh(reason: .manual)
                            }
                        }
                    )
                }

                claudeUsageSection
                menuBarSection
                privacyNote
            }
            .padding(20)
        }
        .background(.background)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Setup").font(.title2.weight(.semibold))
            Text("Token Meter reads local Claude Code and Codex session logs. With your explicit permission, it can also use Claude Code's Keychain sign-in to request Pro / Max usage directly from Anthropic.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var claudeUsageSection: some View {
        SectionBox("Claude Pro / Max usage") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable Claude usage checks", isOn: $settings.claudeOAuthUsageEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: settings.claudeOAuthUsageEnabled) { _, _ in
                        Task {
                            await monitor.detectDataSources()
                            await monitor.refresh(reason: .manual)
                        }
                    }
                Text("If enabled, Token Meter reads the Claude Code-credentials Generic Password from macOS Keychain and uses its OAuth access token only for GET https://api.anthropic.com/api/oauth/usage. It does not save or log the token.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("You can disable this integration at any time. Local token history continues to work without it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var menuBarSection: some View {
        SectionBox("Menu bar") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show Token Meter in the menu bar", isOn: $settings.showMenuBarExtra)
                    .toggleStyle(.switch)

                if !settings.showMenuBarExtra {
                    Label(
                        "With the menu bar item hidden, Token Meter keeps a Dock icon so you can still open this window.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                Picker("Format", selection: $settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .disabled(!settings.showMenuBarExtra)

                Toggle("Show Meter icon", isOn: $settings.showMenuBarIcon)
                    .disabled(!settings.showMenuBarExtra || settings.menuBarStyle == .iconOnly)

                Text("Show in the menu bar")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Remaining usage percentage", isOn: $settings.menuBarShowPercentage)
                    .disabled(!settings.showMenuBarExtra || settings.menuBarStyle == .iconOnly)
                Toggle("Today's token count", isOn: $settings.menuBarShowTokens)
                    .disabled(!settings.showMenuBarExtra || settings.menuBarStyle == .iconOnly)
                Toggle("Countdown to the next 5-hour reset", isOn: $settings.menuBarShowReset)
                    .disabled(!settings.showMenuBarExtra || settings.menuBarStyle == .iconOnly)

                Divider()

                Toggle(isOn: $settings.showClaudeCode) {
                    ProviderLabel(providerID: .claudeCode, font: .body, iconSize: 15)
                }
                Toggle(isOn: $settings.showCodex) {
                    ProviderLabel(providerID: .codex, font: .body, iconSize: 15)
                }

                LabeledContent("Preview") {
                    Text(monitor.menuBarTitle.isEmpty ? "(icon only)" : monitor.menuBarTitle)
                        .font(.callout.monospaced())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                }
                .padding(.top, 2)
            }
        }
    }

    private var privacyNote: some View {
        SectionBox("What Token Meter reads") {
            VStack(alignment: .leading, spacing: 6) {
                Label("~/.claude/projects — Claude Code session logs (token counts only)", systemImage: "doc.text")
                Label("~/.codex/sessions — Codex rollout logs (token counts, usage %, reset time)", systemImage: "doc.text")
                Label("macOS Keychain item Claude Code-credentials — only when Claude usage checks are enabled", systemImage: "key")
                Label("OAuth tokens are sent only to Anthropic and are never stored by Token Meter.", systemImage: "lock.shield")
                Label("Prompts and replies are never parsed or stored — only counts, times, and model names.", systemImage: "hand.raised")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// One provider's connection state, with a concrete next step when something is missing.
struct ConnectionCard: View {
    let providerID: UsageProviderID
    let state: ProviderState?
    let onRecheck: () -> Void

    @State private var copied = false

    private var availability: ProviderAvailability? { state?.availability }

    var body: some View {
        SectionBox(providerID.displayName) {
            VStack(alignment: .leading, spacing: 10) {
                statusRow

                if let availability {
                    Text(availability.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let step = nextStep(for: availability) {
                        stepView(step)
                    }

                    capabilities
                }

                HStack {
                    Button("Re-check", action: onRecheck)
                        .controlSize(.small)
                    Button("Reveal log folder in Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: logPath)
                    }
                    .controlSize(.small)
                    Spacer()
                }
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            ProviderIcon(providerID: providerID, size: 18)
            Image(systemName: availability?.symbolName ?? "questionmark.circle")
                .foregroundStyle(availability?.isAvailable == true ? .green : .orange)
            Text(availability?.headline ?? "Checking…")
                .font(.headline)
            Spacer()
            if let updated = state?.lastSuccessfulUpdate {
                Text("Updated \(updated, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// What each source can report.
    private var capabilities: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Token counts, models, and history", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if providerID == .codex {
                Label("Usage percentage and reset time", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label(
                    "Pro / Max remaining percentages and reset times when OAuth usage checks are enabled",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
                .fixedSize(horizontal: false, vertical: true)

                // We do show a 5-hour reset for Claude Code, but we derive it, and the
                // capability list has to say so or the two sources look alike.
                Label(
                    "5-hour reset time is estimated from activity on this Mac, not reported by Claude Code",
                    systemImage: "clock.badge.questionmark"
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
    }

    private struct Step {
        let text: String
        let command: String?
        let url: URL?
    }

    /// Guidance is limited to things verified to exist: `codex login` is a real
    /// subcommand, the Homebrew cask is how Codex is installed here, and Claude Code
    /// needs no CLI on PATH because Token Meter only reads its logs.
    private func nextStep(for availability: ProviderAvailability) -> Step? {
        switch (providerID, availability) {
        case (.codex, .notInstalled):
            return Step(
                text: "Codex is not installed. Install it, then sign in with `codex login`.",
                command: "brew install --cask codex",
                url: URL(string: "https://github.com/openai/codex")
            )
        case (.codex, .notLoggedIn):
            return Step(
                text: "Codex is installed but not signed in. Sign in, then run Codex once so it writes a session log.",
                command: "codex login",
                url: nil
            )
        case (.codex, .noData):
            return Step(
                text: "Signed in, but no session logs yet. Run Codex once and the usage will appear here.",
                command: "codex",
                url: nil
            )
        case (.claudeCode, .notInstalled):
            return Step(
                text: "No Claude Code data found. Install Claude Code and run it once. Token Meter does not need the CLI on your PATH — it only reads the session logs.",
                command: nil,
                url: URL(string: "https://claude.com/claude-code")
            )
        case (.claudeCode, .noData):
            return Step(
                text: "Claude Code is present but has not written any session logs yet. Start a session and the usage will appear here.",
                command: nil,
                url: nil
            )
        case (.claudeCode, .notLoggedIn):
            return Step(
                text: "Claude plan usage is unavailable. Sign in again with Claude Code, then re-check.",
                command: nil,
                url: URL(string: "https://claude.com/claude-code")
            )
        case (_, .permissionDenied(let path)) where path.contains("Keychain"):
            return Step(
                text: "macOS denied access to Claude Code credentials. Review the access prompt or the item in Keychain Access, then re-check.",
                command: nil,
                url: nil
            )
        case (_, .permissionDenied(let path)):
            return Step(
                text: "macOS blocked access to \(path). Grant Token Meter access under System Settings > Privacy & Security > Files and Folders.",
                command: nil,
                url: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
            )
        default:
            return nil
        }
    }

    @ViewBuilder
    private func stepView(_ step: Step) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(step.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let command = step.command {
                    Text(command)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                        .textSelection(.enabled)

                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    }
                    .controlSize(.small)
                }

                if let url = step.url {
                    Link("Learn more", destination: url)
                        .font(.caption)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
    }

    private var logPath: String {
        providerID == .claudeCode
            ? TokenMeterPaths.claudeProjects.path
            : TokenMeterPaths.codexSessions.path
    }
}
