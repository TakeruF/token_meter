# Windows dependency and asset audit

Audit date: 2026-07-16
Scope: Windows `1.3.0` source, MSIX, and `TokenMeterSetup.exe`

## Runtime dependencies

| Component | Version | License / terms | Distribution decision |
|---|---:|---|---|
| .NET runtime | 10.x | MIT and .NET Library licenses | Included only by the self-contained direct build; permitted redistributable. |
| Microsoft.WindowsAppSDK | 2.2.0 | Microsoft Software License Terms | Store build uses the framework package; the direct build uses the supported self-contained redistribution mode. |
| Microsoft.Data.Sqlite.Core | 10.0.10 | MIT | Included. |
| SQLitePCLRaw bundle/provider/core/config | 3.0.2 | Apache-2.0 | Included. |
| SourceGear.sqlite3 / SQLite | 3.50.4.2 | SQLite public domain dedication and blessing | Native SQLite binary included by SQLitePCLRaw. |

Exact direct and transitive package versions and content hashes are committed in
the six `packages.lock.json` files under `Windows/`. Release restore uses locked
mode and fails if a dependency would change.

Test-only packages (`xunit`, `Microsoft.NET.Test.Sdk`, and their dependencies)
and build-only Windows SDK packages are not shipped as application runtime
components. Their versions remain locked for reproducible CI.

## Assets and trademarks

- Windows package icons (`TokenMeter.ico`, StoreLogo, Square44x44Logo, and
  Square150x150Logo) are Token Meter project assets.
- Claude, Codex, Copilot, Anthropic, OpenAI, GitHub, and Microsoft names are used
  only to identify compatible products. Token Meter is not affiliated with or
  endorsed by those vendors.
- Third-party Claude and Codex logo files are not linked into or distributed in
  the Windows binaries. Provider names are rendered as text.

The notices required for redistributed components are maintained in
[`THIRD-PARTY-NOTICES.md`](../THIRD-PARTY-NOTICES.md). Dependency or asset
changes must update this audit before a release is approved.
