import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

/// A zero-allocation number painter that paints integer numbers, timestamps, and timecodes
/// directly to the Canvas without allocating any [String], [TextSpan], or [Offset] on the Dart heap.
///
/// Rendering pipeline:
/// - At initialization, digits `'0'..'9'` and separators (`':'`, `'.'`, `'-'`, `'/'`, `' / '`)
///   are baked into a single GPU glyph atlas ([ui.Image]) via `Picture.toImageSync`.
/// - During hot-path painting ([paintInt], [paintTimecode], [paintTimeProgress]),
///   glyph source rects and transforms are written into pre-allocated [Float32List]
///   buffers and flushed to Impeller/Skia in **a single [Canvas.drawRawAtlas] call**.
/// - If synchronous image rasterization is unavailable on a given target, falls back
///   to cached [ui.Paragraph] instances with `canvas.drawParagraph` (still zero String allocation).
class ZeroNumberPainter {
  static const int _glyphCount = 15;
  static const int _glyphColon = 10;
  static const int _glyphDot = 11;
  static const int _glyphDash = 12;
  static const int _glyphSlash = 13;
  static const int _glyphSpaceSlashSpace = 14;
  static const int _maxBatchGlyphs = 32;

  static const List<String> _glyphLiterals = <String>[
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    ':', '.', '-', '/', ' / ',
  ];

  final TextStyle style;
  final TextDirection textDirection;
  final double devicePixelRatio;

  final List<TextPainter> _glyphPainters = List<TextPainter>.generate(
    _glyphCount,
    (_) => TextPainter(textDirection: TextDirection.ltr),
    growable: false,
  );

  // Cached dimensions for all 15 glyphs
  final Float64List _glyphWidths = Float64List(_glyphCount);
  final Float32List _atlasRects = Float32List(_glyphCount * 4);
  double _digitHeight = 0.0;
  double _maxDigitWidth = 0.0;
  double _atlasScale = 1.0;

  ui.Image? _atlasImage;
  final Paint _atlasPaint = Paint()..filterQuality = FilterQuality.low;

  // Pre-allocated batch buffers for Canvas.drawRawAtlas (up to 32 glyphs per call)
  final Float32List _rstBuffer = Float32List(_maxBatchGlyphs * 4);
  final Float32List _rectBuffer = Float32List(_maxBatchGlyphs * 4);
  late final List<Float32List> _rstViews = List<Float32List>.generate(
    _maxBatchGlyphs + 1,
    (int n) => Float32List.sublistView(_rstBuffer, 0, n * 4),
    growable: false,
  );
  late final List<Float32List> _rectViews = List<Float32List>.generate(
    _maxBatchGlyphs + 1,
    (int n) => Float32List.sublistView(_rectBuffer, 0, n * 4),
    growable: false,
  );

  // Reusable scratch buffer for digit extraction (up to 32 digits, never reallocated)
  final Uint8List _digitBuffer = Uint8List(_maxBatchGlyphs);
  bool _isDisposed = false;

  /// Whether this painter has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether the single-call GPU glyph atlas is active.
  bool get hasAtlas => _atlasImage != null;

