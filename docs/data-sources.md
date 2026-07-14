# データソース調査結果

調査日: 2026-07-14
調査環境: macOS 26.5.2 (Darwin 25.5.0, arm64) / Xcode 26.2 / Swift 6.2.3

この文書は **実際にこのマシン上で確認できた** データソースだけを記載する。
確認できなかったファイル・コマンド・APIフィールドは「存在しない」として扱い、推測で補完しない。

---

## 0. 調査サマリ

| | Claude Code | Codex |
|---|---|---|
| CLI | `2.1.209` (VS Code拡張同梱バイナリ。**PATH上に`claude`は無い**) | `codex-cli 0.144.3` (`/opt/homebrew/bin/codex`) |
| トークン使用量 | ✅ 取得可 (JSONL) | ✅ 取得可 (JSONL) |
| 利用率 (%) | ❌ **ローカルに存在しない** | ✅ 取得可 (`rate_limits.used_percent`) |
| リセット時刻 | ❌ **ローカルに存在しない** | ✅ 取得可 (`rate_limits.resets_at`) |
| コンテキスト窓サイズ | ❌ 存在しない | ✅ 取得可 (`model_context_window`) |
| 推論トークン | ❌ 分離されていない | ✅ 取得可 (`reasoning_output_tokens`) |

**ローカル調査の結論**: Claude Code は利用率・残量・リセット時刻をセッションログへ書き出していない。
`/usage` は対話TUI内のスラッシュコマンドのみで、非対話サブコマンドは存在しない (後述 3.2)。
ローカルログだけを使う場合は利用率を`nil`として扱う。任意のOAuth連携を有効にした場合に限り、
Anthropicの使用量レスポンスを別ソースとして表示する。ローカル値から架空の％を計算しない。

---

## 1. Claude Code — セッションJSONLログ 【採用】

| 項目 | 内容 |
|---|---|
| データソース名 | Claude Code session transcript (JSONL) |
| パス | `~/.claude/projects/<cwd-slug>/<sessionId>.jsonl` |
| データ形式 | JSON Lines (1行1レコード) |
| 更新頻度 | メッセージ確定ごとに追記 (対話中はほぼリアルタイム) |
| 認証情報を含むか | **含まない** (トークン類は Keychain / `~/.claude.json`の別領域)。ただし**プロンプト本文と応答本文を含む** |
| 採用 | ✅ 採用 |

### 取得できる値

`type == "assistant"` かつ `message.usage` が存在する行から取得する。実測したレコード構造:

```json
{
  "type": "assistant",
  "uuid": "...",
  "requestId": "req_...",
  "sessionId": "964c3a56-...",
  "timestamp": "2026-07-14T13:19:52.123Z",
  "cwd": "/Users/takeru/GitHub/token_meter",
  "gitBranch": "main",
  "version": "2.1.209",
  "isSidechain": false,
  "message": {
    "id": "msg_01...",
    "model": "claude-opus-4-8",
    "role": "assistant",
    "usage": {
      "input_tokens": 2,
      "cache_creation_input_tokens": 16796,
      "cache_read_input_tokens": 11496,
      "output_tokens": 341,
      "service_tier": "standard",
      "cache_creation": { "ephemeral_1h_input_tokens": 16796, "ephemeral_5m_input_tokens": 0 },
      "server_tool_use": { "web_search_requests": 0, "web_fetch_requests": 0 }
    }
  }
}
```

| 値 | フィールド |
|---|---|
| 入力トークン (非キャッシュ) | `message.usage.input_tokens` |
| キャッシュ書き込みトークン | `message.usage.cache_creation_input_tokens` |
| キャッシュ読み出しトークン | `message.usage.cache_read_input_tokens` |
| 出力トークン | `message.usage.output_tokens` |
| モデル名 | `message.model` |
| 日時 | `timestamp` (ISO8601, UTC, ミリ秒つき) |
| セッションID | `sessionId` |
| 重複排除キー | `message.id` + `requestId` |
| 現在のコンテキスト長 | 最新assistant行の `input_tokens + cache_read + cache_creation` |

