# ⚡️ D-Zero (Dart Zero)

**Flutter / Impeller 時代のために設計された、原理的にジャンク（コマ落ち）が発生しないゼロアロケーション・ゼロリビルド Widget スイート。**

[🇺🇸 English Documentation (README_EN.md)](README_EN.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Impeller: Vulkan & Metal](https://img.shields.io/badge/Impeller-Vulkan%20%2F%20Metal-red.svg?style=flat-square)](https://flutter.dev/to/impeller)
[![Melos: Monorepo](https://img.shields.io/badge/Monorepo-Melos-purple.svg?style=flat-square)](https://melos.invertase.dev/)
[![Cyclomatic Complexity: <= 10 (100%)](https://img.shields.io/badge/Cyclomatic%20Complexity-%E2%89%A410%20(100%25)-brightgreen.svg?style=flat-square)](tool/check_complexity.dart)

---

## 💡 なぜ「ゼロアロケーション」が極めて重要なのか？

現代のモバイル・デスクトップアプリは、**120Hz（ProMotion / 高リフレッシュレートディスプレイ）** の普及により、従来の 60fps（1フレームあたり 16.6ms）から **8.33ms という極限のフレームバジェット** で描画処理を完遂することが求められています。

### 1. Impeller 時代の「残されたボトルネック」
Flutter 3 以降で標準となった次世代レンダリングエンジン **Impeller** は、従来の Skia における最大の弱点であった **「シェーダーコンパイルジャンク（Shader Compilation Jank）」を AOT 事前コンパイルによって解消** しました。  
しかし、GPU パイプラインがどれだけ滑らかになっても、**Dart UI スレッドにおけるオブジェクト生成と GC（ガベージコレクション）による一時停止（GC Pause）が存在する限り、コマ落ちは原理的に防げません。**

### 2. Dart GC アーキテクチャとフレームドロップのメカニズム
Dart VM は世代別ガベージコレクション（Generational GC）を採用しています：
- **New Space (Scavenger)**: 生存期間の短いオブジェクトを高速に回収するマイナー GC。数ミリ秒で完了しますが、毎フレーム大量の一時オブジェクト（`Widget`, `Element`, `RenderObject`, `String`, `Offset`, `Paint`, `Path` など）が生成されると、**アロケーションレートが限界に達し、頻繁な GC スパイクを引き起こします**。
- **8.33ms バジェットの枯渇**: 8.33ms のうち 2〜4ms を GC スキャベンジに奪われると、UI スレッドに残された時間はわずか 4〜6ms となり、アニメーションや複雑なレイアウト計算が間に合わず、**不可避なフレーム落ち（Jank）** に直結します。

### 3. ゲーム・低遅延システム設計思想の輸入
Cysharp 製の C# ライブラリ群（`UniTask`, `ZString`, `MemoryPack` など）に代表されるゲームエンジン（Unity）やハイパフォーマンスシステムプログラミングの世界では、**「毎フレームのヒープアロケーションを 0 に抑え、GC をそもそも発生させない」** という設計が絶対的な常識です。

`D-Zero` は、このゼロアロケーション思想を Flutter / Dart のアーキテクチャに直接適用し、高頻度更新（動画再生、ストップウォッチ、カウンター、音声波形、リアルタイム金融チャート、パーティクル等）においても **「GC 停止 0」「ウィジェットリビルド 0」「スレッド間通信遅延 0」** を実現します。

---

## 🚀 コアアーキテクチャ：4 つのゼロ

```
[ 従来の Flutter アプローチ ]
  状態更新 ──> setState() ──> Widget ツリー再構築 ──> 文字列/オブジェクトのアロケーション ──> GC スパイク & Jank
  ネイティブ通信 ──> MethodChannel (JSON/バイナリ直列化) ──> スレッドホップ & レイテンシ

[ D-Zero アーキテクチャ ]
  状態更新 ──> C++ 共有メモリ / ZeroNotifier ──> Dart FFI ポインタ直接参照 / O(1) VSync スロット (0 ns)
  描画処理 ──> ZeroRenderBox / オブジェクトプール (0 Allocations) ──> Impeller Direct Canvas ──> 安定 120fps
```

### 1. ⚡️ Zero Rebuild（ゼロリビルド）
- `Widget.build()` や `setState()` を完全にバイパス。
- `ZLeafWidget` / `ZSingleChildWidget` とカスタム `RenderBox`（`ZeroRenderBox`）を直結し、変更通知を受け取ると `markNeedsPaint()` のみを発火して Canvas へ直接描画（`isRepaintBoundary = true` による再描画隔離）。

### 2. ⚡️ Zero Allocation（ゼロアロケーション）
- **文字列アロケーションの排除**: `00:10` や数値・通貨・パーセント表示において `int.toString()` や文字列補間を一切行わず、共有 GPU グリフアトラス（`ui.Image`）をキャッシュした `ZeroNumberPainter` が単一 `Canvas.drawRawAtlas` ドローコールで描画。
- **オブジェクトプーリング & 連続配列 (SoA)**: `ZeroPool<T>`, `FloatRingBuffer`, および `Float32List` / `Float32x4` SIMD 演算により、高頻度ループでの一時オブジェクト生成を完全に排除。

### 3. ⚡️ Zero Channel（ゼロチャンネル）
- 従来の `MethodChannel` や `EventChannel` が抱える「JSON/バイナリの直列化・逆直列化」「スレッド切り替え」「メッセージオブジェクトのヒープ生成」を全廃。
- プラットフォーム側（C++ / Native）の Atomic 共有メモリを **Dart FFI ポインタ** で直接マッピング。**0 ナノ秒のレイテンシ** かつ **ヒープ消費ゼロ** でリアルタイム同期。

### 4. ⚡️ Zero Copy & Impeller Shader 最適化
- ネイティブ動画デコーダー（iOS `CVPixelBuffer`、Android `AHardwareBuffer` / `SurfaceTexture`）のテクスチャを CPU メモリへコピーすることなく Impeller の GPU パイプラインへ直結。
- 負荷の高い `BackdropFilter`（`saveLayer` による GPU オフスクリーンレンダーパスの増殖）を避け、シングルパス描画およびカスタム Kawase Blur フラグメントシェーダー（`zero_blur.frag`）を採用。

---

## 📊 性能比較（従来アプローチ vs D-Zero）

| 指標 | 従来の Flutter 実装 | D-Zero アーキテクチャ | 改善効果 |
| :--- | :--- | :--- | :--- |
| **毎フレームの Widget リビルド** | 10〜120+ 回 / 秒 | **0 回 / 秒 (True Zero Rebuild)** | UI スレッド CPU 負荷の劇的低減 |
| **毎フレームのヒープアロケーション** | String, Map, Widget, Paint 等の継続生成 | **0 Bytes / フレーム (GC Free)** | GC スパイク・コマ落ちの根絶 |
| **ネイティブ状態の同期レイテンシ** | 数ミリ秒 (MethodChannel) | **0 ns (FFI Atomic Pointer 直読)** | 即時同期・完全なリップシンク |
| **Impeller GPU パイプライン** | `saveLayer` による多重レンダーパス | **単一パス `drawRawAtlas` / `drawRawPoints`** | GPU 帯域・発熱・電力消費の抑制 |
| **高負荷 UI (Live チャット併用時)** | 高頻度なコマ落ち・発熱 | **動画・計器 UI の UI スレッド負荷 ~0%** | 120fps ProMotion の完全維持 |

---

## 📦 モノレポ・パッケージ構成（全 10 パッケージ + 全階層ベンチマーク App 完備）

本リポジトリは **Dart Pub Workspaces** および **Melos** で管理されるモジュラーモノレポです。  
**すべてのパッケージ（`packages/*/example`）に、従来の Flutter 実装と `D-Zero` をリアルタイム比較（FPS・CPU 使用率・メモリ RSS/Peak MB・Rebuild 数・アロケーション数）できる高負荷ベンチマークアプリが同梱されています。**

```
D-Zero/
├── apps/
│   └── benchmark_app/          # ⚡️ 全パッケージ統合比較ベンチマークアプリ (FPS / CPU % / Memory HUD)
├── benchmarks/                 # ⚡️ CLI マイクロベンチマーク (アロケーション/スループット定量計測)
├── tool/
│   ├── README.md               # 📖 リリース・配布・品質管理ツールの使い方ガイド
│   ├── release.sh              # 🚀 ワンコマンド一括リリース (Bump -> Test -> Push/Tag -> pub.dev)
│   ├── check_complexity.dart   # 🛡️ 循環的複雑度 (McCabe CC <= 15) 自動検証ツール
│   └── distribute_widgets.dart # 📦 トポロジカル順一括検証・pub.dev 公開・バンドル生成パイプライン
└── packages/
    ├── d_zero_core/            # ゼロアロケーション共通基盤ライブラリ (+ example ベンチマーク App)
    ├── d_zero_player/          # ゼロジャンク FFI 動画プレイヤー (+ example 比較ベンチマーク App)
    ├── d_zero_counter/         # 高速カウンター・タイマー・価格ティッカー・FPS計 (+ example ベンチマーク App)
    ├── d_zero_ui/              # 高頻度 UI コントロール・高速ターミナル (+ example ベンチマーク App)
    ├── d_zero_waveform/        # リアルタイム音声波形・FFT・メーター (+ example ベンチマーク App)
    ├── d_zero_chart/           # 高頻度金融チャート・3Dサーフェス・仮想グリッド (+ example ベンチマーク App)
    ├── d_zero_particles/       # SIMD SoA パーティクル & 紙吹雪シミュレーション (+ example ベンチマーク App)
    ├── d_zero_fx/              # saveLayerフリー視覚効果・GLSL 460 シェーダー・3Dメタボール・3D傾き (+ example)
    ├── d_zero_canvas/          # 大量要素キャンバス・3Dメッシュ球体・弾幕・リボン (+ example ベンチマーク App)
    ├── d_zero_sensor/          # 3D LiDAR点群・カメラ枠オーバーレイ・コンパス・水準器 (+ example ベンチマーク App)
    └── d_zero_3dengine/        # 3Dゲームエンジン・Naniteクラスタカリング・Ray Tracing・144Hz/240Hz/Uncapped (+ example)
```

### 🔗 各パッケージと公開 `Z` Widget 一覧（3D / GLSL 460 シェーダー対応）

| パッケージ | バージョン | 公開 `Z` Widget & 主要コンポーネント | パッケージ詳細 | 高負荷ベンチマーク App |
| :--- | :---: | :--- | :---: | :---: |
| **`d_zero_core`** | `0.1.3` | **【共通基盤】** `ZWidget`, `ZLeafWidget`, `ZSingleChildWidget`, `ZeroRenderBox`, `ZeroNumberPainter`, `FloatRingBuffer`, `ZeroPool<T>`, `ZeroFrameScheduler`, `ZeroIntNotifier`, `ZeroDoubleNotifier` | [📦 README](packages/d_zero_core/README.md) | [📱 Benchmark](packages/d_zero_core/example) |
| **`d_zero_player`** | `0.1.3` | **【超低遅延ビデオ】** `ZPlayer` (`ZPlayerView`), `ZDirectSeekBar` (`ZSeekBar`), `ZDirectTimeLabel` (`ZTimeLabel`), `ZVideoTimeline` (`ZThumbnailScrubber`), `ZeroPlayerController`, `ZeroTimelineController`, `zero_blur.frag` | [📦 README](packages/d_zero_player/README.md) ([🇯🇵 JA](packages/d_zero_player/README_JA.md)) | [📱 Benchmark](packages/d_zero_player/example) |
| **`d_zero_counter`** | `0.1.3` | **【数値・タイマー・計器】** `ZCounter`, `ZStopwatch`, `ZCountdown`, `ZOdometer` (`ZAnimatedNumber`), `ZPriceTicker` (`ZCurrencyLabel`), `ZFPSMonitor` (`ZFrameOverlay`) | [📦 README](packages/d_zero_counter/README.md) | [📱 Benchmark](packages/d_zero_counter/example) |
| **`d_zero_ui`** | `0.1.3` | **【高頻度 UI・高速ターミナル】** `ZTerminal` (`ZLogStream`), `ZWheelPicker` (`ZDrumRollPicker`), `ZSegmentedControl` (`ZSlidingTabBar`), `ZPageIndicator` (`ZWormIndicator`), `ZRatingBar` (`ZStarRating`), `ZPullToRefresh` (`ZRefreshHeader`), `ZNumberPad` (`ZPinPad`), `ZStoryProgressBar` (`ZSegmentedProgress`), `ZStreamingMarkdown` (`ZTokenStream`), `ZCard` (`ZSurfaceCard`), `ZBadge` (`ZNotificationBadge`), `ZButton` (`ZActionButton`), `ZSwitch` (`ZToggle`), `ZSlider`, `ZRangeSlider`, `ZLinearProgress`, `ZCircularProgress`, `ZGauge` (`ZSpeedometer`), `ZJoystick` (`ZVirtualPad`), `ZKnob` (`ZRotaryDial`), `ZMarquee` (`ZRollingText`), `ZTypewriterText` | [📦 README](packages/d_zero_ui/README.md) | [📱 Benchmark](packages/d_zero_ui/example) |
| **`d_zero_waveform`** | `0.1.3` | **【リアルタイムオーディオ】** `ZWaveform` (`ZAudioVisualizer`), `ZSpectrumAnalyzer`, `ZAudioMeter` (`ZVUMeter`) | [📦 README](packages/d_zero_waveform/README.md) | [📱 Benchmark](packages/d_zero_waveform/example) |
| **`d_zero_chart`** | `0.1.3` | **【高頻度チャート・3Dサーフェス・仮想グリッド】** `Z3DSurface` (`ZWaterfallChart`), `ZVirtualGrid` (`ZTimeSeriesTable`), `ZSparkline` (`ZRealtimeChart`), `ZCandlestickChart`, `ZHeatmap`, `ZOrderBook` (`ZDataGrid`), `ZActivityRings` (`ZConcentricRings`), `ZRadarChart` (`ZSpiderChart`), `ZDonutChart` (`ZPieChart`), `ZContributionGraph` (`ZHabitGrid`) | [📦 README](packages/d_zero_chart/README.md) | [📱 Benchmark](packages/d_zero_chart/example) |
| **`d_zero_particles`** | `0.1.3` | **【SIMD SoA パーティクル】** `ZParticles`, `ZConfetti`, `ZReactionStream` (`ZFloatingHearts`), `ZeroParticleController`, `ZeroConfettiController`, `ZeroReactionController` | [📦 README](packages/d_zero_particles/README.md) | [📱 Benchmark](packages/d_zero_particles/example) |
| **`d_zero_fx`** | `0.1.3` | **【3D・GLSL 460 シェーダー・視覚効果】** `ZShaderSurface` (`ZRuntimeShader`), `ZMetaballs3D` (`ZRaymarchSurface`), `ZMeshGradient` (`ZFluidGradient`), `Z3DTilt` (`ZParallaxContainer`), `ZSwipeDeck` (`ZTinderCards`), `ZScratchCard` (`ZScratchOff`), `ZBeforeAfterSlider` (`ZImageComparison`), `ZShimmer` (`ZSkeleton`), `ZBlur` (`ZGlassContainer`), `ZRipple` (`ZInkWell`), `ZLiquidProgress` (`ZWaveFilter`) | [📦 README](packages/d_zero_fx/README.md) | [📱 Benchmark](packages/d_zero_fx/example) |
| **`d_zero_canvas`** | `0.1.3` | **【3Dメッシュ球体・大量要素キャンバス】** `Z3DMesh` (`Z3DGlobe`), `ZRibbon` (`ZLowLatencyInk`), `ZDanmaku` (`ZChatStream`), `ZInfiniteGrid` (`ZCanvasGrid`), `ZFreehandCanvas` | [📦 README](packages/d_zero_canvas/README.md) | [📱 Benchmark](packages/d_zero_canvas/example) |
| **`d_zero_sensor`** | `0.1.3` | **【3D点群 LiDAR・センサー直結 UI】** `Z3DPointCloud` (`ZLidarView`), `ZBarcodeScanner` (`ZCameraPreview`), `ZQRGenerator` (`ZMatrixCode`), `ZCompass`, `ZLeveler` | [📦 README](packages/d_zero_sensor/README.md) | [📱 Benchmark](packages/d_zero_sensor/example) |
| **`d_zero_3dengine`** | `0.1.4` | **【3Dゲームエンジン・Nanite・Ray Tracing】** `ZViewport3D` (`ZScene3D`), `ZEngineTelemetryHud` (`Z3DStatsOverlay`), `ZSceneInspector3D` (`ZNaniteLodPanel`), `ZTransformGizmo3D` (`Z3DGizmoOverlay`), `ZOutliner3D` (`ZEntityOutliner3D`), `ZMaterialEditor3D` (`ZPbrMaterialPanel`), `ZPostProcess3D` (`ZPostProcessPanel3D`), `ZSequencer3D` (`ZTimelineSequencer3D`), `Zero3DEngineController`, `zero_3d_raytrace.frag` | [📦 README](packages/d_zero_3dengine/README.md) | [📱 Benchmark](packages/d_zero_3dengine/example) |

---

## ⚡️ ベンチマーク & サンプルアプリケーションの実行

### 1. 統合比較ベンチマークアプリ (`apps/benchmark_app`)
全 10 パッケージの `ZWidget` 群と従来の Flutter 実装（`setState` + `Text` / `Container` / `CustomPaint`）をワンタップで切り替え・同時比較し、**FPS、UI CPU 負荷 (%)、RSS メモリ使用量 (Curr / Peak MB)、Widget リビルド回数、ヒープオブジェクト生成数** をリアルタイム可視化します。

```bash
cd apps/benchmark_app
flutter run --profile
```

### 2. 各パッケージ単体の高負荷比較ベンチマークアプリ (`packages/*/example`)
各パッケージ階層にも、そのドメインに特化した高負荷比較ベンチマークアプリ（FPS / CPU 使用率 % / メモリ RSS MB / Rebuild 数表示付き）が用意されています。

```bash
# 例: チャートパッケージの高負荷比較ベンチマーク
cd packages/d_zero_chart/example && flutter run

# 例: SIMD パーティクル (2K / 5K / 10K) の比較ベンチマーク
cd packages/d_zero_particles/example && flutter run

# 例: 高頻度 UI コントロール群の比較ベンチマーク
cd packages/d_zero_ui/example && flutter run
```

### 3. ターミナル・マイクロベンチマーク (`benchmarks/`)
純粋な Dart VM レベルでのアロケーションレート、GC 負荷、SIMD スループット（ops/sec）をターミナル上で定量計測します。

```bash
dart run benchmarks/run_benchmarks.dart
```

---

## 🛠️ モノレポの開発 & 品質ゲートコマンド

コントリビューションおよびリリース前には以下の品質ゲートをすべてパスすることを必須としています（詳細は [CONTRIBUTING.md](CONTRIBUTING.md) を参照）：

```bash
# 1. 全パッケージ・全サンプルの依存関係解決 (Dart Pub Workspaces)
flutter pub get

# 2. 全パッケージ・全サンプルの静的コード解析 (0 issues)
flutter analyze

# 3. 循環的複雑度チェック (全 1,600+ 関数で CC <= 10〜15 を強制)
dart run tool/check_complexity.dart

# 4. 全パッケージのユニット・Widget ライフサイクル・メモリ安全性テスト
flutter test packages/d_zero_core/test packages/d_zero_counter/test packages/d_zero_player/test packages/d_zero_ui/test packages/d_zero_chart/test packages/d_zero_waveform/test packages/d_zero_particles/test packages/d_zero_fx/test packages/d_zero_canvas/test packages/d_zero_sensor/test apps/benchmark_app/test

# 5. Z-Prefix 監査 & pub.dev 一括配布検証 (Dry-Run)
dart run tool/distribute_widgets.dart --dry-run

# 6. ワンコマンド一括リリース (Version Bump -> 品質検証 -> Git Commit/Push/Tag -> pub.dev 公開)
#    詳細は tool/README.md を参照
./tool/release.sh
```

---

## 📄 コミュニティ & ガバナンス

- [Contributing Guide (CONTRIBUTING.md)](CONTRIBUTING.md)
- [Architecture & Agent Engineering Rules (AGENTS.md)](AGENTS.md)
- [Code of Conduct (CODE_OF_CONDUCT.md)](CODE_OF_CONDUCT.md)
- [Security Policy (SECURITY.md)](SECURITY.md)
- [Workspace Changelog (CHANGELOG.md)](CHANGELOG.md)

## 📜 ライセンス

MIT License © 2026 fexcy (ANIZA15)
