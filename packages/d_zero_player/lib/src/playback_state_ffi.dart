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
// 64バイト (1 キャッシュライン) のメモリレイアウトを完全に一致させ、
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

  @ffi.Int64()
  external int anchorTimeUs;

  @ffi.Uint32()
  external int seq;

  @ffi.Uint32()
  external int reserved;
}

/// Zero-overhead typed pointer accessor over [ZeroPlaybackStateNative].
///
/// Pre-casts the struct address to `Pointer<Int64>` / `Pointer<Int32>` / `Pointer<Uint32>`
/// once so hot-path reads compile to direct indexed memory loads (`_i64[idx]`)
/// without creating intermediate `Struct` wrapper views on every frame.
final class ZeroPlaybackStateView {
  // Int64 indices (8-byte stride)
  static const int _idxPositionMs = 0; // offset 0
  static const int _idxDurationMs = 1; // offset 8
  static const int _idxBufferedMs = 2; // offset 16
  static const int _idxAnchorTimeUs = 6; // offset 48

  // Int32 / Uint32 / Float indices (4-byte stride)
  static const int _idxStatus = 6; // offset 24
  static const int _idxPlaybackSpeed = 7; // offset 28
  static const int _idxVideoWidth = 8; // offset 32
  static const int _idxVideoHeight = 9; // offset 36
  static const int _idxSeq = 14; // offset 56

  final ffi.Pointer<ZeroPlaybackStateNative> pointer;
  final ffi.Pointer<ffi.Int64> _i64;
  final ffi.Pointer<ffi.Int32> _i32;
  final ffi.Pointer<ffi.Uint32> _u32;
  final ffi.Pointer<ffi.Float> _f32;

  ZeroPlaybackStateView(this.pointer)
      : _i64 = pointer.cast<ffi.Int64>(),
        _i32 = pointer.cast<ffi.Int32>(),
        _u32 = pointer.cast<ffi.Uint32>(),
        _f32 = pointer.cast<ffi.Float>();

  @pragma('vm:prefer-inline')
  bool get isValid => pointer.address != 0;

  @pragma('vm:prefer-inline')
  int get anchorPositionMs => isValid ? _i64[_idxPositionMs] : 0;

  @pragma('vm:prefer-inline')
  int get durationMs => isValid ? _i64[_idxDurationMs] : 0;

  @pragma('vm:prefer-inline')
  int get bufferedMs => isValid ? _i64[_idxBufferedMs] : 0;

  @pragma('vm:prefer-inline')
  int get anchorTimeUs => isValid ? _i64[_idxAnchorTimeUs] : 0;

  @pragma('vm:prefer-inline')
  int get statusRaw => isValid ? _i32[_idxStatus] : 0;

  @pragma('vm:prefer-inline')
  double get playbackSpeed => isValid ? _f32[_idxPlaybackSpeed] : 1.0;

  @pragma('vm:prefer-inline')
  int get videoWidth => isValid ? _i32[_idxVideoWidth] : 0;

  @pragma('vm:prefer-inline')
  int get videoHeight => isValid ? _i32[_idxVideoHeight] : 0;

  @pragma('vm:prefer-inline')
  int get seq => isValid ? _u32[_idxSeq] : 0;

  /// Reads the extrapolated playback position in milliseconds.
  ///
  /// When not actively playing (`status != 2`), reads directly from the
  /// memory-mapped struct via seqlock verification (~2.7x faster than FFI).
  /// When playing, delegates to `isLeaf: true` FFI for monotonic clock extrapolation.
  @pragma('vm:prefer-inline')
  int get displayPositionMs {
    if (!isValid) return 0;
    if (_i32[_idxStatus] != 2) {
      final int s1 = _u32[_idxSeq];
      final int pos = _i64[_idxPositionMs];
      if ((s1 & 1) == 0 && s1 == _u32[_idxSeq]) {
        return pos;
      }
    }
    return ZeroPlayerNativeBindings.instance.getDisplayPosition(pointer);
  }
}

// C ABI の型シグネチャ定義
typedef _NativeCreateState = ffi.Pointer<ZeroPlaybackStateNative> Function();
typedef _DartCreateState = ffi.Pointer<ZeroPlaybackStateNative> Function();

typedef _NativeDestroyState = ffi.Void Function(
    ffi.Pointer<ZeroPlaybackStateNative>);
