# Token Meter

Claude Code と Codex の利用状況を macOS のメニューバーとデスクトップウィジェットから確認するネイティブアプリ。

Swift / SwiftUI / WidgetKit / Swift Charts。WebView も Electron も使っていない。
トークン履歴はローカルで集計する。ユーザーが明示的に有効化した場合だけ、Claude Pro / Maxの
使用量確認のためAnthropicのOAuth使用量エンドポイントへ通信する。

---

## ⚠️ 最初に読んでほしいこと（このアプリで取得できるもの・できないもの）

実機調査の結果（詳細は [docs/data-sources.md](docs/data-sources.md)）:

| | Claude Code | Codex |
|---|---|---|
| トークン使用量（入力 / キャッシュ / 出力） | ✅ | ✅ |
| 推論トークン | ❌ 分離されていない | ✅ |
| 使用モデル | ✅ | ✅ |
| 履歴・日別集計 | ✅ | ✅ |
| **5時間枠のトークン数** | ⚠️ 実測（枠の区切りは推定） | ✅ Codexが5h枠を報告した時のみ |
| **週次のトークン数** | ⚠️ 実測（直近7日のローリング） | ✅ 実際の週次枠 |
| **利用率（%）** | ✅ OAuth連携有効時 | ✅ |
| **残り利用可能量** | ✅ OAuth連携有効時 | ✅ |
| **利用枠のリセット時刻** | ✅ OAuth連携有効時（ローカル値は推定） | ✅ 報告値 |
| コンテキスト窓サイズ | ❌ 取得不可 | ✅ |

**Claude Code は利用率・残量・リセット時刻をローカルログには書き出していない。**
`claude` CLI に `usage` サブコマンドは存在せず（`--help` の全コマンドを確認済み）、
`/usage` は対話セッション内のスラッシュコマンドのみ。設定ファイルにも該当する値は無い。

設定でClaude OAuth使用量チェックを有効にすると、macOS Keychainの
`Claude Code-credentials`をSecurity Frameworkで読み、`GET https://api.anthropic.com/api/oauth/usage`
から5時間・7日・任意のSonnet 7日枠を取得する。無効時や取得不能時に推定の割合は表示しない。

### なぜ「プランを選んで%を出す」ができないのか

Anthropic は**プランごとのトークン上限を公開していない**。
制限は「会話の長さ・複雑さ・使用モデル・effort」で変動すると説明されており、固定の数値が無い。
さらに (1) Opus は Sonnet の数倍のコストで数えられる（倍率は非公開）、
(2) 利用枠は claude.ai (Web/デスクトップ/モバイル) と共有で、他のマシンの利用も同じ枠を消費する。

分母が存在せず、分子（このMacのClaude Codeログ）も不完全なので、ローカル値から割合を計算しない。
表示する割合はAnthropicの使用量レスポンスに含まれる値だけである。

### 代わりに出しているもの（すべて実測）

| | 中身 | リセット時刻 |
|---|---|---|
| Claude Code · 5時間枠 | 現在のセッションブロックのトークン数 | ⚠️ **推定**（下記） |
| Claude Code · 直近7日 | 7日間のローリング合計 | なし（週次の起点が不明なため） |
| Codex · 5時間枠 / 週次枠 | その枠の中で消費したトークン数 | ✅ Codex の報告値 |

Anthropic は「5時間のセッション枠は最初のメッセージで始まり5時間続く」と説明している。
Claude Code の5時間リセット時刻は、**この規則をローカルのログに当てはめて再現したもの**であり、
Anthropic が出力した値ではない。UI 上では常に *estimated* と明記され、
「このMacの Claude Code のログのみを集計」という注記が付く。

Codex は `rate_limits`（`used_percent` / `resets_at` / `window_minutes`）をログに書き出しているので、
利用率・残量・リセット時刻をすべて実データとして表示できる。
枠の開始時刻も `resets_at - window_minutes` で確定するため、枠内のトークン数も実測値になる。

これらの表示は **設定 > Time windows** で個別にオフにできる。

---

## 対応環境

