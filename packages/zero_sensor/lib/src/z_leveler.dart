import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';

/// Deprecated legacy alias for [ZLeveler].
@Deprecated('Use ZLeveler instead.')
typedef ZeroLeveler = ZLeveler;

/// Zero-allocation 2D tilt (pitch & roll) controller for spirit level widgets.
///
/// Stores `[pitch, roll]` in a pre-allocated 2-element [Float32List] without
/// boxing or allocating objects on sensor ticks.
class ZeroTiltController {
  final Float32List _angles = Float32List(2);
  final ZeroIntNotifier _revision = ZeroIntNotifier(0);
  bool _isDisposed = false;

  /// Creates a [ZeroTiltController] with initial [pitch] and [roll] in degrees.
  ZeroTiltController({double pitch = 0.0, double roll = 0.0}) {
    _angles[0] = pitch.clamp(-90.0, 90.0);
    _angles[1] = roll.clamp(-90.0, 90.0);
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Current pitch angle in degrees (`-90.0..90.0`).
  double get pitch => _isDisposed ? 0.0 : _angles[0];

  /// Current roll angle in degrees (`-90.0..90.0`).
  double get roll => _isDisposed ? 0.0 : _angles[1];

  /// Registers a listener notified when tilt angles change.
  void addListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.addListener(listener);
  }

  /// Removes a previously registered listener.
  void removeListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.removeListener(listener);
  }

  /// Updates [pitch] and [roll] angles (in degrees, clamped to `-90..90`).
  void updateTilt(double pitch, double roll) {
    if (_isDisposed) return;
    final double p = pitch.clamp(-90.0, 90.0);
    final double r = roll.clamp(-90.0, 90.0);
    if (_angles[0] == p && _angles[1] == r) return;
    _angles[0] = p;
    _angles[1] = r;
    _revision.add(1);
  }

  /// Disposes the controller and clears listeners (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _revision.dispose();
  }
}

/// A zero-allocation 2D spirit bubble leveler widget.
///
/// Renders concentric target rings, a dynamic spirit bubble displaced by
/// [ZeroTiltController.pitch] and [ZeroTiltController.roll], and live degree
/// readouts via [ZeroNumberPainter.paintWithSuffix].
class ZLeveler extends ZLeafWidget<RenderZLeveler> {
  /// Controller providing pitch and roll angles in degrees.
  final ZeroTiltController controller;

  /// Target size of the leveler widget.
  final Size size;

  /// Background fill color of the leveler dial.
  final Color backgroundColor;

  /// Guide ring and crosshair color.
  final Color ringColor;

  /// Bubble fill color when tilted.
  final Color bubbleColor;

  /// Bubble fill color when level (near 0°).
  final Color levelColor;

  /// Creates a const [ZLeveler] widget.
  const ZLeveler({
    super.key,
    required this.controller,
    this.size = const Size(160.0, 160.0),
    this.backgroundColor = const Color(0xFF0F172A),
    this.ringColor = const Color(0xFF475569),
    this.bubbleColor = const Color(0xFF38BDF8),
    this.levelColor = const Color(0xFF22C55E),
  });

  @override
  RenderZLeveler createRenderObject(BuildContext context) {
    return RenderZLeveler(
      controller: controller,
      boxSize: size,
      backgroundColor: backgroundColor,
      ringColor: ringColor,
      bubbleColor: bubbleColor,
      levelColor: levelColor,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZLeveler renderObject) {
    renderObject
      ..controller = controller
      ..boxSize = size
      ..backgroundColor = backgroundColor
      ..ringColor = ringColor
      ..bubbleColor = bubbleColor
      ..levelColor = levelColor;
  }
}

/// RenderBox for [ZLeveler] that draws target rings, a spirit bubble, and
/// zero-allocation degree readouts.
class RenderZLeveler extends ZeroRenderBox {
  ZeroTiltController _controller;
  Size _boxSize;
  Color _backgroundColor;
  Color _ringColor;
  Color _bubbleColor;
  Color _levelColor;

  ZeroNumberPainter? _anglePainter;

  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  final Paint _bubblePaint = Paint()..style = PaintingStyle.fill;
  final Paint _levelPaint = Paint()..style = PaintingStyle.fill;

