import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';
import '../controller.dart';

/// Active Z-prefixed alias for [ZMaterialEditor3D].
typedef ZPbrMaterialPanel = ZMaterialEditor3D;

/// Deprecated legacy alias for [ZMaterialEditor3D].
@Deprecated('Use ZMaterialEditor3D instead.')
typedef ZeroMaterialEditor3D = ZMaterialEditor3D;

/// A zero-allocation, zero-rebuild Cook-Torrance GGX PBR Material & Physics Editor widget.
///
/// Provides interactive sliders for:
/// 1. **PBR Metallic (`0.00 .. 1.00`)**
/// 2. **PBR Roughness (`0.04 .. 1.00`)**
/// 3. **PBR Emissive Intensity (`0.00 .. 5.00`)**
/// 4. **C++ Rigid-Body Physics Toggle & Impulse Trigger (`0 / 1`)**
class ZMaterialEditor3D extends ZLeafWidget<RenderZMaterialEditor3D> {
  /// Backing 3D engine controller.
  final Zero3DEngineController controller;

  /// Preferred editor panel size.
  final Size size;

  /// Panel background color.
  final Color backgroundColor;

  /// Primary slider & readout accent color.
  final Color accentColor;

  /// Creates a const [ZMaterialEditor3D].
  const ZMaterialEditor3D({
    super.key,
    required this.controller,
    this.size = const Size(268.0, 178.0),
    this.backgroundColor = const Color(0xD8090D16),
    this.accentColor = const Color(0xFFF43F5E),
  });

  @override
  RenderZMaterialEditor3D createRenderObject(BuildContext context) {
    return RenderZMaterialEditor3D(
      controller: controller,
      preferredSize: size,
      backgroundColor: backgroundColor,
      accentColor: accentColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZMaterialEditor3D renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..backgroundColor = backgroundColor
      ..accentColor = accentColor;
  }
}

/// Custom [ZeroRenderBox] for [ZMaterialEditor3D].
class RenderZMaterialEditor3D extends ZeroRenderBox {
  static const List<String> _rowLabels = <String>[
    'PBR METALLIC (GGX)',
    'PBR ROUGHNESS (GGX)',
    'PBR EMISSIVE GLOW',
    'C++ PHYSICS & IMPULSE',
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

  /// Creates a [RenderZMaterialEditor3D].
  RenderZMaterialEditor3D({
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

  /// Preferred editor panel size.
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
      _applyPointerDrag(event.localPosition, event is PointerDownEvent);
    }
  }

  void _applyPointerDrag(Offset localPos, bool isTapDown) {
    final double trackW = size.width - 80.0;
    if (trackW <= 10.0) return;
    final double t = ((localPos.dx - 12.0) / trackW).clamp(0.0, 1.0);
    final int row = ((localPos.dy / size.height) * 4.0).floor().clamp(0, 3);

    if (row == 0) {
      _controller.setPbrMaterial(metallic: t);
    } else if (row == 1) {
      _controller.setPbrMaterial(roughness: 0.04 + t * 0.96);
    } else if (row == 2) {
      _controller.setPbrMaterial(emissive: t * 5.0);
    } else if (isTapDown) {
      final bool next = !_controller.isPhysicsEnabled;
      _controller.setPhysicsEnabled(next);
      if (next) _controller.applyEntityImpulse(vy: 5.5);
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

    final double m = _controller.pbrMetallic;
    final double r = _controller.pbrRoughness;
    final double e = _controller.pbrEmissive;
    final double phys = _controller.isPhysicsEnabled ? 1.0 : 0.0;

    _paintRow(canvas, offset, 0, m, m, 2);
    _paintRow(canvas, offset, 1, (r - 0.04) / 0.96, r, 2);
    _paintRow(canvas, offset, 2, e / 5.0, e, 2);
    _paintRow(canvas, offset, 3, phys, phys, 0);
  }

  void _paintRow(
    Canvas canvas,
    Offset offset,
    int row,
    double rawNorm,
    double val,
    int digits,
  ) {
    final double x = offset.dx + 12.0;
    final double y = offset.dy + 10.0 + row * 41.0;
    final double trackW = size.width - 80.0;
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
      fractionDigits: digits,
    );
  }
}
