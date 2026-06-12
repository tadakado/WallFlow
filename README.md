# WallFlow

WallFlow は、好きな画像フォルダを選ぶだけで、macOS の画面に画像をゆっくり流せるシンプルなスライドショーアプリです。

写真やイラストをランダムに表示し、ウィンドウいっぱいに広げたり、顔が見える位置へ自動で寄せたりできます。

## ダウンロード

最新版は GitHub Releases からダウンロードできます。

[WallFlow をダウンロード](https://github.com/tadakado/WallFlow/releases/latest)

`WallFlow-1.0.0.dmg` を開き、`WallFlow.app` を `Applications` にドラッグしてください。

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
- `顔検出`: 検出した顔が見える位置へ自動で寄せます。

`枠` をオンにすると、検出した顔候補、信頼度、分類結果、表示位置の判断に使われたかどうかを確認できます。

## 主な機能

- 画像フォルダの選択
- ランダムスライドショー
- 表示間隔の変更
- 前へ / 次へ
- 前回選択したフォルダの復元
- 時計オーバーレイ
- 写真の顔検出
- アニメ調画像向けの顔検出
- 人物らしい顔候補の優先
- 動物キャラクターやマスコットへの誤フォーカス抑制

## macOS の警告について

Developer ID 公証済みのリリースでは、通常の macOS アプリとして開けます。

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

同梱しているアニメ顔検出モデルとアニメキャラクター分類モデルについては [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) を参照してください。

## 同梱モデル

アニメ顔検出用に、物体検出形式の Core ML モデルを `AnimeFaceDetector.mlmodelc` として同梱しています。
モデルは `deepghs/anime_face_detection` の `face_detect_v1.4_n` を Core ML に変換したものです。

アニメキャラクター分類用に、Core ML モデル `AnimeCharacterClassifier.mlmodelc` も同梱しています。
このモデルは `SmilingWolf/wd-vit-tagger-v3` から、WallFlow 用に `human` / `non_human` の分類へ変換したものです。
複数の顔がある場合は、`human` として判定された顔を優先して表示位置を決めます。
`non_human` として判定された顔候補は、動物キャラクターやマスコットへ誤ってフォーカスしにくくするため、優先対象から外します。

アニメ顔検出では、信頼度の高い上位50%の顔候補を表示位置の計算に使います。
`枠` をオンにした場合は、表示位置の計算に使わなかった低信頼度の候補も含めて表示します。

分類モデルを再作成する場合は、通常のターミナルで以下を実行します。

```zsh
./scripts/prepare_anime_character_classifier.sh
```

`AnimeCharacterClassifier.mlmodelc` はサイズが大きいため Git には含めず、配布用 DMG に同梱します。

アプリは以下の順番で表示位置を決めます。

1. Apple Vision の実写顔検出
2. `AnimeFaceDetector.mlmodelc` によるアニメ顔検出
3. 複数の顔候補がある場合は、人物らしい候補を優先し、動物寄りの候補を除外
