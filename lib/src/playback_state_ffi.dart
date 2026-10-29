import 'dart:ffi' as ffi;
import 'dart:io';

// Cの enum ZeroPlaybackStatus に対応
enum ZeroPlaybackStatus {
  idle,
  buffering,
  playing,
  paused,
  completed,
  error,
}

// Cの struct ZeroPlaybackState に直接マッピングする Dart FFI 構造体
// 64ビット整数のメモリレイアウトを完全に一致させ、
// Dart VM から直接ポインタでメモリを覗き見（ゼロレイテンシ・ゼロ通信）する
final class ZeroPlaybackStateNative extends ffi.Struct {
  @ffi.Int64()
  external int positionMs;

  @ffi.Int64()
  external int durationMs;

  @ffi.Int64()
  external int bufferedMs;

  @ffi.Int32()
  external int status;

  @ffi.Float()
  external double playbackSpeed;

  @ffi.Int32()
  external int videoWidth;

  @ffi.Int32()
  external int videoHeight;

  @ffi.Uint64()
  external int frameCount;
}

// C ABI の型シグネチャ定義
typedef _NativeCreateState = ffi.Pointer<ZeroPlaybackStateNative> Function();
typedef _DartCreateState = ffi.Pointer<ZeroPlaybackStateNative> Function();

typedef _NativeDestroyState = ffi.Void Function(ffi.Pointer<ZeroPlaybackStateNative>);
typedef _DartDestroyState = void Function(ffi.Pointer<ZeroPlaybackStateNative>);

typedef _NativeSetPosition = ffi.Void Function(ffi.Pointer<ZeroPlaybackStateNative>, ffi.Int64);
typedef _DartSetPosition = void Function(ffi.Pointer<ZeroPlaybackStateNative>, int);

typedef _NativeSetDuration = ffi.Void Function(ffi.Pointer<ZeroPlaybackStateNative>, ffi.Int64);
typedef _DartSetDuration = void Function(ffi.Pointer<ZeroPlaybackStateNative>, int);

typedef _NativeSetStatus = ffi.Void Function(ffi.Pointer<ZeroPlaybackStateNative>, ffi.Int32);
typedef _DartSetStatus = void Function(ffi.Pointer<ZeroPlaybackStateNative>, int);

/// ネイティブライブラリのバインディング
class ZeroPlayerNativeBindings {
  static final ZeroPlayerNativeBindings instance = ZeroPlayerNativeBindings._();

  late final ffi.DynamicLibrary _dylib;
  late final _DartCreateState createState;
  late final _DartDestroyState destroyState;
  late final _DartSetPosition setPosition;
  late final _DartSetDuration setDuration;
  late final _DartSetStatus setStatus;

  ZeroPlayerNativeBindings._() {
    _dylib = _loadLibrary();
    createState = _dylib.lookupFunction<_NativeCreateState, _DartCreateState>('zero_create_playback_state');
    destroyState = _dylib.lookupFunction<_NativeDestroyState, _DartDestroyState>('zero_destroy_playback_state');
    setPosition = _dylib.lookupFunction<_NativeSetPosition, _DartSetPosition>('zero_set_position');
    setDuration = _dylib.lookupFunction<_NativeSetDuration, _DartSetDuration>('zero_set_duration');
    setStatus = _dylib.lookupFunction<_NativeSetStatus, _DartSetStatus>('zero_set_status');
  }

  static ffi.DynamicLibrary _loadLibrary() {
    if (Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    }
    if (Platform.isMacOS) {
      // テスト環境およびローカル開発環境の dylib フォールバック
      final candidates = [
        'test/libzero_player_test.dylib',
        'src/libzero_player_native.dylib',
        'libzero_player_native.dylib',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) {
          return ffi.DynamicLibrary.open(path);
        }
      }
      return ffi.DynamicLibrary.process();
    }
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libzero_player_native.so');
    }
    if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('zero_player_native.dll');
    }
    if (Platform.isLinux) {
      return ffi.DynamicLibrary.open('libzero_player_native.so');
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}
