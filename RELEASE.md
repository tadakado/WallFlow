# リリース手順

WallFlow は macOS 用の DMG を GitHub Release に添付して配布します。

このドキュメントはメンテナー向けです。通常の利用者向けの案内は `README.md` にまとめます。

## リリースの種類

WallFlow には、現実的には次の2つの配布ルートがあります。

- ad-hoc テストリリース: 早い段階で配布を試すためのリリースです。Developer ID 公証前のため、macOS Gatekeeper の警告が出る場合があります。
- Developer ID 公証済みリリース: 一般公開向けの推奨リリースです。Apple Developer Program、Developer ID 署名、公証が必要です。

現在の `v0.1.0` は ad-hoc テストリリースです。

## 事前準備

コマンドライン用のツールを一度だけインストールします。

```sh
brew install gh create-dmg
gh auth login
```

ツールが使えることを確認します。

```sh
gh auth status
create-dmg --version
```

Developer ID 公証済みリリースを作る場合は、Xcode から Developer ID Application 証明書を使える状態にしておきます。

## バージョン確認

リリースを作る前に確認します。

1. `WallFlow.xcodeproj` の `MARKETING_VERSION` を更新する
2. Bundle Identifier が `com.tadakado.wallflow` であることを確認する
3. ダウンロードファイル名や注意書きが変わる場合は `README.md` を更新する
4. 変更をすべてコミットする
5. 作業ツリーがきれいであることを確認する

```sh
git status --short
```

## DMG を作成する

ad-hoc のローカルビルドから作る場合:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/make-dmg.sh
```

このスクリプトは generic macOS の Release ビルドを作るため、通常は Intel Mac と Apple Silicon Mac の両方に対応したバイナリになります。

Xcode から Developer ID 署名済みの `WallFlow.app` を export した場合:

```sh
APP_PATH="/path/to/WallFlow.app" scripts/make-dmg.sh
```

DMG は次の場所に出力されます。

```text
dist/WallFlow-<version>.dmg
```

`scripts/make-dmg.sh` は `create-dmg` が使える場合はそれを利用します。制限のある環境などで `create-dmg` が最後まで完了できない場合は、`WallFlow.app` と `Applications` リンクだけを含むシンプルな DMG にフォールバックします。

## ビルドを検証する

アプリの対応アーキテクチャを確認します。

```sh
lipo -info .DerivedData/Build/Products/Release/WallFlow.app/Contents/MacOS/WallFlow
```

一般配布向けの期待値:

```text
x86_64 arm64
```

DMG を検証し、SHA-256 を計算します。

```sh
hdiutil verify dist/WallFlow-0.1.0.dmg
shasum -a 256 dist/WallFlow-0.1.0.dmg
```

SHA-256 の値は GitHub Release の説明に記載します。

## Developer ID 公証済みリリース

macOS の警告を減らして一般配布する場合は、Developer ID 署名と公証を行います。

Xcode を使う推奨手順:

1. `WallFlow.xcodeproj` を開く
2. `WallFlow` scheme を選ぶ
3. `Product > Archive` を実行する
4. Organizer で `Distribute App` を選ぶ
5. `Developer ID` を選ぶ
6. Xcode に署名と公証を行わせる
7. 公証済みの `WallFlow.app` を export する
8. `APP_PATH="/path/to/WallFlow.app" scripts/make-dmg.sh` で DMG を作成する

Xcode がアプリ本体だけを公証した場合は、公開前に DMG も公証して staple します。

```sh
xcrun notarytool submit dist/WallFlow-0.1.0.dmg --keychain-profile "notary-profile" --wait
xcrun stapler staple dist/WallFlow-0.1.0.dmg
spctl -a -t open --context context:primary-signature -v dist/WallFlow-0.1.0.dmg
```

## GitHub に公開する

タグを作成して push します。

```sh
git tag v0.1.0
git push origin main
git push origin v0.1.0
```

タグがすでに存在する場合は、意図したコミットを指しているか確認します。

```sh
git rev-parse v0.1.0
git rev-parse main
```

GitHub Release を作成し、DMG をアップロードします。

```sh
gh release create v0.1.0 dist/WallFlow-0.1.0.dmg \
  --target main \
  --title "WallFlow 0.1.0" \
  --notes "Initial public release of WallFlow."
```

既存の Release にある DMG を差し替える場合:

```sh
gh release upload v0.1.0 dist/WallFlow-0.1.0.dmg --clobber
```

Release の内容を確認します。

```sh
gh release view v0.1.0 --json tagName,name,url,assets
```

`dist/` 以下のファイルはコミットしません。
