# ⚡️ d-zero (Dart Zero)

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

`d-zero` は、このゼロアロケーション思想を Flutter / Dart のアーキテクチャに直接適用し、高頻度更新（動画再生、ストップウォッチ、カウンター、音声波形、リアルタイムチャート等）においても **「GC 停止 0」「ウィジェットリビルド 0」「スレッド間通信遅延 0」** を実現します。

---

## 🚀 コアアーキテクチャ：4 つのゼロ

```
[ 従来の Flutter アプローチ ]
  状態更新 ──> setState() ──> Widget ツリー再構築 ──> 文字列/オブジェクトのアロケーション ──> GC スパイク & Jank
  ネイティブ通信 ──> MethodChannel (JSON/バイナリ直列化) ──> スレッドホップ & レイテンシ

[ d-zero アーキテクチャ ]
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

## 📊 性能比較（従来アプローチ vs d-zero）

| 指標 | 従来の Flutter 実装 | d-zero アーキテクチャ | 改善効果 |
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
d-zero/
├── packages/
│   ├── zero_core/       # ゼロアロケーション共通基盤ライブラリ
│   ├── zero_player/     # ゼロジャンク動画プレイヤー
│   └── zero_counter/    # 高速カウンター & ストップウォッチ
└── apps/                # サンプル・検証用アプリケーション
```

### 🔗 各パッケージへのリンク

| パッケージ | バージョン | 説明 | リンク |
| :--- | :---: | :--- | :---: |
| **`zero_core`** | `0.1.0` | **【共通基盤】** ゼロアロケーション RenderBox（`ZeroRenderBox`）、文字列を生成しない数値・タイムコード描画エンジン（`ZeroNumberPainter`）、固定長リングバッファ（`FloatRingBuffer`）、オブジェクトプール（`ZeroPool`）。 | [📦 パッケージ詳細](packages/zero_core) |
| **`zero_player`** | `0.0.2` | **【超低遅延ビデオ】** C++ Atomic 共有メモリ & Dart FFI ダイレクトマッピング、ハードウェアゼロコピーテクスチャ、ゼロリビルド UI（`DirectSeekBar`, `DirectTimeLabel`）、Impeller 最適化 Kawase Blur シェーダーを備えた完全ゼロジャンク動画プレイヤー。 | [📦 パッケージ詳細](packages/zero_player) |
| **`zero_counter`** | `0.1.0` | **【超高速計器・カウンター】** 秒間数百回〜数千回のインクリメントやストップウォッチを、Widget リビルド 0・String アロケーション 0 で滑らかに描画する Widget 群。 | [📦 パッケージ詳細](packages/zero_counter) |
| *(Planned)* **`zero_waveform`** | - | **【リアルタイムオーディオ】** SoA（Structure of Arrays）リングバッファを用いた、音声波形およびスペクトラムアナライザー描画 Widget。 | 企画中 |
| *(Planned)* **`zero_chart`** | - | **【高頻度時系列チャート】** 金融ティックデータ・IoT センサー向けの超高頻度リアルタイム折れ線・オシロスコープ Widget。 | 企画中 |

---

## 🛠️ モノレポの開発コマンド

```bash
# 全パッケージの依存関係解決 (Dart Pub Workspaces)
flutter pub get

# 全パッケージの静的コード解析
melos run analyze

# 全パッケージのユニットテスト実行
melos run test

# キャッシュおよびビルド成果物のクリーンアップ
melos run clean
```

---

## 📜 ライセンス

MIT License © 2026 Kotaro Fujimoto (ANIZA15 / fexcy)