typedef _DartDestroyState = void Function(ffi.Pointer<ZeroPlaybackStateNative>);

typedef _NativeSetPosition = ffi.Void Function(
    ffi.Pointer<ZeroPlaybackStateNative>, ffi.Int64);
typedef _DartSetPosition = void Function(
    ffi.Pointer<ZeroPlaybackStateNative>, int);

typedef _NativeSetPositionAnchor = ffi.Void Function(
    ffi.Pointer<ZeroPlaybackStateNative>, ffi.Int64, ffi.Float);
typedef _DartSetPositionAnchor = void Function(
    ffi.Pointer<ZeroPlaybackStateNative>, int, double);

typedef _NativeSetPlaybackSpeed = ffi.Void Function(
    ffi.Pointer<ZeroPlaybackStateNative>, ffi.Float);
typedef _DartSetPlaybackSpeed = void Function(
    ffi.Pointer<ZeroPlaybackStateNative>, double);

typedef _NativeSetDuration = ffi.Void Function(
    ffi.Pointer<ZeroPlaybackStateNative>, ffi.Int64);
typedef _DartSetDuration = void Function(
    ffi.Pointer<ZeroPlaybackStateNative>, int);

typedef _NativeSetStatus = ffi.Void Function(
    ffi.Pointer<ZeroPlaybackStateNative>, ffi.Int32);
typedef _DartSetStatus = void Function(
    ffi.Pointer<ZeroPlaybackStateNative>, int);

typedef _NativeGetDisplayPosition = ffi.Int64 Function(
    ffi.Pointer<ZeroPlaybackStateNative>);
typedef _DartGetDisplayPosition = int Function(
    ffi.Pointer<ZeroPlaybackStateNative>);

/// ネイティブライブラリのバインディング (`isLeaf: true` で呼び出しオーバーヘッドを最小化)
class ZeroPlayerNativeBindings {
  static final ZeroPlayerNativeBindings instance = ZeroPlayerNativeBindings._();

  late final ffi.DynamicLibrary _dylib;
  late final _DartCreateState createState;
  late final _DartDestroyState destroyState;
  late final _DartSetPosition setPosition;
  late final _DartSetPositionAnchor setPositionAnchor;
  late final _DartSetPlaybackSpeed setPlaybackSpeed;
  late final _DartSetDuration setDuration;
  late final _DartSetStatus setStatus;
  late final _DartGetDisplayPosition getDisplayPosition;

  ZeroPlayerNativeBindings._() {
    _dylib = _loadLibrary();
    createState = _dylib.lookupFunction<_NativeCreateState, _DartCreateState>(
      'zero_create_playback_state',
      isLeaf: true,
    );
    destroyState = _dylib.lookupFunction<_NativeDestroyState, _DartDestroyState>(
      'zero_destroy_playback_state',
      isLeaf: true,
    );
    setPosition = _dylib.lookupFunction<_NativeSetPosition, _DartSetPosition>(
      'zero_set_position',
      isLeaf: true,
    );
    setPositionAnchor = _dylib.lookupFunction<_NativeSetPositionAnchor, _DartSetPositionAnchor>(
      'zero_set_position_anchor',
      isLeaf: true,
    );
    setPlaybackSpeed = _dylib.lookupFunction<_NativeSetPlaybackSpeed, _DartSetPlaybackSpeed>(
      'zero_set_playback_speed',
      isLeaf: true,
    );
    setDuration = _dylib.lookupFunction<_NativeSetDuration, _DartSetDuration>(
      'zero_set_duration',
      isLeaf: true,
    );
    setStatus = _dylib.lookupFunction<_NativeSetStatus, _DartSetStatus>(
      'zero_set_status',
      isLeaf: true,
    );
    getDisplayPosition = _dylib.lookupFunction<_NativeGetDisplayPosition, _DartGetDisplayPosition>(
      'zero_get_display_position',
      isLeaf: true,
    );
  }

  static ffi.DynamicLibrary _loadLibrary() {
    if (Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    }
    if (Platform.isMacOS) {
      // テスト環境およびローカル開発環境の dylib フォールバック
      final candidates = [
        'test/libzero_player_test.dylib',
        'packages/d_zero_player/test/libzero_player_test.dylib',
        'src/libzero_player_native.dylib',
        'packages/d_zero_player/src/libzero_player_native.dylib',
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
