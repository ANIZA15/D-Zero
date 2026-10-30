import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Legacy alias for [ZSlider].
@Deprecated('Use ZSlider instead.')
typedef ZeroSlider = ZSlider;

/// Legacy alias for [ZRangeSlider].
@Deprecated('Use ZRangeSlider instead.')
typedef ZeroRangeSlider = ZRangeSlider;

/// A zero-allocation, zero-rebuild single-value slider widget.
///
/// Handles pointer down/move/up directly inside [RenderZSlider] (`hitTestSelf` + `handleEvent`)
/// and paints track, thumb, and numeric value ([ZeroNumberPainter.paintDouble]) with 0 rebuilds.
class ZSlider extends ZLeafWidget<RenderZSlider> {
  /// Optional [ValueNotifier] controller updated directly on pointer drag.
  final ValueNotifier<double>? controller;

  /// Optional [ValueListenable] when using external state with [onChanged].
  final ValueListenable<double>? valueListenable;

  /// Optional callback invoked when the user drags the slider.
  final ValueChanged<double>? onChanged;

  /// Minimum slider value.
  final double min;

  /// Maximum slider value.
  final double max;

  /// Active track color.
  final Color activeColor;

  /// Inactive track color.
  final Color inactiveColor;

  /// Thumb circle color.
  final Color thumbColor;

  /// Whether to render the numeric value label via [ZeroNumberPainter].
  final bool showValueLabel;

  /// Creates a const [ZSlider].
  const ZSlider({
    super.key,
    this.controller,
    this.valueListenable,
    this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.activeColor = const Color(0xFF00E5FF),
    this.inactiveColor = const Color(0xFF37474F),
    this.thumbColor = const Color(0xFFFFFFFF),
    this.showValueLabel = true,
  }) : assert(
          controller != null || valueListenable != null,
          'Either controller or valueListenable must be provided.',
        );

  ValueListenable<double> get _effectiveListenable =>
      controller ?? valueListenable!;

  @override
  RenderZSlider createRenderObject(BuildContext context) {
    return RenderZSlider(
      listenable: _effectiveListenable,
      controller: controller,
      onChanged: onChanged,
      min: min,
      max: max,
      activeColor: activeColor,
      inactiveColor: inactiveColor,
      thumbColor: thumbColor,
      showValueLabel: showValueLabel,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZSlider renderObject) {
    renderObject
      ..listenable = _effectiveListenable
      ..controller = controller
      ..onChanged = onChanged
      ..min = min
      ..max = max
      ..activeColor = activeColor
      ..inactiveColor = inactiveColor
      ..thumbColor = thumbColor
      ..showValueLabel = showValueLabel;
  }
}

/// Custom [ZeroRenderBox] for [ZSlider].
class RenderZSlider extends ZeroRenderBox {
  ValueListenable<double> _listenable;

  /// Optional mutable controller.
  ValueNotifier<double>? controller;

  /// Optional change callback.
  ValueChanged<double>? onChanged;

  double _min;
  double _max;
  bool _showValueLabel;

  final Paint _activePaint = Paint()..style = PaintingStyle.fill;
  final Paint _inactivePaint = Paint()..style = PaintingStyle.fill;
  final Paint _thumbPaint = Paint()..style = PaintingStyle.fill;
  final ZeroNumberPainter _numberPainter = ZeroNumberPainter();

  /// Creates a [RenderZSlider].
  RenderZSlider({
    required ValueListenable<double> listenable,
    required this.controller,
    required this.onChanged,
    required double min,
    required double max,
    required Color activeColor,
    required Color inactiveColor,
    required Color thumbColor,
    required bool showValueLabel,
  })  : _listenable = listenable,
        _min = min,
        _max = max,
        _showValueLabel = showValueLabel {
    _activePaint.color = activeColor;
    _inactivePaint.color = inactiveColor;
    _thumbPaint.color = thumbColor;
  }

  /// Active listenable value source.
  ValueListenable<double> get listenable => _listenable;
  set listenable(ValueListenable<double> value) {
    if (identical(_listenable, value)) return;
    if (attached) {
      _listenable.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _listenable = value;
    markDirty();
  }

  /// Minimum value.
  double get min => _min;
  set min(double value) {
    if (_min == value) return;
    _min = value;
    markDirty();
  }

  /// Maximum value.
  double get max => _max;
  set max(double value) {
    if (_max == value) return;
    _max = value;
    markDirty();
  }

  /// Active track color.
  Color get activeColor => _activePaint.color;
  set activeColor(Color value) {
    if (_activePaint.color == value) return;
    _activePaint.color = value;
    markDirty();
  }

  /// Inactive track color.
  Color get inactiveColor => _inactivePaint.color;
  set inactiveColor(Color value) {
    if (_inactivePaint.color == value) return;
    _inactivePaint.color = value;
    markDirty();
  }

  /// Thumb color.
  Color get thumbColor => _thumbPaint.color;
  set thumbColor(Color value) {
    if (_thumbPaint.color == value) return;
    _thumbPaint.color = value;
    markDirty();
  }

  /// Whether numeric value label is shown.
  bool get showValueLabel => _showValueLabel;
  set showValueLabel(bool value) {
    if (_showValueLabel == value) return;
    _showValueLabel = value;
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listenable.addListener(markDirty);
  }

  @override
  void detach() {
    _listenable.removeListener(markDirty);
    super.detach();
  }

  @override
  void dispose() {
    _numberPainter.dispose();
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent || event is PointerMoveEvent) {
      _updateFromLocalDx(event.localPosition.dx);
    }
  }

