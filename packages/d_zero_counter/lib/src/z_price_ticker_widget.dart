import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// A zero-allocation financial price ticker and currency label widget.
///
/// Listens to a [ValueListenable<double>], flashes a decaying directional background
/// highlight when the price moves up or down, and renders formatted currency in a
/// single [Canvas.drawRawAtlas] call without allocating [String]s or rebuilding widgets.
class ZPriceTicker extends ZLeafWidget<RenderZPriceTicker> {
  /// The price value source to display.
  final ValueListenable<double> valueListenable;

  /// Text style applied to the price digits and currency glyph.
  final TextStyle style;

  /// Currency glyph ID from [ZeroNumberPainter] (e.g., [ZeroNumberPainter.glyphDollar] or [ZeroNumberPainter.glyphYen]).
  final int currencyGlyph;

  /// Number of decimal places to render (`0..6`).
  final int fractionDigits;

  /// Whether to prepend `'+'` for positive values.
  final bool showPlusSign;

  /// Whether to insert `','` thousands separators.
  final bool thousandsSeparator;

  /// Background flash color when the price increases.
  final Color upFlashColor;

  /// Background flash color when the price decreases.
  final Color downFlashColor;

  const ZPriceTicker({
    super.key,
    required this.valueListenable,
    this.style = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 18.0,
      fontFamily: 'monospace',
    ),
    this.currencyGlyph = ZeroNumberPainter.glyphDollar,
    this.fractionDigits = 2,
    this.showPlusSign = false,
    this.thousandsSeparator = true,
    this.upFlashColor = const Color(0x4400E676),
    this.downFlashColor = const Color(0x44FF5252),
  });

  @override
  RenderZPriceTicker createRenderObject(BuildContext context) {
    return RenderZPriceTicker(
      valueListenable: valueListenable,
      style: style,
      currencyGlyph: currencyGlyph,
      fractionDigits: fractionDigits,
      showPlusSign: showPlusSign,
      thousandsSeparator: thousandsSeparator,
      upFlashColor: upFlashColor,
      downFlashColor: downFlashColor,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZPriceTicker renderObject) {
    renderObject
      ..valueListenable = valueListenable
      ..style = style
      ..currencyGlyph = currencyGlyph
      ..fractionDigits = fractionDigits
      ..showPlusSign = showPlusSign
      ..thousandsSeparator = thousandsSeparator
      ..upFlashColor = upFlashColor
      ..downFlashColor = downFlashColor;
  }
}

/// Alias for [ZPriceTicker] when used as a currency label.
typedef ZCurrencyLabel = ZPriceTicker;

/// Backward compatibility alias for [ZPriceTicker].
@Deprecated('Use ZPriceTicker instead.')
typedef ZeroPriceTicker = ZPriceTicker;

/// Internal RenderBox for [ZPriceTicker] performing zero-allocation currency rendering and flash decay.
class RenderZPriceTicker extends ZeroRenderBox {
  ValueListenable<double> _valueListenable;
  TextStyle _style;
  int _currencyGlyph;
  int _fractionDigits;
  bool _showPlusSign;
  bool _thousandsSeparator;
  Color _upFlashColor;
  Color _downFlashColor;

  late ZeroNumberPainter _painter;
  final Paint _flashPaint = Paint()..style = PaintingStyle.fill;

  double _lastValue;
  int _direction = 0; // +1 for up, -1 for down, 0 for neutral
  double _flashIntensity = 0.0;

  RenderZPriceTicker({
    required ValueListenable<double> valueListenable,
    required TextStyle style,
    required int currencyGlyph,
    required int fractionDigits,
    required bool showPlusSign,
    required bool thousandsSeparator,
    required Color upFlashColor,
    required Color downFlashColor,
  })  : _valueListenable = valueListenable,
        _style = style,
        _currencyGlyph = currencyGlyph,
        _fractionDigits = fractionDigits,
        _showPlusSign = showPlusSign,
        _thousandsSeparator = thousandsSeparator,
        _upFlashColor = upFlashColor,
        _downFlashColor = downFlashColor,
        _lastValue = valueListenable.value,
        super(animatePerFrame: false) {
    _painter = ZeroNumberPainter(style: _style);
  }

