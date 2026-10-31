import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:flutter/foundation.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'terminal_state_ffi.dart';

/// Zero-allocation FFI PTY & VT100/ANSI terminal controller.
///
/// Maps the 128-byte cache-line-aligned C++ `ZeroTerminalState` and fixed-address
/// Structure-of-Arrays (SoA) viewport buffers directly into Dart via zero-copy
/// [Uint32List] and [Uint8List] views.
class ZeroPtyController implements Listenable {
  static const int _scratchCapacity = 65536;
  static final Uint32List _emptyU32 = Uint32List(0);
  static final Uint8List _emptyU8 = Uint8List(0);

  /// Direct FFI pointer to the 128-byte C++ `ZeroTerminalState`.
  final ffi.Pointer<ZeroTerminalStateNative> statePointer;
  final ZeroTerminalStateView _view;
  final ffi.Pointer<ffi.Uint8> _scratchPtr;
  late final Uint8List _scratchBytes;

  late final Uint32List _viewportCodepoints;
  late final Uint32List _viewportFgArgb;
  late final Uint32List _viewportBgArgb;
  late final Uint8List _viewportAttrs;
  late final Uint32List _minimapColors;
  late final Uint8List _minimapFill;

  final ZeroIntNotifier _revision = ZeroIntNotifier(0);
  int _lastObservedSeq = 0;
  bool _isDisposed = false;

  /// Creates a [ZeroPtyController] backed by C++ shared memory.
  factory ZeroPtyController({
    int cols = 80,
    int rows = 24,
    int scrollbackCapacity = 2048,
  }) {
    final bindings = ZeroTerminalNativeBindings.instance;
    final ptr = bindings.createState(cols, rows, scrollbackCapacity);
    return ZeroPtyController._(ptr);
  }

  /// Creates an in-memory simulated FFI terminal controller (alias of default constructor).
  factory ZeroPtyController.simulated({
    int cols = 80,
    int rows = 24,
    int scrollbackCapacity = 2048,
  }) {
    return ZeroPtyController(
      cols: cols,
      rows: rows,
      scrollbackCapacity: scrollbackCapacity,
    );
  }

