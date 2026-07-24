import SwiftUI
import TokenMeterCore

/// The settings form shown in the main window's Settings tab. The standard ⌘,
/// command routes here instead of opening a separate Settings window.
struct SettingsView: View {
    let monitor: UsageMonitor
    @State private var settings = AppSettings.shared
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Language") {
                AppLanguagePicker()
                // Only where the choice means something: English has no myriad words,
                // and an English UI formats as K/M/B whatever is stored here.
                if settings.appLanguage.supportsMyriadNotation {
                    TokenNotationPicker()
                }
            }

            Section("Providers") {
                Toggle(isOn: $settings.showClaudeCode) {
                    ProviderLabel(providerID: .claudeCode, font: .body, iconSize: 15)
                }
                Toggle(isOn: $settings.showCodex) {
                    ProviderLabel(providerID: .codex, font: .body, iconSize: 15)
                }
                Toggle(isOn: $settings.showCopilotCli) {
                    ProviderLabel(providerID: .copilotCli, font: .body, iconSize: 15)
                }
                .onChange(of: settings.showCopilotCli) { _, on in
                    guard on else { return }
                    Task {
                        await monitor.detectDataSources()
                        await monitor.refresh(reason: .manual)
                    }
                }
                Text("GitHub Copilot CLI counts tokens only, and its models overlap Claude Code — enable it if you use Copilot in the terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Setup") {
                Button("Run the setup guide again") {
                    settings.hasCompletedSetup = false
                    MainWindowRouter.shared.selection = .dashboard
                }
                Text("Reopens the welcome flow, including command-line tool installation steps for any provider that isn't set up yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Claude Pro / Max usage") {
                Toggle("Use Claude Code sign-in for usage checks", isOn: $settings.claudeOAuthUsageEnabled)
                    .onChange(of: settings.claudeOAuthUsageEnabled) { _, _ in
                        Task {
                            await monitor.detectDataSources()
                            await monitor.refresh(reason: .manual)
                        }
                    }
                Label(
                    "When enabled, Token Meter reads Claude Code-credentials from macOS Keychain and sends the access token only to api.anthropic.com/api/oauth/usage. The token is never stored, logged, or included in the widget snapshot.",
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Text("This integration uses an OAuth endpoint that Anthropic may change without notice. Turn it off here at any time to stop Keychain and network access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Until a deliberate read has succeeded, macOS will raise its
                // Keychain dialog from whichever background refresh gets there
                // first. Offering the same read as a button puts the user in front
                // of it instead.
                if needsKeychainGrant {
                    ClaudeConnectButton(blocker: .keychainAccess) {
                        Task { await monitor.refresh(reason: .manual) }
                    }
                }
            }

            Section("Time windows") {
                Toggle("Show the 5-hour window", isOn: $settings.showFiveHourWindow)
                Toggle("Show the weekly window", isOn: $settings.showWeeklyWindow)
                Label(
                    "Token window rows are counted from local logs. Claude Pro / Max percentages and resets are shown separately and come from Anthropic when OAuth usage checks are enabled.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Refresh") {
                Picker("Interval", selection: $settings.refreshInterval) {
                    ForEach(AppSettings.refreshIntervalOptions, id: \.self) { seconds in
                        Text(intervalLabel(seconds)).tag(seconds)
                    }
                }
                .onChange(of: settings.refreshInterval) { _, _ in
                    monitor.refreshIntervalChanged()
                }
                Text("Logs are also watched for changes, so this is only a backstop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("Warn at 20% remaining", isOn: $settings.notifyAt20)
                Toggle("Warn at 10% remaining", isOn: $settings.notifyAt10)
                Toggle("Warn at 5% remaining", isOn: $settings.notifyAt5)
                Toggle("Notify when a quota resets", isOn: $settings.notifyOnReset)
                Toggle("Notify on data errors", isOn: $settings.notifyOnError)
                Label(
                    "Each threshold fires once per quota cycle. Claude alerts require the optional OAuth usage integration.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Widget") {
                Toggle("Show token counts", isOn: $settings.widgetShowTokens)
                Toggle("Show reset time", isOn: $settings.widgetShowReset)
                // Liquid Glass exists only on macOS 26+, so the choice is offered
                // there alone; older systems stay on the solid background.
                if #available(macOS 26.0, *) {
                    Picker("Widget background", selection: $settings.widgetBackgroundStyle) {
                        Text("Solid").tag(WidgetBackgroundStyle.solid)
                        Text("Clear (Liquid Glass)").tag(WidgetBackgroundStyle.clear)
                    }
                    .onChange(of: settings.widgetBackgroundStyle) { _, _ in
                        monitor.publishSnapshot()
                    }
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }

            Section("Updates") {
                LabeledContent("Version", value: appVersion)
                UpdaterSettingsView(updater: AppUpdater.shared.updater)
            }

            Section("Data") {
                Picker("Keep history for", selection: $settings.retentionDays) {
                    ForEach(AppSettings.retentionOptions, id: \.self) { days in
                        Text(AppLocalization.format("%d days", days)).tag(days)
                    }
                }
                LabeledContent("Stored events", value: "\(monitor.storedEventCount)")

                Button("Re-detect data sources") {
                    Task {
                        await monitor.detectDataSources()
                        await monitor.refresh(reason: .manual)
                    }
                }
                Button("Delete all history…", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                Text("Deleting removes stored token counts only. The CLI logs on disk are untouched, so history rebuilds on the next refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Diagnostics") {
                DisclosureGroup("Show diagnostic information") {
                    DiagnosticsContent(monitor: monitor)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 420)
        .confirmationDialog(
            "Delete all stored usage history?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { monitor.deleteAllHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    /// Offer the Keychain step until one deliberate read has worked — and again if
    /// a later refresh was denied, since the approval can be withdrawn in Keychain
    /// Access, or lost when the app is replaced by a differently signed build.
    private var needsKeychainGrant: Bool {
        guard settings.claudeOAuthUsageEnabled else { return false }
        if monitor.states[.claudeCode]?.snapshot?.quotaError == .keychainAccessDenied { return true }
        return !settings.claudeKeychainGranted
    }

    private func intervalLabel(_ seconds: TimeInterval) -> String {
        seconds < 3600
            ? AppLocalization.format("%d minutes", Int(seconds / 60))
            : AppLocalization.format("%d hour", Int(seconds / 3600))
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}

/// Exactly where the data comes from and what is missing — the first stop when a
/// number looks wrong.
struct DiagnosticsContent: View {
    let monitor: UsageMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            group("Storage") {
                row("Database", monitor.databasePath)
                row("Stored events", "\(monitor.storedEventCount)")
                row("Widget snapshot", monitor.snapshotPath)
                row(
                    "App Group",
                    monitor.usingAppGroup
                        ? AppLocalization.format("Active (%@)", TokenMeterPaths.appGroupID)
                        : AppLocalization.string("Unavailable — using a local fallback; the widget cannot read this")
                )
            }

            ForEach(UsageProviderID.allCases) { id in
                if let state = monitor.states[id] {
                    group(id.displayName) {
                        row("Status", AppLocalization.string(state.availability.headline))
                        row("Detail", AppLocalization.providerDetail(state.availability.detail))
                        row("Source", state.snapshot.map { AppLocalization.string($0.source.displayName) } ?? "—")
                        row("Publishes quota", AppLocalization.string(state.snapshot?.hasQuotaInformation == true ? "Yes" : "No"))
                        if id == .claudeCode {
                            row("OAuth usage", AppLocalization.string(state.snapshot?.quotaIntegrationEnabled == true ? "Enabled" : "Disabled"))
                            row("OAuth cache", AppLocalization.string(state.snapshot?.quotaIsCached == true ? "Cached" : "Current / unavailable"))
                            row(
                                "Quota updated",
                                state.snapshot?.quotaUpdatedAt?.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(AppLocalization.dateTimeLocale)) ?? AppLocalization.string("Never")
                            )
                        }
                        row("5-hour window", describe(state.snapshot?.shortWindowUsage))
                        row("Weekly window", describe(state.snapshot?.weeklyWindowUsage))
                        row("Model", state.snapshot?.modelName ?? "—")
                        row(
                            "Last update",
                            state.lastSuccessfulUpdate.map { $0.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(AppLocalization.dateTimeLocale)) } ?? AppLocalization.string("Never")
                        )
                        if let error = state.lastError {
                            row("Last error", error)
                        }
                        row("Path", id == .claudeCode
                            ? TokenMeterPaths.claudeProjects.path
                            : TokenMeterPaths.codexSessions.path)
                    }
                }
            }
        }
        .textSelection(.enabled)
        .padding(.vertical, 6)
    }

    /// Spells out where the window's edges came from, so a reported reset time and an
    /// estimated one can never be mistaken for each other while debugging.
    private func describe(_ usage: TokenWindowUsage?) -> String {
        guard let usage else { return "—" }
        var text = AppLocalization.format(
            "%d tokens since %@",
            usage.tokens,
            usage.start.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(AppLocalization.dateTimeLocale))
        )
        if let resetsAt = usage.resetsAt {
            let origin = AppLocalization.string(usage.boundary == .reported ? "reported" : "estimated")
            text += AppLocalization.format(
                ", resets %@ (%@)",
                resetsAt.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(AppLocalization.dateTimeLocale)),
                origin
            )
        } else {
            text += AppLocalization.string(", rolling (no reset)")
        }
        return text
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.caption)
                .monospaced()
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}
