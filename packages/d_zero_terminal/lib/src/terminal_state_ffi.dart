import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

/// Terminal cursor visual shape corresponding to C `ZeroTerminalCursorStyle`.
enum ZeroTerminalCursorStyle {
  /// Solid block cursor (`0`).
  block,

  /// Vertical I-beam cursor (`1`).
  beam,

  /// Horizontal underline cursor (`2`).
  underline,
}

/// Terminal runtime status corresponding to C `ZeroTerminalStatus`.
enum ZeroTerminalStatus {
  /// Terminal is initialized and idle (`0`).
  idle,

  /// Connected to an active POSIX `forkpty` child shell (`1`).
  ptyRunning,

  /// Processing in-memory VT100/ANSI byte streams (`2`).
  streamOnly,

  /// Child shell process has exited (`3`).
  exited,

  /// Terminal encountered a PTY or initialization error (`4`).
  error,
}

/// Special terminal keys corresponding to C `ZeroTerminalKeyCode`.
enum ZeroTerminalKeyCode {
  /// Enter / Return (`\r`).
  enter(1),

  /// Backspace (`0x7F`).
  backspace(2),

  /// Horizontal Tab (`\t`).
  tab(3),

  /// Escape (`\x1b`).
  escape(4),

  /// Cursor Up (`\x1b[A`).
  up(5),

  /// Cursor Down (`\x1b[B`).
  down(6),

  /// Cursor Right (`\x1b[C`).
  right(7),

  /// Cursor Left (`\x1b[D`).
  left(8),

  /// Home (`\x1b[H`).
  home(9),

  /// End (`\x1b[F`).
  end(10),

  /// Page Up (`\x1b[5~`).
  pageUp(11),

  /// Page Down (`\x1b[6~`).
  pageDown(12),

  /// Forward Delete (`\x1b[3~`).
  deleteKey(13),

  /// SIGINT (`Ctrl+C`, `0x03`).
  ctrlC(14),

  /// EOF (`Ctrl+D`, `0x04`).
  ctrlD(15),

  /// Form Feed / Clear (`Ctrl+L`, `0x0C`).
  ctrlL(16);

  /// Native integer code passed to `zero_terminal_send_key_code`.
  final int code;
  const ZeroTerminalKeyCode(this.code);
}

/// Exact 128-byte (2 cache lines) Dart FFI struct matching C++ `ZeroTerminalState`.
final class ZeroTerminalStateNative extends ffi.Struct {
  // --- Cache Line 0 (Offsets 0..63): Grid Geometry, Cursor & Process State ---
  @ffi.Int32()
  external int cols;

  @ffi.Int32()
  external int rows;

  @ffi.Int32()
  external int scrollbackCapacity;

  @ffi.Int32()
  external int cursorCol;

  @ffi.Int32()
  external int cursorRow;

  @ffi.Int32()
  external int cursorVisible;

  @ffi.Int32()
  external int cursorStyle;

  @ffi.Int32()
  external int scrollOffset;

  @ffi.Int32()
  external int totalLines;

  @ffi.Int32()
  external int status;

  @ffi.Int32()
  external int childPid;

  @ffi.Int32()
  external int ptyFd;

  @ffi.Int32()
  external int exitCode;

  @ffi.Int32()
  external int altScreenActive;

  @ffi.Uint32()
  external int seq;

  @ffi.Uint32()
  external int magicGuard;

  // --- Cache Line 1 (Offsets 64..127): Telemetry & Dirty Row Mask ---
  @ffi.Uint64()
  external int bytesProcessed;

  @ffi.Uint64()
  external int framesCommitted;

  @ffi.Uint64()
  external int escapeSeqsParsed;

  @ffi.Uint64()
  external int dirtyRowMaskLo;

  @ffi.Uint64()
  external int dirtyRowMaskHi;

  @ffi.Float()
  external double throughputMbPerSec;

  @ffi.Float()
  external double parseLatencyNs;

  @ffi.Uint32()
  external int activeFgArgb;

  @ffi.Uint32()
  external int activeBgArgb;

  @ffi.Uint32()
  external int activeAttrs;

  @ffi.Uint32()
  external int reservedPad;
}

/// Zero-overhead typed pointer accessor over [ZeroTerminalStateNative].
final class ZeroTerminalStateView {
  /// Alive canary constant (`"ZTRM"` = `0x5A54524D`).
  static const int magicAlive = 0x5A54524D;