### ⚠️ パース上の必須の注意点 (実測により判明)

1. **同一メッセージのusageが複数行に重複して出現する。**
   直近25セッションを実測したところ、`usage`を持つassistant行 **2340行** に対し、
   ユニークな `(message.id, requestId)` は **866組** しかなかった (最大4重複)。
   これは1メッセージが content block 単位で複数行に分割記録され、
   **各行が同一の`usage`オブジェクトを持つ**ため。
   → **`(message.id, requestId)` で重複排除しないと使用量が約2.7倍に過大計上される。**
   本アプリはこのキーをSQLiteのPRIMARY KEYにして構造的に二重計上を防ぐ。

2. `usage`は**累積値ではなくメッセージ単位の値**。差分計算は不要 (重複排除のみで足りる)。

3. `reasoning_output_tokens` に相当するフィールドは **存在しない**。
   thinkingトークンは`output_tokens`に内包される。→ `reasoningTokens = nil`。

4. モデル名が `<synthetic>` の行が存在し得る (API呼び出しを伴わないローカル生成メッセージ)。
   これらは実使用量ではないため除外する。

### パース方法

行単位ストリーム読み込み。ファイル末尾オフセットを永続化して差分のみ再パース (増分パース)。
壊れた行 (書き込み途中の不完全JSON) はスキップする。

---

## 2. Codex — セッション rollout JSONL 【採用・主データソース】

| 項目 | 内容 |
|---|---|
| データソース名 | Codex session rollout log |
| パス | `~/.codex/sessions/YYYY/MM/DD/rollout-<ISO8601>-<sessionId>.jsonl` |
| データ形式 | JSON Lines |
| 更新頻度 | ターン毎/ストリーム毎に追記 (実測: 1セッションに`token_count`が10〜309件) |
| 認証情報を含むか | **含まない** (認証は`~/.codex/auth.json` — 本アプリは読まない) |
| 採用 | ✅ 採用 (**利用率・リセット時刻の唯一のローカル情報源**) |

### 取得できる値

`type == "event_msg"` かつ `payload.type == "token_count"` の行。実測レコード:

```json
{
  "timestamp": "2026-07-14T13:20:58.301Z",
  "type": "event_msg",
  "payload": {
    "type": "token_count",
    "info": {
      "total_token_usage": {
        "input_tokens": 38735413,
        "cached_input_tokens": 37789440,
        "output_tokens": 182658,
        "reasoning_output_tokens": 89125,
        "total_tokens": 38918071
      },
      "last_token_usage": {
        "input_tokens": 196343,
        "cached_input_tokens": 194304,
        "output_tokens": 1083,
        "reasoning_output_tokens": 151,
        "total_tokens": 197426
      },
      "model_context_window": 258400
    },
    "rate_limits": {
      "limit_id": "codex",
      "limit_name": null,
      "primary":   { "used_percent": 25.0, "window_minutes": 10080, "resets_at": 1784494842 },
      "secondary": null,
      "credits": null,
      "individual_limit": null,
      "plan_type": "pro",
      "rate_limit_reached_type": null
    }
  }
}
```

| 値 | フィールド |
|---|---|
| 利用率 | `rate_limits.{primary,secondary}.used_percent` (0–100) |
| 残量 | `100 - used_percent` から算出 |
| リセット時刻 | `rate_limits.{primary,secondary}.resets_at` (**Unix epoch秒**) |
| 枠の種類 | `window_minutes` (実測値: `300` = 5時間枠, `10080` = 週次枠) |
| プラン | `rate_limits.plan_type` (実測: `"pro"`) |
| 累積トークン | `info.total_token_usage.*` (**セッション内累積**) |
| 直近リクエスト | `info.last_token_usage.*` |
| コンテキスト窓 | `info.model_context_window` |
| 推論トークン | `*.reasoning_output_tokens` ✅ |
| モデル名 | 同ファイル内 `type == "turn_context"` の `payload.model` (実測: `gpt-5.6-sol`, `gpt-5.5`, `gpt-5.6-terra` 等) |

### ⚠️ パース上の必須の注意点 (実測により判明)