  /// Creates a [RenderZLeveler].
  RenderZLeveler({
    required ZeroTiltController controller,
    required Size boxSize,
    required Color backgroundColor,
    required Color ringColor,
    required Color bubbleColor,
    required Color levelColor,
  })  : _controller = controller,
        _boxSize = boxSize,
        _backgroundColor = backgroundColor,
        _ringColor = ringColor,
        _bubbleColor = bubbleColor,
        _levelColor = levelColor,
        super(animatePerFrame: false) {
    _rebuildPaints();
    _anglePainter = ZeroNumberPainter(
      style: const TextStyle(
        color: Color(0xFFE2E8F0),
        fontSize: 12.0,
        fontFamily: 'monospace',
      ),
    );
  }

  /// Active tilt controller.
  ZeroTiltController get controller => _controller;
  set controller(ZeroTiltController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(_onTiltChanged);
    }
    _controller = value;
    if (attached) {
      _controller.addListener(_onTiltChanged);
    }
    markDirty();
  }

  /// Target leveler size.
  Size get boxSize => _boxSize;
  set boxSize(Size value) {
    if (_boxSize == value) return;
    _boxSize = value;
    markNeedsLayout();
  }

  /// Dial background color.
  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    _rebuildPaints();
    markDirty();
  }

  /// Target ring and crosshair color.
  Color get ringColor => _ringColor;
  set ringColor(Color value) {
    if (_ringColor == value) return;
    _ringColor = value;
    _rebuildPaints();
    markDirty();
  }

  /// Bubble color when tilted.
  Color get bubbleColor => _bubbleColor;
  set bubbleColor(Color value) {
    if (_bubbleColor == value) return;
    _bubbleColor = value;
    _rebuildPaints();
    markDirty();
  }

  /// Bubble color when level.
  Color get levelColor => _levelColor;
  set levelColor(Color value) {
    if (_levelColor == value) return;
    _levelColor = value;
    _rebuildPaints();
    markDirty();
  }

  void _rebuildPaints() {
    _bgPaint.color = _backgroundColor;
    _ringPaint.color = _ringColor;
    _bubblePaint.color = _bubbleColor;
    _levelPaint.color = _levelColor;
  }

  void _onTiltChanged() {
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(_onTiltChanged);
  }

  @override
  void detach() {
    _controller.removeListener(_onTiltChanged);
    super.detach();
  }

  @override
  void dispose() {
    _controller.removeListener(_onTiltChanged);
    _anglePainter?.dispose();
    _anglePainter = null;
    super.dispose();
  }

  @override
  void performLayout() {
    size = constraints.constrain(_boxSize);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect rect = offset & size;
    final Offset center = rect.center;
    final double radius = math.min(rect.width, rect.height) * 0.5;
    if (radius <= 0.0) return;

    canvas.drawCircle(center, radius, _bgPaint);
    canvas.drawCircle(center, radius - 2.0, _ringPaint);
    canvas.drawCircle(center, radius * 0.5, _ringPaint);
    canvas.drawCircle(center, radius * 0.2, _ringPaint);

    _paintBubble(canvas, center, radius);
    _paintReadout(canvas, offset);
  }

  void _paintBubble(Canvas canvas, Offset center, double radius) {
    final double pitch = _controller.pitch;
    final double roll = _controller.roll;
    final double maxTravel = radius * 0.68;
    final double dx = (roll / 45.0).clamp(-1.0, 1.0) * maxTravel;
    final double dy = (pitch / 45.0).clamp(-1.0, 1.0) * maxTravel;
    final bool isLevel = pitch.abs() < 1.5 && roll.abs() < 1.5;
    final Paint activePaint = isLevel ? _levelPaint : _bubblePaint;
    canvas.drawCircle(
      Offset(center.dx + dx, center.dy + dy),
      radius * 0.16,
      activePaint,
    );
  }

  void _paintReadout(Canvas canvas, Offset offset) {
    final ZeroNumberPainter? painter = _anglePainter;
    if (painter == null) return;
    final double x = offset.dx + 6.0;
    final double y = offset.dy + size.height - painter.height - 4.0;
    final double w1 = painter.paintWithSuffix(
      canvas,
      Offset(x, y),
      _controller.pitch,
      suffixGlyph: ZeroNumberPainter.glyphDegree,
      fractionDigits: 1,
      showPlusSign: true,
    );
    painter.paintWithSuffix(
      canvas,
      Offset(x + w1 + 8.0, y),
      _controller.roll,
      suffixGlyph: ZeroNumberPainter.glyphDegree,
      fractionDigits: 1,
      showPlusSign: true,
    );
  }
}
