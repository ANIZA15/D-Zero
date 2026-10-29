# 🚀 zero_player

**Flutter / Impeller 時代のために設計された、ジャンク（コマ落ち）が原理的に発生しない次世代ビデオプレイヤー Widget。**

---

## ⚡️ なぜ zero_player なのか？

従来の `video_player` は、Flutter の UI スレッド・Main thread・GPU レンダラーの境界で以下の課題を抱えていました：

1. **Rebuild Junk**: 再生位置（`00:10` → `00:11`）が進むたびに Widget ツリーが再構築され、UI スレッドが浪費される。
2. **MethodChannel Congestion**: `MethodChannel` / `EventChannel` のシリアライズ通信により、Main thread 負荷時にシークや再生更新が遅延する。
3. **GPU RenderPass Bottleneck**: `BackdropFilter` や透過オーバーレイによる過剰なオフスクリーンレンダーターゲット（`saveLayer`）の生成。

**`zero_player` は、3つの「Zero」でこれらを根本解決します：**

* **Zero Rebuild**: `LeafRenderObjectWidget` と `RenderBox` により、**Widget ツリーの build() を一切呼ばずに 120fps でシークバーとタイムコードを直接描画**。
* **Zero Channel**: C++ / NDK の Atomic 構造体と **Dart FFI** を直結し、**0 ナノ秒・通信オーバーヘッドゼロ** で再生状態を共有。
* **Zero Copy**: Metal (`CVPixelBuffer`) および Vulkan (`AHardwareBuffer`) の GPU メモリを Impeller パイプラインにダイレクトバインド。

---

## 🏗 アーキテクチャ

```
[ ネイティブデコーダ (ExoPlayer / AVPlayer) ]
     │
     ├─ [ 映像フレーム ] ── (Zero-Copy GPU Buffer) ──► [ Impeller テクスチャ ]
     │                                                         │ (1パス直接サンプリング)
     │                                                         ▼
     │                                                 [ zero_blur.frag ]
     │                                                         │
     └─ [ 再生ミリ秒 ] ──── (C++ Atomic 共有メモリ)               │
                                   │                           ▼
                        (Dart FFI ポインタ直読み)       [ DirectSeekBar / DirectTimeLabel ]
                                   │                           │ (RenderBox.paint)
                                   └──────► Canvas.draw ───────┘ (120fps 完全同期)
```

---

## 📦 提供される Widget / コンポーネント

| コンポーネント | 役割 | パフォーマンス上の利点 |
| :--- | :--- | :--- |
| **`ZeroPlayerView`** | メインプレイヤー Widget | テクスチャとオーバーレイを統合。 |
| **`DirectSeekBar`** | ゼロリビルド・シークバー | `build()` なし。FFI ポインタから数値を直接取得して Canvas 描画。 |
| **`DirectTimeLabel`** | ゼロリビルド・タイムスタンプ | 秒更新時の差分描画のみ。親 Widget を一切リビルドしない。 |
| **`zero_blur.frag`** | Impeller 専用シングルパスシェーダー | `BackdropFilter` の重いレンダーパスを排除し、1 パスですりガラス効果を適用。 |

---

## 🚀 使い方

```dart
import 'package:zero_player/zero_player.dart';

// 1. コントローラの作成（ネイティブ共有メモリのポインタが確保されます）
final controller = ZeroPlayerController.create();

// 2. プレイヤーの配置
ZeroPlayerView(
  controller: controller,
  showControls: true, // DirectSeekBar と DirectTimeLabel が自動配置されます
)
```

---

## 🛠 プロジェクト構成

```
zero_player/
├── lib/
│   ├── zero_player.dart                 # 公開 API
│   └── src/
│       ├── controller.dart              # ZeroPlayerController
│       ├── playback_state_ffi.dart      # FFI 共有メモリ構造体マッピング
│       └── widgets/
│           ├── direct_seek_bar.dart     # RenderBox 駆動シークバー
│           ├── direct_time_label.dart   # RenderBox 駆動タイムスタンプ
│           └── zero_video_view.dart     # メインビュー
├── src/                                 # ネイティブ C++ コア
│   ├── CMakeLists.txt
│   ├── zero_playback_state.h            # C/C++ Atomic 構造体定義
│   └── zero_playback_state.cpp          # メモリ操作実装
└── shaders/
    └── zero_blur.frag                   # Impeller 向けシングルパス Kawase シェーダー
```
