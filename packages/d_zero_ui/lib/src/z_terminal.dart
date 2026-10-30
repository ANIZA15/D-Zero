import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active Z-prefixed alias for [ZTerminal].
typedef ZLogStream = ZTerminal;

/// Deprecated legacy alias for [ZTerminal].
@Deprecated('Use ZTerminal instead.')
typedef ZeroTerminal = ZTerminal;

class _AsciiAtlasKey {
  final double fontSize;
  final FontWeight fontWeight;

  const _AsciiAtlasKey(this.fontSize, this.fontWeight);

  @override
  bool operator ==(Object other) {
    return other is _AsciiAtlasKey &&
        other.fontSize == fontSize &&
        other.fontWeight == fontWeight;
  }

  @override
  int get hashCode => Object.hash(fontSize, fontWeight);
}

class _SharedAsciiAtlas {
  static const int glyphCount = 95; // ASCII 0x20 (' ') .. 0x7E ('~')
  static const int _paddedCount = 96;

  final List<TextPainter> painters;
  final Float32List atlasRects;
  final Float32x4List atlasRects4;
  final double cellWidth;
  final double cellHeight;
  ui.Image? atlasImage;
  int refCount = 1;

  _SharedAsciiAtlas({
    required this.painters,
    required this.atlasRects,
    required this.atlasRects4,
    required this.cellWidth,
    required this.cellHeight,
    required this.atlasImage,
  });

  void dispose() {
    atlasImage?.dispose();
    atlasImage = null;
    for (int i = 0; i < painters.length; i++) {
      painters[i].dispose();
    }
  }

  static final Map<_AsciiAtlasKey, _SharedAsciiAtlas> _cache =
      <_AsciiAtlasKey, _SharedAsciiAtlas>{};

  static _SharedAsciiAtlas acquire(double fontSize, FontWeight fontWeight) {
    final key = _AsciiAtlasKey(fontSize, fontWeight);
    final existing = _cache[key];
    if (existing != null) {
      existing.refCount++;
      return existing;
    }
    final created = _build(fontSize, fontWeight);
    _cache[key] = created;
    return created;
  }

  static void release(_AsciiAtlasKey key) {
    final existing = _cache[key];
    if (existing == null) return;
    existing.refCount--;
    if (existing.refCount <= 0) {
      existing.dispose();
      _cache.remove(key);
    }
  }

