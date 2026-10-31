import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';
import '../controller.dart';

/// Active Z-prefixed alias for [ZPostProcess3D].
typedef ZPostProcessPanel3D = ZPostProcess3D;

/// Deprecated legacy alias for [ZPostProcess3D].
@Deprecated('Use ZPostProcess3D instead.')
typedef ZeroPostProcess3D = ZPostProcess3D;

/// A zero-allocation, zero-rebuild Volumetric Atmosphere & ACES Post-Process Editor widget.
///
/// Controls:
/// 1. **Volumetric Fog & Mie Sun Scattering (`0.00 .. 1.00`)**
/// 2. **Academy ACES Filmic Exposure EV (`0.20 .. 4.00`)**
/// 3. **Specular Bloom Glow Intensity (`0.00 .. 2.00`)**
class ZPostProcess3D extends ZLeafWidget<RenderZPostProcess3D> {
  /// Backing 3D engine controller.
  final Zero3DEngineController controller;

  /// Preferred panel size.
  final Size size;

  /// Panel background color.
  final Color backgroundColor;

  /// Primary slider & readout accent color.
  final Color accentColor;

  /// Creates a const [ZPostProcess3D].
  const ZPostProcess3D({
    super.key,
    required this.controller,
    this.size = const Size(240.0, 140.0),
    this.backgroundColor = const Color(0xD8090D16),
    this.accentColor = const Color(0xFFFBBF24),
  });

  @override
  RenderZPostProcess3D createRenderObject(BuildContext context) {
    return RenderZPostProcess3D(
      controller: controller,
      preferredSize: size,
      backgroundColor: backgroundColor,
      accentColor: accentColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZPostProcess3D renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..backgroundColor = backgroundColor
      ..accentColor = accentColor;
  }
}

/// Custom [ZeroRenderBox] for [ZPostProcess3D].
class RenderZPostProcess3D extends ZeroRenderBox {
  static const List<String> _rowLabels = <String>[
    'VOLUMETRIC FOG',
    'ACES EXPOSURE (EV)',
    'SPECULAR BLOOM',
  ];

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

  /// Creates a [RenderZPostProcess3D].
  RenderZPostProcess3D({
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
    _initLabels();
  }

  void _initNumberPainter() {
    _numPainter = ZeroNumberPainter(
      style: TextStyle(
        color: _accentColor,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  void _initLabels() {
    const TextStyle style = TextStyle(
      color: Color(0xFF94A3B8),
      fontSize: 9.0,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
    );
    for (int i = 0; i < _rowLabels.length; i++) {
      final TextPainter tp = TextPainter(
        text: TextSpan(text: _rowLabels[i], style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      _labels.add(tp);
    }
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

  /// Preferred panel size.
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

  /// Accent color for slider tracks and readouts.
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
      _applyPointerDrag(event.localPosition);
    }
  }

  void _applyPointerDrag(Offset localPos) {
    final double trackW = size.width - 78.0;
    if (trackW <= 10.0) return;
    final double t = ((localPos.dx - 12.0) / trackW).clamp(0.0, 1.0);
    final int row = ((localPos.dy / size.height) * 3.0).floor().clamp(0, 2);

    if (row == 0) {
      _controller.setPostProcess(fogDensity: t);
    } else if (row == 1) {
      _controller.setPostProcess(exposureEv: 0.2 + t * 3.8);
    } else {
      _controller.setPostProcess(bloomIntensity: t * 2.0);
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

    final double fog = _controller.fogDensity;
    final double expEv = _controller.exposureEv;
    final double bloom = _controller.bloomIntensity;

    _paintRow(canvas, offset, 0, fog, fog);
    _paintRow(canvas, offset, 1, (expEv - 0.2) / 3.8, expEv);
    _paintRow(canvas, offset, 2, bloom / 2.0, bloom);
  }

  void _paintRow(
    Canvas canvas,
    Offset offset,
    int row,
    double rawNorm,
    double val,
  ) {
    final double x = offset.dx + 12.0;
    final double y = offset.dy + 10.0 + row * 42.0;
    final double trackW = size.width - 78.0;
    final double norm = rawNorm.clamp(0.0, 1.0);

    _labels[row].paint(canvas, Offset(x, y));
    final double barY = y + 17.0;
    canvas.drawRect(Rect.fromLTWH(x, barY, trackW, 6.0), _trackPaint);
    canvas.drawRect(Rect.fromLTWH(x, barY, trackW * norm, 6.0), _fillPaint);
    canvas.drawCircle(Offset(x + trackW * norm, barY + 3.0), 5.0, _thumbPaint);

    _numPainter.paintDouble(
      canvas,
      Offset(x + trackW + 10.0, barY - 4.0),
      val,
      fractionDigits: 2,
    );
  }
}
