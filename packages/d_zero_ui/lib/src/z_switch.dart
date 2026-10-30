import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active Z-prefixed alias for [ZSwitch].
typedef ZToggle = ZSwitch;

/// Deprecated legacy alias for [ZSwitch].
@Deprecated('Use ZSwitch instead.')
typedef ZeroSwitch = ZSwitch;

/// A zero-allocation, zero-rebuild toggle switch widget.
///
/// Handles tap gestures directly in [RenderZSwitch] and smoothly interpolates
/// the thumb position and track color using a pre-allocated [Paint] palette
/// via [ZeroFrameScheduler] without `setState` or `AnimationController`.
class ZSwitch extends ZLeafWidget<RenderZSwitch> {
  /// Optional mutable [ValueNotifier<bool>] toggled automatically on tap.
  final ValueNotifier<bool>? controller;

  /// Optional external [ValueListenable<bool>] when driving state externally.
  final ValueListenable<bool>? valueListenable;

  /// Optional callback invoked when the user toggles the switch.
  final ValueChanged<bool>? onChanged;

  /// Track color when `value == true`.
  final Color activeTrackColor;

  /// Track color when `value == false`.
  final Color inactiveTrackColor;

  /// Thumb circle color when `value == true`.
  final Color activeThumbColor;

  /// Thumb circle color when `value == false`.
  final Color inactiveThumbColor;

  /// Target size of the switch (`52x30` by default).
  final Size size;

  /// Creates a const [ZSwitch].
  const ZSwitch({
    super.key,
    this.controller,
    this.valueListenable,
    this.onChanged,
    this.activeTrackColor = const Color(0xFF00E5FF),
    this.inactiveTrackColor = const Color(0xFF334155),
    this.activeThumbColor = const Color(0xFF0F172A),
    this.inactiveThumbColor = const Color(0xFFE2E8F0),
    this.size = const Size(52.0, 30.0),
  }) : assert(
          controller != null || valueListenable != null,
          'Either controller or valueListenable must be provided.',
        );

  ValueListenable<bool> get _effectiveListenable =>
      controller ?? valueListenable!;

  @override
  RenderZSwitch createRenderObject(BuildContext context) {
    return RenderZSwitch(
      listenable: _effectiveListenable,
      controller: controller,
      onChanged: onChanged,
      activeTrackColor: activeTrackColor,
      inactiveTrackColor: inactiveTrackColor,
      activeThumbColor: activeThumbColor,
      inactiveThumbColor: inactiveThumbColor,
      boxSize: size,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZSwitch renderObject) {
    renderObject
      ..listenable = _effectiveListenable
      ..controller = controller
      ..onChanged = onChanged
      ..activeTrackColor = activeTrackColor
      ..inactiveTrackColor = inactiveTrackColor
      ..activeThumbColor = activeThumbColor
      ..inactiveThumbColor = inactiveThumbColor
      ..boxSize = size;
  }
}

/// Custom [ZeroRenderBox] for [ZSwitch] that animates toggle transitions
/// with zero heap allocations and zero widget rebuilds.
class RenderZSwitch extends ZeroRenderBox {
  static const int _paletteSteps = 16;

  ValueListenable<bool> _listenable;

  /// Optional mutable controller toggled on tap.
  ValueNotifier<bool>? controller;

  /// Optional callback invoked on toggle.
  ValueChanged<bool>? onChanged;

  Color _activeTrackColor;
  Color _inactiveTrackColor;
  Color _activeThumbColor;
  Color _inactiveThumbColor;
  Size _boxSize;

  double _position = 0.0;
  Duration? _lastElapsed;

  final List<Paint> _trackPaints = List<Paint>.generate(
    _paletteSteps,
    (_) => Paint()..style = PaintingStyle.fill,
    growable: false,
  );
  final List<Paint> _thumbPaints = List<Paint>.generate(
    _paletteSteps,
    (_) => Paint()..style = PaintingStyle.fill,
    growable: false,
  );

  /// Creates a [RenderZSwitch].
  RenderZSwitch({
    required ValueListenable<bool> listenable,
    required this.controller,
    required this.onChanged,
    required Color activeTrackColor,
    required Color inactiveTrackColor,
    required Color activeThumbColor,
    required Color inactiveThumbColor,
    required Size boxSize,
  })  : _listenable = listenable,
        _activeTrackColor = activeTrackColor,
        _inactiveTrackColor = inactiveTrackColor,
        _activeThumbColor = activeThumbColor,
        _inactiveThumbColor = inactiveThumbColor,
        _boxSize = boxSize,
        _position = listenable.value ? 1.0 : 0.0,
        super(animatePerFrame: false) {
    _rebuildPalette();
  }