  void _updateFromLocalDx(double localDx) {
    const double pad = 10.0;
    final double labelW =
        _showValueLabel ? (_numberPainter.maxDigitWidth * 5.0 + 8.0) : 0.0;
    final double trackW = math.max(1.0, size.width - pad * 2.0 - labelW);
    final double t = ((localDx - pad) / trackW).clamp(0.0, 1.0);
    final double newValue = _min + t * (_max - _min);
    controller?.value = newValue;
    onChanged?.call(newValue);
    markDirty();
  }

  @override
  void performLayout() {
    final double w =
        constraints.hasBoundedWidth ? constraints.maxWidth : 220.0;
    final double h =
        constraints.hasBoundedHeight ? constraints.maxHeight : 36.0;
    size = constraints.constrain(Size(w, h));
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    const double pad = 10.0;
    final double labelW =
        _showValueLabel ? (_numberPainter.maxDigitWidth * 5.0 + 8.0) : 0.0;
    final double trackW = math.max(0.0, size.width - pad * 2.0 - labelW);
    const double trackH = 6.0;
    final double cy = offset.dy + size.height * 0.5;
    final double trackX = offset.dx + pad;
    final double span = _max - _min;
    final double val = _listenable.value.clamp(_min, _max);
    final double ratio = span > 0.0 ? ((val - _min) / span).clamp(0.0, 1.0) : 0.0;

    const Radius r = Radius.circular(3.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(trackX, cy - trackH * 0.5, trackW, trackH),
        r,
      ),
      _inactivePaint,
    );

    final double thumbX = trackX + trackW * ratio;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(trackX, cy - trackH * 0.5, trackW * ratio, trackH),
        r,
      ),
      _activePaint,
    );
    canvas.drawCircle(Offset(thumbX, cy), 8.0, _thumbPaint);

    if (_showValueLabel) {
      final double textY = cy - _numberPainter.height * 0.5;
      _numberPainter.paintDouble(
        canvas,
        Offset(trackX + trackW + pad + 4.0, textY),
        val,
        fractionDigits: 2,
      );
    }
  }
}

/// Zero-allocation reactive range controller holding unboxed [start] and [end] values.
///
/// Safe against post-dispose access and repeated [dispose] calls.
class ZeroRangeValuesController extends ChangeNotifier {
  double _start;
  double _end;
  bool _isDisposed = false;

  /// Creates a [ZeroRangeValuesController] with initial [start] and [end].
  ZeroRangeValuesController(double start, double end)
      : _start = math.min(start, end),
        _end = math.max(start, end);

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Current range start value (returns `0.0` if disposed).
  double get start => _isDisposed ? 0.0 : _start;

  /// Current range end value (returns `0.0` if disposed).
  double get end => _isDisposed ? 0.0 : _end;

  /// Updates [start] and [end] in place without allocating a wrapper object.
  void setRange(double newStart, double newEnd) {
    if (_isDisposed) return;
    final double s = math.min(newStart, newEnd);
    final double e = math.max(newStart, newEnd);
    if (_start == s && _end == e) return;
    _start = s;
    _end = e;
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    if (_isDisposed) return;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_isDisposed) return;
    super.removeListener(listener);
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _start = 0.0;
    _end = 0.0;
    super.dispose();
  }
}

/// A zero-allocation, zero-rebuild dual-thumb range slider widget.
class ZRangeSlider extends ZLeafWidget<RenderZRangeSlider> {
  /// Reactive range controller holding `start` and `end`.
  final ZeroRangeValuesController controller;

  /// Minimum range value.
  final double min;

  /// Maximum range value.
  final double max;

  /// Active span color between start and end thumbs.
  final Color activeColor;

  /// Inactive track color.
  final Color inactiveColor;

  /// Thumb circle color.
  final Color thumbColor;

  /// Creates a const [ZRangeSlider].
  const ZRangeSlider({
    super.key,
    required this.controller,
    this.min = 0.0,
    this.max = 100.0,
    this.activeColor = const Color(0xFF00E5FF),
    this.inactiveColor = const Color(0xFF37474F),
    this.thumbColor = const Color(0xFFFFFFFF),
  });

