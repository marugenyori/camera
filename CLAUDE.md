# このリポジトリについて（Claude 向けの作業メモ）

撮った後ではなく、**撮影中のプレビューの時点で**フィルム風・フラッシュ風・岩井俊二風に見えるカメラアプリ「フィルムカメラ」（SwiftUI）です。
持ち主は Mac を持っておらず、Windows PC と iPhone から作業します。ビルドの確認も配信も、すべて GitHub Actions（macOS ランナー）で行います。
仕組みは `marugenyori/claud_code`（PCIe学習アプリ）と同じです。

## 返答のしかた

- **日本語**で、専門用語には短い説明を添える
- 持ち主が自分で操作する手順（Apple Developer、App Store Connect、GitHub の Secrets など）は、画面の項目名どおりに番号付きで書く
- パスワード・API キー・`.p8` の中身は、チャットに貼ってもらわない。GitHub や Apple の画面に直接入力してもらう

## 構成

| パス | 内容 |
|---|---|
| `FilmCamera/App/` | `@main` の App |
| `FilmCamera/Camera/CameraModel.swift` | AVFoundation でカメラを動かす。映像フレームを `latestFrame` に置き、撮影した写真にフィルタをかけて写真アプリに保存する |
| `FilmCamera/Filters/LookMode.swift` | モードの一覧（フィルム／フラッシュ／岩井俊二風） |
| `FilmCamera/Filters/LookRenderer.swift` | 各モードの見え方（Core Image のフィルタの組み合わせ）。**プレビューと保存の両方で同じ関数を使う** |
| `FilmCamera/Views/CameraPreview.swift` | MTKView（Metal）で、フィルタをかけた映像を毎秒30コマ描く |
| `FilmCamera/Views/ContentView.swift` | 画面（モード切り替え、シャッター、日付、カメラ切り替え） |
| `FilmCamera.xcodeproj/` | Xcode プロジェクト（フォルダ同期方式。`FilmCamera/` にファイルを置くだけでビルド対象になる） |
| `.github/workflows/ios-build.yml` | ビルド確認と TestFlight 配信 |

- iOS 17 以上、Swift 5 モード、外部ライブラリなし
- 画面は縦向き固定。保存する写真の向きは `AVCaptureDevice.RotationCoordinator` で端末の傾きに合わせる
- 設定（モード、日付の有無）は `UserDefaults` に保存

## 見え方のしくみ

- プレビュー：カメラのフレーム → 画面サイズに縮小 → `LookRenderer.apply` → MTKView に描画
- 保存：フル解像度の写真 → 同じ `LookRenderer.apply` → JPEG → 写真アプリ
- 粒子の大きさ・周辺減光・日付の文字サイズは**画像サイズに対する割合**で決めているので、プレビューと保存で見た目がそろう。新しいモードを足すときも、ピクセルの固定値ではなく割合で書く
- 目標の見え方（持ち主が見せた参考写真より）
  - フィルム：ネガフィルムで撮った川遊びの写真。低いコントラスト、クリーム〜ピンクの白、緑っぽい影、くすんだ緑、ふんわりしたにじみ
  - フラッシュ：2000年代のコンデジで夜に直射フラッシュを使った写真。手前が平たく明るく、白飛び・黒つぶれ、色が濃い
  - 岩井俊二風：明るめ、淡い水色、低い彩度、ハイライトが大きくにじむ
- **色の調整は sRGB に変換してから行う**（`toSRGB` → 調整 → `toLinear`）。Core Image の作業空間はリニアなので、そのまま黒を持ち上げたりスクリーン合成したりすると、画面全体が白く霞む（実機で一度この失敗をした）
- **画質を落とさない**（持ち主の強い要望）。粒子（`grain`）・ぼかし・強いにじみは「画質が悪い」と受け取られたので、粒子は使わず、にじみ（`diffusion`）も控えめにしている
- 保存は 10 ビット HEIF（失敗したら JPEG）。長い辺が 6048px 未満なら Lanczos で拡大し、輪郭を軽く締めてから保存する（`upscaleForSaving`）。持ち主は「拡大してもいいから画質を良く」と希望している
- 色ごとのトーンカーブは `CIColorPolynomial`（3次式）、にじみはぼかした像のスクリーン合成（`diffusion`）で作っている
- **フラッシュは距離を使う**：背面カメラは LiDAR → デュアルカメラ → 広角の順に選び、フラッシュモードのときだけ距離を測る設定（`applyFormat`）に切り替える。距離（m）は `latestDepth`／写真の `depthData` から `LookOptions.depth` に渡し、`flashFalloff` で「近いほど明るい」マスクにする。距離が取れないときは中央を近いとみなす円形マスク
  - 距離を測れる設定は写真の最大解像度が下がる機種があるので、ほかのモードでは使わない
- 新しいモードは `LookMode` に case を足し、`LookRenderer.apply` の switch に処理を足すだけでよい

## ビルドと配信

- `main` に push すると、署名なしのシミュレータ向けビルドが自動で走る（エラーは実行結果ページの「ビルド結果」にまとまる）
- シミュレータにはカメラがないので「カメラが見つかりません」と出る。見え方の確認は実機（TestFlight）で行う
- TestFlight へ出すとき：Actions → iOS Build → Run workflow →「TestFlight にアップロードする」にチェック
- ビルド番号は Actions の実行番号が自動で入る
- 必要な Secrets：`APPLE_TEAM_ID`、`BUNDLE_ID`（`com.marugenyori.filmcamera`）、`ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_P8`
- Bundle ID はビルド設定 `APP_BUNDLE_ID` で渡す。`PRODUCT_BUNDLE_IDENTIFIER` をコマンドラインで上書きしない

## コードを変えるときの注意

- **複数行文字列（`"""`）**：中の行が、閉じる `"""` より左に出るとコンパイルエラーになる
- **排他アクセスエラー**：書き換え中の配列のクロージャから `self` を読むとエラーになる。`self` を使わない関数は `static` にする
- **スレッド**：`CameraModel` のセッション操作は `sessionQueue`、映像フレームは `videoQueue`、写真の加工は `processingQueue`。`@Published` の値はメインスレッドで変える
- **権限の説明文**：カメラ（`NSCameraUsageDescription`）と写真の保存（`NSPhotoLibraryAddUsageDescription`）は `project.pbxproj` の `INFOPLIST_KEY_` で設定している。マイクや位置情報を使うときは同じように追加する（ないと起動時に落ちる）
- 証明書の上限対策として、ワークフローの「CI が作った古い開発用証明書を整理」ステップ（`.github/scripts/cleanup_dev_certs.py`）で、アーカイブ前に自動で消している
- 色は `Color.accentColor` ではなく `.tint`、文字サイズは `.body` や `.caption` などを使う
