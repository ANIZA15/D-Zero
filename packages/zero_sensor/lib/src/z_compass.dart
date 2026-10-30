import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';

/// Deprecated legacy alias for [ZCompass].
@Deprecated('Use ZCompass instead.')
typedef ZeroCompass = ZCompass;

/// A zero-allocation gyroscope / magnetometer compass dial widget.
///
/// Caches the 72 compass ring ticks into a GPU [ui.Picture] once on layout,
/// rotates the dial directly on the [Canvas] when [headingListenable] (`0..360°`)
/// updates, and renders the center degree readout via
/// [ZeroNumberPainter.paintWithSuffix] (`ZeroNumberPainter.glyphDegree`).
class ZCompass extends ZLeafWidget<RenderZCompass> {
  /// Reactive compass heading in degrees (`0.0..360.0`).
  final ValueListenable<double> headingListenable;

  /// Target diameter/size of the compass dial.
  final Size size;

  /// Dial background fill color.
  final Color backgroundColor;

  /// Tick mark and ring color.
  final Color dialColor;

  /// North indicator needle color.
  final Color northColor;

  /// Creates a const [ZCompass] widget.
  const ZCompass({
    super.key,
    required this.headingListenable,
    this.size = const Size(160.0, 160.0),
    this.backgroundColor = const Color(0xFF0F172A),
    this.dialColor = const Color(0xFF94A3B8),
    this.northColor = const Color(0xFFEF4444),
  });

  @override
  RenderZCompass createRenderObject(BuildContext context) {
    return RenderZCompass(
      headingListenable: headingListenable,
      boxSize: size,
      backgroundColor: backgroundColor,
      dialColor: dialColor,
      northColor: northColor,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZCompass renderObject) {
    renderObject
      ..headingListenable = headingListenable
      ..boxSize = size
      ..backgroundColor = backgroundColor
      ..dialColor = dialColor
      ..northColor = northColor;
  }
}

/// RenderBox for [ZCompass] that caches the dial ticks in a [ui.Picture] and
/// paints the live degree heading via [ZeroNumberPainter].
class RenderZCompass extends ZeroRenderBox {
  static const int _tickCount = 36;

  ValueListenable<double> _headingListenable;
  Size _boxSize;
  Color _backgroundColor;
  Color _dialColor;
  Color _northColor;

  ui.Picture? _cachedDialPicture;
  double _cachedRadius = -1.0;
  ZeroNumberPainter? _degreePainter;

  final Float32List _tickLines = Float32List(_tickCount * 4);
  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _dialPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  final Paint _northPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.0
    ..strokeCap = StrokeCap.round;

  /// Creates a [RenderZCompass].
  RenderZCompass({
    required ValueListenable<double> headingListenable,
    required Size boxSize,
    required Color backgroundColor,
    required Color dialColor,
    required Color northColor,
  })  : _headingListenable = headingListenable,
        _boxSize = boxSize,
        _backgroundColor = backgroundColor,
        _dialColor = dialColor,
        _northColor = northColor,
        super(animatePerFrame: false) {
    _rebuildPaints();
    _degreePainter = ZeroNumberPainter(
      style: const TextStyle(
        color: Color(0xFFFFFFFF),
        fontSize: 16.0,
        fontWeight: FontWeight.bold,
        fontFamily: 'monospace',
      ),
    );
  }

  /// Reactive heading source (`0..360` degrees).
  ValueListenable<double> get headingListenable => _headingListenable;
  set headingListenable(ValueListenable<double> value) {
    if (identical(_headingListenable, value)) return;
    if (attached) {
      _headingListenable.removeListener(_onHeadingChanged);
    }
    _headingListenable = value;
    if (attached) {
      _headingListenable.addListener(_onHeadingChanged);
    }
    markDirty();
  }

  /// Target compass size.
  Size get boxSize => _boxSize;
  set boxSize(Size value) {
    if (_boxSize == value) return;
    _boxSize = value;
    markNeedsLayout();
  }

