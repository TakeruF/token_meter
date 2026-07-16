# Token Meter for Windows

Windows 11 x64向けのToken Meter実装です。C# / .NET 10 / WinUI 3で構成し、macOS版のソースには依存しません。匿名化済みJSONL fixtureだけを両プラットフォームのテストで共有します。

## Code signing policy

直接配布の署名元、公開ビルドの検証方法、担当者と承認手順は
[リポジトリのCode signing policy](../CODE_SIGNING.md)に従います。SignPath Foundationの承認前は
SignPath署名を称しません。依存関係とアセットの確認記録は
[Windows dependency and asset audit](../docs/windows-dependency-audit.md)にあります。

## 構成

| プロジェクト | 役割 |
|---|---|
| `src/TokenMeter.Windows.Core` | モデル、JSONL増分読み取り、3プロバイダーのパーサー、集計、SQLite、Claude利用枠照会、監視 |
| `src/TokenMeter.Windows.App` | WinUI 3、通知領域、ダッシュボード、設定、App Notifications、StartupTask、4言語リソース、MSIX |
| `src/TokenMeter.Windows.Setup` | 署名済みMSIXを内包して現在のユーザーへ導入する、自己完結型の`TokenMeterSetup.exe` |
| `tests/TokenMeter.Windows.Core.Tests` | macOS版と共有する匿名化fixtureを使ったxUnitテスト |
| `tests/TokenMeter.Windows.Setup.Tests` | Setupに埋め込むMSIX manifestの検証テスト |

## 必要環境

- Windows 11 x64（10.0.22000以降）
- Visual Studio 2026または.NET 10 SDKとWindows App SDK用ビルドツール
- Visual Studioでは「.NETデスクトップ開発」と「Windowsアプリケーション開発」ワークロード

Windows App SDKは`Microsoft.WindowsAppSDK 2.2.0`（2026年7月16日時点のStable）へ固定しています。Preview版は使いません。

## ビルドとテスト

PowerShellでリポジトリのルートから実行します。

```powershell
dotnet restore Windows\TokenMeter.Windows.slnx -r win-x64
dotnet test Windows\tests\TokenMeter.Windows.Core.Tests\TokenMeter.Windows.Core.Tests.csproj -c Release
dotnet test Windows\tests\TokenMeter.Windows.Setup.Tests\TokenMeter.Windows.Setup.Tests.csproj -c Release
dotnet build Windows\src\TokenMeter.Windows.App\TokenMeter.Windows.App.csproj -c Release -p:Platform=x64
dotnet build Windows\src\TokenMeter.Windows.Setup\TokenMeter.Windows.Setup.csproj -c Release -p:Platform=x64
```

CoreのxUnitテストは98ケースです。パーサー、累積差分、重複排除、時間枠、タイムゾーン、SQLite、カーソル復元、ファイル切り詰め・置換、Claude資格情報とHTTPエラー分類を対象にしています。`TokenMeter.Windows.App.CompileCheck`はmacOS/Linux CIでもWinUIコードビハインドのC# API整合性を検証する補助プロジェクトで、Windows CIではこれに加えて実際のXAMLコンパイルを行います。

Store提出用パッケージはGitHub Actionsの`Windows`ワークフローを手動実行して生成します。提出前にPartner Centerでアプリ名を予約し、Visual Studioの「Microsoft Storeとアプリを関連付ける」で`Package.appxmanifest`の一時Identity/PublisherをStoreの値へ置換してください。「Token Meter」を予約できない場合は、manifestとStore listingの表示名を「Token Meter – AI Usage」に変更します。

## Setup.exeによる直接配布

`TokenMeterSetup.exe`は、信頼済み証明書で署名したMSIXを1ファイルに内包するx64自己完結型インストーラーです。現在のユーザーへインストールするため管理者権限は要求しません。インストール中は既存のToken Meterを終了し、完了後にそのまま起動できます。セットアップ画面はWindowsの表示言語に合わせて英語、日本語、簡体字中国語、韓国語を切り替えます。

セットアップ画面には、MSIX登録・LocalState・任意のスタートアップタスクなどのシステム変更、
Claudeオンライン照会が既定で無効であること、プライバシーポリシー、アンインストール方法を表示します。
詳しくは[installation and uninstallation](../docs/windows-uninstall.md)を参照してください。

Store提出用の未署名MSIXをSetupへ入れても、一般の端末では信頼されないためインストールできません。直接配布用では次の両方を、MicrosoftのTrusted Rootへ連鎖する同じコード署名証明書またはAzure Artifact Signingで署名してください。

- Setupに埋め込む`.msix`
- 最終的な`TokenMeterSetup.exe`

MSIX manifestの`Identity/Publisher`は、署名証明書のSubjectとフィールド順まで完全に一致する必要があります。GitHub ActionsはPFXのSubjectを読み、直接配布専用の一時manifestを生成して`TokenMeterPackageManifest` MSBuildプロパティへ渡すため、追跡中のStore用manifestは変更しません。手動ビルドでも、証明書のSubjectを設定したmanifestのコピーを同プロパティへ渡せます。PublisherがStore版と異なる場合、Windows上では別アプリとして扱われる点に注意してください。