  ZeroPtyController._(this.statePointer)
      : _view = ZeroTerminalStateView(statePointer),
        _scratchPtr = pkg_ffi.calloc<ffi.Uint8>(_scratchCapacity) {
    _scratchBytes = _scratchPtr.asTypedList(_scratchCapacity);
    final b = ZeroTerminalNativeBindings.instance;
    _viewportCodepoints = b.bindCodepointsView(statePointer);
    _viewportFgArgb = b.bindFgArgbView(statePointer);
    _viewportBgArgb = b.bindBgArgbView(statePointer);
    _viewportAttrs = b.bindAttrsView(statePointer);
    final mmColorPtr = b.getMinimapColors(statePointer);
    final mmFillPtr = b.getMinimapFill(statePointer);
    _minimapColors = mmColorPtr.address != 0
        ? mmColorPtr.asTypedList(ZeroTerminalStateView.minimapBinCount)
        : _emptyU32;
    _minimapFill = mmFillPtr.address != 0
        ? mmFillPtr.asTypedList(ZeroTerminalStateView.minimapBinCount)
        : _emptyU8;
    _lastObservedSeq = _view.seq;
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether the underlying C++ shared memory block is alive and aligned.
  bool get isNativeValid => !_isDisposed && _view.isValid;

  /// Active column count (`0` after dispose).
  int get cols => isNativeValid ? _view.cols : 0;

  /// Active row count (`0` after dispose).
  int get rows => isNativeValid ? _view.rows : 0;

  /// Maximum scrollback line capacity (`0` after dispose).
  int get scrollbackCapacity => isNativeValid ? _view.scrollbackCapacity : 0;

  /// Current zero-based cursor column (`0` after dispose).
  int get cursorCol => isNativeValid ? _view.cursorCol : 0;

  /// Current zero-based cursor row (`0` after dispose).
  int get cursorRow => isNativeValid ? _view.cursorRow : 0;

  /// Whether the cursor should be rendered.
  bool get cursorVisible => isNativeValid && _view.cursorVisible;

  /// Active cursor shape.
  ZeroTerminalCursorStyle get cursorStyle {
    if (!isNativeValid) return ZeroTerminalCursorStyle.block;
    final raw = _view.cursorStyleRaw.clamp(0, 2);
    return ZeroTerminalCursorStyle.values[raw];
  }

  /// Current scrollback offset in lines (`0` = latest bottom rows).
  int get scrollOffset => isNativeValid ? _view.scrollOffset : 0;

  /// Total lines currently stored in the ring buffer.
  int get totalLines => isNativeValid ? _view.totalLines : 0;

  /// Current runtime status of the terminal engine.
  ZeroTerminalStatus get status {
    if (!isNativeValid) return ZeroTerminalStatus.idle;
    final raw = _view.statusRaw.clamp(0, 4);
    return ZeroTerminalStatus.values[raw];
  }

  /// Active POSIX PTY child PID (`-1` when not running).
  int get childPid => isNativeValid ? _view.childPid : -1;

  /// Child process exit status code.
  int get exitCode => isNativeValid ? _view.exitCode : 0;

  /// Whether the alternate screen buffer (`?1049h`) is active.
  bool get altScreenActive => isNativeValid && _view.altScreenActive;

  /// Current C++ seqlock sequence counter.
  int get seq => isNativeValid ? _view.seq : 0;

  /// Cumulative bytes parsed by the C++ VT100 engine.
  int get bytesProcessed => isNativeValid ? _view.bytesProcessed : 0;

  /// Cumulative viewport commits.
  int get framesCommitted => isNativeValid ? _view.framesCommitted : 0;

  /// Cumulative ANSI/VT100 escape sequences parsed.
  int get escapeSeqsParsed => isNativeValid ? _view.escapeSeqsParsed : 0;

  /// Measured C++ parser throughput in MB/s.
  double get throughputMbPerSec =>
      isNativeValid ? _view.throughputMbPerSec : 0.0;

  /// Measured C++ parser latency in nanoseconds per byte.
  double get parseLatencyNs => isNativeValid ? _view.parseLatencyNs : 0.0;

  /// Active SGR foreground color (`0xAARRGGBB`).
  int get activeFgArgb => isNativeValid ? _view.activeFgArgb : 0xFFE6EDF3;

  /// Active SGR background color (`0xAARRGGBB`).
  int get activeBgArgb => isNativeValid ? _view.activeBgArgb : 0xFF0D1117;

  /// Zero-copy view over viewport Unicode codepoints (`stride = 256`).
  Uint32List get viewportCodepoints =>
      isNativeValid ? _viewportCodepoints : _emptyU32;

  /// Zero-copy view over viewport foreground ARGB colors (`stride = 256`).
  Uint32List get viewportFgArgb => isNativeValid ? _viewportFgArgb : _emptyU32;

  /// Zero-copy view over viewport background ARGB colors (`stride = 256`).
  Uint32List get viewportBgArgb => isNativeValid ? _viewportBgArgb : _emptyU32;

  /// Zero-copy view over viewport attribute flags (`stride = 256`).
  Uint8List get viewportAttrs => isNativeValid ? _viewportAttrs : _emptyU8;

  /// Zero-copy view over 256 minimap color summary bins.
  Uint32List get minimapColors => isNativeValid ? _minimapColors : _emptyU32;

  /// Zero-copy view over 256 minimap line fill density bins (`0..255`).
  Uint8List get minimapFill => isNativeValid ? _minimapFill : _emptyU8;

  /// Polls the native seqlock counter and notifies paint listeners if changed.
  bool pollNativeUpdates() {
    if (!isNativeValid) return false;
    final int currentSeq = _view.seq;
    if ((currentSeq & 1) == 0 && currentSeq != _lastObservedSeq) {
      _lastObservedSeq = currentSeq;
      _notifyRevision();
      return true;
    }
    return false;
  }

  /// Spawns a real POSIX `forkpty` shell process (macOS / Linux) or stream fallback.
  int spawnShell({String? shellPath, String? workingDirectory}) {
    if (!isNativeValid) return -1;
    final shPtr = shellPath != null
        ? shellPath.toNativeUtf8().cast<ffi.Char>()
        : ffi.nullptr;
    final wdPtr = workingDirectory != null
        ? workingDirectory.toNativeUtf8().cast<ffi.Char>()
        : ffi.nullptr;
    try {
      final pid = ZeroTerminalNativeBindings.instance
          .spawnPty(statePointer, shPtr, wdPtr);
      _lastObservedSeq = _view.seq;
      _notifyRevision();
      return pid;
    } finally {
      if (shPtr != ffi.nullptr) pkg_ffi.malloc.free(shPtr);
      if (wdPtr != ffi.nullptr) pkg_ffi.malloc.free(wdPtr);
    }
  }

  /// Stops the active PTY child process and joins the native reader thread.
  void stopShell() {
    if (!isNativeValid) return;
    ZeroTerminalNativeBindings.instance.stopPty(statePointer);
    _notifyRevision();
  }

  /// Feeds raw UTF-8 / ANSI bytes directly into the C++ VT100 parser (zero-malloc).
  int feedAnsiBytes(Uint8List bytes) {
    if (!isNativeValid || bytes.isEmpty) return 0;
    return _transferChunked(
      bytes,
      ZeroTerminalNativeBindings.instance.feedBytes,
    );
  }

  /// Feeds a [String] containing ANSI/VT100 sequences into the C++ parser.
  int feedAnsiText(String text) {
    if (!isNativeValid || text.isEmpty) return 0;
    final encoded = utf8.encode(text);
    return feedAnsiBytes(encoded);
  }

  /// Writes raw input bytes to the PTY master FD (or local stream fallback).
  int writeInputBytes(Uint8List bytes) {
    if (!isNativeValid || bytes.isEmpty) return 0;
    return _transferChunked(
      bytes,
      ZeroTerminalNativeBindings.instance.writeInput,
    );
  }

  /// Writes ASCII/UTF-8 text to the PTY input stream.
  int writeInputText(String text) {
    if (!isNativeValid || text.isEmpty) return 0;
    final encoded = utf8.encode(text);
    return writeInputBytes(encoded);
  }

  int _transferChunked(Uint8List bytes, DartFeedBytes fn) {
    int offset = 0;
    int total = 0;
    while (offset < bytes.length) {
      final int chunk = (bytes.length - offset) > _scratchCapacity
          ? _scratchCapacity
          : (bytes.length - offset);
      _scratchBytes.setRange(0, chunk, bytes, offset);
      total += fn(statePointer, _scratchPtr, chunk);
      offset += chunk;
    }
    _lastObservedSeq = _view.seq;
    _notifyRevision();
    return total;
  }

  /// Sends a special terminal key sequence ([ZeroTerminalKeyCode]) with 0 heap allocations.
  int sendKey(ZeroTerminalKeyCode key, {int modifiers = 0}) {
    if (!isNativeValid) return 0;
    final written = ZeroTerminalNativeBindings.instance.sendKeyCode(
      statePointer,
      key.code,
      modifiers,
    );
    _lastObservedSeq = _view.seq;
    _notifyRevision();
    return written;
  }

  /// Resizes the terminal grid and signals `TIOCSWINSZ` to the PTY child process.
  void resize(int newCols, int newRows) {
    if (!isNativeValid) return;
    if (newCols == cols && newRows == rows) return;
    ZeroTerminalNativeBindings.instance.resize(statePointer, newCols, newRows);
    _lastObservedSeq = _view.seq;
    _notifyRevision();
  }

  /// Updates the cursor shape and visibility.
  void setCursorStyle({ZeroTerminalCursorStyle? style, bool? visible}) {
    if (!isNativeValid) return;
    final targetStyle = (style ?? cursorStyle).index;
    final targetVis = (visible ?? cursorVisible) ? 1 : 0;
    ZeroTerminalNativeBindings.instance.setCursorStyle(
      statePointer,
      targetStyle,
      targetVis,
    );
    _notifyRevision();
  }

  /// Scrolls the viewport relative to the current offset (`>0` = up into history).
  void scrollBy(int deltaLines) {
    if (!isNativeValid || deltaLines == 0) return;
    ZeroTerminalNativeBindings.instance.scrollBy(statePointer, deltaLines);
    _lastObservedSeq = _view.seq;
    _notifyRevision();
  }

  /// Sets the exact scrollback offset (`0` = latest bottom rows).
  void setScrollOffset(int offset) {
    if (!isNativeValid) return;
    ZeroTerminalNativeBindings.instance.setScrollOffset(statePointer, offset);
    _lastObservedSeq = _view.seq;
    _notifyRevision();
  }

  /// Clears visible screen cells and resets cursor to `(0, 0)`.
  void clearScreen() {
    if (!isNativeValid) return;
    ZeroTerminalNativeBindings.instance.clearScreen(statePointer);
    _lastObservedSeq = _view.seq;
    _notifyRevision();
  }

  /// Resets the entire terminal buffer, scrollback, and SGR attributes.
  void reset() {
    if (!isNativeValid) return;
    ZeroTerminalNativeBindings.instance.reset(statePointer);
    _lastObservedSeq = _view.seq;
    _notifyRevision();
  }

  /// Generates a high-speed TrueColor ANSI burst in C++ for throughput benchmarking.
  int runStressBurst({int lineCount = 120, int seed = 1}) {
    if (!isNativeValid) return 0;
    final bytes = ZeroTerminalNativeBindings.instance.generateStressBurst(
      statePointer,
      lineCount,
      seed,
    );
    _lastObservedSeq = _view.seq;
    _notifyRevision();
    return bytes;
  }

  /// Reads the ASCII/Unicode string of a visible viewport row (for testing/copying).
  String readVisibleLine(int row) {
    if (!isNativeValid || row < 0 || row >= rows) return '';
    final int base = row * ZeroTerminalStateView.viewportStride;
    final int maxC = cols;
    int lastNonSpace = -1;
    for (int c = 0; c < maxC; c++) {
      if (_viewportCodepoints[base + c] > 0x20) lastNonSpace = c;
    }
    if (lastNonSpace < 0) return '';
    return String.fromCharCodes(
      _viewportCodepoints.sublist(base, base + lastNonSpace + 1),
    );
  }

  void _notifyRevision() {
    if (_isDisposed) return;
    _revision.value = (_revision.value + 1) & 0x3FFFFFFF;
  }

  @override
  void addListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _revision.removeListener(listener);
  }

  /// Safely stops any running PTY thread and frees native shared memory.
  ///
  /// Idempotent: calling [dispose] multiple times is a safe no-op.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _revision.dispose();
    pkg_ffi.calloc.free(_scratchPtr);
    ZeroTerminalNativeBindings.instance.destroyState(statePointer);
  }
}
