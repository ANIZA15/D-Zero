import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Zero-allocation Structure-of-Arrays (SoA) controller for a financial L2 Order Book.
class ZeroOrderBookController implements Listenable {
  /// Number of price levels on each side (bid and ask).
  final int maxDepth;

  final Float32List _bidPrices;
  final Float32List _bidSizes;
  final Float32List _askPrices;
  final Float32List _askSizes;
  final ZeroIntNotifier _revision = ZeroIntNotifier(0);
  bool _isDisposed = false;

  /// Creates a [ZeroOrderBookController] with [maxDepth] price levels per side.
  ZeroOrderBookController({this.maxDepth = 10})
      : _bidPrices = Float32List(maxDepth > 0 ? maxDepth : 1),
        _bidSizes = Float32List(maxDepth > 0 ? maxDepth : 1),
        _askPrices = Float32List(maxDepth > 0 ? maxDepth : 1),
        _askSizes = Float32List(maxDepth > 0 ? maxDepth : 1);

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether any listeners are currently registered.
  bool get hasListeners => !_isDisposed && _revision.hasListeners;

  /// Returns bid price at [level], or `0.0` if disposed/out of bounds.
  double bidPriceAt(int level) {
    if (_isDisposed || level < 0 || level >= _bidPrices.length) return 0.0;
    return _bidPrices[level];
  }

  /// Returns bid size at [level], or `0.0` if disposed/out of bounds.
  double bidSizeAt(int level) {
    if (_isDisposed || level < 0 || level >= _bidSizes.length) return 0.0;
    return _bidSizes[level];
  }

  /// Returns ask price at [level], or `0.0` if disposed/out of bounds.
  double askPriceAt(int level) {
    if (_isDisposed || level < 0 || level >= _askPrices.length) return 0.0;
    return _askPrices[level];
  }

  /// Returns ask size at [level], or `0.0` if disposed/out of bounds.
  double askSizeAt(int level) {
    if (_isDisposed || level < 0 || level >= _askSizes.length) return 0.0;
    return _askSizes[level];
  }

  /// Maximum size across all bid and ask levels (used for relative depth bar scaling).
  double get maxLevelSize {
    if (_isDisposed) return 1.0;
    double maxVal = 1.0;
    for (int i = 0; i < _bidSizes.length; i++) {
      if (_bidSizes[i] > maxVal) maxVal = _bidSizes[i];
      if (_askSizes[i] > maxVal) maxVal = _askSizes[i];
    }
    return maxVal;
  }

  /// Updates a single bid [level] in-place and notifies listeners.
  void updateBid(int level, double price, double size) {
    if (_isDisposed || level < 0 || level >= _bidPrices.length) return;
    _bidPrices[level] = price;
    _bidSizes[level] = size >= 0.0 ? size : 0.0;
    _revision.add(1);
  }

  /// Updates a single ask [level] in-place and notifies listeners.
  void updateAsk(int level, double price, double size) {
    if (_isDisposed || level < 0 || level >= _askPrices.length) return;
    _askPrices[level] = price;
    _askSizes[level] = size >= 0.0 ? size : 0.0;
    _revision.add(1);
  }

  /// Resets all bid and ask levels to `0.0`.
  void clear() {
    if (_isDisposed) return;
    _bidPrices.fillRange(0, _bidPrices.length, 0.0);
    _bidSizes.fillRange(0, _bidSizes.length, 0.0);
    _askPrices.fillRange(0, _askPrices.length, 0.0);
    _askSizes.fillRange(0, _askSizes.length, 0.0);
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

  /// Disposes this controller and releases all listeners (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _bidPrices.fillRange(0, _bidPrices.length, 0.0);
    _bidSizes.fillRange(0, _bidSizes.length, 0.0);
    _askPrices.fillRange(0, _askPrices.length, 0.0);
    _askSizes.fillRange(0, _askSizes.length, 0.0);
    _revision.dispose();
  }
}

/// Active Z-prefixed alias for [ZOrderBook].
typedef ZDataGrid = ZOrderBook;

/// Legacy deprecated alias for [ZOrderBook].
@Deprecated('Use ZOrderBook instead.')
typedef ZeroOrderBook = ZOrderBook;

/// A zero-allocation financial L2 order book & depth data grid widget that renders
/// all depth bars and bid/ask numeric columns inside a single [ZeroRenderBox]
/// using [ZeroNumberPainter] with zero widget rebuilds.
class ZOrderBook extends ZLeafWidget<RenderZOrderBook> {
  /// SoA order book controller.
  final ZeroOrderBookController controller;

  /// Bid depth bar color.
  final Color bidBarColor;

  /// Ask depth bar color.
  final Color askBarColor;

  /// Optional background color.
  final Color? backgroundColor;

  /// Text style for bid prices.
  final TextStyle bidTextStyle;

  /// Text style for ask prices.
  final TextStyle askTextStyle;

