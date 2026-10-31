import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active alias for [ZWheelPicker].
typedef ZDrumRollPicker = ZWheelPicker;

/// Legacy alias for [ZWheelPicker].
@Deprecated('Use ZWheelPicker instead.')
typedef ZeroWheelPicker = ZWheelPicker;

/// Zero-allocation controller for [ZWheelPicker] managing index, scroll offset,
/// and velocity without allocating scroll position objects per frame.
class ZeroWheelPickerController extends ChangeNotifier {
  final int _minValue;
  final int _maxValue;
  double _currentValue;
  double _velocity = 0.0;
  bool _isDisposed = false;

  /// Creates a [ZeroWheelPickerController] bounded by [minValue] and [maxValue].
  ZeroWheelPickerController({
    int minValue = 0,
    int maxValue = 59,
    int initialValue = 0,
  })  : _minValue = math.min(minValue, maxValue),
        _maxValue = math.max(minValue, maxValue),
        _currentValue = initialValue
            .clamp(math.min(minValue, maxValue), math.max(minValue, maxValue))
            .toDouble();

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Minimum integer value.
  int get minValue => _minValue;

  /// Maximum integer value.
  int get maxValue => _maxValue;

  /// Continuous scroll value (returns `0.0` after disposal).
  double get currentValue => _isDisposed ? 0.0 : _currentValue;

  /// Selected nearest integer value (returns `0` after disposal).
  int get selectedValue =>
      _isDisposed ? 0 : _currentValue.round().clamp(_minValue, _maxValue);

  /// Current fling velocity in items per second.
  double get velocity => _isDisposed ? 0.0 : _velocity;

  /// Jumps immediately to [value].
  void jumpToValue(int value) {
    if (_isDisposed) return;
    final double clamped = value.clamp(_minValue, _maxValue).toDouble();
    if (_currentValue == clamped && _velocity == 0.0) return;
    _currentValue = clamped;
    _velocity = 0.0;
    notifyListeners();
  }

  /// Scrolls by [deltaItems] in response to user drag.
  void scrollByItems(double deltaItems) {
    if (_isDisposed) return;
    final double next =
        (_currentValue + deltaItems).clamp(_minValue.toDouble(), _maxValue.toDouble());
    if (next == _currentValue) return;
    _currentValue = next;
    notifyListeners();
  }

  /// Applies inertial velocity in items/second.
  void fling(double itemsPerSecond) {
    if (_isDisposed) return;
    _velocity = itemsPerSecond.clamp(-60.0, 60.0);
    notifyListeners();
  }

  /// Steps inertial decay and snap-to-integer physics for frame [dt] seconds.
  bool stepPhysics(double dt) {
    if (_isDisposed) return false;
    final double target = _currentValue.round().clamp(_minValue, _maxValue).toDouble();
    final double diff = target - _currentValue;
    if (_velocity.abs() < 0.05 && diff.abs() < 0.005) {
      if (_currentValue != target || _velocity != 0.0) {
        _currentValue = target;
        _velocity = 0.0;
        return true;
      }
      return false;
    }
    _currentValue = (_currentValue + _velocity * dt + diff * 8.0 * dt)
        .clamp(_minValue.toDouble(), _maxValue.toDouble());
    _velocity *= math.max(0.0, 1.0 - 6.0 * dt);
    return true;
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
    _currentValue = 0.0;
    _velocity = 0.0;
    super.dispose();
  }
}

/// A zero-allocation cylindrical drum-roll picker widget (`CupertinoPicker` replacement).
///
/// Renders visible integer slots directly from the shared GPU glyph atlas via
/// [ZeroNumberPainter] with 0 child widgets and 0 `String` allocations.
class ZWheelPicker extends ZLeafWidget<RenderZWheelPicker> {
  /// Controller managing the selected value and scroll offset.
  final ZeroWheelPickerController controller;

  /// Optional callback fired when the snapped integer selection changes.
  final ValueChanged<int>? onSelectedItemChanged;

  /// Minimum digits to zero-pad (e.g. `2` for `00..59`).
  final int minDigits;

  /// Height of each virtual item slot in logical pixels.
  final double itemExtent;

  /// Preferred widget size.
  final Size size;

  /// Highlight bar color at the center selection row.
  final Color selectionOverlayColor;

  /// Text style for the active center item.
  final TextStyle selectedStyle;

  /// Creates a const [ZWheelPicker].
  const ZWheelPicker({
    super.key,
    required this.controller,
    this.onSelectedItemChanged,
    this.minDigits = 2,
    this.itemExtent = 28.0,
    this.size = const Size(96.0, 132.0),
    this.selectionOverlayColor = const Color(0x2800E5FF),
    this.selectedStyle = const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: Color(0xFF00E5FF),
      fontFamily: 'monospace',
    ),
  });

  @override
  RenderZWheelPicker createRenderObject(BuildContext context) {
    return RenderZWheelPicker(
      controller: controller,
      onSelectedItemChanged: onSelectedItemChanged,
      minDigits: minDigits,
      itemExtent: itemExtent,
      preferredSize: size,
      selectionOverlayColor: selectionOverlayColor,
      selectedStyle: selectedStyle,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZWheelPicker renderObject,
  ) {
    renderObject
      ..controller = controller
      ..onSelectedItemChanged = onSelectedItemChanged
      ..minDigits = minDigits
      ..itemExtent = itemExtent
      ..preferredSize = size
      ..selectionOverlayColor = selectionOverlayColor;
  }
}

