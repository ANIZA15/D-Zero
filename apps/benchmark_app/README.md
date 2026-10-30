# ⚡️ D-Zero Benchmark App

**`D-Zero`（100% `ZWidget` 構成のゼロアロケーション・ゼロリビルド UI スイート）と、従来の一般的な Flutter Widget（`setState` + `Text` / `Container` / `CustomPaint`）のパフォーマンス差をリアルタイムに可視化・比較する統合ストレステスト＆テレメトリアプリです。**

---

## 🚀 クイックスタート (Running the App)

正確なフレームレート（60fps / 120fps）、GC 挙動、および RSS メモリ推移を計測するため、**`--profile` または `--release` モード**での実行を推奨します。

```bash
cd apps/benchmark_app

# Release モードで起動（最も正確な FPS・メモリ計測）
flutter run --release

# macOS デスクトップで Release 起動
flutter run -d macos --release

# Profile モードで起動（Flutter DevTools 接続・タイムライン解析用）
flutter run --profile
```

---

## 🎯 アプリケーション構成（全 5 タブ）

画面上部の AppBar には常時稼働する **`ZFPSMonitor`（リアルタイム FPS & フレームタイム波形）** と **実メモリ使用量バッジ（`RSS Memory MB`）** が配置されており、どのタブを操作していてもフレームドロップやメモリスパイクを即座に監視できます。

### 1. 🎛️ Tab 1: Suite 比較デモ (`SuiteSwitchDemoView`)
全 `D-Zero` パッケージの `ZWidget` 群を統合した金融・オーディオ・センサー・パーティクル複合ダッシュボードと、同等の UI を通常の Flutter Widget で実装したダッシュボードをワンタップで比較できるメインデモです。

#### 🔀 3 つの表示切替モード
- **⚡️ `D-Zero (ZWidget 100%)`**:
  画面上のすべての動的コンポーネントを [`ZWidget`](../../packages/d_zero_core/lib/src/widgets/z_widget.dart)（`ZLeafWidget` / `ZSingleChildWidget`）のみで構成。毎フレーム数百箇所のデータが更新されても **Widget リビルド回数 `0`、一時オブジェクト生成 `0`** で描画します。
- **❌ `通常の Widget (高負荷)`**:
  同じデータ更新を `setState()` と標準 Widget（`Text`, `Container`, `LinearProgressIndicator`, `Slider`, `Switch`, `CustomPaint` 等）で処理。毎フレームのサブツリー再構築と大量の短命オブジェクト（`String`, `Paint`, `Offset`, `Color`）生成による FPS 低下・GC プレッシャーを再現します。
- **⚖️ `2画面同時比較 (Side-by-Side)`**:
  左右（または並列）に `D-Zero` と通常 Widget を同時配置し、同一 VSync 下での挙動とカウンタ推移を直接比較します。

#### 🔥 負荷調整スライダー（エクストリーム・ストレステスト）
1. **同時更新セル数スライダー（`12` 〜 `120` セル / 最大 `360` 個の `ZWidget`）**:
   - **High-Frequency Ticker Wall**: 各セルに価格ティッカーとプログレスバーを配置し、60/120fps で全セル同時に値を更新します。
   - `D-Zero` では全セルが単一の共有 GPU グリフアトラス（`ZeroNumberPainter`）から `Canvas.drawAtlas` で一括描画されるのに対し、通常モードでは最大 120 個の `Container` + `Text(toStringAsFixed)` + `LinearProgressIndicator` が毎フレーム再生成されます。
2. **同時パーティクル負荷スライダー（`1,000` 〜 `12,000` 個）**:
   - `D-Zero` の `ZParticles`（SoA 連続 `Float32List` 配列 + 単一バッチ GPU ドローコール）と、通常モードの `CustomPaint`（ループ内で毎フレーム数千回の `Paint` 生成 + 個別 `canvas.drawCircle`）の描画スループット差を検証できます。

---

### 2. ⏱️ Tab 2: カウンター & タイマー (`CounterComparisonView`)
- **比較対象**: `ZCounter` / `ZStopwatch` vs `setState()` + `Text`
- **負荷設定**: 更新周波数スライダー（`30Hz` 〜 `500Hz`）および On/Off トグル。
- **検証ポイント**:
  - 従来の `Text('${counter}')` やストップウォッチ文字列生成では、毎秒数百回の `String` ヒープ確保と `TextPainter.layout()` が走ります。
  - `ZCounter` / `ZStopwatch` は UTF-16 コードユニット計算のみで事前生成済みグリフアトラスから直接転送するため、500Hz の超高頻度通知でも UI スレッド負荷がフラットに保たれます。

---

### 3. ✨ Tab 3: パーティクル (`ParticlesBenchmarkView`)
- **比較対象**: `ZParticles` (Data-Oriented SoA) vs OOP `List<Particle>` + `CustomPainter`
- **負荷設定**: パーティクル数（`500` / `2,000` / `5,000` / `10,000` 個）のワンタップ切り替え。
- **検証ポイント**:
  - 10,000 パーティクルの物理演算（重力・速度減衰・境界バウンス）における CPU キャッシュ局所性（Structure of Arrays vs Array of Structures）と、GPU バッチ描画のフレームタイム差を可視化します。

---

### 4. 🧠 Tab 4: バッファ & プール (`BufferBenchmarkView`)
- **比較対象**:
  1. `FloatRingBuffer`（固定長 `Float32List` リングバッファ） vs 標準 `List<double>.add() + removeAt(0)`（O(N) 配列シフト）
  2. `ZeroPool<T>`（事前確保オブジェクトプール） vs 毎フレーム `new Object()` ヒープ割り当て
