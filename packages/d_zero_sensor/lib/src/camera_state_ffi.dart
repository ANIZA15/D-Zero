import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart' as pkg_ffi;

/// Native camera & scanner pipeline status corresponding to C `ZeroCameraStatus`.
enum ZeroCameraStatus {
  idle,
  initializing,
  streaming,
  paused,
  error,
}

/// Opaque FFI handle for the 704-byte (11 cache lines) `ZeroCameraSharedState` C++ struct.
final class ZeroCameraStateNative extends ffi.Opaque {}

typedef _NativeCreateState = ffi.Pointer<ZeroCameraStateNative> Function();
typedef DartCamCreateState = ffi.Pointer<ZeroCameraStateNative> Function();

typedef _NativeDestroyState = ffi.Void Function(
    ffi.Pointer<ZeroCameraStateNative>);
typedef DartCamDestroyState = void Function(ffi.Pointer<ZeroCameraStateNative>);

typedef _NativeResetCounters = ffi.Void Function(
    ffi.Pointer<ZeroCameraStateNative>);
typedef DartCamResetCounters = void Function(
    ffi.Pointer<ZeroCameraStateNative>);

typedef _NativeBeginDetections = ffi.Void Function(
    ffi.Pointer<ZeroCameraStateNative>);
typedef DartCamBeginDetections = void Function(
    ffi.Pointer<ZeroCameraStateNative>);

typedef _NativeSetBox = ffi.Void Function(
  ffi.Pointer<ZeroCameraStateNative>,
  ffi.Int32,
  ffi.Float,
  ffi.Float,
  ffi.Float,
  ffi.Float,
  ffi.Float,
);
typedef DartCamSetBox = void Function(
  ffi.Pointer<ZeroCameraStateNative>,
  int,
  double,
  double,
  double,
  double,
  double,
);

typedef _NativeCommitPayload = ffi.Void Function(
  ffi.Pointer<ZeroCameraStateNative>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Int32,
  ffi.Int64,
);
typedef DartCamCommitPayload = void Function(
  ffi.Pointer<ZeroCameraStateNative>,
  ffi.Pointer<ffi.Uint8>,
  int,
  int,
);

typedef _NativeScanLuma = ffi.Int32 Function(
  ffi.Pointer<ZeroCameraStateNative>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Int32,
  ffi.Int32,
  ffi.Int32,
  ffi.Float,
);
typedef DartCamScanLuma = int Function(
  ffi.Pointer<ZeroCameraStateNative>,
  ffi.Pointer<ffi.Uint8>,
  int,
  int,
  int,
  double,
);

/// Zero-overhead typed pointer accessor over C++ `ZeroCameraSharedState` (704 bytes).
///
/// Pre-casts the native shared memory address to `Pointer<Uint64>`, `Pointer<Int64>`,
/// `Pointer<Int32>`, `Pointer<Uint32>`, `Pointer<Float>`, and `Pointer<Uint8>` once at
/// initialization so VSync hot-path reads compile to single-instruction indexed memory loads.
final class ZeroCameraStateView {
  /// Total byte size of `ZeroCameraSharedState` (11 × 64-byte cache lines).
  static const int structByteSize = 704;

  /// Maximum concurrent detection boxes stored in shared memory.
  static const int maxDetections = 16;

  /// Floats per detection box (`[left, top, right, bottom, confidence]`).
  static const int floatsPerBox = 5;

  /// Maximum UTF-8 payload byte length.
  static const int maxPayloadBytes = 255;

  // 8-byte stride indices (_u64 / _i64)
  static const int _idxFrameCount64 = 0; // byte offset 0
  static const int _idxScanCount64 = 1; // byte offset 8
  static const int _idxUniqueScanCount64 = 2; // byte offset 16
  static const int _idxLastDecodeUs64 = 3; // byte offset 24
  static const int _idxLastPayloadHash64 = 10; // byte offset 80

