import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';
import '../controller.dart';
import '../terminal_state_ffi.dart';

/// Active Z-prefixed alias for [ZPtyTerminal].
typedef ZTerminalEmulator = ZPtyTerminal;

/// Deprecated legacy alias for [ZPtyTerminal].
@Deprecated('Use ZPtyTerminal instead.')
typedef ZeroPtyTerminal = ZPtyTerminal;

class _GlyphAtlasKey {
  final double fontSize;
  final FontWeight fontWeight;

  const _GlyphAtlasKey(this.fontSize, this.fontWeight);

  @override
  bool operator ==(Object other) {
    return other is _GlyphAtlasKey &&
        other.fontSize == fontSize &&
        other.fontWeight == fontWeight;
  }

  @override
  int get hashCode => Object.hash(fontSize, fontWeight);
}

class _SharedTerminalAtlas {
  static const int glyphCount = 95; // ASCII 0x20 (' ') .. 0x7E ('~')
  static const int _paddedCount = 96;

  final List<TextPainter> painters;
  final Float32List atlasRects;
  final Float32x4List atlasRects4;
  final double cellWidth;
  final double cellHeight;
  ui.Image? atlasImage;
  int refCount = 1;

  _SharedTerminalAtlas({
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

  static final Map<_GlyphAtlasKey, _SharedTerminalAtlas> _cache =
      <_GlyphAtlasKey, _SharedTerminalAtlas>{};

  static _SharedTerminalAtlas acquire(double fontSize, FontWeight fontWeight) {
    final key = _GlyphAtlasKey(fontSize, fontWeight);
    final existing = _cache[key];
    if (existing != null) {
      existing.refCount++;
      return existing;
    }
    final created = _build(fontSize, fontWeight);
    _cache[key] = created;
    return created;
  }

  static void release(_GlyphAtlasKey key) {
    final existing = _cache[key];
    if (existing == null) return;
    existing.refCount--;
    if (existing.refCount <= 0) {
      existing.dispose();
      _cache.remove(key);
    }
  }

  static _SharedTerminalAtlas _build(double fontSize, FontWeight fontWeight) {
    final style = TextStyle(
      color: const Color(0xFFFFFFFF),
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontFamily: 'monospace',
    );
    final painters = List<TextPainter>.generate(
      glyphCount,
      (int i) => TextPainter(
        text: TextSpan(text: String.fromCharCode(0x20 + i), style: style),
        textDirection: TextDirection.ltr,
      )..layout(),
      growable: false,
    );

    double maxW = fontSize * 0.60;
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
    final ui.Image? image = _rasterizeSync(
      picture,
      (glyphCount * stepX).ceil(),
      cellH.ceil(),
    );
    picture.dispose();

    return _SharedTerminalAtlas(
      painters: painters,
      atlasRects: atlasRects,
      atlasRects4: atlasRects.buffer.asFloat32x4List(),
      cellWidth: cellW,
      cellHeight: cellH,
      atlasImage: image,
    );
  }

  static ui.Image? _rasterizeSync(ui.Picture pic, int w, int h) {
    if (w <= 0 || h <= 0) return null;
    try {
      return pic.toImageSync(w, h);
    } catch (_) {
      return null;
    }
  }
}

/// Ultra-lightweight, zero-allocation FFI PTY & VT100/TrueColor terminal widget.
///
/// Renders the C++ shared-memory viewport (`viewportCodepoints`, `viewportFgArgb`,
/// `viewportBgArgb`, `viewportAttrs`) in a single `Canvas.drawRawAtlas` pass with
/// zero widget rebuilds and zero per-frame heap allocations.
class ZPtyTerminal extends ZLeafWidget {
  /// The FFI PTY terminal controller.
  final ZeroPtyController controller;

  /// Terminal background color (`0xFF0D1117` by default).
  final Color backgroundColor;

  /// Cursor highlight color (`0xFF58A6FF` by default).
  final Color cursorColor;

  /// Selection highlight color.
  final Color selectionColor;

  /// Monospace font size in logical pixels.
  final double fontSize;

  /// Glyph font weight.
  final FontWeight fontWeight;

  /// Inner viewport padding in logical pixels.
  final double padding;

  /// Corner radius of the terminal surface.
  final double borderRadius;

  /// Whether keyboard input and pointer selection/scrolling are enabled.
  final bool interactive;

  /// Whether layout changes automatically resize the C++ PTY grid (`TIOCSWINSZ`).
  final bool autoResize;

  /// Creates a zero-allocation [ZPtyTerminal].
  const ZPtyTerminal({
    super.key,
    required this.controller,
    this.backgroundColor = const Color(0xFF0D1117),
    this.cursorColor = const Color(0xFF58A6FF),
    this.selectionColor = const Color(0x55388BFD),
    this.fontSize = 13.0,
    this.fontWeight = FontWeight.w500,
    this.padding = 10.0,
    this.borderRadius = 8.0,
    this.interactive = true,
    this.autoResize = false,
  });

  @override
  RenderZPtyTerminal createRenderObject(BuildContext context) {
    return RenderZPtyTerminal(
      controller: controller,
      backgroundColor: backgroundColor,
      cursorColor: cursorColor,
      selectionColor: selectionColor,
      fontSize: fontSize,
      fontWeight: fontWeight,
      padding: padding,
      borderRadius: borderRadius,
      interactive: interactive,
      autoResize: autoResize,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderZPtyTerminal renderObject,
  ) {
    renderObject
      ..controller = controller
      ..backgroundColor = backgroundColor
      ..cursorColor = cursorColor
      ..selectionColor = selectionColor
      ..fontSize = fontSize
      ..fontWeight = fontWeight
      ..padding = padding
      ..borderRadius = borderRadius
      ..interactive = interactive
      ..autoResize = autoResize;
  }
}

/// Custom [ZeroRenderBox] for [ZPtyTerminal].
class RenderZPtyTerminal extends ZeroRenderBox {
  static const int _attrBold = 0x01;
  static const int _attrUnderline = 0x08;
  static const int _attrInverse = 0x20;
  static const int _defaultBgArgb = 0xFF0D1117;

  static final Map<LogicalKeyboardKey, ZeroTerminalKeyCode> _specialKeyMap =
      <LogicalKeyboardKey, ZeroTerminalKeyCode>{
    LogicalKeyboardKey.enter: ZeroTerminalKeyCode.enter,
    LogicalKeyboardKey.numpadEnter: ZeroTerminalKeyCode.enter,
    LogicalKeyboardKey.backspace: ZeroTerminalKeyCode.backspace,
    LogicalKeyboardKey.tab: ZeroTerminalKeyCode.tab,
    LogicalKeyboardKey.escape: ZeroTerminalKeyCode.escape,
    LogicalKeyboardKey.arrowUp: ZeroTerminalKeyCode.up,
    LogicalKeyboardKey.arrowDown: ZeroTerminalKeyCode.down,
    LogicalKeyboardKey.arrowRight: ZeroTerminalKeyCode.right,
    LogicalKeyboardKey.arrowLeft: ZeroTerminalKeyCode.left,
    LogicalKeyboardKey.home: ZeroTerminalKeyCode.home,
    LogicalKeyboardKey.end: ZeroTerminalKeyCode.end,
    LogicalKeyboardKey.pageUp: ZeroTerminalKeyCode.pageUp,
    LogicalKeyboardKey.pageDown: ZeroTerminalKeyCode.pageDown,
    LogicalKeyboardKey.delete: ZeroTerminalKeyCode.deleteKey,
  };

  ZeroPtyController _controller;
  Color _backgroundColor;
  Color _cursorColor;
  Color _selectionColor;
  double _fontSize;
  FontWeight _fontWeight;
  double _padding;
  double _borderRadius;
  bool _interactive;
  bool _autoResize;

  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _cellBgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _cursorPaint = Paint()..style = PaintingStyle.fill;
  final Paint _selectionPaint = Paint()..style = PaintingStyle.fill;
  final Paint _underlinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  final Paint _atlasPaint = Paint();

  _SharedTerminalAtlas? _sharedAtlas;
  _GlyphAtlasKey? _atlasKey;

  Float32List _transforms = Float32List(0);
  Float32x4List _transforms4 = Float32x4List(0);
  Float32List _rects = Float32List(0);
  Float32x4List _rects4 = Float32x4List(0);
  Int32List _colors = Int32List(0);

  bool _hasKeyboardFocus = true;
  bool _keyboardRegistered = false;
  int _selStartRow = -1;
  int _selStartCol = -1;
  int _selEndRow = -1;
  int _selEndCol = -1;
  double _scrollDragRemainder = 0.0;

  /// Creates a [RenderZPtyTerminal].
  RenderZPtyTerminal({
    required ZeroPtyController controller,
    required Color backgroundColor,
    required Color cursorColor,
    required Color selectionColor,
    required double fontSize,
    required FontWeight fontWeight,
    required double padding,
    required double borderRadius,
    required bool interactive,
    required bool autoResize,
  })  : _controller = controller,
        _backgroundColor = backgroundColor,
        _cursorColor = cursorColor,
        _selectionColor = selectionColor,
        _fontSize = fontSize,
        _fontWeight = fontWeight,
        _padding = padding,
        _borderRadius = borderRadius,
        _interactive = interactive,
        _autoResize = autoResize,
        super(animatePerFrame: true) {
    _bgPaint.color = _backgroundColor;
    _cursorPaint.color = _cursorColor;
    _selectionPaint.color = _selectionColor;
    _acquireAtlas();
    _ensureAtlasCapacity(4096);
  }

  /// Active [ZeroPtyController].
  ZeroPtyController get controller => _controller;
  set controller(ZeroPtyController value) {
    if (identical(_controller, value)) return;
    if (attached) _controller.removeListener(markNeedsPaint);
    _controller = value;
    if (attached) _controller.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  /// Surface background color.
  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    _bgPaint.color = value;
    markNeedsPaint();
  }

  /// Cursor highlight color.
  Color get cursorColor => _cursorColor;
  set cursorColor(Color value) {
    if (_cursorColor == value) return;
    _cursorColor = value;
    _cursorPaint.color = value;
    markNeedsPaint();
  }

  /// Selection highlight color.
  Color get selectionColor => _selectionColor;
  set selectionColor(Color value) {
    if (_selectionColor == value) return;
    _selectionColor = value;
    _selectionPaint.color = value;
    markNeedsPaint();
  }

  /// Monospace font size.
  double get fontSize => _fontSize;
  set fontSize(double value) {
    if (_fontSize == value) return;
    _fontSize = value;
    _acquireAtlas();
    markNeedsLayout();
  }

  /// Glyph font weight.
  FontWeight get fontWeight => _fontWeight;
  set fontWeight(FontWeight value) {
    if (_fontWeight == value) return;
    _fontWeight = value;
    _acquireAtlas();
    markNeedsLayout();
  }

  /// Viewport inner padding.
  double get padding => _padding;
  set padding(double value) {
    if (_padding == value) return;
    _padding = value;
    markNeedsLayout();
  }

  /// Corner radius.
  double get borderRadius => _borderRadius;
  set borderRadius(double value) {
    if (_borderRadius == value) return;
    _borderRadius = value;
    markNeedsPaint();
  }

  /// Whether keyboard and mouse interaction is enabled.
  bool get interactive => _interactive;
  set interactive(bool value) {
    if (_interactive == value) return;
    _interactive = value;
    markNeedsPaint();
  }

  /// Whether layout changes automatically resize the PTY grid.
  bool get autoResize => _autoResize;
  set autoResize(bool value) {
    if (_autoResize == value) return;
    _autoResize = value;
    if (value) markNeedsLayout();
  }

  /// Cell width in logical pixels.
  double get cellWidth => _sharedAtlas?.cellWidth ?? 8.0;

  /// Cell height in logical pixels.
  double get cellHeight => _sharedAtlas?.cellHeight ?? 16.0;

  void _acquireAtlas() {
    if (_atlasKey != null) {
      _SharedTerminalAtlas.release(_atlasKey!);
    }
    final double safeFont = _fontSize.clamp(8.0, 48.0);
    _atlasKey = _GlyphAtlasKey(safeFont, _fontWeight);
    _sharedAtlas = _SharedTerminalAtlas.acquire(safeFont, _fontWeight);
  }

  void _releaseAtlas() {
    if (_atlasKey != null) {
      _SharedTerminalAtlas.release(_atlasKey!);
      _atlasKey = null;
      _sharedAtlas = null;
    }
  }

  void _ensureAtlasCapacity(int maxGlyphs) {
    if (_colors.length >= maxGlyphs) return;
    final int cap = ((maxGlyphs + 255) >> 8) << 8;
    _transforms = Float32List(cap * 4);
    _transforms4 = _transforms.buffer.asFloat32x4List();
    _rects = Float32List(cap * 4);
    _rects4 = _rects.buffer.asFloat32x4List();
    _colors = Int32List(cap);
  }

  @override
  bool onFrameTick(Duration elapsed) {
    return _controller.pollNativeUpdates();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (_sharedAtlas == null) _acquireAtlas();
    _controller.addListener(markNeedsPaint);
    _registerKeyboardIfNeeded();
  }

  @override
  void detach() {
    _unregisterKeyboardIfNeeded();
    _controller.removeListener(markNeedsPaint);
    _releaseAtlas();
    super.detach();
  }

  void _registerKeyboardIfNeeded() {
    if (_keyboardRegistered) return;
    _keyboardRegistered = true;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  void _unregisterKeyboardIfNeeded() {
    if (!_keyboardRegistered) return;
    _keyboardRegistered = false;
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!attached || !_interactive || !_hasKeyboardFocus) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    if (_handleCtrlShortcut(event.logicalKey)) return true;
    final special = _specialKeyMap[event.logicalKey];
    if (special != null) {
      _controller.sendKey(special);
      return true;
    }
    final ch = event.character;
    if (ch != null && ch.isNotEmpty) {
      _controller.writeInputText(ch);
      return true;
    }
    return false;
  }

  bool _handleCtrlShortcut(LogicalKeyboardKey key) {
    if (!HardwareKeyboard.instance.isControlPressed) return false;
    if (key == LogicalKeyboardKey.keyC) {
      _controller.sendKey(ZeroTerminalKeyCode.ctrlC);
      return true;
    }
    if (key == LogicalKeyboardKey.keyD) {
      _controller.sendKey(ZeroTerminalKeyCode.ctrlD);
      return true;
    }
    if (key == LogicalKeyboardKey.keyL) {
      _controller.sendKey(ZeroTerminalKeyCode.ctrlL);
      return true;
    }
    return false;
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (!_interactive) return;
    if (event is PointerScrollEvent) {
      _applyWheelScroll(event.scrollDelta.dy);
    } else if (event is PointerDownEvent) {
      _hasKeyboardFocus = true;
      _setSelectionPoint(event.localPosition, isStart: true);
      markNeedsPaint();
    } else if (event is PointerMoveEvent) {
      _setSelectionPoint(event.localPosition, isStart: false);
      markNeedsPaint();
    }
  }

  void _applyWheelScroll(double dy) {
    _scrollDragRemainder += dy;
    final double ch = cellHeight;
    if (_scrollDragRemainder.abs() < ch) return;
    final int lines = (_scrollDragRemainder / ch).truncate();
    _scrollDragRemainder -= lines * ch;
    _controller.scrollBy(-lines);
  }

  void _setSelectionPoint(Offset localPos, {required bool isStart}) {
    final int c = ((localPos.dx - _padding) / cellWidth)
        .floor()
        .clamp(0, math.max(0, _controller.cols - 1));
    final int r = ((localPos.dy - _padding) / cellHeight)
        .floor()
        .clamp(0, math.max(0, _controller.rows - 1));
    if (isStart) {
      _selStartRow = r;
      _selStartCol = c;
    }
    _selEndRow = r;
    _selEndCol = c;
  }

  @override
  void performLayout() {
    final double w =
        constraints.hasBoundedWidth ? constraints.maxWidth : 680.0;
    final double h =
        constraints.hasBoundedHeight ? constraints.maxHeight : 400.0;
    size = constraints.constrain(Size(w, h));

    if (_autoResize && _controller.isNativeValid) {
      final int fitCols =
          ((size.width - _padding * 2.0) / cellWidth).floor().clamp(16, 256);
      final int fitRows =
          ((size.height - _padding * 2.0) / cellHeight).floor().clamp(4, 128);
      _controller.resize(fitCols, fitRows);
    }
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect bounds = offset & size;
    final RRect surfaceRRect = RRect.fromRectAndRadius(
      bounds,
      Radius.circular(_borderRadius),
    );
    canvas.drawRRect(surfaceRRect, _bgPaint);

    if (_controller.isNativeValid) {
      _paintViewportCells(canvas, offset);
      _paintSelection(canvas, offset);
      _paintCursor(canvas, offset);
    }

    _borderPaint.color = _hasKeyboardFocus
        ? _cursorColor.withValues(alpha: 0.45)
        : const Color(0x338B949E);
    canvas.drawRRect(surfaceRRect, _borderPaint);
  }

  void _paintViewportCells(Canvas canvas, Offset offset) {
    final atlas = _sharedAtlas;
    if (atlas == null) return;

    final int rows = _controller.rows;
    final int cols = _controller.cols;
    final double cw = atlas.cellWidth;
    final double ch = atlas.cellHeight;
    final int visibleRows = math.min(
      rows,
      ((size.height - _padding * 2.0) / ch).floor().clamp(1, rows),
    );
    final int visibleCols = math.min(
      cols,
      ((size.width - _padding * 2.0) / cw).floor().clamp(1, cols),
    );

    _ensureAtlasCapacity(visibleRows * visibleCols);
    final int glyphTotal = _buildCellsAndBackgrounds(
      canvas,
      offset,
      atlas,
      visibleRows,
      visibleCols,
    );
    _flushGlyphAtlas(canvas, atlas, glyphTotal);
  }

  int _buildCellsAndBackgrounds(
    Canvas canvas,
    Offset offset,
    _SharedTerminalAtlas atlas,
    int visibleRows,
    int visibleCols,
  ) {
    final Uint32List cps = _controller.viewportCodepoints;
    final Uint32List fgs = _controller.viewportFgArgb;
    final Uint32List bgs = _controller.viewportBgArgb;
    final Uint8List attrs = _controller.viewportAttrs;

    final double cw = atlas.cellWidth;
    final double ch = atlas.cellHeight;
    final double baseX = offset.dx + _padding;
    final double baseY = offset.dy + _padding;
    final Float32x4 scaleRot = Float32x4(1.0, 0.0, 0.0, 0.0);
    int gIdx = 0;

    for (int r = 0; r < visibleRows; r++) {
      final int rowBase = r * ZeroTerminalStateView.viewportStride;
      final double y = baseY + r * ch;
      for (int c = 0; c < visibleCols; c++) {
        final int cellIdx = rowBase + c;
        final double x = baseX + c * cw;
        final int attr = attrs[cellIdx];
        final bool inv = (attr & _attrInverse) != 0;
        final int fgArgb = inv ? bgs[cellIdx] : fgs[cellIdx];
        final int bgArgb = inv ? fgs[cellIdx] : bgs[cellIdx];

        if (bgArgb != _defaultBgArgb) {
          _cellBgPaint.color = Color(bgArgb);
          canvas.drawRect(Rect.fromLTWH(x, y, cw, ch), _cellBgPaint);
        }
        if ((attr & _attrUnderline) != 0) {
          _underlinePaint.color = Color(fgArgb);
          canvas.drawLine(
            Offset(x, y + ch - 1.5),
            Offset(x + cw, y + ch - 1.5),
            _underlinePaint,
          );
        }
        gIdx = _appendGlyphIfPrintable(
          atlas,
          cps[cellIdx],
          fgArgb,
          attr,
          x,
          y,
          scaleRot,
          gIdx,
        );
      }
    }
    return gIdx;
  }

  int _appendGlyphIfPrintable(
    _SharedTerminalAtlas atlas,
    int cp,
    int fgArgb,
    int attr,
    double x,
    double y,
    Float32x4 scaleRot,
    int gIdx,
  ) {
    if (cp <= 0x20) return gIdx;
    final int asciiIdx = (cp >= 0x21 && cp <= 0x7E) ? (cp - 0x20) : 0x1F;
    _transforms4[gIdx] = scaleRot.withZ(x).withW(y);
    _rects4[gIdx] = atlas.atlasRects4[asciiIdx];
    _colors[gIdx] = (attr & _attrBold) != 0 ? (fgArgb | 0xFF000000) : fgArgb;
    return gIdx + 1;
  }

  void _flushGlyphAtlas(
    Canvas canvas,
    _SharedTerminalAtlas atlas,
    int glyphTotal,
  ) {
    if (glyphTotal <= 0) return;
    final ui.Image? atlasImg = atlas.atlasImage;
    if (atlasImg != null) {
      final int fLen = glyphTotal << 2;
      canvas.drawRawAtlas(
        atlasImg,
        Float32List.sublistView(_transforms, 0, fLen),
        Float32List.sublistView(_rects, 0, fLen),
        Int32List.sublistView(_colors, 0, glyphTotal),
        BlendMode.modulate,
        null,
        _atlasPaint,
      );
      return;
    }
    for (int i = 0; i < glyphTotal; i++) {
      final int tBase = i << 2;
      final int glyphIdx =
          (_rects[tBase] / (atlas.cellWidth + 2.0)).round().clamp(0, 94);
      atlas.painters[glyphIdx].paint(
        canvas,
        Offset(_transforms[tBase + 2], _transforms[tBase + 3]),
      );
    }
  }

  void _paintSelection(Canvas canvas, Offset offset) {
    if (_selStartRow < 0 || _selEndRow < 0) return;
    if (_selStartRow == _selEndRow && _selStartCol == _selEndCol) return;

    final int r0 = math.min(_selStartRow, _selEndRow);
    final int r1 = math.max(_selStartRow, _selEndRow);
    final int c0 = math.min(_selStartCol, _selEndCol);
    final int c1 = math.max(_selStartCol, _selEndCol);
    final double cw = cellWidth;
    final double ch = cellHeight;

    for (int r = r0; r <= r1; r++) {
      final double x = offset.dx + _padding + c0 * cw;
      final double y = offset.dy + _padding + r * ch;
      final double w = (c1 - c0 + 1) * cw;
      canvas.drawRect(Rect.fromLTWH(x, y, w, ch), _selectionPaint);
    }
  }

  void _paintCursor(Canvas canvas, Offset offset) {
    if (!_controller.cursorVisible || _controller.scrollOffset > 0) return;
    final int cCol = _controller.cursorCol;
    final int cRow = _controller.cursorRow;
    final double cw = cellWidth;
    final double ch = cellHeight;
    final double cx = offset.dx + _padding + cCol * cw;
    final double cy = offset.dy + _padding + cRow * ch;

    final ZeroTerminalCursorStyle style = _controller.cursorStyle;
    _cursorPaint.color = _cursorColor.withValues(
      alpha: style == ZeroTerminalCursorStyle.block ? 0.65 : 0.95,
    );
    if (style == ZeroTerminalCursorStyle.beam) {
      canvas.drawRect(Rect.fromLTWH(cx, cy, 2.2, ch), _cursorPaint);
    } else if (style == ZeroTerminalCursorStyle.underline) {
      canvas.drawRect(Rect.fromLTWH(cx, cy + ch - 2.5, cw, 2.5), _cursorPaint);
    } else {
      canvas.drawRect(Rect.fromLTWH(cx, cy, cw, ch), _cursorPaint);
    }
  }
}
