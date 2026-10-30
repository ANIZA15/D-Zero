import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';

/// Structure-of-Arrays (SoA) ring buffer for OHLC financial candlesticks.
///
/// Stores `opens`, `highs`, `lows`, and `closes` in contiguous [Float32List] arrays
/// with zero per-candle object allocations.
class ZeroCandlestickBuffer implements Listenable {
  /// Maximum number of OHLC candles retained in the ring buffer.
  final int capacity;

  final Float32List _opens;
  final Float32List _highs;
  final Float32List _lows;
  final Float32List _closes;
  final ZeroIntNotifier _revision = ZeroIntNotifier(0);

  int _head = 0;
  int _count = 0;
  bool _isDisposed = false;

  /// Creates a [ZeroCandlestickBuffer] with fixed [capacity].
  ZeroCandlestickBuffer({this.capacity = 64})
      : _opens = Float32List(capacity > 0 ? capacity : 1),
        _highs = Float32List(capacity > 0 ? capacity : 1),
        _lows = Float32List(capacity > 0 ? capacity : 1),
        _closes = Float32List(capacity > 0 ? capacity : 1);

  /// Whether this buffer has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether any listeners are currently registered.
  bool get hasListeners => !_isDisposed && _revision.hasListeners;

  /// Number of candles currently stored, or `0` if disposed.
  int get count => _isDisposed ? 0 : _count;

  int _physicalIndex(int logicalIndex) {
    final int cap = _opens.length;
    final int start = _count < cap ? 0 : _head;
    final int idx = start + logicalIndex;
    return idx >= cap ? idx - cap : idx;
  }

  /// Returns the open price at [index] (oldest = `0`), or `0.0` if out of range/disposed.
  double openAt(int index) {
    if (_isDisposed || index < 0 || index >= _count) return 0.0;
    return _opens[_physicalIndex(index)];
  }

  /// Returns the high price at [index] (oldest = `0`), or `0.0` if out of range/disposed.
  double highAt(int index) {
    if (_isDisposed || index < 0 || index >= _count) return 0.0;
    return _highs[_physicalIndex(index)];
  }

  /// Returns the low price at [index] (oldest = `0`), or `0.0` if out of range/disposed.
  double lowAt(int index) {
    if (_isDisposed || index < 0 || index >= _count) return 0.0;
    return _lows[_physicalIndex(index)];
  }

  /// Returns the close price at [index] (oldest = `0`), or `0.0` if out of range/disposed.
  double closeAt(int index) {
    if (_isDisposed || index < 0 || index >= _count) return 0.0;
    return _closes[_physicalIndex(index)];
  }

  /// Minimum low price across all stored candles, or `0.0` if empty/disposed.
  double get minPrice {
    if (_isDisposed || _count == 0) return 0.0;
    double m = lowAt(0);
    for (int i = 1; i < _count; i++) {
      final double v = lowAt(i);
      if (v < m) m = v;
    }
    return m;
  }

  /// Maximum high price across all stored candles, or `0.0` if empty/disposed.
  double get maxPrice {
    if (_isDisposed || _count == 0) return 0.0;
    double m = highAt(0);
    for (int i = 1; i < _count; i++) {
      final double v = highAt(i);
      if (v > m) m = v;
    }
    return m;
  }

  /// Appends a new OHLC candle (`open`, `high`, `low`, `close`) into the SoA ring buffer.
  void addCandle(double open, double high, double low, double close) {
    if (_isDisposed) return;
    final int cap = _opens.length;
    final int h = _head;
    _opens[h] = open;
    _highs[h] = high;
    _lows[h] = low;
    _closes[h] = close;
    final int next = h + 1;
    _head = next == cap ? 0 : next;
    if (_count < cap) {
      _count++;
    }
    _revision.add(1);
  }

  /// Updates the most recently added candle in-place (or adds one if empty).
  void updateLastCandle(double open, double high, double low, double close) {
    if (_isDisposed) return;
    if (_count == 0) {
      addCandle(open, high, low, close);
      return;
    }
    final int idx = _physicalIndex(_count - 1);
    _opens[idx] = open;
    _highs[idx] = high;
    _lows[idx] = low;
    _closes[idx] = close;
    _revision.add(1);
  }

  /// Clears all stored candles.
  void clear() {
    if (_isDisposed) return;
    _head = 0;
    _count = 0;
    _revision.add(1);
  }

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

  /// Disposes this buffer and releases all listeners (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _head = 0;
    _count = 0;
    _revision.dispose();
  }
}

/// Legacy deprecated alias for [ZCandlestickChart].
@Deprecated('Use ZCandlestickChart instead.')
typedef ZeroCandlestickChart = ZCandlestickChart;

