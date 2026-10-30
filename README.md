# ⚡️ D-Zero (Dart Zero)

**Flutter / Impeller 時代のために設計された、原理的にジャンク（コマ落ち）が発生しないゼロアロケーション Widget スイート。**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![Impeller: Vulkan & Metal](https://img.shields.io/badge/Impeller-Vulkan%20%2F%20Metal-red.svg?style=flat-square)](https://flutter.dev/to/impeller)
[![Melos: Monorepo](https://img.shields.io/badge/Monorepo-Melos-purple.svg?style=flat-square)](https://melos.invertase.dev/)

---

## 💡 なぜ「ゼロアロケーション」が極めて重要なのか？

現代のモバイル・デスクトップアプリは、**120Hz（ProMotion / 高リフレッシュレートディスプレイ）** の普及により、従来の 60fps（1フレームあたり 16.6ms）から **8.33ms という極限のフレームバジェット** で描画処理を完遂することが求められています。

### 1. Impeller 時代の「残されたボトルネック」
Flutter 3 以降で標準となった次世代レンダリングエンジン **Impeller** は、従来の Skia における最大の弱点であった **「シェーダーコンパイルジャンク（Shader Compilation Jank）」を AOT 事前コンパイルによって解消** しました。  
しかし、GPU パイプラインがどれだけ滑らかになっても、**Dart UI スレッドにおけるオブジェクト生成と GC（ガベージコレクション）による一時停止（GC Pause）が存在する限り、コマ落ちは原理的に防げません。**

### 2. Dart GC アーキテクチャとフレームドロップのメカニズム
Dart VM は世代別ガベージコレクション（Generational GC）を採用しています：
- **New Space (Scavenger)**: 生存期間の短いオブジェクトを高速に回収するマイナー GC。数ミリ秒で完了しますが、毎フレーム大量の一時オブジェクト（Widget、Element、RenderObject、String、Offset、Paint など）が生成されると、**アロケーションレートが限界に達し、頻繁な GC スパイクを引き起こします**。
- **8.33ms バジェットの枯渇**: 8.33ms のうち 2〜4ms を GC スキャベンジに奪われると、UI スレッドに残された時間はわずか 4〜6ms となり、アニメーションや複雑なレイアウト計算が間に合わず、**不可避なフレーム落ち（Jank）** に直結します。

### 3. ゲーム・低遅延システム設計思想の輸入
Cysharp 製の C# ライブラリ群（`UniTask`, `ZString`, `MemoryPack` など）に代表されるゲームエンジン（Unity）やハイパフォーマンスシステムプログラミングの世界では、**「毎フレームのヒープアロケーションを 0 に抑え、GC をそもそも発生させない」** という設計が絶対的な常識です。

`D-Zero` は、このゼロアロケーション思想を Flutter / Dart のアーキテクチャに直接適用し、高頻度更新（動画再生、ストップウォッチ、カウンター、音声波形、リアルタイムチャート等）においても **「GC 停止 0」「ウィジェットリビルド 0」「スレッド間通信遅延 0」** を実現します。

---

## 🚀 コアアーキテクチャ：4 つのゼロ

```
[ 従来の Flutter アプローチ ]
  状態更新 ──> setState() ──> Widget ツリー再構築 ──> 文字列/オブジェクトのアロケーション ──> GC スパイク & Jank
  ネイティブ通信 ──> MethodChannel (JSON/バイナリ直列化) ──> スレッドホップ & レイテンシ

[ D-Zero アーキテクチャ ]
  状態更新 ──> C++ 共有メモリ / Direct Notifier ──> Dart FFI ポインタ直接参照 (0 ns)
  描画処理 ──> ZeroRenderBox / オブジェクトプール (0 Allocations) ──> Impeller Direct Canvas ──> 安定 120fps
```

### 1. ⚡️ Zero Rebuild（ゼロリビルド）
- `Widget.build()` や `setState()` を完全にバイパス。
- `LeafRenderObjectWidget` とカスタム `RenderBox`（`ZeroRenderBox`）を直結し、変更通知を受け取ると `markNeedsPaint()` のみを発火して Canvas へ直接描画。
- ウィジェットツリーの差分検出・インスタンス生成コストをゼロに抑えます。

### 2. ⚡️ Zero Allocation（ゼロアロケーション）
- **文字列アロケーションの排除**: `00:10` や数値の表示において `int.toString()` や文字列フォーマット（ヒープ確保）を行わず、文字テクスチャ・グリフ幅をキャッシュした `ZeroNumberPainter` が数字をダイレクトに Canvas へ描画。
- **オブジェクトプーリング**: 毎フレーム必要となる描画用パラメータやデータ構造は `ZeroPool<T>` から再利用。
- **固定長リングバッファ**: `FloatRingBuffer`（Float32List 基盤）により、オーディオ波形や時系列データの追加・参照時における配列リサイズや再割り当てを排除。

### 3. ⚡️ Zero Channel（ゼロチャンネル）
- 従来の `MethodChannel` や `EventChannel` が抱える「JSON/バイナリの直列化・逆直列化」「スレッド切り替え」「メッセージオブジェクトのヒープ生成」を全廃。
- プラットフォーム側（C++ / Native）の Atomic 共有メモリを **Dart FFI ポインタ** で直接マッピング。**0 ナノ秒のレイテンシ** かつ **ヒープ消費ゼロ** でリアルタイム同期。

### 4. ⚡️ Zero Copy & Impeller Shader 最適化
- ネイティブ動画デコーダー（iOS `CVPixelBuffer`、Android `AHardwareBuffer` / `SurfaceTexture`）のテクスチャを CPU メモリへコピーすることなく Impeller の GPU パイプラインへ直結。
- 負荷の高い `BackdropFilter`（`saveLayer` による GPU オフスクリーンレンダーパスの増殖）を避け、シングルパスの **カスタム Kawase Blur フラグメントシェーダー（`zero_blur.frag`）** を採用。

---

## 📊 性能比較（従来アプローチ vs D-Zero）

| 指標 | 従来の Flutter 実装 | D-Zero アーキテクチャ | 改善効果 |
| :--- | :--- | :--- | :--- |
| **毎フレームの Widget リビルド** | 10〜60+ 回 / 秒 | **0 回 / 秒 (True Zero Rebuild)** | CPU 負荷の劇的低減 |
| **毎フレームのヒープアロケーション** | String, Map, Widget 等の継続生成 | **0 Bytes / フレーム (GC Free)** | GC スパイク・コマ落ちの根絶 |
| **ネイティブ状態の同期レイテンシ** | 数ミリ秒 (MethodChannel) | **0 ns (FFI Atomic Pointer 直読)** | 即時同期・完全なリップシンク |
| **Impeller GPU パイプライン** | `saveLayer` による多重レンダーパス | **シングルパス・カスタムシェーダー** | GPU 帯域・発熱・電力消費の抑制 |
| **高負荷 UI (Live チャット併用時)** | 高頻度なコマ落ち・発熱 | **動画・計器 UI の UI スレッド負荷 0%** | バックグラウンド描画の完全安定 |

---

## 📦 モノレポ・パッケージ構成

本リポジトリは **Dart Pub Workspaces** および **Melos** で管理されるモジュラーモノレポです。

```
D-Zero/
├── apps/
│   └── benchmark_app/   # ⚡️ 従来 Flutter vs D-Zero 統合比較ベンチマークアプリ
├── benchmarks/          # ⚡️ CLI マイクロベンチマーク (アロケーション/スループット定量計測)
└── packages/
    ├── d_zero_core/       # ゼロアロケーション共通基盤ライブラリ
    ├── d_zero_player/     # ゼロジャンク動画プレイヤー (ZPlayer, ZSeekBar, ZTimeLabel)
    ├── d_zero_counter/    # 高速カウンター・タイマー・価格ティッカー・FPS計 (ZCounter, ZStopwatch, ZCountdown, ZOdometer, ZPriceTicker, ZFPSMonitor)
    ├── d_zero_ui/         # 高頻度 UI コントロール (ZCard, ZBadge, ZButton, ZSwitch, ZSlider, ZRangeSlider, ZLinearProgress, ZCircularProgress, ZGauge, ZJoystick, ZKnob, ZMarquee, ZTypewriterText)
    ├── d_zero_waveform/   # リアルタイム音声波形・FFT・メーター (ZWaveform, ZSpectrumAnalyzer, ZAudioMeter)
    ├── d_zero_chart/      # 高頻度チャート・気配値板 (ZSparkline, ZCandlestickChart, ZHeatmap, ZOrderBook)
    ├── d_zero_particles/  # SoA パーティクル & 紙吹雪シミュレーション (ZParticles, ZConfetti)
    ├── d_zero_fx/         # saveLayer フリー視覚エフェクト (ZShimmer, ZBlur, ZRipple, ZLiquidProgress)
    ├── d_zero_canvas/     # 大量要素キャンバス (ZDanmaku, ZInfiniteGrid, ZFreehandCanvas)
    └── d_zero_sensor/     # カメラ枠オーバーレイ・センサー計器 (ZBarcodeScanner, ZCompass, ZLeveler)
```

### 🔗 各パッケージへのリンク

| パッケージ | バージョン | 説明 | リンク | サンプル App |
| :--- | :---: | :--- | :---: | :---: |
| **`d_zero_core`** | `0.1.0` | **【共通基盤】** ゼロアロケーション RenderBox（`ZeroRenderBox`）、単一 GPU ドローコール数値・通貨・オドメーター描画エンジン（`ZeroNumberPainter`）、固定長リングバッファ（`FloatRingBuffer`）、オブジェクトプール（`ZeroPool`）。 | [📦 パッケージ詳細](packages/d_zero_core) | [📱 サンプル](packages/d_zero_core/example) |
| **`d_zero_player`** | `0.0.2` | **【超低遅延ビデオ】** C++ Atomic 共有メモリ & Dart FFI ダイレクトマッピング、ゼロリビルド UI（`ZPlayer`, `ZDirectSeekBar`, `ZDirectTimeLabel`）を備えた動画プレイヤー。 | [📦 パッケージ詳細](packages/d_zero_player) | [📱 比較アプリ](packages/d_zero_player/example) |
| **`d_zero_counter`** | `0.1.0` | **【数値・タイマー・計器】** `ZCounter`, `ZStopwatch`, `ZCountdown`, `ZOdometer` (`ZAnimatedNumber`), `ZPriceTicker` (`ZCurrencyLabel`), `ZFPSMonitor` (`ZFrameOverlay`)。 | [📦 パッケージ詳細](packages/d_zero_counter) | [📱 サンプル](packages/d_zero_counter/example) |
| **`d_zero_ui`** | `0.1.0` | **【高頻度 UI・入力コントロール】** `ZCard` (`ZSurfaceCard`), `ZBadge` (`ZNotificationBadge`), `ZButton` (`ZActionButton`), `ZSwitch` (`ZToggle`), `ZSlider`, `ZRangeSlider`, `ZLinearProgress`, `ZCircularProgress`, `ZGauge` (`ZSpeedometer`), `ZJoystick` (`ZVirtualPad`), `ZKnob` (`ZRotaryDial`), `ZMarquee` (`ZRollingText`), `ZTypewriterText`。 | [📦 パッケージ詳細](packages/d_zero_ui) | - |
| **`d_zero_waveform`** | `0.1.0` | **【リアルタイムオーディオ】** `ZWaveform` (`ZAudioVisualizer`), `ZSpectrumAnalyzer`, `ZAudioMeter` (`ZVUMeter`)。 | [📦 パッケージ詳細](packages/d_zero_waveform) | - |
| **`d_zero_chart`** | `0.1.0` | **【高頻度チャート・板情報】** `ZSparkline` (`ZRealtimeChart`), `ZCandlestickChart`, `ZHeatmap`, `ZOrderBook` (`ZDataGrid`)。 | [📦 パッケージ詳細](packages/d_zero_chart) | - |
| **`d_zero_particles`** | `0.1.0` | **【SoA パーティクル】** `ZParticles`, `ZConfetti`。 | [📦 パッケージ詳細](packages/d_zero_particles) | - |
| **`d_zero_fx`** | `0.1.0` | **【ゼロ saveLayer 視覚効果】** `ZShimmer` (`ZSkeleton`), `ZBlur` (`ZGlassContainer`), `ZRipple` (`ZInkWell`), `ZLiquidProgress` (`ZWaveFilter`)。 | [📦 パッケージ詳細](packages/d_zero_fx) | - |
| **`d_zero_canvas`** | `0.1.0` | **【大量要素・高速キャンバス】** `ZDanmaku` (`ZChatStream`), `ZInfiniteGrid` (`ZCanvasGrid`), `ZFreehandCanvas`。 | [📦 パッケージ詳細](packages/d_zero_canvas) | - |
| **`d_zero_sensor`** | `0.1.0` | **【カメラ・センサー直結 UI】** `ZBarcodeScanner` (`ZCameraPreview`), `ZCompass`, `ZLeveler`。 | [📦 パッケージ詳細](packages/d_zero_sensor) | - |

---

## ⚡️ ベンチマーク & サンプルアプリケーション

### 1. 統合比較ベンチマークアプリ (Flutter UI)
従来の `setState` + `Text` 等による実装と `D-Zero` スイートを Side-by-side で並べ、**リアルタイム FPS、フレームタイム (ms)、コマ落ち（Janks）、Widget リビルド回数** を可視化して比較できる Flutter アプリケーションです。

```bash
# 統合比較ベンチマークアプリの起動
cd apps/benchmark_app
flutter run
```

### 2. ターミナル・マイクロベンチマーク (Raw Performance)
純粋な Dart レベルでのアロケーションレート、GC 負荷、スループット（ops/sec）をターミナルで定量計測します。

```bash
# 全マイクロベンチマークの実行
dart run benchmarks/run_benchmarks.dart
```

### 3. 各プロジェクトの単体サンプル
```bash
# d_zero_core サンプル (FloatRingBuffer & ZeroPool)
cd packages/d_zero_core/example && flutter run

# d_zero_counter サンプル (高速カウンター & ストップウォッチ)
cd packages/d_zero_counter/example && flutter run

# d_zero_player サンプル (標準 video_player との動画再生比較)
cd packages/d_zero_player/example && flutter run
```

---

## 🛠️ モノレポの開発コマンド

```bash
# 全パッケージの依存関係解決 (Dart Pub Workspaces)
flutter pub get

# 全パッケージの静的コード解析
flutter analyze

# 全パッケージのユニットテスト実行
flutter test packages/d_zero_core/test packages/d_zero_counter/test packages/d_zero_player/test

# マイクロベンチマークの実行
dart run benchmarks/run_benchmarks.dart
```

---

## 📜 ライセンス

MIT License © 2026 ANIZA15