/// Custom [ZeroRenderBox] for [ZWheelPicker].
class RenderZWheelPicker extends ZeroRenderBox {
  ZeroWheelPickerController _controller;

  /// Callback invoked when the rounded integer value changes.
  ValueChanged<int>? onSelectedItemChanged;

  int _minDigits;
  double _itemExtent;
  Size _preferredSize;
  int _lastReportedValue;
  double? _lastPointerY;
  Duration? _lastElapsed;

  final Paint _bgPaint = Paint()..color = const Color(0xFF0C121E);
  final Paint _overlayPaint = Paint()..style = PaintingStyle.fill;
  final Paint _borderPaint = Paint()
    ..color = const Color(0xFF1E293B)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  late final ZeroNumberPainter _activePainter;
  late final ZeroNumberPainter _dimPainter;

  /// Creates a [RenderZWheelPicker].
  RenderZWheelPicker({
    required ZeroWheelPickerController controller,
    required this.onSelectedItemChanged,
    required int minDigits,
    required double itemExtent,
    required Size preferredSize,
    required Color selectionOverlayColor,
    required TextStyle selectedStyle,
  })  : _controller = controller,
        _minDigits = minDigits,
        _itemExtent = math.max(16.0, itemExtent),
        _preferredSize = preferredSize,
        _lastReportedValue = controller.selectedValue,
        super(animatePerFrame: true) {
    _overlayPaint.color = selectionOverlayColor;
    _activePainter = ZeroNumberPainter(style: selectedStyle);
    _dimPainter = ZeroNumberPainter(
      style: selectedStyle.copyWith(
        fontSize: (selectedStyle.fontSize ?? 18.0) * 0.82,
        color: const Color(0xFF64748B),
      ),
    );
  }

  /// Active wheel controller.
  ZeroWheelPickerController get controller => _controller;
  set controller(ZeroWheelPickerController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(_onControllerChanged);
      value.addListener(_onControllerChanged);
    }
    _controller = value;
    _lastReportedValue = value.selectedValue;
    markDirty();
  }

  /// Minimum zero-padded digits.
  int get minDigits => _minDigits;
  set minDigits(int value) {
    if (_minDigits == value) return;
    _minDigits = value;
    markDirty();
  }

  /// Vertical height of each item slot.
  double get itemExtent => _itemExtent;
  set itemExtent(double value) {
    final double safe = math.max(16.0, value);
    if (_itemExtent == safe) return;
    _itemExtent = safe;
    markDirty();
  }

  /// Preferred widget size.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// Selection bar overlay color.
  Color get selectionOverlayColor => _overlayPaint.color;
  set selectionOverlayColor(Color value) {
    if (_overlayPaint.color == value) return;
    _overlayPaint.color = value;
    markDirty();
  }

  void _onControllerChanged() {
    final int currentInt = _controller.selectedValue;
    if (currentInt != _lastReportedValue) {
      _lastReportedValue = currentInt;
      onSelectedItemChanged?.call(currentInt);
    }
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void detach() {
    _controller.removeListener(_onControllerChanged);
    _lastElapsed = null;
    super.detach();
  }

  @override
  void dispose() {
    _activePainter.dispose();
    _dimPainter.dispose();
    super.dispose();
  }

  @override
  void onZeroFrame(Duration elapsed) {
    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    if (_lastPointerY != null) return;
    final double dt = prev == null
        ? 0.016
        : ((elapsed - prev).inMicroseconds / 1000000.0).clamp(0.001, 0.05);
    if (_controller.stepPhysics(dt)) {
      _onControllerChanged();
    }
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      _lastPointerY = event.localPosition.dy;
    } else if (event is PointerMoveEvent && _lastPointerY != null) {
      final double dy = event.localPosition.dy - _lastPointerY!;
      _lastPointerY = event.localPosition.dy;
      _controller.scrollByItems(-dy / _itemExtent);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _lastPointerY = null;
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_preferredSize);

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect bounds = offset & size;
    final RRect frame = RRect.fromRectAndRadius(bounds, const Radius.circular(10.0));
    canvas.drawRRect(frame, _bgPaint);

    final double cy = offset.dy + size.height * 0.5;
    final Rect band = Rect.fromLTWH(
      offset.dx + 4.0,
      cy - _itemExtent * 0.5,
      size.width - 8.0,
      _itemExtent,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(band, const Radius.circular(6.0)),
      _overlayPaint,
    );

    canvas.save();
    canvas.clipRRect(frame);
    _paintVisibleSlots(canvas, offset, cy);
    canvas.restore();

    canvas.drawRRect(frame, _borderPaint);
  }

  void _paintVisibleSlots(Canvas canvas, Offset offset, double cy) {
    final double centerVal = _controller.currentValue;
    final int baseItem = centerVal.round();
    const int halfVisible = 2;

    for (int delta = -halfVisible; delta <= halfVisible; delta++) {
      final int itemVal = baseItem + delta;
      if (itemVal < _controller.minValue || itemVal > _controller.maxValue) {
        continue;
      }
      final double itemOffset = itemVal - centerVal;
      final double yPos = cy + itemOffset * _itemExtent;
      final bool isCenter = itemOffset.abs() < 0.45;
      final ZeroNumberPainter painter = isCenter ? _activePainter : _dimPainter;
      final double textW = painter.maxDigitWidth * _minDigits;
      final double dx = offset.dx + (size.width - textW) * 0.5;
      final double dy = yPos - painter.height * 0.5;
      painter.paintInt(canvas, Offset(dx, dy), itemVal, minDigits: _minDigits);
    }
  }
}