1. **`primary` が短期枠とは限らない。**
   直近40セッションを実測した結果、2パターンが混在していた:
   - `primary: window_minutes=300` + `secondary: window_minutes=10080` (173件)
   - `primary: window_minutes=10080`, `secondary: null` (2793件) ← 現在の主流
   → **スロット名(`primary`/`secondary`)で短期/週次を判定してはならない。**
   `window_minutes` の値で分類する (`<= 1440` → 短期枠 / `>= 10080` → 週次枠)。

2. **`total_token_usage` はセッション内の累積値。**
   実測でセッション内は単調増加 (減少0件・同値0件)。
   → 日次集計では **直前イベントとの差分** を取る。差分をそのイベントのタイムスタンプの日に計上する。
   セッションごとの最終累積値をDBに保持し、再パース時も二重計上しない。
   万一減少した場合 (カウンタリセット) は差分を「現在値」として扱う。

3. `rate_limits` は `null` になり得る (レート情報が未取得のターン)。→ その場合ウィンドウは`nil`。

### パース方法

日付ディレクトリを新しい順に走査。増分パース (ファイルオフセット永続化)。
利用率は「最新の`token_count`イベント」の値を採用する。

---

## 2.1 Claude OAuth usage endpoint 【任意・採用】

- エンドポイント: `GET https://api.anthropic.com/api/oauth/usage`
- 認証: macOS KeychainのGeneric Password `Claude Code-credentials`内の
  `claudeAiOauth.accessToken`
- 取得値: `five_hour`、`seven_day`、任意の`seven_day_sonnet`の`utilization`と`resets_at`
- Security Frameworkの`SecItemCopyMatching`を直接使用し、シェルや`security`コマンドは実行しない
- 成功値はメモリだけに5分キャッシュする。トークン・Keychain生データ・API本文は保存／ログ出力しない
- このインターフェースはAnthropic側の非公開仕様とClaude Codeの保存形式に依存し、互換性保証はない

---

## 3. 不採用としたデータソース

### 3.1 `~/.codex/auth.json` 【不採用 — セキュリティ】

- 実在する。キー: `OPENAI_API_KEY`, `auth_mode`, `last_refresh`, `tokens`
- **認証トークンそのものを含むため、本アプリは読み取らない。**
  値は一切参照せず、キー名のみ確認した。ログイン状態の判定はファイルの**存在確認のみ**で行う (中身は開かない)。

### 3.2 `claude` CLI サブコマンド 【不採用 — 該当機能が存在しない】

- `claude` は **PATH上に存在しない**。実体は VS Code拡張に同梱:
  `~/.vscode/extensions/anthropic.claude-code-2.1.209-darwin-arm64/resources/native-binary/claude`
- `claude --help` の Commands を全確認した結果:
  `agents / auth / auto-mode / doctor / gateway / install / mcp / plugin / project / setup-token / ultrareview / update`
- **`usage` サブコマンドは存在しない。** 利用率を出力する非対話コマンドは無い。
  (`/usage` は対話セッション内のスラッシュコマンドのみ)
- → CLI実行による利用率取得は **不可能**。

### 3.3 `~/.claude.json` 【不採用 — 必要な値が無い】

- 実在。全トップレベルキーを確認したが、利用率・残量・リセット時刻に該当するキーは無い。
- `autoCompactWindowsCache` は `null`、`metricsStatusCache` は `{"enabled": false}` で、
  コンテキスト窓サイズも取得できない。
- `oauthAccount` を含むため、そもそも読み取り対象にしない。

### 3.4 Claude Code の OpenTelemetry メトリクス 【不採用 — 前提条件が重い】

- 設定スキーマ上 `env` によるテレメトリ有効化は可能だが、
  利用者が **OTLPコレクタを別途常駐させる必要がある**。
- 現環境では無効 (`metricsStatusCache.enabled = false`)。
- 本アプリの「ローカルで完結する」方針に反するため不採用。

### 3.5 `codex doctor` / `codex mcp-server` / `codex app-server` 【不採用】