  ZeroNumberPainter({
    this.style = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 14.0,
      fontFamily: 'monospace',
    ),
    this.textDirection = TextDirection.ltr,
    this.devicePixelRatio = 2.0,
  }) {
    _initPaintersAndAtlas();
  }

  void _initPaintersAndAtlas() {
    _maxDigitWidth = 0.0;
    _digitHeight = 0.0;

    for (int i = 0; i < _glyphCount; i++) {
      final TextPainter tp = _glyphPainters[i]
        ..textDirection = textDirection
        ..text = TextSpan(text: _glyphLiterals[i], style: style)
        ..layout();
      final double w = tp.width;
      final double h = tp.height;
      _glyphWidths[i] = w;
      if (i < 10 && w > _maxDigitWidth) {
        _maxDigitWidth = w;
      }
      if (h > _digitHeight) {
        _digitHeight = h;
      }
    }

    _buildGlyphAtlas();
  }

  void _buildGlyphAtlas() {
    if (_digitHeight <= 0.0 || _maxDigitWidth <= 0.0) return;
    final double dpr = devicePixelRatio > 0.0 ? devicePixelRatio : 1.0;
    _atlasScale = 1.0 / dpr;

    const double pad = 2.0;
    double cursorX = pad;
    for (int i = 0; i < _glyphCount; i++) {
      final double w = _glyphWidths[i];
      final int base = i * 4;
      _atlasRects[base] = cursorX * dpr;
      _atlasRects[base + 1] = pad * dpr;
      _atlasRects[base + 2] = (cursorX + w) * dpr;
      _atlasRects[base + 3] = (pad + _digitHeight) * dpr;
      cursorX += w + pad;
    }

    final int imgW = ((cursorX + pad) * dpr).ceil();
    final int imgH = ((_digitHeight + pad * 2.0) * dpr).ceil();
    if (imgW <= 0 || imgH <= 0) return;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas atlasCanvas = Canvas(recorder)..scale(dpr, dpr);
    for (int i = 0; i < _glyphCount; i++) {
      final double gx = _atlasRects[i * 4] / dpr;
      _glyphPainters[i].paint(atlasCanvas, Offset(gx, pad));
    }
    final ui.Picture picture = recorder.endRecording();
    try {
      _atlasImage = picture.toImageSync(imgW, imgH);
    } catch (_) {
      _atlasImage = null;
    } finally {
      picture.dispose();
    }
  }

  /// Height of the rendered digits.
  double get height => _digitHeight;

  /// Max width of a single digit (useful for fixed-pitch spacing).
  double get maxDigitWidth => _maxDigitWidth;

  /// Width of ":" delimiter.
  double get colonWidth => _glyphWidths[_glyphColon];

  /// Width of "." delimiter.
  double get dotWidth => _glyphWidths[_glyphDot];

  /// Width of "-" delimiter.
  double get dashWidth => _glyphWidths[_glyphDash];

  /// Width of "/" delimiter.
  double get slashWidth => _glyphWidths[_glyphSlash];

  /// Width of " / " delimiter.
  double get spaceSlashSpaceWidth => _glyphWidths[_glyphSpaceSlashSpace];

  /// Calculates expected width for a timecode formatted as "MM:SS / MM:SS".
  double estimateTimeProgressWidth({bool includeHours = false}) {
    final double timeWidth = estimateTimecodeWidth(includeHours: includeHours);
    return timeWidth * 2.0 + _glyphWidths[_glyphSpaceSlashSpace];
  }

  /// Calculates expected width for a single timecode "MM:SS" (or "HH:MM:SS").
  double estimateTimecodeWidth({bool includeHours = false}) {
    final double colonW = _glyphWidths[_glyphColon];
    if (includeHours) {
      return (_maxDigitWidth * 6.0) + (colonW * 2.0);
    }
    return (_maxDigitWidth * 4.0) + colonW;
  }

  @pragma('vm:prefer-inline')
  double _emitGlyph(int batchIdx, int glyphId, double x, double y, bool monospaceDigit) {
    final int b = batchIdx * 4;
    _rstBuffer[b] = _atlasScale;
    _rstBuffer[b + 1] = 0.0;
    _rstBuffer[b + 2] = x;
    _rstBuffer[b + 3] = y;

    final int s = glyphId * 4;
    _rectBuffer[b] = _atlasRects[s];
    _rectBuffer[b + 1] = _atlasRects[s + 1];
    _rectBuffer[b + 2] = _atlasRects[s + 2];
    _rectBuffer[b + 3] = _atlasRects[s + 3];

    if (monospaceDigit && glyphId < 10) {
      return _maxDigitWidth;
    }
    return _glyphWidths[glyphId];
  }

  int _extractDigits(int nonNegativeValue, int minDigits) {
    int count = 0;
    int temp = nonNegativeValue;
    if (temp == 0) {
      _digitBuffer[0] = 0;
      count = 1;
    } else {
      while (temp > 0 && count < _maxBatchGlyphs) {
        _digitBuffer[count++] = temp % 10;
        temp ~/= 10;
      }
    }
    final int target = minDigits < _maxBatchGlyphs ? minDigits : _maxBatchGlyphs;
    while (count < target) {
      _digitBuffer[count++] = 0;
    }
    return count;
  }

  int _stageInt(
    int startBatchIdx,
    double startX,
    double y,
    int value,
    int minDigits,
    bool monospaceAlignment,
  ) {
    int batchIdx = startBatchIdx;
    double currentX = startX;
    int absVal = value;
    if (value < 0) {
      absVal = -value;
      final double w = _emitGlyph(batchIdx++, _glyphDash, currentX, y, false);
      currentX += monospaceAlignment ? _maxDigitWidth : w;
    }
    final int digitCount = _extractDigits(absVal, minDigits);
    for (int i = digitCount - 1; i >= 0 && batchIdx < _maxBatchGlyphs; i--) {
      final int d = _digitBuffer[i];
      currentX += _emitGlyph(batchIdx++, d, currentX, y, monospaceAlignment);
    }
    return batchIdx;
  }

  void _flushBatch(Canvas canvas, int glyphCount) {
    if (glyphCount <= 0) return;
    final ui.Image? atlas = _atlasImage;
    if (atlas != null) {
      canvas.drawRawAtlas(
        atlas,
        _rstViews[glyphCount],
        _rectViews[glyphCount],
        null,
        null,
        null,
        _atlasPaint,
      );
      return;
    }
    // Fallback when synchronous image creation is unavailable
    for (int i = 0; i < glyphCount; i++) {
      final int b = i * 4;
      final double x = _rstBuffer[b + 2];
      final double y = _rstBuffer[b + 3];
      final double srcLeft = _rectBuffer[b];
      final int glyphId = _findGlyphByLeft(srcLeft);
      _glyphPainters[glyphId].paint(canvas, Offset(x, y));
    }
  }

  int _findGlyphByLeft(double srcLeft) {
    for (int i = 0; i < _glyphCount; i++) {
      if ((_atlasRects[i * 4] - srcLeft).abs() < 0.5) return i;
    }
    return 0;
  }

  /// Paints an integer [value] onto [canvas] at [offset] in a single GPU draw call.
  ///
  /// Zero-allocation: extracts digits via integer division into a pre-allocated buffer
  /// and flushes via [Canvas.drawRawAtlas].
  /// Returns the total painted width.
  double paintInt(
    Canvas canvas,
    Offset offset,
    int value, {
    int minDigits = 1,
    bool monospaceAlignment = true,
  }) {
    if (_isDisposed) return 0.0;
    final int count = _stageInt(
      0,
      offset.dx,
      offset.dy,
      value,
      minDigits,
      monospaceAlignment,
    );
    _flushBatch(canvas, count);
    return _computeBatchSpan(offset.dx, count, monospaceAlignment);
  }

  double _computeBatchSpan(double startX, int count, bool monospaceAlignment) {
    if (count <= 0) return 0.0;
    final int lastB = (count - 1) * 4;
    final double lastX = _rstBuffer[lastB + 2];
    final double lastW = monospaceAlignment
        ? _maxDigitWidth
        : (_rectBuffer[lastB + 2] - _rectBuffer[lastB]) * _atlasScale;
    return (lastX + lastW) - startX;
  }

  int _stageTimecode(
    int startBatchIdx,
    double startX,
    double y,
    int milliseconds,
    bool includeHours,
  ) {
    final int clampedMs = milliseconds > 0 ? milliseconds : 0;
    final int totalSec = clampedMs ~/ 1000;
    final int hours = totalSec ~/ 3600;
    final int minutes = (totalSec % 3600) ~/ 60;
    final int seconds = totalSec % 60;

    int batchIdx = startBatchIdx;
    double currentX = startX;

    if (includeHours || hours > 0) {
      batchIdx = _stageInt(batchIdx, currentX, y, hours, 2, true);
      currentX = _nextCursorX(batchIdx, startX);
      currentX += _emitGlyph(batchIdx++, _glyphColon, currentX, y, false);
    }

    batchIdx = _stageInt(batchIdx, currentX, y, minutes, 2, true);
    currentX = _nextCursorX(batchIdx, startX);
    currentX += _emitGlyph(batchIdx++, _glyphColon, currentX, y, false);

    batchIdx = _stageInt(batchIdx, currentX, y, seconds, 2, true);
    return batchIdx;
  }

  @pragma('vm:prefer-inline')
  double _nextCursorX(int batchIdx, double fallbackX) {
    if (batchIdx <= 0) return fallbackX;
    final int prev = (batchIdx - 1) * 4;
    return _rstBuffer[prev + 2] + _maxDigitWidth;
  }

  /// Paints a timecode in format "MM:SS" or "HH:MM:SS" (if [includeHours] is true)
  /// given [milliseconds] in a single [Canvas.drawRawAtlas] call.
  double paintTimecode(
    Canvas canvas,
    Offset offset,
    int milliseconds, {
    bool includeHours = false,
  }) {
    if (_isDisposed) return 0.0;
    final int count = _stageTimecode(0, offset.dx, offset.dy, milliseconds, includeHours);
    _flushBatch(canvas, count);
    return _computeBatchSpan(offset.dx, count, true);
  }

  /// Paints position and total duration in format "MM:SS / MM:SS"
  /// in a single [Canvas.drawRawAtlas] call (100% zero allocation on the Dart heap).
  double paintTimeProgress(
    Canvas canvas,
    Offset offset,
    int positionMs,
    int durationMs, {
    bool includeHours = false,
  }) {
    if (_isDisposed) return 0.0;
    final double y = offset.dy;
    int batchIdx = _stageTimecode(0, offset.dx, y, positionMs, includeHours);
    double currentX = _nextCursorX(batchIdx, offset.dx);
    currentX += _emitGlyph(batchIdx++, _glyphSpaceSlashSpace, currentX, y, false);
    batchIdx = _stageTimecode(batchIdx, currentX, y, durationMs, includeHours);
    _flushBatch(canvas, batchIdx);
    return _computeBatchSpan(offset.dx, batchIdx, true);
  }

  /// Disposes the underlying GPU atlas image and text painters safely.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _atlasImage?.dispose();
    _atlasImage = null;
    for (int i = 0; i < _glyphCount; i++) {
      _glyphPainters[i].dispose();
    }
  }
}