  /// Current normalized thumb position in `0.0..1.0`.
  double get thumbPosition => _position;

  /// Observed boolean value source.
  ValueListenable<bool> get listenable => _listenable;
  set listenable(ValueListenable<bool> value) {
    if (identical(_listenable, value)) return;
    if (attached) {
      _listenable.removeListener(_onValueChanged);
      value.addListener(_onValueChanged);
    }
    _listenable = value;
    _onValueChanged();
  }

  /// Active track color (`true` state).
  Color get activeTrackColor => _activeTrackColor;
  set activeTrackColor(Color value) {
    if (_activeTrackColor == value) return;
    _activeTrackColor = value;
    _rebuildPalette();
    markDirty();
  }

  /// Inactive track color (`false` state).
  Color get inactiveTrackColor => _inactiveTrackColor;
  set inactiveTrackColor(Color value) {
    if (_inactiveTrackColor == value) return;
    _inactiveTrackColor = value;
    _rebuildPalette();
    markDirty();
  }

  /// Active thumb color (`true` state).
  Color get activeThumbColor => _activeThumbColor;
  set activeThumbColor(Color value) {
    if (_activeThumbColor == value) return;
    _activeThumbColor = value;
    _rebuildPalette();
    markDirty();
  }

  /// Inactive thumb color (`false` state).
  Color get inactiveThumbColor => _inactiveThumbColor;
  set inactiveThumbColor(Color value) {
    if (_inactiveThumbColor == value) return;
    _inactiveThumbColor = value;
    _rebuildPalette();
    markDirty();
  }

  /// Target switch size.
  Size get boxSize => _boxSize;
  set boxSize(Size value) {
    if (_boxSize == value) return;
    _boxSize = value;
    markNeedsLayout();
  }

  void _rebuildPalette() {
    for (int i = 0; i < _paletteSteps; i++) {
      final double t = i / (_paletteSteps - 1);
      _trackPaints[i].color =
          Color.lerp(_inactiveTrackColor, _activeTrackColor, t)!;
      _thumbPaints[i].color =
          Color.lerp(_inactiveThumbColor, _activeThumbColor, t)!;
    }
  }

  void _onValueChanged() {
    final double target = _listenable.value ? 1.0 : 0.0;
    if ((_position - target).abs() > 0.001) {
      _lastElapsed = null;
      animatePerFrame = true;
    }
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listenable.addListener(_onValueChanged);
  }

  @override
  void detach() {
    _listenable.removeListener(_onValueChanged);
    super.detach();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerUpEvent && size.contains(event.localPosition)) {
      final bool next = !_listenable.value;
      controller?.value = next;
      onChanged?.call(next);
    }
  }

  @override
  bool onFrameTick(Duration elapsed) {
    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    final double dt =
        prev == null ? 0.016 : (elapsed - prev).inMicroseconds / 1000000.0;
    final double step = (dt * 8.5).clamp(0.0, 1.0);
    final double target = _listenable.value ? 1.0 : 0.0;

    if ((_position - target).abs() <= step) {
      _position = target;
      animatePerFrame = false;
      return true;
    }
    _position += target > _position ? step : -step;
    return true;
  }

  @override
  void performLayout() {
    size = constraints.constrain(_boxSize);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect trackRect = offset & size;
    final double trackRadius = size.height * 0.5;
    final int paletteIdx =
        (_position * (_paletteSteps - 1)).round().clamp(0, _paletteSteps - 1);

    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, Radius.circular(trackRadius)),
      _trackPaints[paletteIdx],
    );

    const double pad = 3.0;
    final double thumbRadius = (size.height - pad * 2.0) * 0.5;
    final double minX = offset.dx + pad + thumbRadius;
    final double maxX = offset.dx + size.width - pad - thumbRadius;
    final double thumbX = minX + (maxX - minX) * _position;
    final double thumbY = offset.dy + size.height * 0.5;

    canvas.drawCircle(
      Offset(thumbX, thumbY),
      thumbRadius,
      _thumbPaints[paletteIdx],
    );
  }
}