  /// Fixed viewport column stride (`256`).
  static const int viewportStride = 256;

  /// Maximum viewport rows (`128`).
  static const int maxViewportRows = 128;

  /// Total cells in the fixed viewport SoA arrays (`32,768`).
  static const int viewportCellCapacity = viewportStride * maxViewportRows;

  /// Total bins in the minimap summary arrays (`256`).
  static const int minimapBinCount = 256;

  // 32-bit indices (Cache Line 0: 0..15, Cache Line 1: 16..31)
  static const int _idxCols = 0;
  static const int _idxRows = 1;
  static const int _idxScrollbackCap = 2;
  static const int _idxCursorCol = 3;
  static const int _idxCursorRow = 4;
  static const int _idxCursorVisible = 5;
  static const int _idxCursorStyle = 6;
  static const int _idxScrollOffset = 7;
  static const int _idxTotalLines = 8;
  static const int _idxStatus = 9;
  static const int _idxChildPid = 10;
  static const int _idxPtyFd = 11;
  static const int _idxExitCode = 12;
  static const int _idxAltScreen = 13;
  static const int _idxSeq = 14;
  static const int _idxMagic = 15;

  // 64-bit indices (Cache Line 1: 8..12)
  static const int _idx64BytesProcessed = 8;
  static const int _idx64FramesCommitted = 9;
  static const int _idx64EscapeSeqs = 10;
  static const int _idx64DirtyLo = 11;
  static const int _idx64DirtyHi = 12;

  // Float / Uint32 indices in Cache Line 1
  static const int _idxThroughputMbS = 26;
  static const int _idxParseLatencyNs = 27;
  static const int _idxActiveFg = 28;
  static const int _idxActiveBg = 29;
  static const int _idxActiveAttrs = 30;

  /// Raw FFI pointer to the shared memory block.
  final ffi.Pointer<ZeroTerminalStateNative> pointer;
  final ffi.Pointer<ffi.Int32> _i32;
  final ffi.Pointer<ffi.Uint32> _u32;
  final ffi.Pointer<ffi.Uint64> _u64;
  final ffi.Pointer<ffi.Float> _f32;

  /// Creates a [ZeroTerminalStateView] wrapping [pointer].
  ZeroTerminalStateView(this.pointer)
      : _i32 = pointer.cast<ffi.Int32>(),
        _u32 = pointer.cast<ffi.Uint32>(),
        _u64 = pointer.cast<ffi.Uint64>(),
        _f32 = pointer.cast<ffi.Float>();

  /// Returns `true` if [pointer] is aligned and holds the active canary value.
  @pragma('vm:prefer-inline')
  bool get isValid {
    final int addr = pointer.address;
    if (addr == 0 || (addr & 63) != 0) return false;
    return _u32[_idxMagic] == magicAlive;
  }

  /// Active terminal width in columns.
  @pragma('vm:prefer-inline')
  int get cols => isValid ? _i32[_idxCols] : 0;

  /// Active terminal height in rows.
  @pragma('vm:prefer-inline')
  int get rows => isValid ? _i32[_idxRows] : 0;

  /// Maximum retained scrollback lines.
  @pragma('vm:prefer-inline')
  int get scrollbackCapacity => isValid ? _i32[_idxScrollbackCap] : 0;

  /// Zero-based cursor column.
  @pragma('vm:prefer-inline')
  int get cursorCol => isValid ? _i32[_idxCursorCol] : 0;

  /// Zero-based cursor row.
  @pragma('vm:prefer-inline')
  int get cursorRow => isValid ? _i32[_idxCursorRow] : 0;

  /// Whether the cursor is visible.
  @pragma('vm:prefer-inline')
  bool get cursorVisible => isValid && _i32[_idxCursorVisible] != 0;

  /// Raw cursor style index (`0..2`).
  @pragma('vm:prefer-inline')
  int get cursorStyleRaw => isValid ? _i32[_idxCursorStyle] : 0;

  /// Active scrollback offset in lines (`0` = bottom).
  @pragma('vm:prefer-inline')
  int get scrollOffset => isValid ? _i32[_idxScrollOffset] : 0;

  /// Total lines stored in the ring buffer.
  @pragma('vm:prefer-inline')
  int get totalLines => isValid ? _i32[_idxTotalLines] : 0;

