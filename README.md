# WallFlow

WallFlow は、好きな画像フォルダを選ぶだけで、macOS の画面に画像をゆっくり流せるシンプルなスライドショーアプリです。

写真やイラストをランダムに表示し、ウィンドウいっぱいに広げたり、顔が見える位置へ自動で寄せたりできます。

## ダウンロード

最新版は GitHub Releases からダウンロードできます。

[WallFlow をダウンロード](https://github.com/tadakado/WallFlow/releases/latest)

`WallFlow-0.1.0.dmg` を開き、`WallFlow.app` を `Applications` にドラッグしてください。

## 使い方

1. WallFlow を起動します。
2. `フォルダ選択` で画像フォルダを選びます。
3. 表示間隔を秒数で指定します。
4. `開始` を押すと、画像がランダムに切り替わります。

対応画像形式:

- jpg
- jpeg
- png
- heic

## 表示モード

- `全体`: 画像全体が見えるように表示します。
- `ウィンド`: ウィンドウいっぱいに画像を表示します。
- `顔検出`: 顔や注目領域が見える位置へ自動で寄せます。

`枠` をオンにすると、表示位置の判断に使った検出範囲を確認できます。

## 主な機能

- 画像フォルダの選択
- ランダムスライドショー
- 表示間隔の変更
- 前へ / 次へ
- 前回選択したフォルダの復元
- 時計オーバーレイ
- 写真の顔検出
- アニメ調画像向けの顔検出
- 顔が見つからない場合の注目領域検出

## macOS の警告について

現在のリリースは Developer ID による公証前のため、初回起動時に macOS の警告が出る場合があります。

その場合は、Finder で `WallFlow.app` を右クリックして `開く` を選んでください。次回以降は通常どおり起動できます。

## 開発者向け

Xcode で開く場合:

1. `WallFlow.xcodeproj` を Xcode で開く
2. `WallFlow` scheme を選ぶ
3. Run

コマンドラインでビルドする場合:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project WallFlow.xcodeproj \
  -scheme WallFlow \
  -configuration Debug \
  -derivedDataPath .DerivedData \
  build
```

リリース用 DMG の作成と GitHub Releases への公開手順は [RELEASE.md](RELEASE.md) を参照してください。

## ライセンス

WallFlow のアプリ本体は MIT License です。詳しくは [LICENSE](LICENSE) を参照してください。

同梱しているアニメ顔検出モデルについては [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) を参照してください。

## アニメ顔検出モデル

アニメ顔検出用に、物体検出形式の Core ML モデルを `AnimeFaceDetector.mlmodelc` として同梱しています。
モデルは `deepghs/anime_face_detection` の `face_detect_v1.4_n` を Core ML に変換したものです。

アプリは以下の順番で表示位置を決めます。

1. Apple Vision の実写顔検出
2. `AnimeFaceDetector.mlmodelc` によるアニメ顔検出
3. Apple Vision の注目領域検出