- **検証ポイント**:
  - 1 フレームあたり `500` 〜 `10,000` 回のストリーム挿入・取得を実行し、マイクロ秒（`µs`）単位の実行時間差とリアルタイム波形を描画します。

---

### 5. 📐 Tab 5: 設計 & 8.33ms バジェット (`ArchitectureOverviewView`)
- **120Hz (ProMotion) の 8.33ms フレームバジェット内訳**:
  - 従来の Flutter UI が New Space GC（Scavenger）と Widget Rebuild / Layout でバジェットを超過するメカニズムと、`D-Zero` が余裕を持って 8.33ms 以内に収める構造を図解します。
- **4 つのゼロ原則（The 4 Pillars of D-Zero）**:
  - **Zero Rebuild** / **Zero Allocation** / **Zero Channel** / **Zero Copy & Shader** のアーキテクチャ解説。

---

## 📊 リアルタイム診断 HUD (Live Diagnostics Metrics)

`Suite 比較デモ` タブの上部 HUD では、以下のテレメトリ指標をすべて **`ZWidget` 自身（`ZFPSMonitor`, `ZPriceTicker`, `ZCounter`）** を用いてゼロアロケーションで表示しています：

| HUD メトリクス | 表示 Widget | 計測内容と意味 |
| :--- | :--- | :--- |
| **FPS & Frame Bars** | `ZFPSMonitor` | 現在の FPS と直近フレームの処理時間ヒストグラム（緑: 快適 / 黄: 注意 / 赤: ジャンク）。 |
| **RSS Memory (Curr / Peak MB)** | `ZPriceTicker` × 2 | `ProcessInfo.currentRss` から取得したプロセス実メモリ使用量（現在値 MB / ピーク値 MB）。 |
| **D-Zero Rebuilds** | `ZCounter` | `D-Zero` モード稼働中のフレーム毎リビルド回数（常時 **`0`**）。 |
| **Traditional Rebuilds** | `ZCounter` | 通常 Widget モード稼働中に `setState()` によって発生した累積ツリー再構築回数。 |
| **Heap Objects Created (Trad)** | `ZCounter` | 通常 Widget モードでフレーム毎にヒープ領域へ新規割り当てされた一時オブジェクト（`Widget`, `String`, `Paint`, `Offset`, `Color`）の推定累積数。 |
| **VSync Slots / GPU Atlases** | `ZCounter` × 2 | `ZeroFrameScheduler` に登録されているアクティブな O(1) VSync スロット数と、`ZeroNumberPainter` で共有されている GPU グリフアトラス数。 |
| **Active ZWidgets on Screen** | `ZCounter` | 現在画面上にマウントされている `ZWidget`（`isZeroAllocation == true`）の総インスタンス数。 |

---

## 🧩 デモ内で稼働している全 `ZWidget` 一覧

`Suite 比較デモ` では、モノレポ内の全パッケージにまたがる以下の `ZWidget` が同時に連携動作しています：

| パッケージ | デモ内で使用している `ZWidget` クラス | 比較対象の通常 Flutter 実装 |
| :--- | :--- | :--- |
| **`d_zero_core`** | `ZWidget`, `ZLeafWidget`, `ZSingleChildWidget`, `ZeroFrameScheduler`, `ZeroNumberPainter`, `FloatRingBuffer` | `StatefulWidget`, `setState`, `Ticker`, `List<double>` |
| **`d_zero_counter`** | `ZFPSMonitor`, `ZPriceTicker`, `ZCounter`, `ZStopwatch`, `ZOdometer` | `Text(value.toStringAsFixed(2))` |
| **`d_zero_ui`** | `ZCard`, `ZBadge`, `ZButton`, `ZSwitch`, `ZSlider`, `ZLinearProgress`, `ZGauge`, `ZMarquee` | `Card`, `Container`, `ElevatedButton`, `Switch`, `Slider`, `LinearProgressIndicator` |
| **`d_zero_chart`** | `ZSparkline`, `ZCandlestickChart`, `ZOrderBook`, `ZHeatmap` | `CustomPaint` + ネストされた `Row`/`Column`/`Container` グリッド |
| **`d_zero_waveform`** | `ZWaveform`, `ZSpectrumAnalyzer`, `ZAudioMeter` | `CustomPaint` + `LinearProgressIndicator` |
| **`d_zero_particles`** | `ZParticles`, `ZConfetti` | オブジェクト配列 + 個別 `canvas.drawCircle` ループ |
| **`d_zero_fx`** | `ZLiquidProgress` | `LinearProgressIndicator` / `CustomPaint` |
| **`d_zero_canvas`** | `ZDanmaku` | `Stack` + `Positioned` + `Text` |
| **`d_zero_sensor`** | `ZCompass`, `ZLeveler` | `Container` + `Text` インジケーター |

---

## 🧪 テスト & 品質ゲート (Testing & Verification)

ベンチマークアプリには、モード切替・HUD 表示・狭小画面（360px 幅）でのレスポンシブレイアウト・パーティクル物理更新を検証するウィジェットテストが含まれています。

```bash
# ワークスペースルートから実行
# 1. 静的解析
flutter analyze

# 2. 循環的複雑度チェック (全関数 CC <= 15 を強制)
dart run tool/check_complexity.dart

# 3. ベンチマークアプリの Widget テスト実行
flutter test apps/benchmark_app
```