  // 4-byte stride indices (_i32 / _u32 / _f32)
  static const int _idxFrameWidth32 = 10; // byte offset 40
  static const int _idxFrameHeight32 = 11; // byte offset 44
  static const int _idxStatus32 = 12; // byte offset 48
  static const int _idxActiveBoxCount32 = 13; // byte offset 52
  static const int _idxSeq32 = 14; // byte offset 56
  static const int _idxPayloadLen32 = 15; // byte offset 60
  static const int _idxCameraFps32 = 16; // byte offset 64
  static const int _idxMeanLuma32 = 17; // byte offset 68
  static const int _idxConfirmStreak32 = 22; // byte offset 88
  static const int _idxBoxesBase32 = 24; // byte offset 96 (80 floats)

  // 1-byte stride offset (_u8)
  static const int _offsetPayloadBytes = 416; // byte offset 416 (256 bytes)

  final ffi.Pointer<ZeroCameraStateNative> pointer;
  final bool allocatedByCalloc;
  final ffi.Pointer<ffi.Uint64> _u64;
  final ffi.Pointer<ffi.Int64> _i64;
  final ffi.Pointer<ffi.Int32> _i32;
  final ffi.Pointer<ffi.Uint32> _u32;
  final ffi.Pointer<ffi.Float> _f32;
  final ffi.Pointer<ffi.Uint8> _u8;

  ZeroCameraStateView(this.pointer, {this.allocatedByCalloc = false})
      : _u64 = pointer.cast<ffi.Uint64>(),
        _i64 = pointer.cast<ffi.Int64>(),
        _i32 = pointer.cast<ffi.Int32>(),
        _u32 = pointer.cast<ffi.Uint32>(),
        _f32 = pointer.cast<ffi.Float>(),
        _u8 = pointer.cast<ffi.Uint8>();

  /// Whether the underlying native pointer is non-null.
  @pragma('vm:prefer-inline')
  bool get isValid => pointer.address != 0;

  /// Seqlock sequence counter (even = stable snapshot, odd = write in progress).
  @pragma('vm:prefer-inline')
  int get seq => isValid ? _u32[_idxSeq32] : 0;

  /// Total camera frames processed by the native pipeline.
  @pragma('vm:prefer-inline')
  int get frameCount => isValid ? _u64[_idxFrameCount64] : 0;

  /// Total QR / barcode frames decoded.
  @pragma('vm:prefer-inline')
  int get scanCount => isValid ? _u64[_idxScanCount64] : 0;

  /// Total deduplicated unique QR codes decoded.
  @pragma('vm:prefer-inline')
  int get uniqueScanCount => isValid ? _u64[_idxUniqueScanCount64] : 0;

  /// Duration in microseconds of the most recent C++ decode pass.
  @pragma('vm:prefer-inline')
  int get lastDecodeUs => isValid ? _i64[_idxLastDecodeUs64] : 0;

  /// Smoothed native camera FPS.
  @pragma('vm:prefer-inline')
  double get cameraFps => isValid ? _f32[_idxCameraFps32] : 0.0;

  /// Mean luminance (`0.0..255.0`) of the active scan window.
  @pragma('vm:prefer-inline')
  double get meanLuma => isValid ? _f32[_idxMeanLuma32] : 0.0;

  /// Frame width in pixels.
  @pragma('vm:prefer-inline')
  int get frameWidth => isValid ? _i32[_idxFrameWidth32] : 0;

  /// Frame height in pixels.
  @pragma('vm:prefer-inline')
  int get frameHeight => isValid ? _i32[_idxFrameHeight32] : 0;

  /// Active status code (`0..4`).
  @pragma('vm:prefer-inline')
  int get statusRaw => isValid ? _i32[_idxStatus32] : 0;

  /// Number of currently active detection bounding boxes (`0..16`).
  @pragma('vm:prefer-inline')
  int get activeBoxCount =>
      isValid ? _i32[_idxActiveBoxCount32].clamp(0, maxDetections) : 0;

  /// Consecutive frame streak for the current QR payload.
  @pragma('vm:prefer-inline')
  int get confirmStreak => isValid ? _i32[_idxConfirmStreak32] : 0;

  /// FNV-1a 64-bit hash of the most recently decoded payload.
  @pragma('vm:prefer-inline')
  int get lastPayloadHash => isValid ? _u64[_idxLastPayloadHash64] : 0;