  static _SharedAsciiAtlas _build(double fontSize, FontWeight fontWeight) {
    final style = TextStyle(
      color: const Color(0xFFFFFFFF),
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontFamily: 'monospace',
    );
    final painters = List<TextPainter>.generate(
      glyphCount,
      (int i) => TextPainter(
        text: TextSpan(
          text: String.fromCharCode(0x20 + i),
          style: style,
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
      growable: false,
    );

    double maxW = fontSize * 0.62;
    double maxH = fontSize * 1.25;
    for (int i = 0; i < glyphCount; i++) {
      if (painters[i].width > maxW) maxW = painters[i].width;
      if (painters[i].height > maxH) maxH = painters[i].height;
    }
    final double cellW = maxW.ceilToDouble();
    final double cellH = maxH.ceilToDouble();
    final double stepX = cellW + 2.0;

    final atlasRects = Float32List(_paddedCount * 4);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    for (int i = 0; i < glyphCount; i++) {
      final double gx = i * stepX;
      painters[i].paint(canvas, Offset(gx, 0.0));
      final int rIdx = i << 2;
      atlasRects[rIdx] = gx;
      atlasRects[rIdx + 1] = 0.0;
      atlasRects[rIdx + 2] = gx + cellW;
      atlasRects[rIdx + 3] = cellH;
    }

    final picture = recorder.endRecording();
    ui.Image? image;
    final int imgW = (glyphCount * stepX).ceil();
    final int imgH = cellH.ceil();
    if (imgW > 0 && imgH > 0) {
      try {
        image = picture.toImageSync(imgW, imgH);
      } catch (_) {
        image = null;
      }
    }
    picture.dispose();

    return _SharedAsciiAtlas(
      painters: painters,
      atlasRects: atlasRects,
      atlasRects4: atlasRects.buffer.asFloat32x4List(),
      cellWidth: cellW,
      cellHeight: cellH,
      atlasImage: image,
    );
  }
}

/// Fixed-capacity Structure-of-Arrays (SoA) ring buffer controller for [ZTerminal].
///
/// Stores ASCII log lines in contiguous [Uint8List] buffers (`_glyphs`, `_lineLengths`,
/// `_lineLevels`) so streaming tens of thousands of log lines allocates zero heap
/// strings or paragraph layouts during rendering.
class ZeroTerminalController implements Listenable {
  /// Maximum allowed line capacity (`16,384`).
  static const int maxAllowedLines = 16384;

  /// Maximum allowed columns per line (`256`).
  static const int maxAllowedCols = 256;

  /// Severity level for standard output (`0`).
  static const int levelNormal = 0;

  /// Severity level for informational logs (`1`).
  static const int levelInfo = 1;

  /// Severity level for warning logs (`2`).
  static const int levelWarn = 2;

  /// Severity level for error logs (`3`).
  static const int levelError = 3;

  /// Maximum retained lines in the circular buffer.
  final int maxLines;

  /// Maximum characters retained per line.
  final int maxCols;

  late final Uint8List _glyphs;
  late final Uint8List _lineLengths;
  late final Uint8List _lineLevels;
  final ZeroIntNotifier _revision = ZeroIntNotifier(0);

  int _writeSlot = 0;
  int _lineCount = 0;
  int _totalLinesWritten = 0;
  bool _isDisposed = false;

  /// Creates a [ZeroTerminalController] with fixed [maxLines] and [maxCols].
  ZeroTerminalController({
    int maxLines = 256,
    int maxCols = 80,
  })  : maxLines = _clampDim(maxLines, 1, maxAllowedLines),
        maxCols = _clampDim(maxCols, 1, maxAllowedCols) {
    _glyphs = Uint8List(this.maxLines * this.maxCols);
    _lineLengths = Uint8List(this.maxLines);
    _lineLevels = Uint8List(this.maxLines);
  }

  static int _clampDim(int value, int minVal, int maxVal) {
    if (value < minVal) return minVal;
    if (value > maxVal) return maxVal;
    return value;
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Number of lines currently stored in the ring buffer (`0..maxLines`).
  int get lineCount => _isDisposed ? 0 : _lineCount;

  /// Total cumulative lines written since creation or last [clear].
  int get totalLinesWritten => _isDisposed ? 0 : _totalLinesWritten;

  @override
  void addListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.removeListener(listener);
  }

  /// Appends a string [line] to the ring buffer at severity [level] (`0..3`).
  void writeLine(String line, {int level = levelNormal}) {
    if (_isDisposed) return;
    _writeCodeUnits(line.codeUnits, level);
  }

  /// Appends raw ASCII [codeUnits] to the ring buffer with zero [String] allocation.
  void writeAscii(List<int> codeUnits, {int level = levelNormal}) {
    if (_isDisposed) return;
    _writeCodeUnits(codeUnits, level);
  }

  void _writeCodeUnits(List<int> units, int level) {
    final int slot = _writeSlot;
    _writeSlot = (slot + 1) % maxLines;
    if (_lineCount < maxLines) {
      _lineCount++;
    }
    _totalLinesWritten++;

    final int len = units.length < maxCols ? units.length : maxCols;
    final int baseOffset = slot * maxCols;
    for (int i = 0; i < len; i++) {
      _glyphs[baseOffset + i] = _toGlyphIndex(units[i]);
    }
    _lineLengths[slot] = len;
    _lineLevels[slot] = level & 0x03;
    _revision.add(1);
  }

  static int _toGlyphIndex(int codeUnit) {
    if (codeUnit >= 0x20 && codeUnit <= 0x7E) {
      return codeUnit - 0x20;
    }
    return 0x3F - 0x20; // '?'
  }

  int _physicalSlot(int logicalIndex) {
    final int startSlot =
        _lineCount < maxLines ? 0 : _writeSlot;
    return (startSlot + logicalIndex) % maxLines;
  }

  /// Returns the character length of the line at [logicalIndex] (`0..lineCount - 1`).
  int lineLengthAt(int logicalIndex) {
    if (_isDisposed || logicalIndex < 0 || logicalIndex >= _lineCount) {
      return 0;
    }
    return _lineLengths[_physicalSlot(logicalIndex)];
  }

  /// Returns the severity level (`0..3`) of the line at [logicalIndex].
  int lineLevelAt(int logicalIndex) {
    if (_isDisposed || logicalIndex < 0 || logicalIndex >= _lineCount) {
      return 0;
    }
    return _lineLevels[_physicalSlot(logicalIndex)];
  }

  /// Returns the glyph index (`0..94`) at `(logicalIndex, col)`.
  int glyphAt(int logicalIndex, int col) {
    if (_isDisposed ||
        logicalIndex < 0 ||
        logicalIndex >= _lineCount ||
        col < 0 ||
        col >= maxCols) {
      return 0;
    }
    final int slot = _physicalSlot(logicalIndex);
    if (col >= _lineLengths[slot]) return 0;
    return _glyphs[slot * maxCols + col];
  }

  /// Clears all buffered terminal lines.
  void clear() {
    if (_isDisposed) return;
    _writeSlot = 0;
    _lineCount = 0;
    _totalLinesWritten = 0;
    _lineLengths.fillRange(0, maxLines, 0);
    _lineLevels.fillRange(0, maxLines, 0);
    _revision.add(1);
  }

  /// Disposes the controller and zeros internal buffers (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _writeSlot = 0;
    _lineCount = 0;
    _totalLinesWritten = 0;
    _glyphs.fillRange(0, _glyphs.length, 0);
    _lineLengths.fillRange(0, _lineLengths.length, 0);
    _lineLevels.fillRange(0, _lineLevels.length, 0);
    _revision.dispose();
  }
}

/// A zero-allocation, single-draw-call ASCII terminal and log stream widget.
///
/// Bakes printable ASCII glyphs (`0x20..0x7E`) into a shared GPU glyph atlas and
/// renders all visible characters on screen in a single [Canvas.drawRawAtlas] call
/// with pre-allocated [Float32List] transform/UV buffers—eliminating `ListView`,
/// `Sliver`, and per-line `TextPainter` allocations.
class ZTerminal extends ZLeafWidget<RenderZTerminal> {
  /// Backing ring-buffer controller holding ASCII log lines.
  final ZeroTerminalController controller;

