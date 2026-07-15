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
            Section("Providers") {
                Toggle(isOn: $settings.showClaudeCode) {
                    ProviderLabel(providerID: .claudeCode, font: .body, iconSize: 15)
                }
                Toggle(isOn: $settings.showCodex) {
                    ProviderLabel(providerID: .codex, font: .body, iconSize: 15)
                }
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

            Section("Menu bar") {
                Toggle("Show Token Meter in the menu bar", isOn: $settings.showMenuBarExtra)
                Picker("Format", selection: $settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .disabled(!settings.showMenuBarExtra)

                Toggle("Show Meter icon", isOn: $settings.showMenuBarIcon)
                    .disabled(!settings.showMenuBarExtra || settings.menuBarStyle == .iconOnly)

                Toggle("Show usage percentage", isOn: $settings.menuBarShowPercentage)
                    .disabled(!settings.showMenuBarExtra || settings.menuBarStyle == .iconOnly)
                Toggle("Show today's token count", isOn: $settings.menuBarShowTokens)
                    .disabled(!settings.showMenuBarExtra || settings.menuBarStyle == .iconOnly)
                Toggle("Show the next 5-hour reset", isOn: $settings.menuBarShowReset)
                    .disabled(!settings.showMenuBarExtra || settings.menuBarStyle == .iconOnly)

                LabeledContent("Preview") {
                    MenuBarLabel(monitor: monitor)
                        .font(.callout)
                }
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
                        Text("\(days) days").tag(days)
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

    private func intervalLabel(_ seconds: TimeInterval) -> String {
        seconds < 3600
            ? "\(Int(seconds / 60)) minutes"
            : "\(Int(seconds / 3600)) hour"
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
                        ? "Active (\(TokenMeterPaths.appGroupID))"
                        : "Unavailable — using a local fallback; the widget cannot read this"
                )
            }

            ForEach(UsageProviderID.allCases) { id in
                if let state = monitor.states[id] {
                    group(id.displayName) {
                        row("Status", state.availability.headline)
                        row("Detail", state.availability.detail)
                        row("Source", state.snapshot?.source.displayName ?? "—")
                        row("Publishes quota", state.snapshot?.hasQuotaInformation == true ? "Yes" : "No")
                        if id == .claudeCode {
                            row("OAuth usage", state.snapshot?.quotaIntegrationEnabled == true ? "Enabled" : "Disabled")
                            row("OAuth cache", state.snapshot?.quotaIsCached == true ? "Cached" : "Current / unavailable")
                            row(
                                "Quota updated",
                                state.snapshot?.quotaUpdatedAt?.formatted(date: .abbreviated, time: .standard) ?? "Never"
                            )
                        }
                        row("5-hour window", describe(state.snapshot?.shortWindowUsage))
                        row("Weekly window", describe(state.snapshot?.weeklyWindowUsage))
                        row("Model", state.snapshot?.modelName ?? "—")
                        row(
                            "Last update",
                            state.lastSuccessfulUpdate.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "Never"
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
        var text = "\(usage.tokens) tokens since \(usage.start.formatted(date: .abbreviated, time: .standard))"
        if let resetsAt = usage.resetsAt {
            let origin = usage.boundary == .reported ? "reported" : "estimated"
            text += ", resets \(resetsAt.formatted(date: .abbreviated, time: .standard)) (\(origin))"
        } else {
            text += ", rolling (no reset)"
        }
        return text
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
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