署名済みMSIXがある場合は、Windows 11のPowerShellから次を実行します。

```powershell
$env:TOKEN_METER_PFX_PASSWORD = '<PFX password>'
Windows\scripts\Build-Setup.ps1 `
  -MsixPath C:\path\to\TokenMeter.msix `
  -CertificatePath C:\path\to\code-signing.pfx `
  -CertificatePassword $env:TOKEN_METER_PFX_PASSWORD
```

通常のPFX経路の出力は`Windows\artifacts\setup\TokenMeterSetup.exe`と`SHA256SUMS.txt`です。スクリプトは埋め込み前のMSIX署名と、生成後のSetup署名・payloadを検証します。Azure Artifact Signingなどで後段署名する場合は`-DeferSetupSigning`を指定し、その直後にSetupへ署名してから`TokenMeterSetup.exe --verify-payload`と署名検証を実行し、終了コード0を確認して最終ファイルのSHA-256を生成します。後段署名ではファイルハッシュが変わるため、deferred経路は署名前の`SHA256SUMS.txt`を生成しません。

直接配布用MSIXは`SelfContained=true`と`WindowsAppSDKSelfContained=true`で生成します。Setupは外部のWindows App Runtimeや.NET runtimeに依存するMSIXを拒否するため、初期状態のWindows 11でも単一のSetupだけで導入できます。CIでは一時的な自己署名証明書を使い、MSIX生成、Setupへの埋め込み、payload読取までを毎回smoke testします。自己署名証明書はこのテストだけに使い、公開成果物には含めません。

GitHub Actionsから生成する場合は、リポジトリのActions secretsへ次を登録して`Windows`ワークフローを手動実行します。

| Secret | 内容 |
|---|---|
| `WINDOWS_SIGNING_CERTIFICATE_BASE64` | CA発行PFXをBase64化した値 |
| `WINDOWS_SIGNING_CERTIFICATE_PASSWORD` | PFXのパスワード |

Secretsが設定されている場合だけ、Store用成果物とは別に`token-meter-windows-setup-1.3.0.0` artifactを生成します。Secrets未設定時は、動作しない未署名Setupを誤って配布しないようSetup成果物を生成しません。証明書ファイルはrunnerの一時領域から最後に削除されます。Release packageは`main`上のクリーンな`v1.3.0`タグを指定して手動実行し、GitHubの`windows-signing` Environmentでも承認します。

このSecrets経路は、CI利用を許可されたエクスポート可能PFX向けです。HSM、USBトークン、CAのクラウド署名、Azure Artifact Signingを利用する場合は秘密鍵をPFX化せず、署名済みMSIXを用意して`Build-Setup.ps1 -DeferSetupSigning`でSetupを生成し、各サービスの署名処理をSetupへ適用してください。

## 実装済みのOS連携

- `Shell_NotifyIcon`による通知領域アイコン
- 左クリックのコンパクト表示、右クリックのDashboard / Refresh / Settings / Exit
- 閉じる操作でトレイ常駐し、Exitだけで終了
- Windows App SDKの単一インスタンス転送
- `FileSystemWatcher`の3秒デバウンス、定期・手動・復帰・日付変更時更新
- App Notificationsによる残量20 / 10 / 5%、リセット、データエラー通知と重複抑止
- MSIX `StartupTask`によるログイン時起動
- 英語、日本語、簡体字中国語、韓国語の`.resw`
- MSIX LocalState内のSQLite DBとスキーマ移行

## 読み取り先

| Provider | Windowsパス |
|---|---|
| Claude Code | `%CLAUDE_CONFIG_DIR%\projects`、未設定時は`%USERPROFILE%\.claude\projects` |
| Claude資格情報（任意） | Claude homeの`.credentials.json` |
| Codex | `%CODEX_HOME%\sessions`、未設定時は`%USERPROFILE%\.codex\sessions` |
| Copilot CLI | `%USERPROFILE%\.copilot\session-state\*\events.jsonl` |

Codexの`auth.json`は開きません。Claudeの`.credentials.json`は設定で利用枠照会を明示的に有効化した場合だけ読み、アクセストークンはリクエスト中のメモリにだけ保持します。

## Windows実機で必要なリリース検証

コードだけでは完了できない項目です。公開前にStoreの非公開flightで記録してください。

- Claude Code、Codex、Copilot CLIのWindowsネイティブ実ログで追記、再開、置換、切り詰め、削除、同時書き込み
- `.credentials.json`の未設定、不正JSON、期限切れ、ACL拒否と、APIの401 / 403 / 429 / オフライン
- タイムゾーン、夏時間、スリープ復帰、日付変更、カーソル復元、履歴再構築
- 100 / 150 / 200% DPI、ライト / ダーク、4言語、キーボード、Narrator
- 起動からトレイ3秒以内、ログ追記から更新5秒以内、二重計上ゼロ
- 最低5台・7日間、P0/P1ゼロ、履歴破損ゼロ

Windows Widgets、WSL統合、ARM64はこのv1に含みません。直接配布版には独自の自動更新機構をまだ含めず、更新時は新しいSetupを再実行します。