| | |
|---|---|
| macOS | 14.0 以降（開発・動作確認は macOS 26.5） |
| Xcode | 15 以降（動作確認は Xcode 26.2） |
| Swift | 5.9 以降（動作確認は 6.2.3） |
| 生成ツール | [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`） |

## ビルド

```bash
# 1. Xcodeプロジェクトを生成（project.yml から）
xcodegen generate

# 2. ビルド
open TokenMeter.xcodeproj    # Xcode から ⌘R

# またはコマンドラインで
xcodebuild -project TokenMeter.xcodeproj -scheme TokenMeter \
  -configuration Debug -destination 'platform=macOS' build
```

### 署名について（Widget を使うなら必須）

Developer Team `B97M43J5TT` とAutomatic Signingを`project.yml`に設定している。
両ターゲットはApp Group `group.com.tokenmeter.b97m43j5tt.shared`を使用する。

初回ビルドではXcodeにApple Accountを追加したうえで、Provisioning Profileの作成を許可する:

```bash
xcodebuild -project TokenMeter.xcodeproj -scheme TokenMeter \
  -configuration Debug -destination 'platform=macOS' \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
```

署名を無効にしたローカルビルドではApp Groupを利用できず、アプリ本体だけローカルディレクトリへ
フォールバックする。利用状況は **設定 > Diagnostics** の`App Group: Active` / `Unavailable`で確認できる。

### Developer ID配布

Release Archive、Developer ID署名、Notarization、配布用ZIP作成をスクリプト化している。

```bash
# テスト、Archive、Developer ID署名、Notary Serviceへのアップロード
./scripts/release.sh prepare

# AppleのNotarization承認後、チケット付きアプリとZIPを書き出す
./scripts/release.sh finish
```

出力は`build/TokenMeter-<version>.zip`。ZIPを展開し、`TokenMeter.app`を`/Applications`へ移動する。
DMGで配布する場合は、アプリだけでなく最終DMGコンテナにもDeveloper ID署名とNotarizationを行うこと。
プライバシーポリシーは[docs/privacy.md](docs/privacy.md)を参照。

### アプリ内アップデート

Sparkle 2を使用し、起動中に更新を自動確認する。更新があれば標準の通知画面からリリースノートを確認し、
署名済みZIPをダウンロードしてアプリを置き換えられる。Settings > Updatesまたはアプリメニューの
`Check for Updates…`から手動確認も可能。

更新フィードはリポジトリ直下の`appcast.xml`、配布ZIPはGitHub Releasesに置く。
`./scripts/release.sh finish`は、Keychain内のSparkle EdDSA鍵（account: `com.tokenmeter.app`）でZIPへ署名し、
`appcast.xml`を更新する。秘密鍵はリポジトリへ保存しない。

リリースごとに`MARKETING_VERSION`と、Sparkleが比較に使う`CURRENT_PROJECT_VERSION`を増やしてから実行する。
完了後は次の2点を行う:

1. `v<version>`タグのGitHub Releaseへ`build/TokenMeter-<version>.zip`をアップロード
2. 更新された`appcast.xml`をmainブランチへcommit/push

## テスト

パーサーとストアのテストは Swift Package 側にある。

```bash
swift test --package-path TokenMeterCore
# 75 tests, 0 failures
```

カバーしている内容:

- Claude Code / Codex パーサー（実ログから作った匿名化 fixture を使用）
- **時間枠**（5時間ブロックの区切り、期限切れ枠は表示しない、報告された枠の開始時刻の算出、
  ローリング枠にリセット時刻を付けない、推定/報告の区別がWidget JSONを越えても失われない）
- **重複排除**（Claude Code の同一メッセージ重複、Codex の同値イベント）
- **累積トークンの差分計算**（セッション再開時の二重計上防止、カウンタリセット）
- 不完全なJSON / 未知のフィールド / 空ファイル / 壊れたJSONL
- 日付変更・タイムゾーン処理（UTCログ → ローカル日付）
- Widget用JSONの読み書き（並行書き込み・破損ファイル）
- データソース未検出時・増分読み込み

fixture は実データから生成しているが、**プロンプト本文・応答本文・認証情報・個人情報は完全に除去**してある
（`TokenMeterCore/Tests/TokenMeterCoreTests/Fixtures/`）。

## 初期設定

初回起動時はセットアップ画面が開く（メニューバーの Token Meter → Dashboard → Setup からいつでも開ける）。

- 各プロバイダの接続状態と、未接続時の具体的な対処（コマンドはコピーできる）
- メニューバーに表示するかどうか、表示形式、表示項目
- 何を読み取っているかの明示

### Claude Code との接続

**設定は不要。** Claude Code を1回でも使っていれば自動的に検出される。

- 読み取り先: `~/.claude/projects/<プロジェクト>/<セッションID>.jsonl`
- `claude` CLI が PATH に無くても動く（ログファイルだけを読むため）
- 何も表示されない場合は、Claude Code でセッションを1回実行する

### Codex との接続

- 読み取り先: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`
- 未インストールなら: `brew install --cask codex`
- 未ログインなら: `codex login`
- ログイン後、Codex を1回実行するとログが書かれ、利用率が表示される

**認証ファイル（`~/.codex/auth.json`）は開かない。** ログイン判定はファイルの存在確認のみ。

### Widget の追加

1. アプリを1回起動する（スナップショットが書かれる）
2. デスクトップを右クリック →「ウィジェットを編集」
3. Token Meter を選び、Small / Medium / Large から選択
4. Widget をクリックするとアプリのダッシュボードが開く

Widget は**ログを直接読まない**。本体アプリが App Group に書いた JSON スナップショットだけを読む。

| サイズ | 表示内容 |
|---|---|
| Small | Claude / Codex の残量（またはトークン数）、最終更新時刻 |
| Medium | プログレスバー、次の5時間リセットまでの時間、今日のトークン |
| Large | 上記 + 5時間枠 / 今日 / 週次（または直近7日）のトークン、簡易グラフ |

推定のリセット時刻には Widget 上でも `est.` が付く。

## データ保存場所

| データ | 場所 |
|---|---|
| 履歴DB（SQLite） | `~/Library/Application Support/TokenMeter/history.sqlite` |
| Widget用スナップショット | `~/Library/Group Containers/group.com.tokenmeter.b97m43j5tt.shared/snapshot.json` |
| （App Group未使用時） | `~/Library/Application Support/TokenMeter/snapshot.json` |
| 設定 | UserDefaults |

スナップショットは一時ファイルに書いてからアトミックに置換するため、書き込み中の破損は起きない。

## セキュリティ方針

- **認証トークンを保存しない。** DB にも UserDefaults にも書かない
- Claude連携を有効にした場合だけ、Security Frameworkの`SecItemCopyMatching`で
  `Claude Code-credentials`を読み、アクセストークンをAnthropicの固定エンドポイントだけへ送る
- **CLIの認証ファイルを読まない・コピーしない。** `~/.codex/auth.json` は存在確認のみ、中身は開かない
- **プロンプト本文・応答本文を保存しない。** パース対象は `usage` / `token_count` 相当のフィールドのみ
- 保存するのは **トークン数・日時・モデル名・利用率・リセット時刻** だけ
- Claude OAuth使用量照会とGitHubへのアプリ更新確認以外の外部送信は行わない。Analytics・クラッシュレポートは使用しない
- ファイルアクセスは `~/.claude/projects` と `~/.codex/sessions`、任意連携時のKeychain項目だけ
- ログに秘密情報を出力しない
- Widget はサンドボックス内で動作し、App Group の JSON しか読めない

本体アプリは App Sandbox を無効にしている。`~/.claude` と `~/.codex` はサンドボックスコンテナの
外にあり、読み取りに必要なため。書き込みは自身の Application Support と App Group のみ。

Token Meter自身はKeychainへ資格情報を書き込まない。Claude Codeが保存した項目を使用量照会中だけ読む。

### Keychain / Sandbox / 配布上の制約

- 現在の本体ターゲットは`ENABLE_APP_SANDBOX=NO`で、Keychain access groupは指定していない。
  直接配布版では一般のGeneric Passwordを`SecItemCopyMatching`で照会できるが、項目のACLによって
  初回アクセス確認が出る、または拒否される場合がある。
- WidgetはSandbox有効だがKeychainにもネットワークにも触れず、本体が資格情報を除いて書いた
  App Groupスナップショットだけを読む。
- Sandboxを有効にすると、Claude Codeとは署名チーム／Keychain access groupを共有していないため、
  Claude Codeが作成した項目を通常は読めない。勝手にSandboxを無効化するフォールバックは行わない。
- Mac App Store版はSandboxが原則必要なうえ、現在のローカルログ読み取りにも同じ制約があるため、
  この方式のClaude連携をそのまま提供するのは現実的ではない。Anthropicが公式API／共有access group／
  安全なIPCを提供しない限り、直接配布の非Sandbox版が実用的な構成となる。
- トークン手入力は実装しない。Sandbox版が必要なら、ユーザーが明示的に起動する非Sandboxの
  署名済みヘルパーまたはClaude Code側の公式ローカル連携が必要だが、現時点では採用していない。

## 更新のタイミング

| 経路 | 実装 |
|---|---|
| アプリ起動時 | `applicationDidFinishLaunching` |
| CLIログ更新時 | FSEvents（3秒デバウンス） |
| 一定間隔 | タイマー（既定5分。最短1分） |
| 手動更新 | メニューバー / ダッシュボードの更新ボタン |
| macOS復帰時 | `NSWorkspace.didWakeNotification` |
| 日付変更時 | `NSCalendarDayChanged` |

更新は直列化してあり、同時実行しない。タイムアウトあり。
ログは**追記分だけ**を読む（ファイルオフセットを永続化）ので、2回目以降は軽い。
Claude OAuthの成功値はメモリに5分キャッシュし、失敗時も前回値とその更新時刻を維持する。

## トラブルシューティング

**メニューバーに何も出ない**
→ まず 設定 > メニューバー >「Show Token Meter in the menu bar」を確認。
これをオフにすると Dock アイコンに切り替わる（ウィンドウを開けなくならないように）。

→ オンなのに見えない場合、**メニューバーの空きが足りずに macOS が項目を隠している**可能性が高い。
ノッチ付きMacで、前面アプリのメニューが多いときに起きる。実機で確認した挙動として、
このときステータス項目自体は生成されている（`NSStatusBarWindow` が画面外座標に配置される）。
メニューバーの `•••` をクリックするか、他のメニューバー常駐アプリを減らすと表示される。
表示形式を Compact / Icon only にすると幅が縮むので改善することがある。

**Claude Code の利用率が出ない**
→ 設定 > Claude Pro / Max usage でOAuth使用量チェックを有効にし、Claude Codeでログイン済みか確認する。
Keychain拒否、401/403、レート制限、オフライン、API形式変更は画面上で区別して表示する。
連携を無効にした場合も5時間枠・直近7日のローカルトークン数は表示できる。

**Claude Code の5時間リセット時刻がずれている気がする**
→ その可能性はある。この時刻は Anthropic が出力した値ではなく、
「セッションは最初のメッセージで始まり5時間続く」という公開仕様を
**このMacのログに当てはめて再現した推定値**（UI では *estimated* と表示）。
claude.ai のブラウザ利用や他のマシンでの Claude Code 利用で枠が始まっていた場合、
こちらの推定は実際より遅くなる。正確な値は Claude Code 内の `/usage` で確認できる。

**Codex の5時間枠が表示されない**
→ Codex は `rate_limits` に5時間枠を常に含めるわけではない（週次枠のみのセッションがある）。
報告が無いときは推測せず、行ごと表示しない。

**Codex の利用率が出ない**
→ `codex login` 済みか、Codex を1回でも実行したかを確認。
Setup 画面に具体的な対処が出る。

**Widget にデータが出ない**
→ App Group には署名が必要。設定 > Diagnostics で `App Group: Unavailable` なら、
Xcode で開発チームを設定して再ビルドする。

**数字が古い**
→ 更新から1時間以上経過すると「Data may be outdated」と明示される。
古いデータを最新のように見せることはしない。

**表示がおかしい / 数字を疑うとき**
→ 設定 > Diagnostics に、DBパス・スナップショットパス・各プロバイダの検出状態・
読み取り元パス・最終更新時刻・直近のエラーがすべて出る。

## 構成

```
TokenMeterCore/          Swift Package（UI非依存・テスト対象）
  Models/                UsageSnapshot, UsageWindow, UsageEvent, 可用性・エラー
  Parsing/               ClaudeCodeLogParser, CodexLogParser, 増分JSONLリーダー
  Providers/             UsageProvider プロトコルと2実装
  Persistence/           UsageStore(SQLite), SharedSnapshotStore(App Group)
  Aggregation/           日次集計・モデル別集計
  Monitoring/            FSEvents ディレクトリ監視
TokenMeterApp/           メニューバー・ダッシュボード・設定・通知
TokenMeterWidget/        Small / Medium / Large
docs/data-sources.md     データソース調査結果
```

データ取得・ログ解析・UI は分離してある。Widget は Core のモデルだけを共有し、ログには触れない。

## 既知の制限

- Claude使用量は非公開OAuthエンドポイントとClaude Codeの資格情報形式に依存し、予告なく動かなくなる可能性がある
- Keychain項目のアクセス制御によっては、Sandbox無効の直接配布版でもユーザー許可または再署名後の再許可が必要
- Claude Code の5時間枠の区切りは**推定**であり、claude.ai や他のマシンでの利用は見えない。
  トークン数そのものは実測だが、「このMacの Claude Code 分だけ」の合計である
- Codex の5時間枠は、Codex が `rate_limits` に含めたセッションでのみ表示される
- 初回起動時は全ログを読むため数秒かかる（実測: 約4秒 / ログ約680MB）。2回目以降は差分のみ
- メニューバーの空きが無いと macOS が項目を隠す（上記トラブルシューティング参照）
- Developer ID署名済み・Notarization済みアプリでApp Groupコンテナ作成とスナップショット書き込みを確認済み。
  Widgetのデスクトップ上での最終描画は別Macでの配布テストが必要
- 目視確認済み: メニューバー項目・ポップオーバー・ダッシュボード・Setup 画面（ライト/ダーク両モード）。
  ただし時間枠の行（5時間枠・週次）はダークモードでのみ実機確認しており、ライトモードは未確認
