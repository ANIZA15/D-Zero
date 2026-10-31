import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';
import '../controller.dart';

/// Active Z-prefixed alias for [ZTransformGizmo3D].
typedef Z3DGizmoOverlay = ZTransformGizmo3D;

/// Deprecated legacy alias for [ZTransformGizmo3D].
@Deprecated('Use ZTransformGizmo3D instead.')
typedef ZeroTransformGizmo3D = ZTransformGizmo3D;

/// A zero-allocation, zero-rebuild 3D Entity Transform Gizmo & Axis Controller widget.
///
/// Allows real-time manipulation of the selected C++ `Zero3DEcsWorld` entity's
/// **Position X (Red)**, **Position Y (Green)**, **Position Z (Blue)**, and
/// **Uniform Scale (Amber)** with 0 heap allocations and 0 widget rebuilds.
class ZTransformGizmo3D extends ZLeafWidget<RenderZTransformGizmo3D> {
  /// Backing 3D engine controller.
  final Zero3DEngineController controller;

  /// Preferred gizmo panel size.
  final Size size;

  /// Panel background color.
  final Color backgroundColor;

  /// Creates a const [ZTransformGizmo3D].
  const ZTransformGizmo3D({
    super.key,
    required this.controller,
    this.size = const Size(268.0, 178.0),
    this.backgroundColor = const Color(0xD8090D16),
  });

  @override
  RenderZTransformGizmo3D createRenderObject(BuildContext context) {
    return RenderZTransformGizmo3D(
      controller: controller,
      preferredSize: size,
      backgroundColor: backgroundColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZTransformGizmo3D renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..backgroundColor = backgroundColor;
  }
}

/// Custom [ZeroRenderBox] for [ZTransformGizmo3D].
class RenderZTransformGizmo3D extends ZeroRenderBox {
  static const List<Color> _axisColors = <Color>[
    Color(0xFFEF4444), // X Axis (Red)
    Color(0xFF22C55E), // Y Axis (Green)
    Color(0xFF3B82F6), // Z Axis (Blue)
    Color(0xFFF59E0B), // Uniform Scale (Amber)
  ];

  static const List<String> _axisLabels = <String>[
    'TRANSLATE X (M)',
    'TRANSLATE Y (M)',
    'TRANSLATE Z (M)',
    'ENTITY SCALE',
  ];

  Zero3DEngineController _controller;
  Size _preferredSize;
  Color _backgroundColor;

  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..color = const Color(0x6638BDF8);
  final Paint _trackPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = const Color(0xFF1E293B);
  final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _thumbPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = const Color(0xFFF8FAFC);

  late ZeroNumberPainter _numPainter;
  final List<TextPainter> _labels = <TextPainter>[];

  /// Creates a [RenderZTransformGizmo3D].
  RenderZTransformGizmo3D({
    required Zero3DEngineController controller,
    required Size preferredSize,
    required Color backgroundColor,
  })  : _controller = controller,
        _preferredSize = preferredSize,
        _backgroundColor = backgroundColor {
    _bgPaint.color = _backgroundColor;
    _numPainter = ZeroNumberPainter(
      style: const TextStyle(
        color: Color(0xFFE2E8F0),
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
    );
    _initLabels();
  }

  void _initLabels() {
    for (int i = 0; i < _axisLabels.length; i++) {
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: _axisLabels[i],
          style: TextStyle(
            color: _axisColors[i],
            fontSize: 9.0,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
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

  /// Preferred gizmo panel size.
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
      _applyAxisDrag(event.localPosition);
    }
  }

  int _activeEntityId() {
    final int sel = _controller.selectedEntityId;
    return sel >= 0 ? sel : 0;
  }

  void _applyAxisDrag(Offset localPos) {
    final double trackW = size.width - 80.0;
    if (trackW <= 10.0) return;
    final double t = ((localPos.dx - 12.0) / trackW).clamp(0.0, 1.0);
    final int id = _activeEntityId();
    final int row = ((localPos.dy / size.height) * 4.0).floor().clamp(0, 3);

    if (row == 0) {
      _controller.setEntityTransform(entityId: id, x: -2.0 + t * 4.0);
    } else if (row == 1) {
      _controller.setEntityTransform(entityId: id, y: -0.6 + t * 2.2);
    } else if (row == 2) {
      _controller.setEntityTransform(entityId: id, z: -2.0 + t * 4.0);
    } else {
      _controller.setEntityTransform(entityId: id, scale: 0.3 + t * 2.2);
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

    final int id = _activeEntityId();
    final double ex = _controller.getEntityX(id);
    final double ey = _controller.getEntityY(id);
    final double ez = _controller.getEntityZ(id);
    final double es = _controller.getEntityScale(id);

    _paintRow(canvas, offset, 0, (ex + 2.0) / 4.0, ex);
    _paintRow(canvas, offset, 1, (ey + 0.6) / 2.2, ey);
    _paintRow(canvas, offset, 2, (ez + 2.0) / 4.0, ez);
    _paintRow(canvas, offset, 3, (es - 0.3) / 2.2, es);
  }

  void _paintRow(
    Canvas canvas,
    Offset offset,
    int row,
    double rawNorm,
    double val,
  ) {
    final double x = offset.dx + 12.0;
    final double y = offset.dy + 10.0 + row * 41.0;
    final double trackW = size.width - 80.0;
    final double norm = rawNorm.clamp(0.0, 1.0);

    _labels[row].paint(canvas, Offset(x, y));
    final double barY = y + 17.0;
    _fillPaint.color = _axisColors[row];
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
