# Token Meter リリース手順書

次の依頼を受けたときに使う、署名・公証・Sparkle 更新・GitHub Release までを含む手順です。

> 更新を反映してzipを作って、commit/pushおよび、github releaseまで作成して。aboutページ更新も忘れずに

この手順は `v1.1.4` と同じ `scripts/release.sh` のフローで、`v1.1.8` の公開時に検証済みです。

## 前提条件

- `main` がリモートと同期していること
- Xcode、XcodeGen、GitHub CLI（`gh`）を利用できること
- Developer ID の署名証明書、Apple Developer アカウント、Sparkle の Keychain キー `com.tokenmeter.app` がこの Mac に設定済みであること
- `gh auth status` が成功し、対象リポジトリへの push・Release 作成権限があること

リリース対象外のローカルメモや作業中ファイルがあれば、事前に `git status --short` で確認し、コミットに含めないでください。

## 1. バージョンとリリースノートを更新する

次のバージョンを決めます。通常のパッチリリースでは `1.1.8` のように PATCH を 1 つ上げ、build number も 1 つ上げます。

1. `project.yml` の `MARKETING_VERSION` と `CURRENT_PROJECT_VERSION` を更新する。
2. `docs/releases/v<version>.md` を追加する。リリースノートは多言語対応で、1 ファイル内に全言語のセクションを持たせる。
   - 先頭に `# Token Meter <version>` のタイトル行を 1 つ置く。
   - その下に `## English` / `## 日本語` / `## 中文` / `## 한국어` の 4 セクションを、この順で並べる。各セクション内の小見出しは `### ` を使う（`docs/releases.html` が描画時に 1 段繰り上げる）。
   - 各言語に変更内容、動作環境、インストール手順を記載する。`docs/releases.html` は該当言語セクションが空のときだけ English にフォールバックするため、原則すべての言語を翻訳する。
3. `docs/releases.html` の `versions` 配列の先頭に `'v<version>'` を追加する。この配列に載っていないバージョンはリリースノート一覧に表示されない。
4. 公開サイト（About ページ）を更新する。
   - `docs/index.html` の 3 つの ZIP URL と日本語の表示バージョン
   - `docs/releases.html` の nav にある `header-download` の ZIP URL（index.html と同じ更新が必要。忘れやすい）
   - `docs/localization.js` の全言語（ja/en/zh-CN/ko）の `downloadVersion`
   - `docs/index.html` と `docs/releases.html` の両方にある `localization.js?v=<version>` のキャッシュバスター用クエリを新バージョンに更新する
   - ZIP の URL は `https://github.com/TakeruF/token_meter/releases/download/v<version>/TokenMeter-<version>.zip`

   バージョン参照の残りがないことを確認する（出力が空になること）:

   ```zsh
   rg -n "1\.1\.9" docs/index.html docs/releases.html docs/localization.js
   ```

まだ Release は存在しないため、この時点で About ページとリリースノートのリンクは一時的に未公開の URL を指します。後の Release 作成で有効になります。

## 2. 事前検証する

```zsh
xcodegen generate
swift test --package-path TokenMeterCore
xcodebuild build \
  -project TokenMeter.xcodeproj \
  -scheme TokenMeter \
  -configuration Release \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
git diff --check
```

テストまたはビルドが失敗した場合は、リリース作業を進めず修正します。

## 3. Developer ID 署名と Apple 公証を申請する

```zsh
scripts/release.sh prepare
```

このコマンドは、テスト、archive、Developer ID 署名済み export、署名検証、Apple Notary Service への upload を実行します。

`Config/ExportOptions-Notarize.plist` の `destination=upload` は Apple へ直接アップロードするため、`build/notarize-upload` が残らないことがあります。これは正常です。`xcrun notarytool` の別プロファイルを作る必要はありません。

Apple の処理が完了したら、次を実行します。

```zsh
scripts/release.sh finish
```

成功時には以下が生成・検証されます。

- `build/notarized/TokenMeter.app` — ステープル済みアプリ
- `build/TokenMeter-<version>.zip` — 公証済み配布 ZIP
- `appcast.xml` — EdDSA 署名済みの Sparkle 更新フィード
- `build/updates/TokenMeter<build>-*.delta` — Sparkle 差分更新

`finish` は `codesign`、`stapler validate`、`spctl` も実行します。`accepted` と `source=Notarized Developer ID` を確認してください。Sparkle のシンボリックリンク権限に関する delta の警告は、これまでのリリースと同様に許容されます。

## 4. 生成物と appcast を確認する

```zsh
VERSION=1.1.8
BUILD=11

plutil -extract CFBundleShortVersionString raw \
  build/notarized/TokenMeter.app/Contents/Info.plist
plutil -extract CFBundleVersion raw \
  build/notarized/TokenMeter.app/Contents/Info.plist
shasum -a 256 "build/TokenMeter-$VERSION.zip"
du -h "build/TokenMeter-$VERSION.zip"
git diff -- appcast.xml docs/index.html docs/releases.html docs/localization.js project.yml
```

確認項目:

- app の version/build と `project.yml` が一致する
- `appcast.xml` の full ZIP の URL、サイズ、EdDSA 署名が新バージョンを指す
- `appcast.xml` に新 build から過去 build への delta がある
- About ページの全 ZIP URL と全言語の表示バージョンが新バージョンになっている
- `docs/releases.html` の `versions` 配列に新バージョンが含まれ、`docs/releases/v<version>.md` に 4 言語すべてのセクションがある
- `docs/index.html` と `docs/releases.html` の `localization.js?v=` クエリが新バージョンになっている

## 5. コミット、タグ付け、push する

リリースに必要な変更だけを明示的に stage します。`build/` は `.gitignore` 済みなので stage しません。

```zsh
VERSION=1.1.8

git add \
  TokenMeterApp \
  TokenMeterWidget \
  appcast.xml \
  docs/index.html \
  docs/releases.html \
  docs/localization.js \
  "docs/releases/v$VERSION.md" \
  project.yml
git diff --cached --check
git commit -m "Release Token Meter $VERSION"
git tag -a "v$VERSION" -m "Release Token Meter $VERSION"
git push origin main "v$VERSION"
```

プッシュ後に確認します。

```zsh
git status --short --branch
git log -1 --oneline --decorate
git ls-remote --tags origin "refs/tags/v$VERSION"
```

## 6. GitHub Release を公開する

full ZIP と、appcast に記載したすべての delta を同じ Release に添付します。

```zsh
VERSION=1.1.8
BUILD=11

gh release create "v$VERSION" \
  "build/TokenMeter-$VERSION.zip" \
  build/updates/TokenMeter"$BUILD"-*.delta \
  --title "Token Meter $VERSION" \
  --notes-file "docs/releases/v$VERSION.md"

gh release view "v$VERSION" --json url,isDraft,isPrerelease,assets
```

Release は draft / prerelease ではなく公開状態にします。asset 数、ファイル名、サイズが `appcast.xml` と一致することを確認してください。

## 7. 公開後の最終確認

```zsh
curl -fsSL --max-time 20 https://takeruf.github.io/token_meter/ \
  | rg "releases/download/v$VERSION/TokenMeter-$VERSION.zip"
```

以下を最終報告します。

- リリース URL
- version / build
- ZIP の SHA-256
- 実行したテスト・署名・公証検証
- リリース対象から除外したローカルファイル（存在する場合）
