import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';
import '../controller.dart';

/// Active Z-prefixed alias for [ZSceneInspector3D].
typedef ZNaniteLodPanel = ZSceneInspector3D;

/// Deprecated legacy alias for [ZSceneInspector3D].
@Deprecated('Use ZSceneInspector3D instead.')
typedef ZeroSceneInspector3D = ZSceneInspector3D;

/// A zero-allocation, zero-rebuild 3D Game Engine Scene Inspector & Nanite DAG Control Panel.
///
/// Renders interactive drag tracks for:
/// 1. **Nanite Screen-Space Error Threshold (`0.25px .. 8.0px`)**
/// 2. **Directional Sun Light Azimuth & Elevation (`0 .. 2π`)**
/// 3. **Camera Vertical FOV (`20° .. 120°`)**
/// using pre-allocated [ZeroNumberPainter] glyph atlases with 0 `String` allocations.
class ZSceneInspector3D extends ZLeafWidget<RenderZSceneInspector3D> {
  /// Backing 3D engine controller.
  final Zero3DEngineController controller;

  /// Preferred inspector panel size.
  final Size size;

  /// Panel background color.
  final Color backgroundColor;

  /// Primary slider & metric accent color.
  final Color accentColor;

  /// Creates a const [ZSceneInspector3D].
  const ZSceneInspector3D({
    super.key,
    required this.controller,
    this.size = const Size(268.0, 148.0),
    this.backgroundColor = const Color(0xD80B101B),
    this.accentColor = const Color(0xFF38BDF8),
  });

  @override
  RenderZSceneInspector3D createRenderObject(BuildContext context) {
    return RenderZSceneInspector3D(
      controller: controller,
      preferredSize: size,
      backgroundColor: backgroundColor,
      accentColor: accentColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZSceneInspector3D renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..backgroundColor = backgroundColor
      ..accentColor = accentColor;
  }
}

/// Custom [ZeroRenderBox] for [ZSceneInspector3D].
class RenderZSceneInspector3D extends ZeroRenderBox {
  Zero3DEngineController _controller;
  Size _preferredSize;
  Color _backgroundColor;
  Color _accentColor;

  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  final Paint _trackPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = const Color(0xFF1E293B);
  final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _thumbPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = const Color(0xFFF8FAFC);

  late ZeroNumberPainter _numPainter;
  final List<TextPainter> _labels = <TextPainter>[];

  static const List<String> _labelStrings = <String>[
    'NANITE LOD ERROR (PX)',
    'SUN LIGHT AZIMUTH (RAD)',
    'CAMERA FOV (DEG)',
  ];

  /// Creates a [RenderZSceneInspector3D].
  RenderZSceneInspector3D({
    required Zero3DEngineController controller,
    required Size preferredSize,
    required Color backgroundColor,
    required Color accentColor,
  })  : _controller = controller,
        _preferredSize = preferredSize,
        _backgroundColor = backgroundColor,
        _accentColor = accentColor {
    _bgPaint.color = _backgroundColor;
    _borderPaint.color = _accentColor.withValues(alpha: 0.45);
    _fillPaint.color = _accentColor;
    _initNumberPainter();
    _initStaticLabels();
  }