  /// Raw terminal status index (`0..4`).
  @pragma('vm:prefer-inline')
  int get statusRaw => isValid ? _i32[_idxStatus] : 0;

  /// Spawned child shell PID (`-1` when not running).
  @pragma('vm:prefer-inline')
  int get childPid => isValid ? _i32[_idxChildPid] : -1;

  /// Master PTY file descriptor (`-1` when not running).
  @pragma('vm:prefer-inline')
  int get ptyFd => isValid ? _i32[_idxPtyFd] : -1;

  /// Child process exit status code.
  @pragma('vm:prefer-inline')
  int get exitCode => isValid ? _i32[_idxExitCode] : 0;

  /// Whether the alternate screen buffer (`?1049h`) is active.
  @pragma('vm:prefer-inline')
  bool get altScreenActive => isValid && _i32[_idxAltScreen] != 0;

  /// Seqlock sequence counter.
  @pragma('vm:prefer-inline')
  int get seq => isValid ? _u32[_idxSeq] : 0;

  /// Cumulative bytes parsed by the C++ VT engine.
  @pragma('vm:prefer-inline')
  int get bytesProcessed => isValid ? _u64[_idx64BytesProcessed] : 0;

  /// Cumulative viewport commits.
  @pragma('vm:prefer-inline')
  int get framesCommitted => isValid ? _u64[_idx64FramesCommitted] : 0;

  /// Cumulative ANSI/VT100 escape sequences parsed.
  @pragma('vm:prefer-inline')
  int get escapeSeqsParsed => isValid ? _u64[_idx64EscapeSeqs] : 0;

  /// Dirty bitmask for rows `0..63`.
  @pragma('vm:prefer-inline')
  int get dirtyRowMaskLo => isValid ? _u64[_idx64DirtyLo] : 0;

  /// Dirty bitmask for rows `64..127`.
  @pragma('vm:prefer-inline')
  int get dirtyRowMaskHi => isValid ? _u64[_idx64DirtyHi] : 0;

  /// Measured C++ parser throughput in MB/s.
  @pragma('vm:prefer-inline')
  double get throughputMbPerSec => isValid ? _f32[_idxThroughputMbS] : 0.0;

  /// Measured C++ parser latency in nanoseconds per byte.
  @pragma('vm:prefer-inline')
  double get parseLatencyNs => isValid ? _f32[_idxParseLatencyNs] : 0.0;

  /// Active SGR foreground color (`0xAARRGGBB`).
  @pragma('vm:prefer-inline')
  int get activeFgArgb => isValid ? _u32[_idxActiveFg] : 0xFFE6EDF3;

  /// Active SGR background color (`0xAARRGGBB`).
  @pragma('vm:prefer-inline')
  int get activeBgArgb => isValid ? _u32[_idxActiveBg] : 0xFF0D1117;

  /// Active SGR attribute bitmask.
  @pragma('vm:prefer-inline')
  int get activeAttrs => isValid ? _u32[_idxActiveAttrs] : 0;
}

typedef _NativeAbiVersion = ffi.Uint32 Function();
typedef DartAbiVersion = int Function();

typedef _NativeIsStateValid = ffi.Bool Function(
  ffi.Pointer<ZeroTerminalStateNative>,
);
typedef DartIsStateValid = bool Function(ffi.Pointer<ZeroTerminalStateNative>);

typedef _NativeCreateState = ffi.Pointer<ZeroTerminalStateNative> Function(
  ffi.Int32,
  ffi.Int32,
  ffi.Int32,
);
typedef DartCreateState = ffi.Pointer<ZeroTerminalStateNative> Function(
  int,
  int,
  int,
);

typedef _NativeStateVoid = ffi.Void Function(
  ffi.Pointer<ZeroTerminalStateNative>,
);
typedef DartStateVoid = void Function(ffi.Pointer<ZeroTerminalStateNative>);

typedef _NativeResize = ffi.Void Function(
  ffi.Pointer<ZeroTerminalStateNative>,
  ffi.Int32,
  ffi.Int32,
);
typedef DartResize = void Function(
  ffi.Pointer<ZeroTerminalStateNative>,
  int,
  int,
);

typedef _NativeStateI32 = ffi.Void Function(
  ffi.Pointer<ZeroTerminalStateNative>,
  ffi.Int32,
);
typedef DartStateI32 = void Function(
  ffi.Pointer<ZeroTerminalStateNative>,
  int,
);

