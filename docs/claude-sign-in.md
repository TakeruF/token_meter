# Claude Code のサインインと Keychain 許可（手動手順）

Token Meter の「Claude Code にサインイン」「キーチェーンへのアクセスを許可」「Claude Code を入手」ボタンは、
このページに書かれている操作をワンクリックで代行するだけのものです。
アプリに任せず自分で操作したい場合は、ここの手順をそのまま実行してください。

Token Meter は Claude の資格情報を自分で更新（リフレッシュ）しません。トークンのローテーションによって
Claude Code 側のログインが壊れるためです。読み取りは、Anthropic に使用量を問い合わせる 1 回だけです。

---

## 1. Claude Code が入っているか確認する

```sh
command -v claude
```

パスが表示されれば入っています。何も出なければ <https://claude.com/claude-code> からインストールしてください。

Token Meter はトークン数を数えるだけなら CLI が PATH になくても動きます（`~/.claude/projects` のログを読むだけ）。
`claude` が必要になるのは、この手順でサインインし直すときだけです。

## 2. サインインし直す

ターミナルで:

```sh
claude
```

起動したら、REPL の中で:

```
/login
```

ブラウザが開くのでサインインを完了します。`/login` は REPL 内のスラッシュコマンドで、
CLI のフラグではありません。したがって Token Meter を含め、外部から非対話で完了させることはできません。

サインインが終わったら Token Meter の「再確認」を押してください。

## 3. Keychain へのアクセスを許可する

Claude 使用量（Pro / Max の残量）を表示するには、Claude Code が macOS Keychain に保存した
`Claude Code-credentials` を Token Meter が読み取る必要があります。

初回の読み取りで macOS 自身が次のようなダイアログを出します:

> "Token Meter" wants to use your confidential information stored in "Claude Code-credentials" in your keychain.

- **常に許可 (Always Allow)** を選ぶと、以後の更新では聞かれません。
- **許可 (Allow)** を選ぶと 1 回だけ許可され、次の更新でまた聞かれます。
- **拒否 (Deny)** を選ぶと、以後は下の「拒否してしまったとき」の手順が必要になります。

Token Meter の「キーチェーンへのアクセスを許可」ボタンは、この読み取りをその場で 1 回だけ実行して、
バックグラウンドの更新ではなくクリックの直後にダイアログが出るようにするためのものです。

### 拒否してしまったとき

macOS はアイテムごとの拒否を記憶するので、アプリ側からは元に戻せません。キーチェーンアクセスで直します。

1. **キーチェーンアクセス**を開く（Spotlight で「キーチェーンアクセス」/「Keychain Access」を検索。macOS のバージョンによって `/System/Applications/Utilities/` か `/System/Library/CoreServices/Applications/` にあります）
2. `Claude Code-credentials` を検索して開く
3. **アクセス制御**タブで Token Meter を許可する（または一覧から Token Meter を削除して、次回もう一度聞かせる）
4. Token Meter に戻って「再確認」

Claude の使用量表示自体をやめたい場合は、設定 > 「Claude Pro / Max 使用量」のトグルをオフにしてください。
Keychain の読み取りとネットワークアクセスは停止し、ローカルログによるトークン数の表示だけが残ります。

## 4. うまくいかないとき

| 症状 | 見るところ |
| --- | --- |
| 「サインインが失効しています」が消えない | `claude` を起動し `/login` をやり直す。完了後に「再確認」 |
| `command not found: claude` | インストール先が PATH にない。`.zprofile` / `.zshrc` を確認 |
| ダイアログが出ずに拒否される | 上記「拒否してしまったとき」 |
| 署名し直した版に入れ替えた | 別バイナリ扱いになるため、Keychain の許可をもう一度求められる |

---

# Signing in to Claude Code and granting Keychain access (manual steps)

Token Meter's **Sign in to Claude Code**, **Allow Keychain access**, and **Get Claude Code** buttons only
perform the steps written here, one click at a time. Do them yourself if you would rather not be driven.

Token Meter never refreshes Claude's credentials itself — rotating the token would break Claude Code's own
session. It reads the credential once, only to ask Anthropic for your usage.

**1. Check the install:** `command -v claude`. Nothing printed? Install from <https://claude.com/claude-code>.
Token counts work without the CLI on your PATH; `claude` is only needed to sign in again.

**2. Sign in again:** run `claude` in Terminal, type `/login` in the REPL, finish in the browser. `/login` is a
slash command inside the interactive REPL, not a CLI flag, so no tool can complete it unattended. Then press
**Re-check** in Token Meter.

**3. Grant Keychain access:** the first read of the `Claude Code-credentials` item makes macOS ask
*"Token Meter wants to use your confidential information stored in Claude Code-credentials"*. Choose
**Always Allow** so it stops asking on every refresh. Token Meter's button simply performs that one read on
demand, so the dialog appears right after your click instead of out of a background refresh.

**If you denied it:** macOS remembers the denial per item and no app can undo it. Open **Keychain Access**,
find `Claude Code-credentials`, and allow Token Meter under **Access Control** (or remove Token Meter from the
list so you get asked again). Alternatively turn the Claude usage check off in Settings — Keychain and network
access stop, and local token counts keep working.

Re-signed builds count as a different binary, so macOS will ask for approval again after an app update that
changed signing.