  /// Preferred viewport size when unconstrained.
  final Size size;

  /// Monospace font size in logical pixels.
  final double fontSize;

  /// Terminal background color.
  final Color backgroundColor;

  /// Default text color for [ZeroTerminalController.levelNormal].
  final Color textColor;

  /// Text color for [ZeroTerminalController.levelInfo].
  final Color infoColor;

  /// Text color for [ZeroTerminalController.levelWarn].
  final Color warnColor;

  /// Text color for [ZeroTerminalController.levelError].
  final Color errorColor;

  /// Whether new lines automatically pin scroll position to the bottom.
  final bool autoScroll;

  /// Creates a const [ZTerminal] widget.
  const ZTerminal({
    super.key,
    required this.controller,
    this.size = const Size(360.0, 220.0),
    this.fontSize = 12.0,
    this.backgroundColor = const Color(0xFF0A0E17),
    this.textColor = const Color(0xFFE2E8F0),
    this.infoColor = const Color(0xFF38BDF8),
    this.warnColor = const Color(0xFFFACC15),
    this.errorColor = const Color(0xFFF87171),
    this.autoScroll = true,
  });

  @override
  RenderZTerminal createRenderObject(BuildContext context) {
    return RenderZTerminal(
      controller: controller,
      preferredSize: size,
      fontSize: fontSize,
      backgroundColor: backgroundColor,
      textColor: textColor,
      infoColor: infoColor,
      warnColor: warnColor,
      errorColor: errorColor,
      autoScroll: autoScroll,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZTerminal renderObject) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..fontSize = fontSize
      ..backgroundColor = backgroundColor
      ..textColor = textColor
      ..infoColor = infoColor
      ..warnColor = warnColor
      ..errorColor = errorColor
      ..autoScroll = autoScroll;
  }
}

/// Custom [ZeroRenderBox] that batch-renders [ZTerminal] lines via [Canvas.drawRawAtlas].
class RenderZTerminal extends ZeroRenderBox {
  static const int _maxBatchGlyphs = 2048;
  static const double _padding = 8.0;

  ZeroTerminalController _controller;
  Size _preferredSize;
  double _fontSize;
  Color _backgroundColor;
  Color _textColor;
  Color _infoColor;
  Color _warnColor;
  Color _errorColor;
  bool _autoScroll;

  late _AsciiAtlasKey _atlasKey;
  late _SharedAsciiAtlas _atlas;

  final Float32List _batchTransforms = Float32List(_maxBatchGlyphs * 4);
  final Float32List _batchRects = Float32List(_maxBatchGlyphs * 4);
  late final Float32x4List _batchRects4 =
      _batchRects.buffer.asFloat32x4List();
  final Int32List _batchColors = Int32List(_maxBatchGlyphs);
  final Int32List _levelPalette = Int32List(4);

  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _atlasPaint = Paint()..filterQuality = FilterQuality.low;

  double _scrollOffset = 0.0;
  bool _userScrolledUp = false;