typedef _NativeFeedBytes = ffi.Int32 Function(
  ffi.Pointer<ZeroTerminalStateNative>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Int32,
);
typedef DartFeedBytes = int Function(
  ffi.Pointer<ZeroTerminalStateNative>,
  ffi.Pointer<ffi.Uint8>,
  int,
);

typedef _NativeSpawnPty = ffi.Int32 Function(
  ffi.Pointer<ZeroTerminalStateNative>,
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Char>,
);
typedef DartSpawnPty = int Function(
  ffi.Pointer<ZeroTerminalStateNative>,
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Char>,
);

typedef _NativeSendKeyCode = ffi.Int32 Function(
  ffi.Pointer<ZeroTerminalStateNative>,
  ffi.Int32,
  ffi.Int32,
);
typedef DartSendKeyCode = int Function(
  ffi.Pointer<ZeroTerminalStateNative>,
  int,
  int,
);

typedef _NativeStressBurst = ffi.Int32 Function(
  ffi.Pointer<ZeroTerminalStateNative>,
  ffi.Int32,
  ffi.Uint32,
);
typedef DartStressBurst = int Function(
  ffi.Pointer<ZeroTerminalStateNative>,
  int,
  int,
);

typedef _NativeGetU32Ptr = ffi.Pointer<ffi.Uint32> Function(
  ffi.Pointer<ZeroTerminalStateNative>,
);
typedef DartGetU32Ptr = ffi.Pointer<ffi.Uint32> Function(
  ffi.Pointer<ZeroTerminalStateNative>,
);

typedef _NativeGetU8Ptr = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ZeroTerminalStateNative>,
);
typedef DartGetU8Ptr = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ZeroTerminalStateNative>,
);

/// Low-overhead (`isLeaf: true`) Dart FFI bindings to the C++17 terminal engine.
class ZeroTerminalNativeBindings {
  /// Singleton bindings instance.
  static final ZeroTerminalNativeBindings instance =
      ZeroTerminalNativeBindings._();

  late final ffi.DynamicLibrary _dylib;

  /// Returns the C++ ABI version.
  late final DartAbiVersion abiVersion;

  /// Checks whether a state pointer is alive and valid.
  late final DartIsStateValid isStateValid;

  /// Allocates and initializes a 128-byte `ZeroTerminalState` + ring buffer.
  late final DartCreateState createState;

  /// Stops any active PTY thread and frees a `ZeroTerminalState`.
  late final DartStateVoid destroyState;

  /// Resets all cells, scrollback, and parser state.
  late final DartStateVoid reset;

  /// Clears visible screen cells.
  late final DartStateVoid clearScreen;

  /// Resizes the active grid and notifies `TIOCSWINSZ` when PTY is active.
  late final DartResize resize;

  /// Sets the scrollback offset (`0` = latest bottom rows).
  late final DartStateI32 setScrollOffset;

  /// Scrolls by a relative line delta.
  late final DartStateI32 scrollBy;

  /// Updates cursor shape (`0..2`) and visibility (`0..1`).
  late final DartResize setCursorStyle;

  /// Clears the 128-bit dirty row mask.
  late final DartStateVoid clearDirtyMask;

  /// Feeds raw ANSI/VT100/UTF-8 bytes directly into the C++ state machine.
  late final DartFeedBytes feedBytes;

  /// Spawns a POSIX `forkpty` shell process and starts the C++ reader thread.
  late final DartSpawnPty spawnPty;

  /// Writes user input bytes to the PTY master FD (or local stream fallback).
  late final DartFeedBytes writeInput;

  /// Sends a special terminal key sequence by [ZeroTerminalKeyCode].
  late final DartSendKeyCode sendKeyCode;

  /// Terminates the active PTY child process and joins the reader thread.
  late final DartStateVoid stopPty;

  /// Generates and parses a high-speed TrueColor stress burst in C++.
  late final DartStressBurst generateStressBurst;

  /// Returns the fixed-address zero-copy viewport codepoint buffer (`Uint32*`).
  late final DartGetU32Ptr getViewportCodepoints;

  /// Returns the fixed-address zero-copy viewport foreground ARGB buffer (`Uint32*`).
  late final DartGetU32Ptr getViewportFgArgb;