  @override
  RenderZRangeSlider createRenderObject(BuildContext context) {
    return RenderZRangeSlider(
      controller: controller,
      min: min,
      max: max,
      activeColor: activeColor,
      inactiveColor: inactiveColor,
      thumbColor: thumbColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZRangeSlider renderObject,
  ) {
    renderObject
      ..controller = controller
      ..min = min
      ..max = max
      ..activeColor = activeColor
      ..inactiveColor = inactiveColor
      ..thumbColor = thumbColor;
  }
}

/// Custom [ZeroRenderBox] for [ZRangeSlider].
class RenderZRangeSlider extends ZeroRenderBox {
  ZeroRangeValuesController _controller;
  double _min;
  double _max;

  final Paint _activePaint = Paint()..style = PaintingStyle.fill;
  final Paint _inactivePaint = Paint()..style = PaintingStyle.fill;
  final Paint _thumbPaint = Paint()..style = PaintingStyle.fill;
  final ZeroNumberPainter _numberPainter = ZeroNumberPainter();

  /// Creates a [RenderZRangeSlider].
  RenderZRangeSlider({
    required ZeroRangeValuesController controller,
    required double min,
    required double max,
    required Color activeColor,
    required Color inactiveColor,
    required Color thumbColor,
  })  : _controller = controller,
        _min = min,
        _max = max {
    _activePaint.color = activeColor;
    _inactivePaint.color = inactiveColor;
    _thumbPaint.color = thumbColor;
  }

  /// Range controller.
  ZeroRangeValuesController get controller => _controller;
  set controller(ZeroRangeValuesController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _controller = value;
    markDirty();
  }

  /// Minimum bound.
  double get min => _min;
  set min(double value) {
    if (_min == value) return;
    _min = value;
    markDirty();
  }

  /// Maximum bound.
  double get max => _max;
  set max(double value) {
    if (_max == value) return;
    _max = value;
    markDirty();
  }

  /// Active bar color.
  Color get activeColor => _activePaint.color;
  set activeColor(Color value) {
    if (_activePaint.color == value) return;
    _activePaint.color = value;
    markDirty();
  }

  /// Inactive bar color.
  Color get inactiveColor => _inactivePaint.color;
  set inactiveColor(Color value) {
    if (_inactivePaint.color == value) return;
    _inactivePaint.color = value;
    markDirty();
  }

  /// Thumb color.
  Color get thumbColor => _thumbPaint.color;
  set thumbColor(Color value) {
    if (_thumbPaint.color == value) return;
    _thumbPaint.color = value;
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(markDirty);
  }

  @override
  void detach() {
    _controller.removeListener(markDirty);
    super.detach();
  }

  @override
  void dispose() {
    _numberPainter.dispose();
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent || event is PointerMoveEvent) {
      _updateThumbFromLocalDx(event.localPosition.dx);
    }
  }

  void _updateThumbFromLocalDx(double localDx) {
    const double pad = 10.0;
    final double trackW = math.max(1.0, size.width - pad * 2.0);
    final double t = ((localDx - pad) / trackW).clamp(0.0, 1.0);
    final double targetVal = _min + t * (_max - _min);
    final double s = _controller.start.clamp(_min, _max);
    final double e = _controller.end.clamp(_min, _max);
    if ((targetVal - s).abs() <= (targetVal - e).abs()) {
      _controller.setRange(math.min(targetVal, e), e);
    } else {
      _controller.setRange(s, math.max(targetVal, s));
    }
  }

  @override
  void performLayout() {
    final double w =
        constraints.hasBoundedWidth ? constraints.maxWidth : 240.0;
    final double h =
        constraints.hasBoundedHeight ? constraints.maxHeight : 44.0;
    size = constraints.constrain(Size(w, h));
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    const double pad = 10.0;
    final double trackW = math.max(0.0, size.width - pad * 2.0);
    final double trackX = offset.dx + pad;
    final double cy = offset.dy + size.height * 0.4;
    final double span = _max - _min;
    final double s = _controller.start.clamp(_min, _max);
    final double e = _controller.end.clamp(_min, _max);
    final double startRatio = span > 0.0 ? ((s - _min) / span).clamp(0.0, 1.0) : 0.0;
    final double endRatio = span > 0.0 ? ((e - _min) / span).clamp(0.0, 1.0) : 0.0;

    const Radius r = Radius.circular(3.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(trackX, cy - 3.0, trackW, 6.0), r),
      _inactivePaint,
    );

    final double sx = trackX + trackW * startRatio;
    final double ex = trackX + trackW * endRatio;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(sx, cy - 3.0, ex - sx, 6.0), r),
      _activePaint,
    );

    canvas.drawCircle(Offset(sx, cy), 8.0, _thumbPaint);
    canvas.drawCircle(Offset(ex, cy), 8.0, _thumbPaint);

    final double labelY = offset.dy + size.height - _numberPainter.height;
    _numberPainter.paintDouble(canvas, Offset(trackX, labelY), s, fractionDigits: 1);
    final double rightX = trackX + trackW - _numberPainter.maxDigitWidth * 4.5;
    _numberPainter.paintDouble(canvas, Offset(rightX, labelY), e, fractionDigits: 1);
  }
}