  /// Length in bytes of the UTF-8 payload in shared memory.
  @pragma('vm:prefer-inline')
  int get payloadLength =>
      isValid ? _u32[_idxPayloadLen32].clamp(0, maxPayloadBytes) : 0;

  /// Reads float component [comp] (`0=left, 1=top, 2=right, 3=bottom, 4=conf`)
  /// of detection slot [index] directly from C++ shared memory (`0` heap alloc).
  @pragma('vm:prefer-inline')
  double boxComponent(int index, int comp) {
    if (!isValid || index < 0 || index >= maxDetections) return 0.0;
    return _f32[_idxBoxesBase32 + index * floatsPerBox + comp];
  }

  /// Copies active bounding boxes directly into a destination [Float32List] (`length >= 80`)
  /// using a Seqlock-verified read without allocating any Dart objects.
  int copyBoxesInto(Float32List dst) {
    if (!isValid) return 0;
    int count = 0;
    for (int retry = 0; retry < 4; retry++) {
      final int s1 = _u32[_idxSeq32];
      if ((s1 & 1) != 0) continue;
      count = _i32[_idxActiveBoxCount32].clamp(0, maxDetections);
      final int totalFloats = count * floatsPerBox;
      for (int i = 0; i < totalFloats; i++) {
        dst[i] = _f32[_idxBoxesBase32 + i];
      }
      if (s1 == _u32[_idxSeq32]) break;
    }
    return count;
  }

  /// Decodes the current UTF-8 payload string from shared memory (called only when
  /// `lastPayloadHash` changes, keeping steady-state frames at 0 allocations).
  String readPayloadString() {
    if (!isValid) return '';
    final int len = payloadLength;
    if (len <= 0) return '';
    final Uint8List view = _u8.asTypedList(structByteSize);
    return utf8.decode(
      Uint8List.sublistView(view, _offsetPayloadBytes, _offsetPayloadBytes + len),
      allowMalformed: true,
    );
  }

  // --- Direct Shared-Memory Writers (fallback when C++ dylib is not linked) ---

  void resetDirect() {
    if (!isValid) return;
    _u32[_idxSeq32] = _u32[_idxSeq32] + 1;
    _u64[_idxFrameCount64] = 0;
    _u64[_idxScanCount64] = 0;
    _u64[_idxUniqueScanCount64] = 0;
    _i64[_idxLastDecodeUs64] = 0;
    _i32[_idxActiveBoxCount32] = 0;
    _u32[_idxPayloadLen32] = 0;
    _u64[_idxLastPayloadHash64] = 0;
    _i32[_idxConfirmStreak32] = 0;
    _u32[_idxSeq32] = _u32[_idxSeq32] + 1;
  }

  void beginDetectionsDirect() {
    if (!isValid) return;
    _u32[_idxSeq32] = _u32[_idxSeq32] + 1;
    _i32[_idxActiveBoxCount32] = 0;
  }

  void setBoxDirect(
    int index,
    double l,
    double t,
    double r,
    double b,
    double conf,
  ) {
    if (!isValid || index < 0 || index >= maxDetections) return;
    final int base = _idxBoxesBase32 + index * floatsPerBox;
    _f32[base] = l;
    _f32[base + 1] = t;
    _f32[base + 2] = r;
    _f32[base + 3] = b;
    _f32[base + 4] = conf <= 1.0 ? conf * 100.0 : conf;
    if (index + 1 > _i32[_idxActiveBoxCount32]) {
      _i32[_idxActiveBoxCount32] = index + 1;
    }
  }

