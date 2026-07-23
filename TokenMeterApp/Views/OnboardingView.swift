import SwiftUI
import TokenMeterCore

/// A short first-run flow. Provider and menu-bar choices are written through the
/// same settings object used by Setup and Settings, so there is only one source of
/// truth and every choice remains editable later.
struct OnboardingView: View {
    let monitor: UsageMonitor

    @State private var settings = AppSettings.shared
    @State private var step: Step
    @State private var rechecking = false

    private enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case providers
        case install
        case display
        case ready

        var id: Int { rawValue }

        var buttonTitle: LocalizedStringKey {
            switch self {
            case .welcome: return "Get Started"
            case .providers, .install, .display: return "Continue"
            case .ready: return "Open Dashboard"
            }
        }
    }

    init(monitor: UsageMonitor) {
        self.monitor = monitor
        _step = State(initialValue: Step(rawValue: AppLaunchOptions.onboardingStep ?? 0) ?? .welcome)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), Color.clear, Color.purple.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                onboardingHeader

                Group {
                    switch step {
                    case .welcome: welcome
                    case .providers: providers
                    case .install: install
                    case .display: display
                    case .ready: ready
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
            .padding(28)
        }
        .frame(minWidth: 760, minHeight: 540)
    }

    private var onboardingHeader: some View {
        ZStack {
            progress
            HStack {
                Spacer()
                AppLanguagePicker()
            }
        }
        .frame(minHeight: 30)
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(visibleSteps) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.18))
                    .frame(width: item == step ? 34 : 16, height: 5)
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(AppLocalization.format(
                "Onboarding step %d of %d",
                stepNumber,
                visibleSteps.count
            ))
        )
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.13))
                    .frame(width: 104, height: 104)
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.tint)
            }

            VStack(spacing: 8) {
                Text("Welcome to Token Meter")
                    .font(.largeTitle.weight(.bold))
                Text("Claude and Codex usage, at a glance.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            usagePreview

            Label(
                "Your token history stays on this Mac.",
                systemImage: "lock.shield"
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer(minLength: 4)
        }
        .multilineTextAlignment(.center)
    }

    private var usagePreview: some View {
        HStack(spacing: 12) {
            OnboardingUsageCard(providerID: .claudeCode, remaining: "68%", reset: "resets in 2h 14m")
            OnboardingUsageCard(providerID: .codex, remaining: "42%", reset: "resets in 1h 06m")
        }
        .frame(maxWidth: 540)
    }

    private var providers: some View {
        VStack(spacing: 24) {
            Spacer()

            OnboardingHeading(
                title: "What do you want to track?",
                subtitle: "Choose either provider or both. You can change this anytime in Settings."
            )

            HStack(spacing: 16) {
                ProviderChoiceCard(
                    providerID: .claudeCode,
                    subtitle: "Local session tokens and optional Pro / Max usage",
                    isSelected: $settings.showClaudeCode
                )
                ProviderChoiceCard(
                    providerID: .codex,
                    subtitle: "Local sessions, 5-hour usage, and weekly usage",
                    isSelected: $settings.showCodex
                )
            }
            .frame(maxWidth: 650)

            if settings.showClaudeCode {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Show Claude Pro / Max usage", isOn: $settings.claudeOAuthUsageEnabled)
                        .toggleStyle(.switch)
                    Text("Optional. Token Meter reads Claude Code's Keychain sign-in only to request usage from Anthropic. The credential is never saved or logged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: 650, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $settings.showCopilotCli) {
                    ProviderLabel(providerID: .copilotCli, font: .body, iconSize: 15)
                }
                .toggleStyle(.switch)
                Text("Also track GitHub Copilot CLI. Token counts only, and its models overlap Claude Code. Off by default — turn it on if you use Copilot in the terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: 650, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            if !hasSelectedProvider {
                Label("Select at least one provider to continue.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Spacer()
        }
    }

    private var install: some View {
        VStack(spacing: 22) {
            Spacer()

            OnboardingHeading(
                title: "Let's confirm the connection",
                subtitle: "Token Meter checks whether it can actually read usage for what you picked — not just whether a tool is installed. Follow any step below, then Re-check."
            )

            VStack(spacing: 14) {
                ForEach(selectedProviders) { id in
                    ConnectionStatusCard(providerID: id, availability: monitor.states[id]?.availability)
                }
            }
            .frame(maxWidth: 620)

            Button {
                recheck()
            } label: {
                Label(rechecking ? "Re-checking…" : "Re-check", systemImage: "arrow.clockwise")
            }
            .controlSize(.large)
            .disabled(rechecking)

            Text("Fixed it? Re-check to confirm. Token Meter also keeps looking in the background — you can finish setup now and connect later.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        // Verify against reality on entry: OAuth sign-in state, in particular, is only
        // known after a live refresh, so a stale "connected" guess can't slip through.
        .task(id: step) {
            guard step == .install else { return }
            recheck()
        }
    }

    private var display: some View {
        VStack(spacing: 24) {
            Spacer()

            OnboardingHeading(
                title: "Make it yours",
                subtitle: "Keep usage close in the menu bar, then open Dashboard when you want the details."
            )

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Show Token Meter in the menu bar", isOn: $settings.showMenuBarExtra)
                        .toggleStyle(.switch)

                    Toggle("Show Meter icon", isOn: $settings.showMenuBarIcon)
                        .disabled(!settings.showMenuBarExtra || settings.menuBarStyle == .iconOnly)

                    Picker("Menu bar format", selection: $settings.menuBarStyle) {
                        Text("Full").tag(MenuBarStyle.full)
                        Text("Compact").tag(MenuBarStyle.compact)
                        Text("Icon only").tag(MenuBarStyle.iconOnly)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!settings.showMenuBarExtra)

                    Text("Widgets can be added from the macOS widget gallery after setup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 320, alignment: .leading)

                MenuBarPreview(settings: settings)
                    .frame(maxWidth: 300)
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

            Spacer()
        }
    }

    private var ready: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 68))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: step)

            OnboardingHeading(
                title: "You're ready",
                subtitle: "Token Meter will detect local session logs and start updating automatically."
            )

            VStack(alignment: .leading, spacing: 12) {
                readyRow("Tracking", value: selectedProviderNames, systemImage: "checklist")
                readyRow(
                    "Menu bar",
                    value: settings.showMenuBarExtra ? "Shown" : "Hidden — Dock icon stays available",
                    systemImage: "menubar.rectangle"
                )
                readyRow("Privacy", value: "Local by default", systemImage: "lock.shield")
            }
            .padding(18)
            .frame(maxWidth: 520, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

            Text("If a provider needs attention, open the Setup tab for exact connection steps.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") { move(by: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
            }

            Spacer()

            Text(AppLocalization.format(
                "Step %d of %d",
                stepNumber,
                visibleSteps.count
            ))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(step.buttonTitle) {
                if step == .ready {
                    finish()
                } else {
                    move(by: 1)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(step == .providers && !hasSelectedProvider)
        }
        .frame(minHeight: 42)
    }

    private var hasSelectedProvider: Bool {
        settings.showClaudeCode || settings.showCodex || settings.showCopilotCli
    }

    private var selectedProviderNames: String {
        if settings.showClaudeCode && settings.showCodex {
            return AppLocalization.format("%@ and %@", "Claude", "Codex")
        }
        return settings.showClaudeCode ? "Claude" : "Codex"
    }

    /// The connection step is a real verification, so it shows whenever a provider is
    /// selected — each one reports connected (green) or the exact action to fix it.
    /// Its truth comes from live availability, not from whether a CLI is on PATH.
    private var visibleSteps: [Step] {
        Step.allCases.filter { $0 != .install || hasSelectedProvider }
    }

    private var stepNumber: Int {
        (visibleSteps.firstIndex(of: step) ?? step.rawValue) + 1
    }

    private var selectedProviders: [UsageProviderID] {
        UsageProviderID.allCases.filter { settings.enabledProviders().contains($0) }
    }

    private func move(by offset: Int) {
        let steps = visibleSteps
        guard let index = steps.firstIndex(of: step) else { return }
        let target = index + offset
        guard steps.indices.contains(target) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = steps[target] }
    }

    private func recheck() {
        guard !rechecking else { return }
        rechecking = true
        Task {
            await monitor.detectDataSources()
            await monitor.refresh(reason: .manual)
            rechecking = false
        }
    }

    private func finish() {
        settings.hasCompletedSetup = true
        MainWindowRouter.shared.selection = .dashboard
        NSApp.setActivationPolicy(settings.showMenuBarExtra ? .accessory : .regular)

        Task {
            await monitor.detectDataSources()
            await monitor.refresh(reason: .manual)
        }
    }

    private func readyRow(_ label: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(.tint)
            Text(LocalizedStringKey(label))
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(LocalizedStringKey(value))
                .fontWeight(.medium)
            Spacer()
        }
    }
}

private struct OnboardingHeading: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.largeTitle.weight(.bold))
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingUsageCard: View {
    let providerID: UsageProviderID
    let remaining: String
    let reset: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProviderLabel(providerID: providerID, font: .headline, iconSize: 18)
            Text(remaining)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("remaining · \(Text(reset))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.14))
        }
    }
}

private struct ProviderChoiceCard: View {
    let providerID: UsageProviderID
    let subtitle: LocalizedStringKey
    @Binding var isSelected: Bool

    var body: some View {
        Button { isSelected.toggle() } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ProviderIcon(providerID: providerID, size: 30)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                }

                Text(providerID.displayName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
            .background(
                isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.16), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(providerID.displayName)
        .accessibilityValue(Text(LocalizedStringKey(isSelected ? "Selected" : "Not selected")))
        .accessibilityHint(
            Text(AppLocalization.format(
                "Toggle whether %@ is displayed",
                providerID.displayName
            ))
        )
    }
}

/// Connection guidance for one provider that is not yet returning data. Unlike a
/// pure "is it installed?" check, this speaks to the actual availability — missing
/// tool, signed out, expired sign-in, blocked permission, or simply no logs yet —
/// so onboarding tells the truth about whether usage can be read. Mirrors the
/// verified steps in Setup.
private struct ConnectionStatusCard: View {
    let providerID: UsageProviderID
    let availability: ProviderAvailability?

    @State private var copied = false

    private var isConnected: Bool { availability?.isAvailable == true }

    private var showsClaudeSignIn: Bool {
        guard providerID == .claudeCode, case .notLoggedIn = availability else { return false }
        return true
    }

    /// The concrete next action for the current state. `nil` while availability is
    /// still being determined.
    private var instruction: LocalizedStringKey? {
        switch (providerID, availability) {
        case (_, .none):
            return "Checking…"
        case (_, .available):
            return nil
        case (.codex, .notInstalled):
            return "Install Codex with Homebrew, then sign in with `codex login` and run it once."
        case (.codex, .notLoggedIn):
            return "Codex is installed but signed out. Run `codex login`, then run Codex once."
        case (.codex, .noData):
            return "Codex is signed in but hasn't written a session log yet. Run Codex once."
        case (.claudeCode, .notInstalled):
            return "Install Claude Code and run it once. Token Meter needs no CLI on your PATH — it only reads the session logs."
        case (.claudeCode, .notLoggedIn):
            return "Claude Code's sign-in has expired. Open Claude Code, run /login to sign in again, then Re-check."
        case (.claudeCode, .noData):
            return "Claude Code is present but hasn't written a session log yet. Start a session, then Re-check."
        case (.copilotCli, .notInstalled):
            return "Install GitHub Copilot CLI and run it once. Token Meter needs no CLI on your PATH — it only reads the session logs."
        case (.copilotCli, .noData):
            return "Copilot CLI is present but hasn't written a session log yet. Run a session and end it, then Re-check."
        case (_, .permissionDenied):
            return "macOS is blocking access. Grant Token Meter access in System Settings > Privacy & Security, then Re-check."
        default:
            return "Not connected yet. Follow the steps in Setup, then Re-check."
        }
    }

    private var command: String? {
        switch (providerID, availability) {
        case (.codex, .notInstalled): return "brew install --cask codex"
        case (.codex, .notLoggedIn): return "codex login"
        case (.claudeCode, .notLoggedIn): return "claude"
        case (.copilotCli, .notInstalled): return "npm install -g @github/copilot"
        default: return nil
        }
    }

    private var url: URL? {
        switch providerID {
        case .codex: return URL(string: "https://github.com/openai/codex")
        case .claudeCode: return URL(string: "https://claude.com/claude-code")
        case .copilotCli: return URL(string: "https://github.com/github/copilot-cli")
        }
    }

    private var statusLabel: LocalizedStringKey {
        LocalizedStringKey(availability?.headline ?? "Checking…")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProviderIcon(providerID: providerID, size: 22)
                Text(providerID.displayName)
                    .font(.headline)
                Spacer()
                Image(systemName: isConnected ? "checkmark.circle.fill" : (availability?.symbolName ?? "arrow.down.circle"))
                    .foregroundStyle(isConnected ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isConnected {
                Label("Connected — usage is coming through.", systemImage: "checkmark.seal")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else if let instruction {
                Text(instruction)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                if showsClaudeSignIn { ClaudeSignInButton() }

                HStack(spacing: 8) {
                    if let command {
                        Text(command)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                            .textSelection(.enabled)

                        Button(AppLocalization.string(copied ? "Copied" : "Copy")) {
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

                    if let url {
                        Link("Learn more", destination: url)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.14))
        }
    }
}

private struct MenuBarPreview: View {
    let settings: AppSettings

    var body: some View {
        VStack(spacing: 14) {
            Text("Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                if !settings.showMenuBarExtra {
                    Text("Menu bar item hidden")
                        .foregroundStyle(.secondary)
                } else {
                    if settings.showMenuBarIcon || settings.menuBarStyle == .iconOnly {
                        Image(systemName: "gauge.with.dots.needle.33percent")
                    }
                    if settings.menuBarStyle == .compact {
                        compactPreview
                    } else if settings.menuBarStyle != .iconOnly {
                        Text(previewTitle)
                            .monospacedDigit()
                    }
                }
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(Color.primary.opacity(0.08), in: Capsule())
        }
        .frame(maxWidth: .infinity, minHeight: 130)
    }

    private var previewTitle: String {
        var parts: [String] = []
        if settings.showClaudeCode {
            parts.append("Claude 68%")
        }
        if settings.showCodex {
            parts.append("Codex 42%")
        }
        return parts.joined(separator: " · ")
    }

    private var compactPreview: some View {
        HStack(spacing: 6) {
            if settings.showClaudeCode {
                HStack(spacing: 2) {
                    MenuBarProviderIcon(providerID: .claudeCode)
                    Text("68%")
                        .monospacedDigit()
                }
            }
            if settings.showCodex {
                HStack(spacing: 2) {
                    MenuBarProviderIcon(providerID: .codex)
                    Text("42%")
                        .monospacedDigit()
                }
            }
        }
    }
}
