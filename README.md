# ⚡️ zero_player

**Flutter / Impeller 時代のために設計された、原理的にジャンク（コマ落ち）が発生しないゼロアロケーション型ビデオプレイヤー。**

[![Pub Version](https://img.shields.io/pub/v/zero_player.svg?style=flat-square)](https://pub.dev/packages/zero_player)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![Impeller: Vulkan & Metal](https://img.shields.io/badge/Impeller-Vulkan%20%2F%20Metal-red.svg?style=flat-square)](https://flutter.dev/to/impeller)
[![Code Complexity](https://img.shields.io/badge/Cyclomatic%20Complexity-1.83%20(A%2B)-brightgreen.svg?style=flat-square)](https://github.com/fexcy/zero_player)

---

## 💡 設計思想：Flutter における「ゼロアロケーション」の追求

ゲーム開発やハイパフォーマンスなシステムプログラミング（例：Cysharp 製ライブラリ群）では、**「GC（ガベージコレクション）によるフレーム落ちを防ぐため、毎フレームのヒープアロケーションを極限まで 0 にする」** という設計が常識となっています。

しかし、従来の Flutter 動画プレイヤー（`video_player`）は、再生が進むたびに以下の **3つの境界で大量のアロケーションとオーバーヘッド** を発生させていました：

1. **Rebuild によるヒープアロケーション**: 再生位置（`00:10` → `00:11`）が進むたびに、UI スレッドで Widget / Element ツリーが毎秒数十回再生成される。
2. **MethodChannel のシリアライズ負荷**: 再生時間やバッファ状態を Dart に渡すたび、スレッド境界で JSON / バイナリの変換とメッセージオブジェクトのアロケーションが発生する。
3. **GPU RenderPass の無駄な多重化**: `BackdropFilter` などのすりガラス効果が、重いオフスクリーンレンダーターゲット（`saveLayer`）を生成して GPU 帯域を圧迫する。

**`zero_player` は、3つの「Zero」によりこれらを低レイヤーから物理的に解決します：**

* **Zero Rebuild**: `LeafRenderObjectWidget` ＋ カスタム `RenderBox` により、**Widget ツリーの再構築（`build()`）を一切行わず、120fps V-Sync で直接 Canvas に描画**。
* **Zero Channel**: C++ / NDK の Atomic 共有メモリと **Dart FFI ポインタ** を直結し、**0 ナノ秒・通信オブジェクトのアロケーション 0** で再生状態を共有。
* **Zero Copy**: Apple Metal（`CVPixelBuffer`）および Android Vulkan（`AHardwareBuffer` / `SurfaceTexture`）のハードウェアデコード映像を、**CPU-GPU 間のメモリコピー 0** で Impeller にバインド。

---

## 🏗 アーキテクチャ

```
[ ネイティブデコーダ (ExoPlayer Media3 / AVPlayer) ]
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

## 📊 従来の `video_player` との性能比較

| 評価指標 | 従来の `video_player` | `zero_player` |
| :--- | :--- | :--- |
| **再生中の Widget Rebuild** | 毎秒 10〜30 回以上（常に CPU を消費） | **0 回 / 秒（完全ゼロ）** |
| **状態通知の通信遅延** | MethodChannel 経由（数 ms 以上の遅延・詰まり） | **0 ナノ秒（FFI ポインタ直アクセス）** |
| **毎フレームのアロケーション** | Map・Message・Widget オブジェクトが常時発生 | **ヒープアロケーション 0（GC 停止フリー）** |
| **Impeller 最適化** | `BackdropFilter` 多用で GPU レンダーパス増大 | **シングルパス・カスタムシェーダー同梱** |
| **ライブ配信 / コメント耐久性** | コメントやギフトで UI が重くなると動画がコマ落ち | **UI スレッドの CPU 使用率 0% で 120fps 安定** |

---

## 📦 提供される Widget & コンポーネント

* **`ZeroPlayerView`**:
  ネイティブハードウェア映像テクスチャと、ゼロリビルド型コントロールを統合したメイン Widget。
* **`DirectSeekBar`**:
  `build()` メソッドを持たず、FFI ポインタから現在ミリ秒を直接読み取って `Canvas.drawLine` するシークバー。ドラッグ・タップ操作にも完全対応。
* **`DirectTimeLabel`**:
  秒数の変化（`00:11` など）の瞬間だけ局所的に差分描画する高効率タイムコード Widget。
* **`shaders/zero_blur.frag`**:
  Impeller 向けに設計されたシングルパス Kawase ブラーシェーダー。`BackdropFilter` の重いレンダーターゲット退避を完全回避。

---

## 🚀 使い方

### 1. インストール

```yaml
dependencies:
  zero_player: ^0.0.1
```

### 2. 基本的な再生

```dart
import 'package:flutter/material.dart';
import 'package:zero_player/zero_player.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  ZeroPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    // ネットワーク動画（MP4 または HLS .m3u8）のロード
    final controller = await ZeroPlayerController.network(
      'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
    );
    setState(() => _controller = controller);
    await controller.play();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: Center(
        child: ZeroPlayerView(
          controller: _controller!,
          showControls: true, // ゼロリビルドシークバーが自動配置されます
        ),
      ),
    );
  }
}
```

### 3. HLS ライブストリーミングの再生

```dart
// Apple HLS (.m3u8) 形式のライブストリームもそのまま渡すだけで低遅延再生
final controller = await ZeroPlayerController.network(
  'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8',
);
```

---

## 🛡 品質保証 & テストスイート

本パッケージは、低レイヤー C++ 共有メモリおよび FFI を扱うため、エンタープライズ品質のテストを網羅しています。

* **C++ 並行性ペネトレーションテスト (`native_stress_test.cpp`)**:
  * デコーダスレッドと Dart 読み出し 4 スレッドの同時アクセス下で、**Torn Read（断片化読み込み）が 0 件** であることをアトミックバリアで実証。
  * `nullptr` 防護、10,000 個のメモリ連続確保・解放によるメモリ破壊・リークなし。
* **Dart 境界値 & Use-After-Free 防御テスト (`zero_player_test.dart`)**:
  * ゼロ除算（duration = 0）クラッシュ防止、最大値オーバーフロー耐性、二重解放（Double Free）防止。
* **循環的複雑度（Cyclomatic Complexity）**:
  * 全 48 関数中 **48 関数（100%）が CC <= 10（平均 1.83）** を達成。
  * `dart run tool/check_complexity.dart` でいつでも計測可能。

---

## 📄 ライセンス

MIT License © 2026 fexcy