  /// Creates a [RenderZTerminal].
  RenderZTerminal({
    required ZeroTerminalController controller,
    required Size preferredSize,
    required double fontSize,
    required Color backgroundColor,
    required Color textColor,
    required Color infoColor,
    required Color warnColor,
    required Color errorColor,
    required bool autoScroll,
  })  : _controller = controller,
        _preferredSize = preferredSize,
        _fontSize = fontSize > 6.0 ? fontSize : 6.0,
        _backgroundColor = backgroundColor,
        _textColor = textColor,
        _infoColor = infoColor,
        _warnColor = warnColor,
        _errorColor = errorColor,
        _autoScroll = autoScroll {
    _bgPaint.color = _backgroundColor;
    _rebuildPalette();
    _atlasKey = _AsciiAtlasKey(_fontSize, FontWeight.w500);
    _atlas = _SharedAsciiAtlas.acquire(_atlasKey.fontSize, _atlasKey.fontWeight);
  }

  /// Backing terminal controller.
  ZeroTerminalController get controller => _controller;
  set controller(ZeroTerminalController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(_onControllerChanged);
    }
    _controller = value;
    if (attached) {
      _controller.addListener(_onControllerChanged);
    }
    markDirty();
  }

  /// Preferred size of the terminal viewport.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// Font size in logical pixels.
  double get fontSize => _fontSize;
  set fontSize(double value) {
    final double clamped = value > 6.0 ? value : 6.0;
    if (_fontSize == clamped) return;
    _SharedAsciiAtlas.release(_atlasKey);
    _fontSize = clamped;
    _atlasKey = _AsciiAtlasKey(_fontSize, FontWeight.w500);
    _atlas = _SharedAsciiAtlas.acquire(_atlasKey.fontSize, _atlasKey.fontWeight);
    markDirty();
  }

