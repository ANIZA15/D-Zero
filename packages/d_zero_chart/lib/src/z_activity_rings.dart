import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active alias for [ZActivityRings].
typedef ZConcentricRings = ZActivityRings;

/// Legacy alias for [ZActivityRings].
@Deprecated('Use ZActivityRings instead.')
typedef ZeroActivityRings = ZActivityRings;

/// Zero-allocation controller for [ZActivityRings] storing up to 4 concentric
/// ring progress ratios (`0.0 .. 1.0+`) in a flat `Float32List`.
class ZeroActivityRingsController extends ChangeNotifier {
  final int _ringCount;
  late final Float32List _progress;
  bool _isDisposed = false;

  /// Creates a [ZeroActivityRingsController] with [ringCount] rings (`1..4`).
  ZeroActivityRingsController({
    int ringCount = 3,
    double move = 0.78,
    double exercise = 0.64,
    double stand = 0.92,
  }) : _ringCount = ringCount.clamp(1, 4) {
    _progress = Float32List(_ringCount);
    if (_ringCount >= 1) _progress[0] = move.clamp(0.0, 2.0);
    if (_ringCount >= 2) _progress[1] = exercise.clamp(0.0, 2.0);
    if (_ringCount >= 3) _progress[2] = stand.clamp(0.0, 2.0);
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  @override
  bool get hasListeners => !_isDisposed && super.hasListeners;

  /// Number of concentric rings.
  int get ringCount => _ringCount;

  /// Reads progress ratio for [ringIndex] (`0.0` if disposed or out of bounds).
  double progressAt(int ringIndex) {
    if (_isDisposed || ringIndex < 0 || ringIndex >= _ringCount) return 0.0;
    return _progress[ringIndex];
  }

  /// Average completion percentage (`0..100`) across all rings.
  double get overallPercent {
    if (_isDisposed || _ringCount == 0) return 0.0;
    double sum = 0.0;
    for (int i = 0; i < _ringCount; i++) {
      sum += _progress[i].clamp(0.0, 1.0);
    }
    return (sum / _ringCount) * 100.0;
  }

  /// Updates a single ring's progress ratio in place.
  void setRingProgress(int ringIndex, double ratio) {
    if (_isDisposed || ringIndex < 0 || ringIndex >= _ringCount) return;
    final double clamped = ratio.clamp(0.0, 2.0);
    if (_progress[ringIndex] == clamped) return;
    _progress[ringIndex] = clamped;
    notifyListeners();
  }

  /// Updates the primary 3 rings (`move`, `exercise`, `stand`) in a single batch.
  void updateRings({
    required double move,
    required double exercise,
    required double stand,
  }) {
    if (_isDisposed) return;
    if (_ringCount >= 1) _progress[0] = move.clamp(0.0, 2.0);
    if (_ringCount >= 2) _progress[1] = exercise.clamp(0.0, 2.0);
    if (_ringCount >= 3) _progress[2] = stand.clamp(0.0, 2.0);
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
    _progress.fillRange(0, _progress.length, 0.0);
    super.dispose();
  }
}

/// A zero-allocation Apple Fitness / healthcare concentric activity rings widget.
///
/// Renders multiple concentric progress arcs and center completion percentage
/// inside a single [ZeroRenderBox] with pre-allocated `Paint` palettes.
class ZActivityRings extends ZLeafWidget<RenderZActivityRings> {
  /// Controller holding concentric ring progress values.
  final ZeroActivityRingsController controller;

  /// Preferred widget size.
  final Size size;

  /// Stroke width of each concentric ring.
  final double strokeWidth;

  /// Creates a const [ZActivityRings].
  const ZActivityRings({
    super.key,
    required this.controller,
    this.size = const Size(116.0, 116.0),
    this.strokeWidth = 9.0,
  });

  @override
  RenderZActivityRings createRenderObject(BuildContext context) {
    return RenderZActivityRings(
      controller: controller,
      preferredSize: size,
      strokeWidth: strokeWidth,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZActivityRings renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..strokeWidth = strokeWidth;
  }
}

/// Custom [ZeroRenderBox] for [ZActivityRings].
class RenderZActivityRings extends ZeroRenderBox {
  ZeroActivityRingsController _controller;
  Size _preferredSize;
  double _strokeWidth;

  static const List<Color> _ringColors = <Color>[
    Color(0xFFFF1744),
    Color(0xFF00E676),
    Color(0xFF00E5FF),
    Color(0xFFFFEA00),
  ];

  late final List<Paint> _trackPaints;
  late final List<Paint> _arcPaints;
  final ZeroNumberPainter _centerPainter = ZeroNumberPainter(
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.bold,
      color: Color(0xFFFFFFFF),
      fontFamily: 'monospace',
    ),
  );

  /// Creates a [RenderZActivityRings].
  RenderZActivityRings({
    required ZeroActivityRingsController controller,
    required Size preferredSize,
    required double strokeWidth,
  })  : _controller = controller,
        _preferredSize = preferredSize,
        _strokeWidth = math.max(3.0, strokeWidth) {
    _trackPaints = List<Paint>.generate(4, (i) {
      return Paint()
        ..color = _ringColors[i].withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth;
    }, growable: false);
    _arcPaints = List<Paint>.generate(4, (i) {
      return Paint()
        ..color = _ringColors[i]
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = _strokeWidth;
    }, growable: false);
  }

  /// Activity rings controller.
  ZeroActivityRingsController get controller => _controller;
  set controller(ZeroActivityRingsController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _controller = value;
    markDirty();
  }

  /// Preferred size.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// Ring stroke width.
  double get strokeWidth => _strokeWidth;
  set strokeWidth(double value) {
    final double safe = math.max(3.0, value);
    if (_strokeWidth == safe) return;
    _strokeWidth = safe;
    for (int i = 0; i < 4; i++) {
      _trackPaints[i].strokeWidth = safe;
      _arcPaints[i].strokeWidth = safe;
    }
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
    _centerPainter.dispose();
    super.dispose();
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
    final Offset center = offset + Offset(size.width * 0.5, size.height * 0.5);
    final double outerRadius =
        math.min(size.width, size.height) * 0.5 - _strokeWidth * 0.7;
    final double ringStep = _strokeWidth + 3.0;
    final int count = _controller.ringCount;

    for (int i = 0; i < count; i++) {
      final double r = outerRadius - i * ringStep;
      if (r <= 4.0) break;
      final Rect oval = Rect.fromCircle(center: center, radius: r);
      canvas.drawOval(oval, _trackPaints[i]);
      final double sweep =
          _controller.progressAt(i).clamp(0.0, 1.0) * math.pi * 2.0;
      canvas.drawArc(oval, -math.pi * 0.5, sweep, false, _arcPaints[i]);
    }

    final double textW = _centerPainter.maxDigitWidth * 3.5;
    final double textX = center.dx - textW * 0.5;
    final double textY = center.dy - _centerPainter.height * 0.5;
    _centerPainter.paintPercent(
      canvas,
      Offset(textX, textY),
      _controller.overallPercent,
      fractionDigits: 0,
    );
  }
}