  /// Returns the fixed-address zero-copy viewport background ARGB buffer (`Uint32*`).
  late final DartGetU32Ptr getViewportBgArgb;

  /// Returns the fixed-address zero-copy viewport attribute buffer (`Uint8*`).
  late final DartGetU8Ptr getViewportAttrs;

  /// Returns the fixed-address minimap color summary buffer (`Uint32*`).
  late final DartGetU32Ptr getMinimapColors;

  /// Returns the fixed-address minimap line density buffer (`Uint8*`).
  late final DartGetU8Ptr getMinimapFill;

  ZeroTerminalNativeBindings._() {
    _dylib = _loadLibrary();
    _bindCoreLifecycle();
    _bindStreamAndPty();
    _bindViewportPointers();
  }

  void _bindCoreLifecycle() {
    abiVersion = _dylib.lookupFunction<_NativeAbiVersion, DartAbiVersion>(
      'zero_terminal_abi_version',
      isLeaf: true,
    );
    isStateValid = _dylib.lookupFunction<_NativeIsStateValid, DartIsStateValid>(
      'zero_terminal_is_state_valid',
      isLeaf: true,
    );
    createState = _dylib.lookupFunction<_NativeCreateState, DartCreateState>(
      'zero_terminal_create_state',
      isLeaf: true,
    );
    destroyState = _dylib.lookupFunction<_NativeStateVoid, DartStateVoid>(
      'zero_terminal_destroy_state',
      isLeaf: true,
    );
    reset = _dylib.lookupFunction<_NativeStateVoid, DartStateVoid>(
      'zero_terminal_reset',
      isLeaf: true,
    );
    clearScreen = _dylib.lookupFunction<_NativeStateVoid, DartStateVoid>(
      'zero_terminal_clear_screen',
      isLeaf: true,
    );
    resize = _dylib.lookupFunction<_NativeResize, DartResize>(
      'zero_terminal_resize',
      isLeaf: true,
    );
    setScrollOffset = _dylib.lookupFunction<_NativeStateI32, DartStateI32>(
      'zero_terminal_set_scroll_offset',
      isLeaf: true,
    );
    scrollBy = _dylib.lookupFunction<_NativeStateI32, DartStateI32>(
      'zero_terminal_scroll_by',
      isLeaf: true,
    );
    setCursorStyle = _dylib.lookupFunction<_NativeResize, DartResize>(
      'zero_terminal_set_cursor_style',
      isLeaf: true,
    );
    clearDirtyMask = _dylib.lookupFunction<_NativeStateVoid, DartStateVoid>(
      'zero_terminal_clear_dirty_mask',
      isLeaf: true,
    );
  }

  void _bindStreamAndPty() {
    feedBytes = _dylib.lookupFunction<_NativeFeedBytes, DartFeedBytes>(
      'zero_terminal_feed_bytes',
      isLeaf: true,
    );
    spawnPty = _dylib.lookupFunction<_NativeSpawnPty, DartSpawnPty>(
      'zero_terminal_spawn_pty',
      isLeaf: true,
    );
    writeInput = _dylib.lookupFunction<_NativeFeedBytes, DartFeedBytes>(
      'zero_terminal_write_input',
      isLeaf: true,
    );
    sendKeyCode = _dylib.lookupFunction<_NativeSendKeyCode, DartSendKeyCode>(
      'zero_terminal_send_key_code',
      isLeaf: true,
    );
    stopPty = _dylib.lookupFunction<_NativeStateVoid, DartStateVoid>(
      'zero_terminal_stop_pty',
      isLeaf: true,
    );
    generateStressBurst =
        _dylib.lookupFunction<_NativeStressBurst, DartStressBurst>(
      'zero_terminal_generate_stress_burst',
      isLeaf: true,
    );
  }