  /// Background circle color.
  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    _rebuildPaints();
    markDirty();
  }

  /// Dial ring and tick color.
  Color get dialColor => _dialColor;
  set dialColor(Color value) {
    if (_dialColor == value) return;
    _dialColor = value;
    _rebuildPaints();
    _invalidateDialPicture();
    markDirty();
  }

  /// North pointer needle color.
  Color get northColor => _northColor;
  set northColor(Color value) {
    if (_northColor == value) return;
    _northColor = value;
    _rebuildPaints();
    _invalidateDialPicture();
    markDirty();
  }

  void _rebuildPaints() {
    _bgPaint.color = _backgroundColor;
    _dialPaint.color = _dialColor;
    _northPaint.color = _northColor;
  }

  void _invalidateDialPicture() {
    _cachedDialPicture?.dispose();
    _cachedDialPicture = null;
    _cachedRadius = -1.0;
  }

  void _onHeadingChanged() {
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _headingListenable.addListener(_onHeadingChanged);
  }

  @override
  void detach() {
    _headingListenable.removeListener(_onHeadingChanged);
    super.detach();
  }

  @override
  void dispose() {
    _headingListenable.removeListener(_onHeadingChanged);
    _invalidateDialPicture();
    _degreePainter?.dispose();
    _degreePainter = null;
    super.dispose();
  }

  @override
  void performLayout() {
    size = constraints.constrain(_boxSize);
  }

  void _ensureDialPicture(double radius) {
    if (_cachedDialPicture != null && _cachedRadius == radius) return;
    _invalidateDialPicture();
    _cachedRadius = radius;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas c = Canvas(recorder);
    c.drawCircle(Offset.zero, radius - 2.0, _dialPaint);

    for (int i = 0; i < _tickCount; i++) {
      final double angle = (i * 10.0) * (math.pi / 180.0);
      final double cosA = math.cos(angle);
      final double sinA = math.sin(angle);
      final double outerR = radius - 4.0;
      final double innerR = (i % 9 == 0) ? radius - 14.0 : radius - 9.0;
      final int b = i << 2;
      _tickLines[b] = cosA * innerR;
      _tickLines[b + 1] = sinA * innerR;
      _tickLines[b + 2] = cosA * outerR;
      _tickLines[b + 3] = sinA * outerR;
    }
    c.drawRawPoints(ui.PointMode.lines, _tickLines, _dialPaint);
    c.drawLine(
      Offset(0.0, -(radius - 6.0)),
      Offset(0.0, -(radius * 0.38)),
      _northPaint,
    );
    _cachedDialPicture = recorder.endRecording();
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect rect = offset & size;
    final Offset center = rect.center;
    final double radius = math.min(rect.width, rect.height) * 0.5;
    if (radius <= 0.0) return;

    canvas.drawCircle(center, radius, _bgPaint);
    _ensureDialPicture(radius);

    final double rawHeading = _headingListenable.value % 360.0;
    final double normalized = rawHeading < 0.0 ? rawHeading + 360.0 : rawHeading;
    final double radians = -normalized * (math.pi / 180.0);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(radians);
    final ui.Picture? dialPic = _cachedDialPicture;
    if (dialPic != null) {
      canvas.drawPicture(dialPic);
    }
    canvas.restore();

    _paintHeadingText(canvas, center, normalized);
  }

  void _paintHeadingText(Canvas canvas, Offset center, double degrees) {
    final ZeroNumberPainter? painter = _degreePainter;
    if (painter == null) return;
    final double approxW = painter.maxDigitWidth * 4.0;
    painter.paintWithSuffix(
      canvas,
      Offset(center.dx - approxW * 0.5, center.dy - painter.height * 0.5),
      degrees,
      suffixGlyph: ZeroNumberPainter.glyphDegree,
      fractionDigits: 0,
    );
  }
}
