import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';

/// A high-performance, zero-allocation integer counter widget.
/// 
/// Listens to a [ValueListenable<int>] and repaints the latest value directly
/// to the Canvas without rebuilding the widget tree or allocating [String]s.
class ZCounter extends LeafRenderObjectWidget {
  /// The integer source to display.
  final ValueListenable<int> valueListenable;

  /// Text style applied to the counter digits.
  final TextStyle style;

  /// Minimum number of digits to display (padded with leading zeros).
  final int minDigits;

  /// Whether each digit should be monospaced for consistent tabular alignment.
  final bool monospaceAlignment;

  const ZCounter({
    super.key,
    required this.valueListenable,
    this.style = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 18.0,
      fontFamily: 'monospace',
    ),
    this.minDigits = 1,
    this.monospaceAlignment = true,
  });

  @override
  RenderZeroCounter createRenderObject(BuildContext context) {
    return RenderZeroCounter(
      valueListenable: valueListenable,
      style: style,
      minDigits: minDigits,
      monospaceAlignment: monospaceAlignment,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZeroCounter renderObject) {
    renderObject
      ..valueListenable = valueListenable
      ..style = style
      ..minDigits = minDigits
      ..monospaceAlignment = monospaceAlignment;
  }
}

/// Backward compatibility alias for [ZCounter].
@Deprecated('Use ZCounter instead.')
typedef ZeroCounter = ZCounter;

class RenderZeroCounter extends ZeroRenderBox {
  ValueListenable<int> _valueListenable;
  TextStyle _style;
  int _minDigits;
  bool _monospaceAlignment;
  late ZeroNumberPainter _painter;

  RenderZeroCounter({
    required ValueListenable<int> valueListenable,
    required TextStyle style,
    required int minDigits,
    required bool monospaceAlignment,
  })  : _valueListenable = valueListenable,
        _style = style,
        _minDigits = minDigits,
        _monospaceAlignment = monospaceAlignment,
        super(animatePerFrame: false) {
    _painter = ZeroNumberPainter(style: _style);
  }

  ValueListenable<int> get valueListenable => _valueListenable;
  set valueListenable(ValueListenable<int> value) {
    if (_valueListenable == value) return;
    if (attached) {
      _valueListenable.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _valueListenable = value;
    markDirty();
  }

  TextStyle get style => _style;
  set style(TextStyle value) {
    if (_style == value) return;
    _style = value;
    _painter.dispose();
    _painter = ZeroNumberPainter(style: _style);
    markNeedsLayout();
  }

  int get minDigits => _minDigits;
  set minDigits(int value) {
    if (_minDigits == value) return;
    _minDigits = value;
    markNeedsLayout();
  }

  bool get monospaceAlignment => _monospaceAlignment;
  set monospaceAlignment(bool value) {
    if (_monospaceAlignment == value) return;
    _monospaceAlignment = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _valueListenable.addListener(markDirty);
  }

  @override
  void detach() {
    _valueListenable.removeListener(markDirty);
    super.detach();
  }

  @override
  void performLayout() {
    final digitWidth = _painter.maxDigitWidth;
    final width = digitWidth * (_minDigits > 0 ? _minDigits : 1);
    final height = _painter.height;
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    _painter.paintInt(
      context.canvas,
      offset,
      _valueListenable.value,
      minDigits: _minDigits,
      monospaceAlignment: _monospaceAlignment,
    );
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }
}