  void _bindViewportPointers() {
    getViewportCodepoints =
        _dylib.lookupFunction<_NativeGetU32Ptr, DartGetU32Ptr>(
      'zero_terminal_get_viewport_codepoints',
      isLeaf: true,
    );
    getViewportFgArgb = _dylib.lookupFunction<_NativeGetU32Ptr, DartGetU32Ptr>(
      'zero_terminal_get_viewport_fg_argb',
      isLeaf: true,
    );
    getViewportBgArgb = _dylib.lookupFunction<_NativeGetU32Ptr, DartGetU32Ptr>(
      'zero_terminal_get_viewport_bg_argb',
      isLeaf: true,
    );
    getViewportAttrs = _dylib.lookupFunction<_NativeGetU8Ptr, DartGetU8Ptr>(
      'zero_terminal_get_viewport_attrs',
      isLeaf: true,
    );
    getMinimapColors = _dylib.lookupFunction<_NativeGetU32Ptr, DartGetU32Ptr>(
      'zero_terminal_get_minimap_colors',
      isLeaf: true,
    );
    getMinimapFill = _dylib.lookupFunction<_NativeGetU8Ptr, DartGetU8Ptr>(
      'zero_terminal_get_minimap_fill',
      isLeaf: true,
    );
  }

  /// Creates a zero-copy [Uint32List] view over the C++ viewport codepoints.
  Uint32List bindCodepointsView(ffi.Pointer<ZeroTerminalStateNative> state) {
    final ptr = getViewportCodepoints(state);
    if (ptr.address == 0) return Uint32List(0);
    return ptr.asTypedList(ZeroTerminalStateView.viewportCellCapacity);
  }

  /// Creates a zero-copy [Uint32List] view over the C++ viewport foreground colors.
  Uint32List bindFgArgbView(ffi.Pointer<ZeroTerminalStateNative> state) {
    final ptr = getViewportFgArgb(state);
    if (ptr.address == 0) return Uint32List(0);
    return ptr.asTypedList(ZeroTerminalStateView.viewportCellCapacity);
  }

  /// Creates a zero-copy [Uint32List] view over the C++ viewport background colors.
  Uint32List bindBgArgbView(ffi.Pointer<ZeroTerminalStateNative> state) {
    final ptr = getViewportBgArgb(state);
    if (ptr.address == 0) return Uint32List(0);
    return ptr.asTypedList(ZeroTerminalStateView.viewportCellCapacity);
  }

  /// Creates a zero-copy [Uint8List] view over the C++ viewport cell attributes.
  Uint8List bindAttrsView(ffi.Pointer<ZeroTerminalStateNative> state) {
    final ptr = getViewportAttrs(state);
    if (ptr.address == 0) return Uint8List(0);
    return ptr.asTypedList(ZeroTerminalStateView.viewportCellCapacity);
  }

  static ffi.DynamicLibrary? _loadMacOSTestFallback() {
    const candidates = <String>[
      'test/libzero_terminal_test.dylib',
      'packages/d_zero_terminal/test/libzero_terminal_test.dylib',
      'src/libzero_terminal_native.dylib',
      'packages/d_zero_terminal/src/libzero_terminal_native.dylib',
    ];
    for (final relativePath in candidates) {
      final file = File(relativePath);
      if (file.existsSync()) {
        return ffi.DynamicLibrary.open(file.absolute.path);
      }
    }
    return _buildMacOSTestDylib();
  }

  static ffi.DynamicLibrary? _buildMacOSTestDylib() {
    const buildTargets = <(String, String)>[
      ('src/zero_terminal_state.cpp', 'test/libzero_terminal_test.dylib'),
      (
        'packages/d_zero_terminal/src/zero_terminal_state.cpp',
        'packages/d_zero_terminal/test/libzero_terminal_test.dylib',
      ),
    ];
    for (final (srcPath, outPath) in buildTargets) {
      final srcFile = File(srcPath);
      if (!srcFile.existsSync()) continue;
      final outDir = File(outPath).parent;
      if (!outDir.existsSync()) outDir.createSync(recursive: true);
      final res = Process.runSync('clang++', [
        '-std=c++17',
        '-O2',
        '-dynamiclib',
        srcFile.path,
        '-o',
        outPath,
      ]);
      if (res.exitCode == 0 && File(outPath).existsSync()) {
        return ffi.DynamicLibrary.open(File(outPath).absolute.path);
      }
    }
    return null;
  }

  static ffi.DynamicLibrary _loadLibrary() {
    if (Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    }
    if (Platform.isMacOS) {
      final processLib = ffi.DynamicLibrary.process();
      if (processLib.providesSymbol('zero_terminal_create_state')) {
        return processLib;
      }
      return _loadMacOSTestFallback() ?? processLib;
    }
    if (Platform.isAndroid || Platform.isLinux) {
      return ffi.DynamicLibrary.open('libzero_terminal_native.so');
    }
    if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('d_zero_terminal_plugin.dll');
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}
