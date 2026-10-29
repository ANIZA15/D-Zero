# ⚡️ d-zero (Dart Zero)

**Flutter / Impeller 時代のために設計された、原理的にジャンク（コマ落ち）が発生しないゼロアロケーション Widget スイート。**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![Impeller: Vulkan & Metal](https://img.shields.io/badge/Impeller-Vulkan%20%2F%20Metal-red.svg?style=flat-square)](https://flutter.dev/to/impeller)

---

## 💡 コンセプト：Flutter における「ゼロアロケーション」

ゲーム開発やハイパフォーマンスシステムプログラミング（例：Cysharp 製 C# ライブラリ群）では、**「GC（ガベージコレクション）によるフレーム落ちを防ぐため、毎フレームのヒープアロケーションを極限まで 0 にする」** という設計が常識です。

`d-zero` は、従来の Flutter UI 開発で当たり前とされてきた **「毎フレームの Widget リビルド」** や **「描画用 String / オブジェクトのヒープアロケーション」** を排除し、120fps / Impeller の極限性能を引き出すモジュラーモノレポです。

```
[ Traditional Flutter Widget ]
  State Change ──> setState() ──> Rebuild Widget Tree (Heap Allocations) ──> GC Spikes & Jank

[ d-zero Widget ]
  State Change ──> Pointer / Direct Notifier ──> ZeroRenderBox (0 Allocations) ──> Pure 120fps
```

---

## 📦 パッケージ一覧

| パッケージ | バージョン | 概要 |
| :--- | :--- | :--- |
| **[`zero_core`](packages/zero_core)** | `0.1.0` | **【共通基盤】** ゼロアロケーション RenderBox、数値・タイムコード直接描画エンジン、固定長リングバッファ、オブジェクトプール |
| **[`zero_player`](packages/zero_player)** | `0.0.2` | **【ビデオ】** C++ 共有メモリ & FFI ダイレクトマッピングによる完全ゼロジャンク動画プレイヤー |
| **[`zero_counter`](packages/zero_counter)** | `0.1.0` | **【カウンター・計器】** 秒間数百回の高速カウント・ストップウォッチをリビルド 0・String アロケーション 0 で描画 |
| *(Planned)* `zero_waveform` | - | **【オーディオ】** SoA リングバッファを用いた音声波形・スペクトラムアナライザー |
| *(Planned)* `zero_chart` | - | **【チャート】** 金融・IoT 向けの超高頻度リアルタイム時系列チャート |

---

## 🛠️ モノレポの開発コマンド (Melos & Pub Workspaces)

本プロジェクトは **Dart Pub Workspaces** および **Melos** で管理されています。

```bash
# 依存関係の解決
flutter pub get

# 全パッケージの静的解析
melos run analyze

# 全パッケージのテスト実行
melos run test

# キャッシュ・ビルド成果物のクリーン
melos run clean
```

---

## 📜 ライセンス

MIT License © 2026 Kotaro Fujimoto (ANIZA15 / fexcy)