  /// Background color of the terminal.
  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    _bgPaint.color = value;
    markDirty();
  }

  /// Normal severity text color.
  Color get textColor => _textColor;
  set textColor(Color value) {
    if (_textColor == value) return;
    _textColor = value;
    _rebuildPalette();
    markDirty();
  }

  /// Info severity text color.
  Color get infoColor => _infoColor;
  set infoColor(Color value) {
    if (_infoColor == value) return;
    _infoColor = value;
    _rebuildPalette();
    markDirty();
  }

  /// Warning severity text color.
  Color get warnColor => _warnColor;
  set warnColor(Color value) {
    if (_warnColor == value) return;
    _warnColor = value;
    _rebuildPalette();
    markDirty();
  }

  /// Error severity text color.
  Color get errorColor => _errorColor;
  set errorColor(Color value) {
    if (_errorColor == value) return;
    _errorColor = value;
    _rebuildPalette();
    markDirty();
  }

  /// Whether new lines automatically scroll to bottom.
  bool get autoScroll => _autoScroll;
  set autoScroll(bool value) {
    if (_autoScroll == value) return;
    _autoScroll = value;
    if (value) _userScrolledUp = false;
    markDirty();
  }

  /// Current vertical scroll offset in logical pixels.
  double get scrollOffset => _scrollOffset;

  void _rebuildPalette() {
    _levelPalette[0] = _colorToArgb32(_textColor);
    _levelPalette[1] = _colorToArgb32(_infoColor);
    _levelPalette[2] = _colorToArgb32(_warnColor);
    _levelPalette[3] = _colorToArgb32(_errorColor);
  }

  static int _colorToArgb32(Color c) {
    final int a = (c.a * 255.0).round() & 0xFF;
    final int r = (c.r * 255.0).round() & 0xFF;
    final int g = (c.g * 255.0).round() & 0xFF;
    final int b = (c.b * 255.0).round() & 0xFF;
    return ((a << 24) | (r << 16) | (g << 8) | b).toSigned(32);
  }

  void _onControllerChanged() {
    if (_autoScroll && !_userScrolledUp) {
      _scrollOffset = _maxScrollExtent();
    }
    markDirty();
  }

  double _maxScrollExtent() {
    if (!hasSize) return 0.0;
    final double contentH = _controller.lineCount * _atlas.cellHeight;
    final double viewH = size.height - (_padding * 2.0);
    final double maxExt = contentH - viewH;
    return maxExt > 0.0 ? maxExt : 0.0;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void detach() {
    _controller.removeListener(_onControllerChanged);
    super.detach();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _SharedAsciiAtlas.release(_atlasKey);
    super.dispose();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return constraints.constrain(_preferredSize);
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerMoveEvent) {
      _applyScrollDelta(-event.delta.dy);
    } else if (event is PointerScrollEvent) {
      _applyScrollDelta(event.scrollDelta.dy);
    }
  }

  void _applyScrollDelta(double deltaY) {
    final double maxExt = _maxScrollExtent();
    final double next = (_scrollOffset + deltaY).clamp(0.0, maxExt);
    _userScrolledUp = next < maxExt - 2.0;
    if ((next - _scrollOffset).abs() > 0.1) {
      _scrollOffset = next;
      markDirty();
    }
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect bounds = offset & size;
    canvas.drawRect(bounds, _bgPaint);
    if (_controller.isDisposed || _controller.lineCount == 0) return;

    final double maxExt = _maxScrollExtent();
    if (_autoScroll && !_userScrolledUp) {
      _scrollOffset = maxExt;
    } else if (_scrollOffset > maxExt) {
      _scrollOffset = maxExt;
    }

    canvas.save();
    canvas.clipRect(bounds.deflate(_padding));
    _paintVisibleLines(canvas, offset.dx + _padding, offset.dy + _padding);
    canvas.restore();
  }

  void _paintVisibleLines(Canvas canvas, double originX, double originY) {
    final double cellH = _atlas.cellHeight;
    final double cellW = _atlas.cellWidth;
    final double viewH = size.height - (_padding * 2.0);
    final double viewW = size.width - (_padding * 2.0);
    if (viewH <= 0.0 || viewW <= 0.0 || cellH <= 0.0 || cellW <= 0.0) return;

    final int totalLines = _controller.lineCount;
    final int firstLine = (_scrollOffset ~/ cellH).clamp(0, totalLines - 1);
    final int visibleRows = (viewH ~/ cellH) + 2;
    final int endLine = (firstLine + visibleRows).clamp(0, totalLines);
    final int maxVisibleCols = (viewW ~/ cellW).clamp(1, _controller.maxCols);

    final ui.Image? atlasImg = _atlas.atlasImage;
    int batchCount = 0;

    for (int lineIdx = firstLine; lineIdx < endLine; lineIdx++) {
      final double rowY = originY + (lineIdx * cellH) - _scrollOffset;
      batchCount = _stageLineGlyphs(
        canvas: canvas,
        atlasImg: atlasImg,
        lineIdx: lineIdx,
        originX: originX,
        rowY: rowY,
        cellW: cellW,
        maxVisibleCols: maxVisibleCols,
        batchCount: batchCount,
      );
    }

    if (batchCount > 0 && atlasImg != null) {
      _flushAtlasBatch(canvas, atlasImg, batchCount);
    }
  }

  int _stageLineGlyphs({
    required Canvas canvas,
    required ui.Image? atlasImg,
    required int lineIdx,
    required double originX,
    required double rowY,
    required double cellW,
    required int maxVisibleCols,
    required int batchCount,
  }) {
    final int len = _controller.lineLengthAt(lineIdx);
    final int cols = len < maxVisibleCols ? len : maxVisibleCols;
    final int colorArgb = _levelPalette[_controller.lineLevelAt(lineIdx)];

    int count = batchCount;
    for (int col = 0; col < cols; col++) {
      final int glyph = _controller.glyphAt(lineIdx, col);
      if (glyph <= 0) continue; // Skip whitespace (' ')

      final double x = originX + (col * cellW);
      if (atlasImg == null) {
        _atlas.painters[glyph].paint(canvas, Offset(x, rowY));
        continue;
      }

      if (count >= _maxBatchGlyphs) {
        _flushAtlasBatch(canvas, atlasImg, count);
        count = 0;
      }

      final int tIdx = count << 2;
      _batchTransforms[tIdx] = 1.0;
      _batchTransforms[tIdx + 1] = 0.0;
      _batchTransforms[tIdx + 2] = x;
      _batchTransforms[tIdx + 3] = rowY;
      _batchRects4[count] = _atlas.atlasRects4[glyph];
      _batchColors[count] = colorArgb;
      count++;
    }
    return count;
  }

  void _flushAtlasBatch(Canvas canvas, ui.Image atlasImg, int count) {
    final int floatLen = count << 2;
    canvas.drawRawAtlas(
      atlasImg,
       Float32List.sublistView(_batchTransforms, 0, floatLen),
      Float32List.sublistView(_batchRects, 0, floatLen),
      Int32List.sublistView(_batchColors, 0, count),
      BlendMode.modulate,
      null,
      _atlasPaint,
    );
  }
}
