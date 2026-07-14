# Token Meter プライバシーポリシー

最終更新日: 2026年7月15日

Token Meterは、Claude CodeおよびCodexの利用状況をユーザー自身のMac上で確認するためのアプリです。

## 取り扱うデータ

- `~/.claude/projects`および`~/.codex/sessions`内の利用量関連フィールド
- Claude CodeがmacOS Keychainに保存したOAuthアクセストークン（Claude連携を有効にした場合のみ）
- トークン数、日時、モデル名、使用率、リセット時刻

プロンプト本文と応答本文は保存しません。OAuthアクセストークンとKeychainの生データを、ログ、
UserDefaults、Analytics、クラッシュレポート、平文ファイルへ保存しません。

## 外部送信

Claude連携を有効にした場合、OAuthアクセストークンをAnthropicの使用量照会エンドポイントへの
認証にのみ使用します。Token Meter独自のサーバー、広告事業者、Analytics事業者へデータを送信しません。

アプリの更新確認を有効にしている場合、GitHub上の更新フィードへ接続し、更新のダウンロード時は
GitHub Releasesへ接続します。プロンプト、応答、トークン使用量、OAuthアクセストークンは更新確認に
含めません。自動更新確認はSettings > Updatesから無効化できます。

## ローカル保存

集計した利用量はアプリのApplication Support領域と、Widget表示用のApp Groupコンテナに保存します。
保存対象にOAuthアクセストークンは含まれません。

## ユーザーによる制御

Claude連携は設定画面から無効化できます。アプリを削除した後、関連データも削除したい場合は、
Token MeterのApplication SupportディレクトリとApp Groupコンテナを削除できます。

## 問い合わせ

不具合やプライバシーに関する問い合わせは、
[GitHub Issues](https://github.com/TakeruF/token_meter/issues)から連絡してください。