  /// Text style for sizes/quantities.
  final TextStyle sizeTextStyle;

  /// Decimal places for prices.
  final int priceFractionDigits;

  /// Decimal places for sizes.
  final int sizeFractionDigits;

  /// Fallback size when unconstrained.
  final Size preferredSize;

  /// Creates a const [ZOrderBook].
  const ZOrderBook({
    super.key,
    required this.controller,
    this.bidBarColor = const Color(0x3300E676),
    this.askBarColor = const Color(0x33FF1744),
    this.backgroundColor,
    this.bidTextStyle = const TextStyle(
      color: Color(0xFF00E676),
      fontSize: 11.0,
      fontFamily: 'monospace',
    ),
    this.askTextStyle = const TextStyle(
      color: Color(0xFFFF5252),
      fontSize: 11.0,
      fontFamily: 'monospace',
    ),
    this.sizeTextStyle = const TextStyle(
      color: Color(0xFFCFD8DC),
      fontSize: 11.0,
      fontFamily: 'monospace',
    ),
    this.priceFractionDigits = 2,
    this.sizeFractionDigits = 2,
    this.preferredSize = const Size(320.0, 180.0),
  });

  @override
  RenderZOrderBook createRenderObject(BuildContext context) {
    return RenderZOrderBook(
      controller: controller,
      bidBarColor: bidBarColor,
      askBarColor: askBarColor,
      backgroundColor: backgroundColor,
      bidTextStyle: bidTextStyle,
      askTextStyle: askTextStyle,
      sizeTextStyle: sizeTextStyle,
      priceFractionDigits: priceFractionDigits,
      sizeFractionDigits: sizeFractionDigits,
      preferredSize: preferredSize,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZOrderBook renderObject) {
    renderObject
      ..controller = controller
      ..bidBarColor = bidBarColor
      ..askBarColor = askBarColor
      ..backgroundColor = backgroundColor
      ..bidTextStyle = bidTextStyle
      ..askTextStyle = askTextStyle
      ..sizeTextStyle = sizeTextStyle
      ..priceFractionDigits = priceFractionDigits
      ..sizeFractionDigits = sizeFractionDigits
      ..preferredSize = preferredSize;
  }
}

/// Direct-to-Canvas [ZeroRenderBox] for [ZOrderBook].
class RenderZOrderBook extends ZeroRenderBox {
  ZeroOrderBookController _controller;
  Color _bidBarColor;
  Color _askBarColor;
  Color? _backgroundColor;
  TextStyle _bidTextStyle;
  TextStyle _askTextStyle;
  TextStyle _sizeTextStyle;
  int _priceFractionDigits;
  int _sizeFractionDigits;
  Size _preferredSize;

  final Paint _bidBarPaint = Paint()..style = PaintingStyle.fill;
  final Paint _askBarPaint = Paint()..style = PaintingStyle.fill;
  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;

  ZeroNumberPainter? _bidPainter;
  ZeroNumberPainter? _askPainter;
  ZeroNumberPainter? _sizePainter;

  /// Creates a [RenderZOrderBook].
  RenderZOrderBook({
    required ZeroOrderBookController controller,
    required Color bidBarColor,
    required Color askBarColor,
    required Color? backgroundColor,
    required TextStyle bidTextStyle,
    required TextStyle askTextStyle,
    required TextStyle sizeTextStyle,
    required int priceFractionDigits,
    required int sizeFractionDigits,
    required Size preferredSize,
  })  : _controller = controller,
        _bidBarColor = bidBarColor,
        _askBarColor = askBarColor,
        _backgroundColor = backgroundColor,
        _bidTextStyle = bidTextStyle,
        _askTextStyle = askTextStyle,
        _sizeTextStyle = sizeTextStyle,
        _priceFractionDigits = priceFractionDigits,
        _sizeFractionDigits = sizeFractionDigits,
        _preferredSize = preferredSize {
    _bidBarPaint.color = bidBarColor;
    _askBarPaint.color = askBarColor;
    if (backgroundColor != null) {
      _bgPaint.color = backgroundColor;
    }
    _bidPainter = ZeroNumberPainter(style: bidTextStyle);
    _askPainter = ZeroNumberPainter(style: askTextStyle);
    _sizePainter = ZeroNumberPainter(style: sizeTextStyle);
  }

  /// Active order book controller.
  ZeroOrderBookController get controller => _controller;
  set controller(ZeroOrderBookController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
    }
    _controller = value;
    if (attached) {
      _controller.addListener(markDirty);
    }
    markDirty();
  }

  /// Bid depth bar color.
  Color get bidBarColor => _bidBarColor;
  set bidBarColor(Color value) {
    if (_bidBarColor == value) return;
    _bidBarColor = value;
    _bidBarPaint.color = value;
    markDirty();
  }