/// A zero-allocation financial OHLC candlestick chart widget backed by [ZeroCandlestickBuffer].
class ZCandlestickChart extends ZLeafWidget<RenderZCandlestickChart> {
  /// SoA candlestick buffer.
  final ZeroCandlestickBuffer buffer;

  /// Color for bullish (`close >= open`) candles.
  final Color bullishColor;

  /// Color for bearish (`close < open`) candles.
  final Color bearishColor;

  /// Optional background color.
  final Color? backgroundColor;

  /// Whether to render the right-hand price axis labels via [ZeroNumberPainter].
  final bool showPriceAxis;

  /// Number of decimal digits for price axis labels.
  final int fractionDigits;

  /// Text style for price axis labels.
  final TextStyle labelStyle;

  /// Fallback size when unconstrained.
  final Size preferredSize;

  /// Creates a const [ZCandlestickChart].
  const ZCandlestickChart({
    super.key,
    required this.buffer,
    this.bullishColor = const Color(0xFF00E676),
    this.bearishColor = const Color(0xFFFF1744),
    this.backgroundColor,
    this.showPriceAxis = true,
    this.fractionDigits = 2,
    this.labelStyle = const TextStyle(
      color: Color(0xFFB0BEC5),
      fontSize: 11.0,
      fontFamily: 'monospace',
    ),
    this.preferredSize = const Size(280.0, 120.0),
  });

  @override
  RenderZCandlestickChart createRenderObject(BuildContext context) {
    return RenderZCandlestickChart(
      buffer: buffer,
      bullishColor: bullishColor,
      bearishColor: bearishColor,
      backgroundColor: backgroundColor,
      showPriceAxis: showPriceAxis,
      fractionDigits: fractionDigits,
      labelStyle: labelStyle,
      preferredSize: preferredSize,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZCandlestickChart renderObject) {
    renderObject
      ..buffer = buffer
      ..bullishColor = bullishColor
      ..bearishColor = bearishColor
      ..backgroundColor = backgroundColor
      ..showPriceAxis = showPriceAxis
      ..fractionDigits = fractionDigits
      ..labelStyle = labelStyle
      ..preferredSize = preferredSize;
  }
}

/// Direct-to-Canvas [ZeroRenderBox] for [ZCandlestickChart].
class RenderZCandlestickChart extends ZeroRenderBox {
  ZeroCandlestickBuffer _buffer;
  Color _bullishColor;
  Color _bearishColor;
  Color? _backgroundColor;
  bool _showPriceAxis;
  int _fractionDigits;
  TextStyle _labelStyle;
  Size _preferredSize;

  final Paint _bullFillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _bearFillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _bullWickPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  final Paint _bearWickPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;

  ZeroNumberPainter? _numberPainter;

  /// Creates a [RenderZCandlestickChart].
  RenderZCandlestickChart({
    required ZeroCandlestickBuffer buffer,
    required Color bullishColor,
    required Color bearishColor,
    required Color? backgroundColor,
    required bool showPriceAxis,
    required int fractionDigits,
    required TextStyle labelStyle,
    required Size preferredSize,
  })  : _buffer = buffer,
        _bullishColor = bullishColor,
        _bearishColor = bearishColor,
        _backgroundColor = backgroundColor,
        _showPriceAxis = showPriceAxis,
        _fractionDigits = fractionDigits,
        _labelStyle = labelStyle,
        _preferredSize = preferredSize {
    _bullFillPaint.color = bullishColor;
    _bullWickPaint.color = bullishColor;
    _bearFillPaint.color = bearishColor;
    _bearWickPaint.color = bearishColor;
    if (backgroundColor != null) {
      _bgPaint.color = backgroundColor;
    }
    _numberPainter = ZeroNumberPainter(style: labelStyle);
  }

  /// Active candlestick SoA buffer.
  ZeroCandlestickBuffer get buffer => _buffer;
  set buffer(ZeroCandlestickBuffer value) {
    if (identical(_buffer, value)) return;
    if (attached) {
      _buffer.removeListener(markDirty);
    }
    _buffer = value;
    if (attached) {
      _buffer.addListener(markDirty);
    }
    markDirty();
  }

  /// Bullish candle color.
  Color get bullishColor => _bullishColor;
  set bullishColor(Color value) {
    if (_bullishColor == value) return;
    _bullishColor = value;
    _bullFillPaint.color = value;
    _bullWickPaint.color = value;
    markDirty();
  }

  /// Bearish candle color.
  Color get bearishColor => _bearishColor;
  set bearishColor(Color value) {
    if (_bearishColor == value) return;
    _bearishColor = value;
    _bearFillPaint.color = value;
    _bearWickPaint.color = value;
    markDirty();
  }