  void _initStaticLabels() {
    const TextStyle labelStyle = TextStyle(
      color: Color(0xFF94A3B8),
      fontSize: 9.0,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
    );
    for (int i = 0; i < _labelStrings.length; i++) {
      final TextPainter tp = TextPainter(
        text: TextSpan(text: _labelStrings[i], style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      _labels.add(tp);
    }
  }

  void _initNumberPainter() {
    _numPainter = ZeroNumberPainter(
      style: TextStyle(
        color: _accentColor,
        fontSize: 12.0,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  /// Backing 3D engine controller.
  Zero3DEngineController get controller => _controller;
  set controller(Zero3DEngineController value) {
    if (identical(_controller, value)) return;
    if (attached) _controller.removeListener(markDirty);
    _controller = value;
    if (attached) _controller.addListener(markDirty);
    markDirty();
  }

  /// Preferred inspector panel size.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// Panel background color.
  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    _bgPaint.color = value;
    markDirty();
  }

  /// Accent color for slider tracks and numeric readouts.
  Color get accentColor => _accentColor;
  set accentColor(Color value) {
    if (_accentColor == value) return;
    _accentColor = value;
    _borderPaint.color = value.withValues(alpha: 0.45);
    _fillPaint.color = value;
    _numPainter.dispose();
    _initNumberPainter();
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
    _controller.removeListener(markDirty);
    _numPainter.dispose();
    for (int i = 0; i < _labels.length; i++) {
      _labels[i].dispose();
    }
    _labels.clear();
    super.dispose();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return constraints.constrain(_preferredSize);
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (_controller.isDisposed) return;
    if (event is PointerDownEvent || event is PointerMoveEvent) {
      _applyPointerSliderDrag(event.localPosition);
    }
  }

  void _applyPointerSliderDrag(Offset localPos) {
    final double trackWidth = size.width - 78.0;
    if (trackWidth <= 10.0) return;
    final double t = ((localPos.dx - 12.0) / trackWidth).clamp(0.0, 1.0);

    if (localPos.dy < size.height * 0.36) {
      // Row 0: Nanite LOD Error Threshold (0.25 .. 8.0)
      _controller.setPipelineConfig(lodErrorThreshold: 0.25 + t * 7.75);
    } else if (localPos.dy < size.height * 0.68) {
      // Row 1: Directional Light Azimuth (-pi .. pi)
      _controller.setLightAngles(
        (t * 2.0 - 1.0) * math.pi,
        _controller.lightElevation,
      );
    } else {
      // Row 2: Camera FOV Degrees (20.0 .. 120.0)
      _controller.setCameraOrbit(fovDeg: 20.0 + t * 100.0);
    }
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final RRect panel = RRect.fromRectAndRadius(
      offset & size,
      const Radius.circular(8.0),
    );
    canvas.drawRRect(panel, _bgPaint);
    canvas.drawRRect(panel, _borderPaint);
    if (_controller.isDisposed) return;

    final double lodNorm =
        ((_controller.lodErrorThreshold - 0.25) / 7.75).clamp(0.0, 1.0);
    final double lightNorm =
        ((_controller.lightAzimuth / math.pi + 1.0) * 0.5).clamp(0.0, 1.0);
    final double fovNorm =
        ((_controller.cameraFovDeg - 20.0) / 100.0).clamp(0.0, 1.0);

    _labels[0].paint(canvas, Offset(offset.dx + 12.0, offset.dy + 10.0));
    _paintSliderRow(
      canvas: canvas,
      x: offset.dx + 12.0,
      y: offset.dy + 28.0,
      norm: lodNorm,
      displayVal: _controller.lodErrorThreshold,
      digits: 2,
    );
    _labels[1].paint(canvas, Offset(offset.dx + 12.0, offset.dy + 54.0));
    _paintSliderRow(
      canvas: canvas,
      x: offset.dx + 12.0,
      y: offset.dy + 72.0,
      norm: lightNorm,
      displayVal: _controller.lightAzimuth,
      digits: 2,
    );
    _labels[2].paint(canvas, Offset(offset.dx + 12.0, offset.dy + 98.0));
    _paintSliderRow(
      canvas: canvas,
      x: offset.dx + 12.0,
      y: offset.dy + 116.0,
      norm: fovNorm,
      displayVal: _controller.cameraFovDeg,
      digits: 0,
    );
  }

  void _paintSliderRow({
    required Canvas canvas,
    required double x,
    required double y,
    required double norm,
    required double displayVal,
    required int digits,
  }) {
    final double trackW = size.width - 78.0;
    if (trackW <= 8.0) return;

    final Rect trackRect = Rect.fromLTWH(x, y, trackW, 6.0);
    final Rect fillRect = Rect.fromLTWH(x, y, trackW * norm, 6.0);
    canvas.drawRect(trackRect, _trackPaint);
    canvas.drawRect(fillRect, _fillPaint);
    canvas.drawCircle(Offset(x + trackW * norm, y + 3.0), 5.5, _thumbPaint);

    _numPainter.paintDouble(
      canvas,
      Offset(x + trackW + 10.0, y - 4.0),
      displayVal,
      fractionDigits: digits,
    );
  }
}