  /// Ask depth bar color.
  Color get askBarColor => _askBarColor;
  set askBarColor(Color value) {
    if (_askBarColor == value) return;
    _askBarColor = value;
    _askBarPaint.color = value;
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

  /// Text style for bid prices.
  TextStyle get bidTextStyle => _bidTextStyle;
  set bidTextStyle(TextStyle value) {
    if (_bidTextStyle == value) return;
    _bidTextStyle = value;
    _bidPainter?.dispose();
    _bidPainter = ZeroNumberPainter(style: value);
    markDirty();
  }

  /// Text style for ask prices.
  TextStyle get askTextStyle => _askTextStyle;
  set askTextStyle(TextStyle value) {
    if (_askTextStyle == value) return;
    _askTextStyle = value;
    _askPainter?.dispose();
    _askPainter = ZeroNumberPainter(style: value);
    markDirty();
  }

  /// Text style for sizes.
  TextStyle get sizeTextStyle => _sizeTextStyle;
  set sizeTextStyle(TextStyle value) {
    if (_sizeTextStyle == value) return;
    _sizeTextStyle = value;
    _sizePainter?.dispose();
    _sizePainter = ZeroNumberPainter(style: value);
    markDirty();
  }

  /// Decimal digits for prices.
  int get priceFractionDigits => _priceFractionDigits;
  set priceFractionDigits(int value) {
    if (_priceFractionDigits == value) return;
    _priceFractionDigits = value;
    markDirty();
  }

  /// Decimal digits for sizes.
  int get sizeFractionDigits => _sizeFractionDigits;
  set sizeFractionDigits(int value) {
    if (_sizeFractionDigits == value) return;
    _sizeFractionDigits = value;
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
    _controller.addListener(markDirty);
    _bidPainter ??= ZeroNumberPainter(style: _bidTextStyle);
    _askPainter ??= ZeroNumberPainter(style: _askTextStyle);
    _sizePainter ??= ZeroNumberPainter(style: _sizeTextStyle);
  }

  @override
  void detach() {
    _controller.removeListener(markDirty);
    super.detach();
  }

  @override
  void dispose() {
    _bidPainter?.dispose();
    _askPainter?.dispose();
    _sizePainter?.dispose();
    _bidPainter = null;
    _askPainter = null;
    _sizePainter = null;
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
    if (_controller.isDisposed) return;

    final int rows = _controller.maxDepth;
    if (rows <= 0) return;

    final double halfW = w * 0.5;
    final double rowH = h / rows;
    final double maxSz = _controller.maxLevelSize;

    for (int i = 0; i < rows; i++) {
      final double rowY = offset.dy + i * rowH;
      _paintOrderRow(canvas, offset.dx, rowY, halfW, rowH, i, maxSz);
    }
  }

  void _paintOrderRow(
    Canvas canvas,
    double leftX,
    double rowY,
    double halfW,
    double rowH,
    int level,
    double maxSz,
  ) {
    final double bidSz = _controller.bidSizeAt(level);
    final double askSz = _controller.askSizeAt(level);
    final double bidBarW = (bidSz / maxSz).clamp(0.0, 1.0) * halfW;
    final double askBarW = (askSz / maxSz).clamp(0.0, 1.0) * halfW;
    final double midX = leftX + halfW;

    if (bidBarW > 0.5) {
      canvas.drawRect(Rect.fromLTWH(midX - bidBarW, rowY, bidBarW, rowH - 1.0), _bidBarPaint);
    }
    if (askBarW > 0.5) {
      canvas.drawRect(Rect.fromLTWH(midX, rowY, askBarW, rowH - 1.0), _askBarPaint);
    }
    _paintOrderRowNumbers(canvas, leftX, midX, rowY, halfW, rowH, level, bidSz, askSz);
  }

  void _paintOrderRowNumbers(
    Canvas canvas,
    double leftX,
    double midX,
    double rowY,
    double halfW,
    double rowH,
    int level,
    double bidSz,
    double askSz,
  ) {
    final ZeroNumberPainter? bidP = _bidPainter;
    final ZeroNumberPainter? askP = _askPainter;
    final ZeroNumberPainter? szP = _sizePainter;
    if (bidP == null || askP == null || szP == null) return;

    final double textY = rowY + (rowH - bidP.height) * 0.5;
    szP.paintDouble(canvas, Offset(leftX + 4.0, textY), bidSz, fractionDigits: _sizeFractionDigits);
    bidP.paintDouble(
      canvas,
      Offset(leftX + halfW * 0.48, textY),
      _controller.bidPriceAt(level),
      fractionDigits: _priceFractionDigits,
    );
    askP.paintDouble(
      canvas,
      Offset(midX + 6.0, textY),
      _controller.askPriceAt(level),
      fractionDigits: _priceFractionDigits,
    );
    szP.paintDouble(
      canvas,
      Offset(midX + halfW * 0.52, textY),
      askSz,
      fractionDigits: _sizeFractionDigits,
    );
  }
}