- `codex doctor` の出力に利用率・プラン情報は含まれなかった。
- `app-server` / `mcp-server` は常駐プロセスを要し、JSONLで同じ情報が取れるため不要。

### 3.6 `~/.codex/logs_2.sqlite` / `state_5.sqlite` 【不採用】

- 実在するが (371MB)、スキーマは非公開かつ会話本文を含む。
- JSONLで必要な値が全て取れるため参照しない。

---

## 4. 本アプリが採用する構成

| Provider | ソース | `UsageSource` | 取得する値 |
|---|---|---|---|
| Claude Code | `~/.claude/projects/*/*.jsonl` | `.localLog` | トークン内訳・モデル・コンテキスト長・履歴 |
| Claude Pro / Max（任意） | Keychain + `api.anthropic.com/api/oauth/usage` | `.officialAPI`（ローカルログなしの場合） | **利用率・残量・リセット時刻** |
| Codex | `~/.codex/sessions/*/*/*/rollout-*.jsonl` | `.localLog` | 上記 + **利用率・残量・リセット時刻**・推論トークン |

通常の読み取りは上記2つのディレクトリのみ。OAuth連携を明示的に有効にした場合だけKeychainを読む。
平文の認証ファイルには一切触れない。
プロンプト本文・応答本文はパース対象外で、DBにも保存しない (トークン数・日時・モデル名・利用率のみ保存)。

## 5. 取得できない値の扱い

| 値 | Claude Code | Codex |
|---|---|---|
| `shortWindow` / `weeklyWindow`（利用率） | OAuth連携成功時は実値、それ以外は**`nil`** | 実値 |
| `reasoningTokens` | **`nil`** → 内訳では「データなし」 | 実値 |
| `contextWindowTokens` | **`nil`** | 実値 |

`nil` を `0` として表示することはしない。

## 6. 時間枠のトークン数 (`TokenWindowUsage`)

利用率（%）とは別に、**枠内で消費したトークン数**を表示する。これは計測値であって
利用枠ではない。分母は持たないので、%もプログレスバーも描かない。

境界の出どころを `boundary` で区別し、UIはそれを必ず表示する:

| `boundary` | 意味 | 使う場面 |
|---|---|---|
| `.reported` | プロバイダがリセット時刻と枠の長さを報告した | Codex（`resets_at` − `window_minutes` で開始時刻が確定する） |
| `.inferred` | 公開仕様をローカルログに当てはめて**再現した**もの | Claude Code の5時間枠 |
| `.rolling` | 単なる遡り集計。リセットは存在しない | Claude Code の「直近7日」 |

### Claude Code の5時間枠を推定してよい根拠と、その限界

Anthropic のヘルプは「5時間のセッション枠は最初のメッセージで始まり5時間続く」と
公開している（[Models, usage, and limits in Claude Code](https://support.claude.com/en/articles/14552983-models-usage-and-limits-in-claude-code)）。
`UsageAggregator.sessionBlock` はこの規則をイベント列に適用し、
直前のブロックの終了後に現れた最初のイベントを新しいブロックの開始とする。

**これは推定であり、次の限界がある。ゆえに UI では常に *estimated* と表示する:**

1. Anthropic は境界値をローカルに出力していない。照合できない。
2. 同じ利用枠は **claude.ai (Web/デスクトップ/モバイル) と共有**されており、
   他のマシンの Claude Code 利用も同じ枠を消費する。ローカルのログはそれらを見ていない。
   ブラウザで先に枠が始まっていた場合、この推定は実際より遅くなる。
3. 枠が失効していれば `nil` を返す（古い枠を現在のものとして見せない）。

### 「プランを選ばせて%を出す」を採用しない理由

Anthropic は**プランごとのトークン上限を公開していない**。
制限は「会話の長さ・複雑さ・使用モデル・effort レベル」で変動すると説明され、固定値が無い。
加えて Opus は Sonnet の数倍のコストで計上される（倍率は非公開）ため、
ローカルのトークン合計は利用枠が数えている単位そのものではない。
分母が存在せず分子も不完全である以上、算出した % は架空の数値になる。よって実装しない。