  void commitPayloadDirect(
    ffi.Pointer<ffi.Uint8> utf8Ptr,
    int len,
    int decodeUs,
  ) {
    if (!isValid) return;
    _u64[_idxFrameCount64] = _u64[_idxFrameCount64] + 1;
    _i64[_idxLastDecodeUs64] = decodeUs;
    final int safeLen = len.clamp(0, maxPayloadBytes);
    int hash = 0xCBF29CE484222325;
    for (int i = 0; i < safeLen; i++) {
      final int byte = utf8Ptr[i];
      _u8[_offsetPayloadBytes + i] = byte;
      hash = (hash ^ byte) * 0x100000001B3;
    }
    _u8[_offsetPayloadBytes + safeLen] = 0;
    _u32[_idxPayloadLen32] = safeLen;
    _u64[_idxScanCount64] = _u64[_idxScanCount64] + 1;
    if (hash != _u64[_idxLastPayloadHash64]) {
      _u64[_idxLastPayloadHash64] = hash;
      _i32[_idxConfirmStreak32] = 1;
      _u64[_idxUniqueScanCount64] = _u64[_idxUniqueScanCount64] + 1;
    } else {
      _i32[_idxConfirmStreak32] = _i32[_idxConfirmStreak32] + 1;
    }
    _u32[_idxSeq32] = _u32[_idxSeq32] + 1;
  }
}

/// Native C++17 library bindings (`isLeaf: true`) for `d_zero_sensor`.
class ZeroCameraNativeBindings {
  static final ZeroCameraNativeBindings instance =
      ZeroCameraNativeBindings._();

  ffi.DynamicLibrary? _dylib;
  DartCamCreateState? _createState;
  DartCamDestroyState? _destroyState;
  DartCamResetCounters? _resetCounters;
  DartCamBeginDetections? _beginDetections;
  DartCamSetBox? _setBox;
  DartCamCommitPayload? _commitPayload;
  DartCamScanLuma? _scanLuma;

  /// Whether the native C++17 shared library (`libzero_sensor_native`) is linked.
  bool get hasNativeCppLibrary => _dylib != null;

  ZeroCameraNativeBindings._() {
    _dylib = _tryLoadLibrary();
    final ffi.DynamicLibrary? lib = _dylib;
    if (lib == null) return;
    _bindFunctions(lib);
  }

  void _bindFunctions(ffi.DynamicLibrary lib) {
    _createState = lib.lookupFunction<_NativeCreateState, DartCamCreateState>(
      'zero_camera_create_state',
      isLeaf: true,
    );
    _destroyState =
        lib.lookupFunction<_NativeDestroyState, DartCamDestroyState>(
      'zero_camera_destroy_state',
      isLeaf: true,
    );
    _resetCounters =
        lib.lookupFunction<_NativeResetCounters, DartCamResetCounters>(
      'zero_camera_reset_Counters',
      isLeaf: true,
    );
    _beginDetections =
        lib.lookupFunction<_NativeBeginDetections, DartCamBeginDetections>(
      'zero_camera_begin_detections',
      isLeaf: true,
    );
    _setBox = lib.lookupFunction<_NativeSetBox, DartCamSetBox>(
      'zero_camera_set_detection_box',
      isLeaf: true,
    );
    _commitPayload =
        lib.lookupFunction<_NativeCommitPayload, DartCamCommitPayload>(
      'zero_camera_commit_detection_payload',
      isLeaf: true,
    );
    _scanLuma = lib.lookupFunction<_NativeScanLuma, DartCamScanLuma>(
      'zero_camera_scan_luma_frame',
      isLeaf: true,
    );
  }

  /// Allocates and initializes a 704-byte `ZeroCameraSharedState` in native memory.
  ZeroCameraStateView allocateState() {
    final DartCamCreateState? fn = _createState;
    if (fn != null) {
      return ZeroCameraStateView(fn(), allocatedByCalloc: false);
    }
    final ffi.Pointer<ffi.Uint8> raw =
        pkg_ffi.calloc<ffi.Uint8>(ZeroCameraStateView.structByteSize);
    return ZeroCameraStateView(
      raw.cast<ZeroCameraStateNative>(),
      allocatedByCalloc: true,
    );
  }

  /// Frees a previously allocated [ZeroCameraStateView].
  void freeState(ZeroCameraStateView view) {
    if (!view.isValid) return;
    if (view.allocatedByCalloc) {
      pkg_ffi.calloc.free(view.pointer.cast<ffi.Uint8>());
      return;
    }
    _destroyState?.call(view.pointer);
  }

  /// Resets all counters and bounding boxes atomically.
  void resetCounters(ZeroCameraStateView view) {
    if (!view.isValid) return;
    final DartCamResetCounters? fn = _resetCounters;
    if (fn != null && !view.allocatedByCalloc) {
      fn(view.pointer);
      return;
    }
    view.resetDirect();
  }