  /// Optional background color.
  Color? get backgroundColor => _backgroundColor;
  set backgroundColor(Color? value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    if (value != null) {
      _bgPaint.color = value;
    }
    markDirty();
  }

  /// Whether to render the price axis.
  bool get showPriceAxis => _showPriceAxis;
  set showPriceAxis(bool value) {
    if (_showPriceAxis == value) return;
    _showPriceAxis = value;
    markDirty();
  }

  /// Number of decimal digits on the price axis.
  int get fractionDigits => _fractionDigits;
  set fractionDigits(int value) {
    if (_fractionDigits == value) return;
    _fractionDigits = value;
    markDirty();
  }

  /// Text style for price axis labels.
  TextStyle get labelStyle => _labelStyle;
  set labelStyle(TextStyle value) {
    if (_labelStyle == value) return;
    _labelStyle = value;
    _numberPainter?.dispose();
    _numberPainter = ZeroNumberPainter(style: value);
    markDirty();
  }

  /// Fallback size when unconstrained.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _buffer.addListener(markDirty);
    _numberPainter ??= ZeroNumberPainter(style: _labelStyle);
  }

  @override
  void detach() {
    _buffer.removeListener(markDirty);
    super.detach();
  }

  @override
  void dispose() {
    _numberPainter?.dispose();
    _numberPainter = null;
    super.dispose();
  }

  @override
  void performLayout() {
    size = constraints.constrain(_preferredSize);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final double w = size.width;
    final double h = size.height;
    if (w <= 0.0 || h <= 0.0) return;

    if (_backgroundColor != null) {
      canvas.drawRect(offset & size, _bgPaint);
    }
    if (_buffer.isDisposed || _buffer.count == 0) return;

    final double axisReserve = _showPriceAxis ? 56.0 : 0.0;
    final double plotW = (w - axisReserve).clamp(16.0, w);
    final double minP = _buffer.minPrice;
    final double maxP = _buffer.maxPrice;
    final double span = (maxP - minP) > 1e-6 ? (maxP - minP) : 1.0;

    _paintCandles(canvas, offset.dx, offset.dy + 4.0, plotW, h - 8.0, minP, span);
    if (_showPriceAxis) {
      _paintPriceAxis(canvas, offset.dx + plotW + 4.0, offset.dy + 2.0, h, minP, maxP);
    }
  }

  void _paintCandles(
    Canvas canvas,
    double left,
    double top,
    double plotW,
    double plotH,
    double minP,
    double span,
  ) {
    final int n = _buffer.count;
    final double slotW = plotW / _buffer.capacity;
    final double bodyW = (slotW * 0.7).clamp(1.5, slotW);

    for (int i = 0; i < n; i++) {
      final double o = _buffer.openAt(i);
      final double hi = _buffer.highAt(i);
      final double lo = _buffer.lowAt(i);
      final double c = _buffer.closeAt(i);
      final double x = left + i * slotW + (slotW - bodyW) * 0.5;
      _paintSingleCandle(canvas, x, bodyW, top, plotH, minP, span, o, hi, lo, c);
    }
  }

  void _paintSingleCandle(
    Canvas canvas,
    double x,
    double bodyW,
    double top,
    double plotH,
    double minP,
    double span,
    double o,
    double hi,
    double lo,
    double c,
  ) {
    final bool isBull = c >= o;
    final double wickX = x + bodyW * 0.5;
    final double highY = top + (1.0 - (hi - minP) / span) * plotH;
    final double lowY = top + (1.0 - (lo - minP) / span) * plotH;
    final double openY = top + (1.0 - (o - minP) / span) * plotH;
    final double closeY = top + (1.0 - (c - minP) / span) * plotH;

    canvas.drawLine(
      Offset(wickX, highY),
      Offset(wickX, lowY),
      isBull ? _bullWickPaint : _bearWickPaint,
    );
    final double bodyTop = openY < closeY ? openY : closeY;
    final double bodyH = (openY - closeY).abs().clamp(1.5, plotH);
    canvas.drawRect(
      Rect.fromLTWH(x, bodyTop, bodyW, bodyH),
      isBull ? _bullFillPaint : _bearFillPaint,
    );
  }

  void _paintPriceAxis(
    Canvas canvas,
    double x,
    double top,
    double totalH,
    double minP,
    double maxP,
  ) {
    final ZeroNumberPainter? np = _numberPainter;
    if (np == null) return;
    np.paintDouble(canvas, Offset(x, top), maxP, fractionDigits: _fractionDigits);
    np.paintDouble(
      canvas,
      Offset(x, top + totalH - np.height - 4.0),
      minP,
      fractionDigits: _fractionDigits,
    );
  }
}
