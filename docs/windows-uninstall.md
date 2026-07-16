# Token Meter for Windows — installation and uninstallation

## Changes made during installation

Both the Microsoft Store package and `TokenMeterSetup.exe` install the same type
of per-user MSIX package. Installation:

- registers Token Meter in **Settings > Apps > Installed apps**;
- installs the app files in Windows-managed package storage;
- creates a private LocalState directory when the app first runs;
- makes an optional **Start Token Meter when I sign in** task available, but
  leaves it disabled until the user enables it in Token Meter Settings; and
- does not modify `PATH`, install a Windows service or driver, add a firewall
  rule, or change Claude Code, Codex, or Copilot CLI files.

The installer may close a running Token Meter process when updating the MSIX.
Claude online usage lookup is disabled by default and is never enabled by the
installer.

## Uninstall

1. Exit Token Meter from its notification-area menu.
2. Open **Windows Settings > Apps > Installed apps**.
3. Find **Token Meter**, open its menu, and select **Uninstall**.
4. Confirm the Windows prompt.

Normal MSIX removal unregisters the optional startup task and removes Token
Meter's package files and LocalState, including its settings and local SQLite
history. It does not remove or modify the source CLI logs under `.claude`,
`.codex`, or `.copilot`.

If Windows cannot remove the package through Settings, run the following command
for the current user in PowerShell:

```powershell
Get-AppxPackage | Where-Object { $_.Name -eq "com.tokenmeter.windows" } | Remove-AppxPackage
```

Store-associated and direct-distribution identities may differ. In that case,
use Windows Settings so the correct installed identity is selected.
