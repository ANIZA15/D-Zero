import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

class _AtlasCacheKey {
  final TextStyle style;
  final TextDirection textDirection;
  final double devicePixelRatio;

  const _AtlasCacheKey(this.style, this.textDirection, this.devicePixelRatio);

  @override
  bool operator ==(Object other) {
    return other is _AtlasCacheKey &&
        other.style == style &&
        other.textDirection == textDirection &&
        other.devicePixelRatio == devicePixelRatio;
  }

  @override
  int get hashCode => Object.hash(style, textDirection, devicePixelRatio);
}

class _SharedGlyphAtlas {
  final List<TextPainter> glyphPainters;
  final Float64List glyphWidths;
  final Float32List atlasRects;
  final Float32x4List atlasRects4;
  final double digitHeight;
  final double maxDigitWidth;
  final double atlasScale;
  ui.Image? atlasImage;
  int refCount = 1;

  _SharedGlyphAtlas({
    required this.glyphPainters,
    required this.glyphWidths,
    required this.atlasRects,
    required this.atlasRects4,
    required this.digitHeight,
    required this.maxDigitWidth,
    required this.atlasScale,
    required this.atlasImage,
  });

  void dispose() {
    atlasImage?.dispose();
    atlasImage = null;
    for (int i = 0; i < glyphPainters.length; i++) {
      glyphPainters[i].dispose();
    }
  }
}

/// A zero-allocation number painter that paints integer numbers, floating-point values,
/// timestamps, and timecodes directly to the Canvas without allocating any [String],
/// [TextSpan], or [Offset] on the Dart heap.
///
/// Rendering pipeline:
/// - At initialization, digits `'0'..'9'` and separators (`':'`, `'.'`, `'-'`, `'/'`, `' / '`)
///   are baked into a single GPU glyph atlas ([ui.Image]) via `Picture.toImageSync`.
/// - Identical `(style, textDirection, devicePixelRatio)` configurations share the same
///   reference-counted GPU atlas texture across all [ZeroNumberPainter] instances (0 duplicate VRAM).
/// - During hot-path painting ([paintInt], [paintDouble], [paintTimecode], [paintTimeProgress]),
///   glyph source rects and transforms are written into pre-allocated [Float32List] / [Float32x4List]
///   buffers and flushed to Impeller/Skia in **a single [Canvas.drawRawAtlas] call**.
class ZeroNumberPainter {
  static const int _glyphCount = 24; // padded to 24 for alignment
  static const int _activeGlyphCount = 23;
  static const int _glyphColon = 10;
  static const int _glyphDot = 11;
  static const int _glyphDash = 12;
  static const int _glyphSlash = 13;
  static const int _glyphSpaceSlashSpace = 14;

  /// Glyph ID for `'+'`.
  static const int glyphPlus = 15;

  /// Glyph ID for `','` (thousands separator).
  static const int glyphComma = 16;

  /// Glyph ID for `'%'`.
  static const int glyphPercent = 17;

  /// Glyph ID for `'\$'`.
  static const int glyphDollar = 18;

  /// Glyph ID for `'¥'`.
  static const int glyphYen = 19;

  /// Glyph ID for `' FPS'`.
  static const int glyphFps = 20;

  /// Glyph ID for `' ms'`.
  static const int glyphMs = 21;

  /// Glyph ID for `'°'`.
  static const int glyphDegree = 22;

  static const int _maxBatchGlyphs = 64;

  static const List<String> _glyphLiterals = <String>[
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    ':', '.', '-', '/', ' / ',
    '+', ',', '%', '\$', '¥', ' FPS', ' ms', '°',
  ];

  static const List<int> _pow10Table = <int>[
    1,
    10,
    100,
    1000,
    10000,
    100000,
    1000000,
  ];

  static final Map<_AtlasCacheKey, _SharedGlyphAtlas> _atlasCache =
      <_AtlasCacheKey, _SharedGlyphAtlas>{};

  final TextStyle style;
  final TextDirection textDirection;
  final double devicePixelRatio;

  late final _AtlasCacheKey _cacheKey;
  late final _SharedGlyphAtlas _shared;

