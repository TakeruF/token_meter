# Token Meter

**English** · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [한국어](README.ko.md)

A native macOS / Windows app for keeping an eye on Claude Code, Codex, and Copilot CLI usage.

[<img src="https://raw.githubusercontent.com/machiav3lli/oandbackupx/main/badge_github.png" alt="Get it on GitHub" height="60">](https://github.com/TakeruF/token_meter/releases/latest) [<img src="assets/badges/download-from-website.png" alt="Download from Website" height="60">](https://takeruf.github.io/token_meter/)

[Website · Download](https://takeruf.github.io/token_meter/) · [GitHub Releases](https://github.com/TakeruF/token_meter/releases/latest)

## Screenshots

**Menu bar and widgets — usage at a glance.**

![A Mac showing the Token Meter menu bar popover and widgets with Claude and Codex usage](docs/screenshots/promo-at-a-glance.jpg)

**The dashboard breaks usage down by day and by model.**

![The Token Meter dashboard showing daily trends, a token breakdown, and per-model usage](docs/screenshots/promo-dashboard.jpg)

**Available in English, Japanese, Chinese, and Korean.**

![The Token Meter settings screen with the English, Japanese, Chinese, and Korean language picker open](docs/screenshots/promo-languages.jpg)

## Code signing policy

The signing authority, approval procedure, maintainers, and privacy terms for the direct-download
Windows build are published in the [Code signing policy](CODE_SIGNING.md). The application to the
SignPath Foundation is still in preparation, and binaries are not presented as SignPath-signed
before that approval.

macOS is Swift / SwiftUI / WidgetKit; Windows is C# / .NET 10 / WinUI 3. No WebView, no Electron.
Token history is aggregated locally. Only when you explicitly enable it does the app talk to
Anthropic's OAuth usage endpoint to check Claude Pro / Max usage.

---

## ⚠️ Read this first — what this app can and cannot show

Findings from testing against real logs (details in [docs/data-sources.md](docs/data-sources.md)):

| | Claude Code | Codex | Copilot CLI |
|---|---|---|---|
| Token usage (input / cache / output) | ✅ | ✅ | ✅ at session end |
| Reasoning tokens | ❌ not separated | ✅ | ❌ not reported |
| Model used | ✅ | ✅ | ✅ |
| History and daily totals | ✅ | ✅ | ✅ |
| **Tokens in the 5-hour window** | ⚠️ measured (window boundary estimated) | ✅ only when Codex reports a 5h window | ❌ no such concept |
| **Tokens in the weekly window** | ⚠️ measured (rolling last 7 days) | ✅ the real weekly window | ❌ |
| **Usage percentage** | ✅ when the OAuth integration is on | ✅ | ❌ not available locally |
| **Remaining allowance** | ✅ when the OAuth integration is on | ✅ | ❌ |
| **Window reset time** | ✅ when the OAuth integration is on (local value is an estimate) | ✅ as reported | ❌ |
| Context window size | ❌ unavailable | ✅ | ❌ |

**Claude Code does not write usage percentage, remaining allowance, or reset time to its local logs.**
The `claude` CLI has no `usage` subcommand (every command in `--help` was checked), and `/usage` is
only a slash command inside an interactive session. The configuration files hold no such values either.

When you turn on the Claude OAuth usage check in Settings, the app reads `Claude Code-credentials`
from the macOS Keychain through the Security framework and calls
`GET https://api.anthropic.com/api/oauth/usage` for the 5-hour, 7-day, and optional Sonnet 7-day
windows. When the integration is off or the call fails, no estimated percentage is shown.

### Why "pick your plan and show a percentage" is not possible

Anthropic **does not publish per-plan token limits**. The limits are described as varying with
conversation length, complexity, model, and effort, so there is no fixed number. On top of that,
(1) Opus counts several times more than Sonnet (the multiplier is not published), and
(2) the allowance is shared with claude.ai (web / desktop / mobile), so usage on other machines
consumes the same budget.

There is no denominator, and the numerator (this Mac's Claude Code logs) is incomplete, so the app
never computes a percentage from local values. The only percentages shown are the ones contained in
Anthropic's usage response.

### What is shown instead (all measured)

| | Contents | Reset time |
|---|---|---|
| Claude Code · 5-hour window | Tokens in the current session block | ⚠️ **estimated** (see below) |
| Claude Code · last 7 days | Rolling 7-day total | None (the weekly start point is unknown) |
| Codex · 5-hour / weekly window | Tokens consumed inside that window | ✅ as reported by Codex |
| Copilot CLI · today / history | Per-model token counts finalized at session end | None (no published allowance) |

Anthropic states that "the 5-hour session window starts with your first message and lasts 5 hours."
Claude Code's 5-hour reset time here is **that rule reproduced against local logs**, not a value
Anthropic emitted. The UI always labels it *estimated* and notes that it is "counted from this Mac's
Claude logs only."

Codex writes `rate_limits` (`used_percent` / `resets_at` / `window_minutes`) to its logs, so usage
percentage, remaining allowance, and reset time can all be shown as real data. The window start is
also determined as `resets_at - window_minutes`, which makes the in-window token count measured too.

Copilot CLI publishes no allowance locally, so no percentage, remaining allowance, or reset time is
shown. Token counts come from the per-model cumulative values in the `session.shutdown` event, so
they **appear once you end a session** (a running session is not counted yet).

Each of these rows can be turned off individually under **Settings > Time windows**.

---

## Requirements

| | |
|---|---|
| macOS | 14.0 or later (developed and verified on macOS 26.5) |
| Xcode | 15 or later (verified on Xcode 26.2) |
| Swift | 5.9 or later (verified on 6.2.3) |
| Project generator | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) |
| Windows | Windows 11 x64 (Windows v1) |
| Windows SDK | .NET 10 LTS / Windows App SDK Stable / WinUI 3 |

The Windows app is a separate solution under `Windows/`. It supports the notification area,
dashboard, settings, notifications, English / Japanese / Simplified Chinese / Korean, and
Claude Code / Codex / Copilot CLI. Besides the Microsoft Store MSIX, it can also produce
`TokenMeterSetup.exe` with a Trusted Signing MSIX bundled inside. See
[Windows/README.md](Windows/README.md) for building, signing, and pre-submission verification.

For how to uninstall the Windows build and what system changes the installer makes, see
[Windows installation and uninstallation](docs/windows-uninstall.md).

## Building

```bash
# 1. Generate the Xcode project (from project.yml)
xcodegen generate

# 2. Build
open TokenMeter.xcodeproj    # then ⌘R in Xcode

# or from the command line
xcodebuild -project TokenMeter.xcodeproj -scheme TokenMeter \
  -configuration Debug -destination 'platform=macOS' build
```

### Signing (required if you want the widget)

`project.yml` sets Developer Team `B97M43J5TT` and automatic signing. Both targets use the App Group
`group.com.tokenmeter.b97m43j5tt.shared`.

For the first build, add your Apple Account to Xcode and allow provisioning profiles to be created:

```bash
xcodebuild -project TokenMeter.xcodeproj -scheme TokenMeter \
  -configuration Debug -destination 'platform=macOS' \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
```

A local build with signing disabled cannot use the App Group; only the main app falls back to a local
directory. You can check which is in effect under **Settings > Diagnostics**
(`App Group: Active` / `Unavailable`).

### Developer ID distribution

Release archiving, Developer ID signing, notarization, and building the distribution ZIP are scripted.

```bash
# Test, archive, sign with Developer ID, and upload to the Notary Service
./scripts/release.sh prepare

# After Apple approves notarization, export the stapled app and ZIP
./scripts/release.sh finish
```

The output is `build/TokenMeter-<version>.zip`. Unzip it and move `TokenMeter.app` to `/Applications`.
If you distribute a DMG, sign and notarize the final DMG container as well, not just the app.
See [docs/privacy.md](docs/privacy.md) for the privacy policy.

### In-app updates

Sparkle 2 checks for updates automatically while the app runs. When an update is available you can
read the release notes in the standard update window, download the signed ZIP, and replace the app.
Manual checks are available from Settings > Updates or `Check for Updates…` in the app menu.

The update feed is `appcast.xml` at the repository root, and the distribution ZIPs live in GitHub
Releases. `./scripts/release.sh finish` signs the ZIP with the Sparkle EdDSA key in the Keychain
(account: `com.tokenmeter.app`) and updates `appcast.xml`. The private key is never stored in the
repository.

For each release, bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` (the value Sparkle compares)
before running the script. Afterwards, do two things:

1. Upload `build/TokenMeter-<version>.zip` to the GitHub Release for the `v<version>` tag
2. Commit and push the updated `appcast.xml` to `main`

## Tests

The parser and store tests live in the Swift package.

```bash
swift test --package-path TokenMeterCore
# 111 tests, 0 failures
```

What is covered:

- Claude Code / Codex / Copilot CLI parsers (using anonymized fixtures built from real logs)
- **Time windows** (5-hour block boundaries, hiding expired windows, deriving a reported window's
  start time, not attaching a reset time to rolling windows, and keeping the estimated/reported
  distinction intact across the widget JSON)
- **Deduplication** (repeated Claude Code messages, identical Codex events)
- **Cumulative token deltas** (no double counting when a session resumes, counter resets)
- **Claude OAuth usage lookups** (shape changes in the Keychain JSON, expired tokens, classification
  of 401/403/429/500, network loss, and API format changes, in-memory caching and coalescing of
  concurrent requests, and the absence of credentials in the widget JSON)
- **Allowance reset detection** (not mistaking a 5-hour rollover for a weekly one, not treating
  consumption or a first observation as a reset)
- Incomplete JSON / unknown fields / empty files / corrupt JSONL
- Date rollover and time zone handling (UTC logs → local dates)
- Reading and writing the widget JSON (concurrent writes, corrupt files)
- Missing data sources and incremental reads

The fixtures are generated from real data, but **prompt bodies, response bodies, credentials, and
personal information are completely stripped**
(`TokenMeterCore/Tests/TokenMeterCoreTests/Fixtures/`).

The Windows tests live on the .NET side under `Windows/` and share the same anonymized fixtures.
See [Windows/README.md](Windows/README.md) for how to run them.

## Getting set up

The setup screen opens on first launch (and any time from Token Meter in the menu bar → Dashboard →
Setup).

- Connection status for each provider, with concrete fixes when a provider is not connected
  (commands are copyable)
- Whether to show in the menu bar, the display style, and which items to show
- An explicit statement of what is being read

### Connecting Claude Code

**No configuration needed.** If you have used Claude Code even once, it is detected automatically.

- Reads: `~/.claude/projects/<project>/<session-id>.jsonl`
- Works even if the `claude` CLI is not on your PATH (only log files are read)
- If nothing appears, run one session in Claude Code

### Connecting Codex

- Reads: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`
- If not installed: `brew install --cask codex`
- If not signed in: `codex login`
- After signing in, run Codex once so logs are written and the usage percentage appears

**The credential file (`~/.codex/auth.json`) is never opened.** Sign-in is determined by checking
that the file exists, nothing more.

### Connecting Copilot CLI

- Reads: `~/.copilot/session-state/<session-id>/events.jsonl`
- If not installed: `npm install -g @github/copilot`
- Works even if the `copilot` CLI is not on your PATH (only session logs are read)
- Token counts are written on `session.shutdown`, so **end one session** for them to appear
- Copilot does not publish its allowance locally, so no percentage, remaining allowance, or reset
  time is shown

### Adding the widget

1. Launch the app once (so a snapshot is written)
2. Right-click the desktop → "Edit Widgets"
3. Pick Token Meter and choose Small / Medium / Large
4. Clicking the widget opens the app's dashboard

The widget **never reads logs directly**. It only reads the JSON snapshot the main app wrote to the
App Group.

| Size | Contents |
|---|---|
| Small | Claude / Codex remaining (or token counts) and the last update time |
| Medium | Progress bars, time until the next 5-hour reset, today's tokens |
| Large | The above plus 5-hour / today / weekly (or last 7 days) tokens and a compact chart |

Estimated reset times are marked `est.` in the widget too.

## Where data is stored

| Data | Location |
|---|---|
| History database (SQLite) | `~/Library/Application Support/TokenMeter/history.sqlite` |
| Widget snapshot | `~/Library/Group Containers/group.com.tokenmeter.b97m43j5tt.shared/snapshot.json` |
| (when the App Group is unavailable) | `~/Library/Application Support/TokenMeter/snapshot.json` |
| Settings | UserDefaults |

The snapshot is written to a temporary file and swapped in atomically, so a write in progress cannot
corrupt it.

## Security policy

- **No credentials are stored.** Nothing is written to the database or to UserDefaults
- Only when the Claude integration is enabled does the app read `Claude Code-credentials` via the
  Security framework's `SecItemCopyMatching` and send the access token to Anthropic's fixed endpoint
  and nowhere else
- **CLI credential files are never read or copied.** `~/.codex/auth.json` is only checked for
  existence; its contents are never opened
- **Prompt and response bodies are never stored.** Only fields equivalent to `usage` / `token_count`
  are parsed
- What is stored is **token counts, timestamps, model names, usage percentages, and reset times** —
  nothing else
- Nothing is sent externally other than the Claude OAuth usage lookup and the app update check
  against GitHub. No analytics, no crash reporting
- File access is limited to `~/.claude/projects`, `~/.codex/sessions`, `~/.copilot/session-state`,
  and the Keychain item when the optional integration is enabled
- No secrets are written to logs
- The widget runs sandboxed and can only read the App Group JSON

The main app has App Sandbox disabled. `~/.claude`, `~/.codex`, and `~/.copilot` live outside the
sandbox container and must be readable. Writes go only to its own Application Support directory and
the App Group.

Token Meter never writes credentials to the Keychain. It reads the item Claude Code stored, and only
for the duration of a usage lookup.

### Keychain / sandbox / distribution constraints

- The current main target uses `ENABLE_APP_SANDBOX=NO` and specifies no Keychain access group.
  In the direct-download build, a generic password item can be queried with `SecItemCopyMatching`,
  but depending on the item's ACL macOS may prompt on first access, or deny it.
- The widget is sandboxed but touches neither the Keychain nor the network; it only reads the App
  Group snapshot the main app wrote with credentials excluded.
- With the sandbox enabled, items created by Claude Code generally cannot be read, because the app
  shares neither a signing team nor a Keychain access group with Claude Code. The app does not
  silently disable the sandbox as a fallback.
- A Mac App Store build effectively requires the sandbox, and the same constraint applies to the
  current local log reading, so shipping this style of Claude integration there is not realistic.
  Unless Anthropic provides an official API, a shared access group, or safe IPC, a directly
  distributed non-sandboxed build is the practical arrangement.
- Manual token entry will not be implemented. A sandboxed build would need either a signed
  non-sandboxed helper that the user launches explicitly, or an official local integration on the
  Claude Code side; neither is adopted at this point.

## When data refreshes

| Trigger | Implementation |
|---|---|
| App launch | `applicationDidFinishLaunching` |
| CLI log changes | FSEvents (3-second debounce) |
| On an interval | Timer (5 minutes by default, 1 minute minimum) |
| Manual refresh | The refresh button in the menu bar / dashboard |
| Waking from sleep | `NSWorkspace.didWakeNotification` |
| Date change | `NSCalendarDayChanged` |

Refreshes are serialized, never concurrent, and time out. Logs are read **append-only** (file offsets
are persisted), so every read after the first is cheap. Successful Claude OAuth values are cached in
memory for 5 minutes, and on failure the previous value and its timestamp are kept.

## Troubleshooting

**Nothing appears in the menu bar**
→ First check Settings > Menu bar > "Show Token Meter in the menu bar". Turning it off switches to a
Dock icon instead (so you can never lock yourself out of the window).

→ If it is on but still invisible, the likely cause is that **macOS is hiding the item because the
menu bar is out of room**. This happens on notched Macs when the frontmost app has many menus. As
verified on a real machine, the status item itself does exist in this state (`NSStatusBarWindow` is
placed at off-screen coordinates). Click `•••` in the menu bar, or reduce the number of menu bar apps.
Switching the display style to Compact or Icon only narrows the item and can help.

**No Claude Code usage percentage**
→ Enable the OAuth usage check under Settings > Claude Pro / Max usage and confirm you are signed in
to Claude Code. Keychain denial, 401/403, rate limiting, being offline, and API format changes are
reported distinctly on screen. Even with the integration off, local token counts for the 5-hour
window and last 7 days are still shown.

**The Claude Code 5-hour reset time looks wrong**
→ It may well be. That time is not a value Anthropic emitted; it is **an estimate produced by
applying the published rule ("a session starts with your first message and lasts 5 hours") to this
Mac's logs** (labeled *estimated* in the UI). If the window actually started from claude.ai in a
browser or from Claude Code on another machine, this estimate will be later than reality. For the
accurate value, use `/usage` inside Claude Code.

**No Codex 5-hour window**
→ Codex does not always include a 5-hour window in `rate_limits` (some sessions report only the
weekly one). When it is not reported, the app does not guess — it hides the row.

**No Codex usage percentage**
→ Check that you have run `codex login` and used Codex at least once. The Setup screen shows the
specific fix.

**No Copilot CLI token counts**
→ Check that you have **ended** a session at least once. Copilot only finalizes token counts in the
`session.shutdown` event, so a running session is not reflected. The absence of percentage and reset
time rows for Copilot is by design (they do not exist in the local logs).

**No data in the widget**
→ The App Group requires signing. If Settings > Diagnostics shows `App Group: Unavailable`, set a
development team in Xcode and rebuild.

**The numbers look stale**
→ More than an hour after the last refresh, the app says "Data may be outdated" explicitly. Stale
data is never presented as current.

**Something looks off, or you doubt a number**
→ Settings > Diagnostics lists the database path, snapshot path, detection status for each provider,
the paths being read, the last update time, and the most recent errors.

## Layout

```
TokenMeterCore/          Swift package (UI-independent, the tested part)
  Models/                UsageSnapshot, UsageWindow, UsageEvent, TokenWindowUsage, availability, errors
  Parsing/               ClaudeCodeLogParser, CodexLogParser, CopilotLogParser, incremental JSONL reader
  Providers/             The UsageProvider protocol, three implementations, Claude OAuth usage lookup
  Persistence/           UsageStore (SQLite), SharedSnapshotStore (App Group)
  Aggregation/           Daily and per-model aggregation
  Monitoring/            FSEvents directory watching
  Support/               Path definitions, allowance reset detection, warning levels from remaining usage
TokenMeterApp/           Menu bar, dashboard, settings, notifications (en / ja / zh-Hans / ko)
TokenMeterWidget/        Small / Medium / Large
Windows/                 The Windows app (C# / .NET 10 / WinUI 3, separate solution)
docs/data-sources.md     Data source investigation results
docs/claude-sign-in.md   Manual Claude Code sign-in and Keychain approval steps
docs/release-runbook.md  macOS release procedure
```

Data collection, log parsing, and UI are kept separate. The widget shares only Core's models and
never touches logs. The Windows app does not depend on the macOS sources; it shares only the
anonymized fixtures.

## Known limitations

- Claude usage depends on a private OAuth endpoint and on Claude Code's credential format, and may
  stop working without notice
- Depending on the Keychain item's access control, even the non-sandboxed direct-download build may
  need user approval, or re-approval after re-signing
- Claude Code's 5-hour window boundary is an **estimate**, and usage on claude.ai or on other
  machines is invisible. The token counts themselves are measured, but they total "this Mac's
  Claude Code usage only"
- The Codex 5-hour window is shown only for sessions where Codex included it in `rate_limits`
- Copilot CLI finalizes token counts only at session end, so running sessions are not reflected.
  Because it publishes no allowance locally, percentage, remaining allowance, and reset time cannot
  be shown either
- The widget shows only Claude Code and Codex; Copilot CLI appears only in the main app (menu bar
  and dashboard)
- The first launch reads all logs and takes a few seconds (measured: about 4 seconds for ~680 MB of
  logs). Subsequent launches read only the delta
- macOS hides the menu bar item when there is no room (see troubleshooting above)
- App Group container creation and snapshot writing are verified with the Developer ID-signed,
  notarized app. Final widget rendering on the desktop still needs a distribution test on a
  different Mac
- Visually verified: the menu bar item, popover, dashboard, and Setup screen (both light and dark
  mode). The time window rows (5-hour and weekly) have been verified on a real machine in dark mode
  only; light mode is unverified

## Contributing and reporting

| | |
|---|---|
| Pull requests | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Code of conduct | [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) |
| Reporting vulnerabilities | [SECURITY.md](SECURITY.md) (use GitHub private reporting, not a public issue) |

Do not include personal information — prompt bodies, response bodies, credentials, real paths — in
issues, pull requests, or fixtures.

## License

Apache License 2.0. See [LICENSE](LICENSE) for the full text.

```
Copyright 2026 Takeru Fujii

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

"Token Meter" is a trademark of Takeru Fujii, and under section 6 of the Apache License 2.0 this
license does not grant permission to use it. Forks and derivative works must use a different name.

Copyright notices and licenses for the third-party components bundled in the binary (Sparkle and
others) are in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). Include [NOTICE](NOTICE) when
redistributing (Apache License 2.0, section 4(d)).

Token Meter is not affiliated with or endorsed by Anthropic, OpenAI, GitHub, or Microsoft.