  /// Begins a Seqlock detection write transaction.
  void beginDetections(ZeroCameraStateView view) {
    if (!view.isValid) return;
    final DartCamBeginDetections? fn = _beginDetections;
    if (fn != null && !view.allocatedByCalloc) {
      fn(view.pointer);
      return;
    }
    view.beginDetectionsDirect();
  }

  /// Writes a bounding box to slot [index] in shared memory.
  void setDetectionBox(
    ZeroCameraStateView view,
    int index,
    double l,
    double t,
    double r,
    double b,
    double conf,
  ) {
    if (!view.isValid) return;
    final DartCamSetBox? fn = _setBox;
    if (fn != null && !view.allocatedByCalloc) {
      fn(view.pointer, index, l, t, r, b, conf);
      return;
    }
    view.setBoxDirect(index, l, t, r, b, conf);
  }

  /// Commits the UTF-8 payload and closes the Seqlock write transaction.
  void commitDetectionPayload(
    ZeroCameraStateView view,
    ffi.Pointer<ffi.Uint8> utf8Ptr,
    int byteLen,
    int decodeUs,
  ) {
    if (!view.isValid) return;
    final DartCamCommitPayload? fn = _commitPayload;
    if (fn != null && !view.allocatedByCalloc) {
      fn(view.pointer, utf8Ptr, byteLen, decodeUs);
      return;
    }
    view.commitPayloadDirect(utf8Ptr, byteLen, decodeUs);
  }

  /// Executes the C++17 zero-allocation YUV420 Luma frame scanner directly on [lumaPtr].
  int scanLumaFrame(
    ZeroCameraStateView view,
    ffi.Pointer<ffi.Uint8> lumaPtr,
    int width,
    int height,
    int stride,
    double windowFraction,
  ) {
    if (!view.isValid || lumaPtr.address == 0) return 0;
    final DartCamScanLuma? fn = _scanLuma;
    if (fn != null && !view.allocatedByCalloc) {
      return fn(view.pointer, lumaPtr, width, height, stride, windowFraction);
    }
    return 0;
  }

  static ffi.DynamicLibrary? _tryLoadLibrary() {
    try {
      if (Platform.isMacOS) return _loadMacOSLibrary();
      if (Platform.isAndroid || Platform.isLinux) {
        return ffi.DynamicLibrary.open('libzero_sensor_native.so');
      }
      if (Platform.isIOS) {
        final proc = ffi.DynamicLibrary.process();
        return proc.providesSymbol('zero_camera_create_state') ? proc : null;
      }
      if (Platform.isWindows) {
        return ffi.DynamicLibrary.open('zero_sensor_native.dll');
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static ffi.DynamicLibrary? _loadMacOSLibrary() {
    final proc = ffi.DynamicLibrary.process();
    if (proc.providesSymbol('zero_camera_create_state')) return proc;
    const candidates = <String>[
      'src/libzero_sensor_native.dylib',
      'packages/d_zero_sensor/src/libzero_sensor_native.dylib',
      '../../src/libzero_sensor_native.dylib',
    ];
    for (final rel in candidates) {
      final f = File(rel);
      if (f.existsSync()) {
        return ffi.DynamicLibrary.open(f.absolute.path);
      }
    }
    return _buildMacOSDylib();
  }

  static ffi.DynamicLibrary? _buildMacOSDylib() {
    const targets = <(String, String)>[
      ('src/zero_camera_state.cpp', 'src/libzero_sensor_native.dylib'),
      (
        'packages/d_zero_sensor/src/zero_camera_state.cpp',
        'packages/d_zero_sensor/src/libzero_sensor_native.dylib',
      ),
    ];
    for (final (srcPath, outPath) in targets) {
      if (!File(srcPath).existsSync()) continue;
      final res = Process.runSync('clang++', [
        '-std=c++17',
        '-O3',
        '-dynamiclib',
        srcPath,
        '-o',
        outPath,
      ]);
      if (res.exitCode == 0 && File(outPath).existsSync()) {
        return ffi.DynamicLibrary.open(File(outPath).absolute.path);
      }
    }
    return null;
  }
}