  ValueListenable<double> get valueListenable => _valueListenable;
  set valueListenable(ValueListenable<double> value) {
    if (_valueListenable == value) return;
    if (attached) {
      _valueListenable.removeListener(_onPriceChanged);
      value.addListener(_onPriceChanged);
    }
    _valueListenable = value;
    _onPriceChanged();
  }

  TextStyle get style => _style;
  set style(TextStyle value) {
    if (_style == value) return;
    _style = value;
    _painter.dispose();
    _painter = ZeroNumberPainter(style: _style);
    markNeedsLayout();
  }

  int get currencyGlyph => _currencyGlyph;
  set currencyGlyph(int value) {
    if (_currencyGlyph == value) return;
    _currencyGlyph = value;
    markNeedsLayout();
  }

  int get fractionDigits => _fractionDigits;
  set fractionDigits(int value) {
    if (_fractionDigits == value) return;
    _fractionDigits = value;
    markNeedsLayout();
  }

  bool get showPlusSign => _showPlusSign;
  set showPlusSign(bool value) {
    if (_showPlusSign == value) return;
    _showPlusSign = value;
    markNeedsLayout();
  }

  bool get thousandsSeparator => _thousandsSeparator;
  set thousandsSeparator(bool value) {
    if (_thousandsSeparator == value) return;
    _thousandsSeparator = value;
    markNeedsLayout();
  }

  Color get upFlashColor => _upFlashColor;
  set upFlashColor(Color value) {
    if (_upFlashColor == value) return;
    _upFlashColor = value;
    markNeedsPaint();
  }

  Color get downFlashColor => _downFlashColor;
  set downFlashColor(Color value) {
    if (_downFlashColor == value) return;
    _downFlashColor = value;
    markNeedsPaint();
  }

  void _onPriceChanged() {
    final double current = _valueListenable.value;
    if (current > _lastValue) {
      _direction = 1;
      _flashIntensity = 1.0;
      animatePerFrame = true;
    } else if (current < _lastValue) {
      _direction = -1;
      _flashIntensity = 1.0;
      animatePerFrame = true;
    }
    _lastValue = current;
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _valueListenable.addListener(_onPriceChanged);
  }

  @override
  void detach() {
    _valueListenable.removeListener(_onPriceChanged);
    super.detach();
  }

  @override
  bool onFrameTick(Duration elapsed) {
    if (_flashIntensity <= 0.01) {
      _flashIntensity = 0.0;
      animatePerFrame = false;
      return true;
    }
    _flashIntensity *= 0.88;
    return true;
  }

  @override
  void performLayout() {
    final double charW = _painter.maxDigitWidth;
    final double width = charW * (10 + _fractionDigits.clamp(0, 6));
    final double height = _painter.height + 4.0;
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    if (_flashIntensity > 0.01 && _direction != 0) {
      _paintFlashBackground(canvas, offset);
    }
    _painter.paintCurrency(
      canvas,
      Offset(offset.dx + 4.0, offset.dy + 2.0),
      _valueListenable.value,
      currencyGlyph: _currencyGlyph,
      fractionDigits: _fractionDigits,
      showPlusSign: _showPlusSign,
      thousandsSeparator: _thousandsSeparator,
    );
  }

  void _paintFlashBackground(Canvas canvas, Offset offset) {
    final Color baseColor = _direction > 0 ? _upFlashColor : _downFlashColor;
    final int alpha = (baseColor.a * 255.0 * _flashIntensity).round().clamp(0, 255);
    _flashPaint.color = baseColor.withAlpha(alpha);
    final RRect rrect = RRect.fromRectAndRadius(
      offset & size,
      const Radius.circular(4.0),
    );
    canvas.drawRRect(rrect, _flashPaint);
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }
}