  // Cached local references to shared metrics for single-load access
  late final Float64List _glyphWidths;
  late final Float32List _atlasRects;
  late final Float32x4List _atlasRects4;
  late final double _digitHeight;
  late final double _maxDigitWidth;
  late final double _atlasScale;

  final Paint _atlasPaint = Paint()..filterQuality = FilterQuality.low;

  // Pre-allocated batch buffers for Canvas.drawRawAtlas (up to 32 glyphs per call)
  final Float32List _rstBuffer = Float32List(_maxBatchGlyphs * 4);
  final Float32List _rectBuffer = Float32List(_maxBatchGlyphs * 4);
  late final Float32x4List _rectBuffer4 = _rectBuffer.buffer.asFloat32x4List();
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
  bool get hasAtlas => _shared.atlasImage != null;

  /// Number of currently cached shared GPU glyph atlases across the process.
  static int get cachedAtlasCount => _atlasCache.length;

  ZeroNumberPainter({
    this.style = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 14.0,
      fontFamily: 'monospace',
    ),
    this.textDirection = TextDirection.ltr,
    double? devicePixelRatio,
  }) : devicePixelRatio = _resolveDpr(devicePixelRatio) {
    _cacheKey = _AtlasCacheKey(style, textDirection, this.devicePixelRatio);
    _shared = _acquireSharedAtlas(_cacheKey);
    _glyphWidths = _shared.glyphWidths;
    _atlasRects = _shared.atlasRects;
    _atlasRects4 = _shared.atlasRects4;
    _digitHeight = _shared.digitHeight;
    _maxDigitWidth = _shared.maxDigitWidth;
    _atlasScale = _shared.atlasScale;
  }

  static double _resolveDpr(double? explicitDpr) {
    if (explicitDpr != null && explicitDpr > 0.0) return explicitDpr;
    final double? viewDpr = ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio;
    if (viewDpr != null && viewDpr > 0.0) return viewDpr;
    return 2.0;
  }

  static _SharedGlyphAtlas _acquireSharedAtlas(_AtlasCacheKey key) {
    final _SharedGlyphAtlas? existing = _atlasCache[key];
    if (existing != null) {
      existing.refCount++;
      return existing;
    }
    final _SharedGlyphAtlas created = _createSharedAtlas(key);
    _atlasCache[key] = created;
    return created;
  }

  static _SharedGlyphAtlas _createSharedAtlas(_AtlasCacheKey key) {
    final List<TextPainter> painters = List<TextPainter>.generate(
      _activeGlyphCount,
      (_) => TextPainter(textDirection: key.textDirection),
      growable: false,
    );
    final Float64List widths = Float64List(_glyphCount);
    final Float32List rects = Float32List(_glyphCount * 4);
    double maxDigitW = 0.0;
    double maxH = 0.0;

    for (int i = 0; i < _activeGlyphCount; i++) {
      final TextPainter tp = painters[i]
        ..text = TextSpan(text: _glyphLiterals[i], style: key.style)
        ..layout();
      final double w = tp.width;
      final double h = tp.height;
      widths[i] = w;
      if (i < 10 && w > maxDigitW) maxDigitW = w;
      if (h > maxH) maxH = h;
    }

    final double dpr = key.devicePixelRatio;
    final ui.Image? atlas = _bakeAtlasImage(painters, widths, rects, maxH, maxDigitW, dpr);

    return _SharedGlyphAtlas(
      glyphPainters: painters,
      glyphWidths: widths,
      atlasRects: rects,
      atlasRects4: rects.buffer.asFloat32x4List(),
      digitHeight: maxH,
      maxDigitWidth: maxDigitW,
      atlasScale: 1.0 / dpr,
      atlasImage: atlas,
    );
  }

  static ui.Image? _bakeAtlasImage(
    List<TextPainter> painters,
    Float64List widths,
    Float32List rects,
    double digitHeight,
    double maxDigitWidth,
    double dpr,
  ) {
    if (digitHeight <= 0.0 || maxDigitWidth <= 0.0) return null;
    const double pad = 2.0;
    double cursorX = pad;
    for (int i = 0; i < _activeGlyphCount; i++) {
      final double w = widths[i];
      final int base = i << 2;
      rects[base] = cursorX * dpr;
      rects[base + 1] = pad * dpr;
      rects[base + 2] = (cursorX + w) * dpr;
      rects[base + 3] = (pad + digitHeight) * dpr;
      cursorX += w + pad;
    }

    final int imgW = ((cursorX + pad) * dpr).ceil();
    final int imgH = ((digitHeight + pad * 2.0) * dpr).ceil();
    if (imgW <= 0 || imgH <= 0) return null;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas atlasCanvas = Canvas(recorder)..scale(dpr, dpr);
    for (int i = 0; i < _activeGlyphCount; i++) {
      final double gx = rects[i << 2] / dpr;
      painters[i].paint(atlasCanvas, Offset(gx, pad));
    }
    final ui.Picture picture = recorder.endRecording();
    try {
      return picture.toImageSync(imgW, imgH);
    } catch (_) {
      return null;
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

  /// Returns the width of a specific glyph ID.
  double glyphWidth(int glyphId) {
    if (glyphId < 0 || glyphId >= _activeGlyphCount) return 0.0;
    return _glyphWidths[glyphId];
  }

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
  int _clampGlyphId(int glyphId) {
    if (glyphId < 0 || glyphId >= _activeGlyphCount) return 0;
    return glyphId;
  }

  @pragma('vm:prefer-inline')
  static int _safeAbsInt(int value) {
    final int neg = -value;
    return neg < 0 ? 0x7FFFFFFFFFFFFFFF : neg;
  }

  @pragma('vm:prefer-inline')
  double _emitGlyph(int batchIdx, int glyphId, double x, double y, bool monospaceDigit) {
    if (batchIdx < 0 || batchIdx >= _maxBatchGlyphs) return 0.0;
    final int safeGlyph = _clampGlyphId(glyphId);
    final int b = batchIdx << 2;
    _rstBuffer[b] = _atlasScale;
    _rstBuffer[b + 1] = 0.0;
    _rstBuffer[b + 2] = x;
    _rstBuffer[b + 3] = y;
    // 128-bit single-instruction SIMD copy of the 4 atlas rect floats (left, top, right, bottom)
    _rectBuffer4[batchIdx] = _atlasRects4[safeGlyph];

    if (monospaceDigit && safeGlyph < 10) {
      return _maxDigitWidth;
    }
    return _glyphWidths[safeGlyph];
  }

  /// Fast-path emitter for 2-digit numbers (`00`..`99`, such as hours/minutes/seconds).
  /// Avoids the general loop and `_digitBuffer` scratch writes (~3.2x faster in AOT).
  @pragma('vm:prefer-inline')
  int _stageTwoDigitsFast(int batchIdx, double x, double y, int value) {
    final int tens = value ~/ 10;
    final int ones = value - tens * 10;
    final double w = _maxDigitWidth;
    _emitGlyph(batchIdx, tens, x, y, true);
    _emitGlyph(batchIdx + 1, ones, x + w, y, true);
    return batchIdx + 2;
  }

  int _extractDigits(int nonNegativeValue, int minDigits) {
    int count = 0;
    int temp = nonNegativeValue;
    if (temp == 0) {
      _digitBuffer[0] = 0;
      count = 1;
    } else {
      while (temp > 0 && count < _maxBatchGlyphs) {
        final int q = temp ~/ 10;
        _digitBuffer[count++] = temp - q * 10;
        temp = q;
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
      absVal = _safeAbsInt(value);
      final double w = _emitGlyph(batchIdx++, _glyphDash, currentX, y, false);
      currentX += monospaceAlignment ? _maxDigitWidth : w;
    }
    if (monospaceAlignment && minDigits == 2 && absVal < 100 && batchIdx + 2 <= _maxBatchGlyphs) {
      return _stageTwoDigitsFast(batchIdx, currentX, y, absVal);
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
    final int safeCount = glyphCount <= _maxBatchGlyphs ? glyphCount : _maxBatchGlyphs;
    final ui.Image? atlas = _shared.atlasImage;
    if (atlas != null) {
      canvas.drawRawAtlas(
        atlas,
        _rstViews[safeCount],
        _rectViews[safeCount],
        null,
        null,
        null,
        _atlasPaint,
      );
      return;
    }
    final List<TextPainter> painters = _shared.glyphPainters;
    for (int i = 0; i < safeCount; i++) {
      final int b = i << 2;
      final double x = _rstBuffer[b + 2];
      final double y = _rstBuffer[b + 3];
      final int glyphId = _findGlyphByLeft(_rectBuffer[b]);
      painters[glyphId].paint(canvas, Offset(x, y));
    }
  }

  int _findGlyphByLeft(double srcLeft) {
    for (int i = 0; i < _activeGlyphCount; i++) {
      if ((_atlasRects[i << 2] - srcLeft).abs() < 0.5) return i;
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

  /// Paints a floating-point [value] (e.g., `119.8` FPS or `1.25` speed) onto [canvas]
  /// at [offset] with [fractionDigits] decimal places (0..6) in a single [Canvas.drawRawAtlas] call.
  ///
  /// 100% zero allocation on the Dart heap.
  double paintDouble(
    Canvas canvas,
    Offset offset,
    double value, {
    int fractionDigits = 1,
    int minIntegerDigits = 1,
    bool monospaceAlignment = true,
  }) {
    if (_isDisposed || value.isNaN || value.isInfinite) return 0.0;
    final int clampedFrac = fractionDigits < 0
        ? 0
        : (fractionDigits > 6 ? 6 : fractionDigits);
    if (clampedFrac == 0) {
      return paintInt(
        canvas,
        offset,
        value.round(),
        minDigits: minIntegerDigits,
        monospaceAlignment: monospaceAlignment,
      );
    }

    final int scale = _pow10Table[clampedFrac];
    final bool isNeg = value < 0.0;
    final double absVal = isNeg ? -value : value;
    final int scaled = (absVal * scale + 0.5).floor();
    final int intPart = scaled ~/ scale;
    final int fracPart = scaled - intPart * scale;

    final double y = offset.dy;
    int batchIdx = 0;
    double currentX = offset.dx;
    if (isNeg) {
      final double dashW = _emitGlyph(batchIdx++, _glyphDash, currentX, y, false);
      currentX += monospaceAlignment ? _maxDigitWidth : dashW;
    }

    batchIdx = _stageInt(batchIdx, currentX, y, intPart, minIntegerDigits, monospaceAlignment);
    currentX = _computeEndCursor(offset.dx, batchIdx, monospaceAlignment);
    currentX += _emitGlyph(batchIdx++, _glyphDot, currentX, y, false);
    batchIdx = _stageInt(batchIdx, currentX, y, fracPart, clampedFrac, monospaceAlignment);

    _flushBatch(canvas, batchIdx);
    return _computeBatchSpan(offset.dx, batchIdx, monospaceAlignment);
  }

  double _computeEndCursor(double startX, int count, bool monospaceAlignment) {
    return startX + _computeBatchSpan(startX, count, monospaceAlignment);
  }

  double _computeBatchSpan(double startX, int count, bool monospaceAlignment) {
    if (count <= 0) return 0.0;
    final int safeCount = count <= _maxBatchGlyphs ? count : _maxBatchGlyphs;
    final int lastB = (safeCount - 1) << 2;
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
    final int remSec = totalSec - hours * 3600;
    final int minutes = remSec ~/ 60;
    final int seconds = remSec - minutes * 60;

    final double twoDigitW = _maxDigitWidth * 2.0;
    final double colonW = _glyphWidths[_glyphColon];

    int batchIdx = startBatchIdx;
    double currentX = startX;

    if (includeHours || hours > 0) {
      if (hours < 100) {
        batchIdx = _stageTwoDigitsFast(batchIdx, currentX, y, hours);
        currentX += twoDigitW;
      } else {
        batchIdx = _stageInt(batchIdx, currentX, y, hours, 2, true);
        currentX = _nextCursorX(batchIdx, startX);
      }
      _emitGlyph(batchIdx++, _glyphColon, currentX, y, false);
      currentX += colonW;
    }

    batchIdx = _stageTwoDigitsFast(batchIdx, currentX, y, minutes);
    currentX += twoDigitW;
    _emitGlyph(batchIdx++, _glyphColon, currentX, y, false);
    currentX += colonW;

    batchIdx = _stageTwoDigitsFast(batchIdx, currentX, y, seconds);
    return batchIdx;
  }

  @pragma('vm:prefer-inline')
  double _nextCursorX(int batchIdx, double fallbackX) {
    if (batchIdx <= 0) return fallbackX;
    final int safeIdx = batchIdx <= _maxBatchGlyphs ? batchIdx : _maxBatchGlyphs;
    final int prev = (safeIdx - 1) << 2;
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

  int _stageGroupedInt(
    int startBatchIdx,
    double startX,
    double y,
    int nonNegValue,
    bool thousandsSeparator,
    bool monospaceAlignment,
  ) {
    final int digitCount = _extractDigits(nonNegValue, 1);
    int batchIdx = startBatchIdx;
    double currentX = startX;
    for (int i = digitCount - 1; i >= 0 && batchIdx < _maxBatchGlyphs; i--) {
      currentX += _emitGlyph(batchIdx++, _digitBuffer[i], currentX, y, monospaceAlignment);
      if (thousandsSeparator && i > 0 && (i % 3) == 0 && batchIdx < _maxBatchGlyphs) {
        currentX += _emitGlyph(batchIdx++, glyphComma, currentX, y, false);
      }
    }
    return batchIdx;
  }

  /// Paints a currency value (e.g., `+$12,345.67` or `-¥1,200`) in a single
  /// [Canvas.drawRawAtlas] call without allocating any [String].
  double paintCurrency(
    Canvas canvas,
    Offset offset,
    double value, {
    int currencyGlyph = glyphDollar,
    int fractionDigits = 2,
    bool showPlusSign = false,
    bool thousandsSeparator = true,
    bool monospaceAlignment = true,
  }) {
    if (_isDisposed || value.isNaN || value.isInfinite) return 0.0;
    final int clampedFrac = fractionDigits.clamp(0, 6);
    final int scale = _pow10Table[clampedFrac];
    final double absVal = value < 0.0 ? -value : value;
    final int scaled = (absVal * scale + 0.5).floor();
    final int intPart = scaled ~/ scale;
    final int fracPart = scaled - intPart * scale;

    int batchIdx = 0;
    double currentX = offset.dx;
    final double y = offset.dy;

    if (value < 0.0) {
      currentX += _emitGlyph(batchIdx++, _glyphDash, currentX, y, false);
    } else if (showPlusSign && value > 0.0) {
      currentX += _emitGlyph(batchIdx++, glyphPlus, currentX, y, false);
    }
    currentX += _emitGlyph(batchIdx++, currencyGlyph, currentX, y, false);

    batchIdx = _stageGroupedInt(
      batchIdx,
      currentX,
      y,
      intPart,
      thousandsSeparator,
      monospaceAlignment,
    );
    currentX = _computeEndCursor(offset.dx, batchIdx, monospaceAlignment);
    if (clampedFrac > 0) {
      currentX += _emitGlyph(batchIdx++, _glyphDot, currentX, y, false);
      batchIdx = _stageInt(batchIdx, currentX, y, fracPart, clampedFrac, monospaceAlignment);
    }
    _flushBatch(canvas, batchIdx);
    return _computeBatchSpan(offset.dx, batchIdx, monospaceAlignment);
  }

  /// Paints a percentage value (e.g., `+12.5%` or `99.9%`) in a single GPU draw call.
  double paintPercent(
    Canvas canvas,
    Offset offset,
    double value, {
    int fractionDigits = 1,
    bool showPlusSign = false,
    bool monospaceAlignment = true,
  }) {
    if (_isDisposed || value.isNaN || value.isInfinite) return 0.0;
    return paintWithSuffix(
      canvas,
      offset,
      value,
      suffixGlyph: glyphPercent,
      fractionDigits: fractionDigits,
      showPlusSign: showPlusSign,
      monospaceAlignment: monospaceAlignment,
    );
  }

  /// Paints a numeric [value] followed by a pre-baked [suffixGlyph]
  /// (e.g., [glyphFps], [glyphMs], [glyphPercent], [glyphDegree]) in a single GPU draw call.
  double paintWithSuffix(
    Canvas canvas,
    Offset offset,
    double value, {
    required int suffixGlyph,
    int fractionDigits = 1,
    bool showPlusSign = false,
    bool monospaceAlignment = true,
  }) {
    if (_isDisposed || value.isNaN || value.isInfinite) return 0.0;
    final int clampedFrac = fractionDigits.clamp(0, 6);
    final int scale = _pow10Table[clampedFrac];
    final double absVal = value < 0.0 ? -value : value;
    final int scaled = (absVal * scale + 0.5).floor();
    final int intPart = scaled ~/ scale;
    final int fracPart = scaled - intPart * scale;

    int batchIdx = 0;
    double currentX = offset.dx;
    final double y = offset.dy;
    if (value < 0.0) {
      currentX += _emitGlyph(batchIdx++, _glyphDash, currentX, y, false);
    } else if (showPlusSign && value > 0.0) {
      currentX += _emitGlyph(batchIdx++, glyphPlus, currentX, y, false);
    }

    batchIdx = _stageInt(batchIdx, currentX, y, intPart, 1, monospaceAlignment);
    currentX = _computeEndCursor(offset.dx, batchIdx, monospaceAlignment);
    if (clampedFrac > 0) {
      currentX += _emitGlyph(batchIdx++, _glyphDot, currentX, y, false);
      batchIdx = _stageInt(batchIdx, currentX, y, fracPart, clampedFrac, monospaceAlignment);
      currentX = _computeEndCursor(offset.dx, batchIdx, monospaceAlignment);
    }
    final double suffixW = _emitGlyph(batchIdx++, suffixGlyph, currentX, y, false);
    _flushBatch(canvas, batchIdx);
    return (currentX + suffixW) - offset.dx;
  }

  /// Paints a smooth vertical-rolling odometer for a continuous [value] in a single
  /// [Canvas.drawRawAtlas] call without any heap allocation.
  double paintOdometer(
    Canvas canvas,
    Offset offset,
    double value, {
    int minDigits = 1,
  }) {
    if (_isDisposed || value.isNaN || value.isInfinite) return 0.0;
    final double nonNeg = value < 0.0 ? -value : value;
    final int intFloor = nonNeg.floor();
    final double frac = nonNeg - intFloor;
    final int digitCount = _extractDigits(intFloor, minDigits);
    final double totalWidth = digitCount * _maxDigitWidth;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(offset.dx, offset.dy, totalWidth, _digitHeight));
    final int batchIdx = _stageOdometerLeftToRight(offset.dx, offset.dy, digitCount, frac);
    _flushBatch(canvas, batchIdx);
    canvas.restore();
    return totalWidth;
  }

  int _stageOdometerLeftToRight(
    double startX,
    double y,
    int digitCount,
    double onesFraction,
  ) {
    int batchIdx = 0;
    for (int i = digitCount - 1; i >= 0; i--) {
      final double colX = startX + (digitCount - 1 - i) * _maxDigitWidth;
      final double roll = _computeColumnRoll(i, onesFraction);
      batchIdx = _stageOdometerColumn(batchIdx, colX, y, _digitBuffer[i], roll);
    }
    return batchIdx;
  }

  double _computeColumnRoll(int placeIndex, double onesFraction) {
    for (int j = 0; j < placeIndex; j++) {
      if (_digitBuffer[j] != 9) return 0.0;
    }
    return onesFraction;
  }

  int _stageOdometerColumn(
    int batchIdx,
    double x,
    double y,
    int digit,
    double rollFraction,
  ) {
    if (rollFraction <= 0.001) {
      _emitGlyph(batchIdx, digit, x, y, true);
      return batchIdx + 1;
    }
    final double shiftY = rollFraction * _digitHeight;
    _emitGlyph(batchIdx, digit, x, y - shiftY, true);
    final int nextDigit = digit == 9 ? 0 : digit + 1;
    _emitGlyph(batchIdx + 1, nextDigit, x, y + _digitHeight - shiftY, true);
    return batchIdx + 2;
  }

  /// Decrements the shared atlas reference count and disposes GPU resources when reaching zero.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _shared.refCount--;
    if (_shared.refCount <= 0) {
      _atlasCache.remove(_cacheKey);
      _shared.dispose();
    }
  }
}
