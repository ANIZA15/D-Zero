import 'dart:ffi' as ffi;
import 'package:flutter/services.dart';
import 'playback_state_ffi.dart';

/// ゼロ通信・共有メモリ直結型のビデオコントローラ
class ZeroPlayerController {
  static const MethodChannel _channel = MethodChannel('com.fexcy.zero_player');

  final ffi.Pointer<ZeroPlaybackStateNative> statePointer;
  final int textureId;
  bool _isDisposed = false;

  ZeroPlayerController._({
    required this.statePointer,
    required this.textureId,
  });

  /// ネットワーク URL からプレイヤーを作成する
  /// ネイティブ側（iOS: AVPlayer, Android: ExoPlayer）でデコーダを立ち上げ、
  /// C++ 共有メモリのアドレス（stateAddress）を Dart FFI ポインタとして受け取ります。
  static Future<ZeroPlayerController> network(String url) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('create', {'url': url});
    if (result == null) {
      throw StateError('Failed to initialize zero_player');
    }

    final textureId = result['textureId'] as int;
    final stateAddress = result['stateAddress'] as int;
    final pointer = ffi.Pointer<ZeroPlaybackStateNative>.fromAddress(stateAddress);

    return ZeroPlayerController._(
      statePointer: pointer,
      textureId: textureId,
    );
  }

  /// テスト用のダミーコントローラ（ネイティブプラグインなしで UI 単体テストを行う場合）
  factory ZeroPlayerController.simulated() {
    final ptr = ZeroPlayerNativeBindings.instance.createState();
    return ZeroPlayerController._(
      statePointer: ptr,
      textureId: -1,
    );
  }

  /// 再生開始
  Future<void> play() async {
    if (_isDisposed || textureId == -1) return;
    await _channel.invokeMethod('play', {'textureId': textureId});
  }

  /// 一時停止
  Future<void> pause() async {
    if (_isDisposed || textureId == -1) return;
    await _channel.invokeMethod('pause', {'textureId': textureId});
  }

  /// シーク（位置変更）
  Future<void> seekTo(Duration position) async {
    if (_isDisposed || textureId == -1) return;
    await _channel.invokeMethod('seekTo', {
      'textureId': textureId,
      'positionMs': position.inMilliseconds,
    });
  }

  /// 現在の再生位置（ミリ秒）
  /// 【重要】MethodChannel等の通信を一切介さず、ネイティブのメモリを直接参照します（0ナノ秒）
  int get positionMs {
    if (_isDisposed) return 0;
    return statePointer.ref.positionMs;
  }

  /// 総再生時間（ミリ秒）
  int get durationMs {
    if (_isDisposed) return 0;
    return statePointer.ref.durationMs;
  }

  /// バッファ済み時間（ミリ秒）
  int get bufferedMs {
    if (_isDisposed) return 0;
    return statePointer.ref.bufferedMs;
  }

  /// 再生ステータス
  ZeroPlaybackStatus get status {
    if (_isDisposed) return ZeroPlaybackStatus.idle;
    final val = statePointer.ref.status;
    if (val >= 0 && val < ZeroPlaybackStatus.values.length) {
      return ZeroPlaybackStatus.values[val];
    }
    return ZeroPlaybackStatus.idle;
  }

  /// 再生進捗率 (0.0 〜 1.0)
  double get progress {
    final dur = durationMs;
    if (dur <= 0) return 0.0;
    final pos = positionMs;
    return (pos / dur).clamp(0.0, 1.0);
  }

  /// 手動シミュレーション更新（テスト用）
  void setPositionSimulated(int ms) {
    if (_isDisposed) return;
    ZeroPlayerNativeBindings.instance.setPosition(statePointer, ms);
  }

  /// 手動シミュレーション更新（動画長さ設定用）
  void setDurationSimulated(int ms) {
    if (_isDisposed) return;
    ZeroPlayerNativeBindings.instance.setDuration(statePointer, ms);
  }

  /// リソースの破棄
  Future<void> dispose() async {
    if (!_isDisposed) {
      _isDisposed = true;
      if (textureId != -1) {
        await _channel.invokeMethod('dispose', {'textureId': textureId});
      } else {
        ZeroPlayerNativeBindings.instance.destroyState(statePointer);
      }
    }
  }
}
