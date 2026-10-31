import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';
import '../controller.dart';

/// Active Z-prefixed alias for [ZEngineTelemetryHud].
typedef Z3DStatsOverlay = ZEngineTelemetryHud;

/// Deprecated legacy alias for [ZEngineTelemetryHud].
@Deprecated('Use ZEngineTelemetryHud instead.')
typedef ZeroEngineTelemetryHud = ZEngineTelemetryHud;

/// A zero-allocation, zero-rebuild 3D Engine Telemetry HUD widget.
///
/// Directly reads the 128-byte FFI shared memory (`Zero3DEngineState`) on every frame
/// and paints live **Render FPS**, **Monitor Refresh Rate (60/120/144/240Hz)**,
/// **Active Nanite Clusters**, and **Hardware Rays Traced (K)** using pre-allocated
/// [ZeroNumberPainter] glyph atlases with 0 `String` allocations.
class ZEngineTelemetryHud extends ZLeafWidget<RenderZEngineTelemetryHud> {
  /// Backing 3D engine controller.
  final Zero3DEngineController controller;

  /// Preferred HUD box size.
  final Size size;

  /// HUD background fill color.
  final Color backgroundColor;

  /// Primary metric readout color.
  final Color accentColor;

  /// Creates a const [ZEngineTelemetryHud].
  const ZEngineTelemetryHud({
    super.key,
    required this.controller,
    this.size = const Size(240.0, 88.0),
    this.backgroundColor = const Color(0xCC090D16),
    this.accentColor = const Color(0xFF00F5D4),
  });

  @override
  RenderZEngineTelemetryHud createRenderObject(BuildContext context) {
    return RenderZEngineTelemetryHud(
      controller: controller,
      preferredSize: size,
      backgroundColor: backgroundColor,
      accentColor: accentColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZEngineTelemetryHud renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..backgroundColor = backgroundColor
      ..accentColor = accentColor;
  }
}

/// Custom [ZeroRenderBox] for [ZEngineTelemetryHud].
class RenderZEngineTelemetryHud extends ZeroRenderBox {
  Zero3DEngineController _controller;
  Size _preferredSize;
  Color _backgroundColor;
  Color _accentColor;

  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  final Paint _barTrackPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = const Color(0xFF1E293B);
  final Paint _barFillPaint = Paint()..style = PaintingStyle.fill;

  late ZeroNumberPainter _fpsPainter;
  late ZeroNumberPainter _statPainter;

  /// Creates a [RenderZEngineTelemetryHud].
  RenderZEngineTelemetryHud({
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
    _barFillPaint.color = _accentColor;
    _initNumberPainters();
  }

  void _initNumberPainters() {
    _fpsPainter = ZeroNumberPainter(
      style: TextStyle(
        color: _accentColor,
        fontSize: 15.0,
        fontWeight: FontWeight.w700,
      ),
    );
    _statPainter = ZeroNumberPainter(
      style: const TextStyle(
        color: Color(0xFFE2E8F0),
        fontSize: 12.0,
        fontWeight: FontWeight.w600,
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

  /// Preferred HUD box size.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// HUD background color.
  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    _bgPaint.color = value;
    markDirty();
  }

  /// Accent color for FPS and bars.
  Color get accentColor => _accentColor;
  set accentColor(Color value) {
    if (_accentColor == value) return;
    _accentColor = value;
    _borderPaint.color = value.withValues(alpha: 0.45);
    _barFillPaint.color = value;
    _fpsPainter.dispose();
    _statPainter.dispose();
    _initNumberPainters();
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
    _fpsPainter.dispose();
    _statPainter.dispose();
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
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final RRect panel = RRect.fromRectAndRadius(
      offset & size,
      const Radius.circular(8.0),
    );
    canvas.drawRRect(panel, _bgPaint);
    canvas.drawRRect(panel, _borderPaint);

    if (_controller.isDisposed) return;

    final double ox = offset.dx + 10.0;
    final double oy = offset.dy + 8.0;

    // Row 1: Render FPS & Display Refresh Hz (e.g. 144.0 / 240.0)
    _fpsPainter.paintDouble(
      canvas,
      Offset(ox, oy),
      _controller.renderFps,
      fractionDigits: 1,
    );
    _statPainter.paintInt(
      canvas,
      Offset(ox + 92.0, oy + 2.0),
      _controller.displayRefreshHz.round(),
    );

    // Row 2: Active Nanite Clusters & Visible Triangles
    _statPainter.paintInt(
      canvas,
      Offset(ox, oy + 26.0),
      _controller.activeClusters,
    );
    _statPainter.paintInt(
      canvas,
      Offset(ox + 92.0, oy + 26.0),
      _controller.visibleTriangles,
    );

    // Row 3: Rays Traced (K) & Culling Efficiency Bar
    _statPainter.paintInt(
      canvas,
      Offset(ox, oy + 48.0),
      _controller.raysTracedK,
    );
    _paintCullingRatioBar(canvas, ox + 92.0, oy + 53.0, size.width - 112.0);
  }

  void _paintCullingRatioBar(
    Canvas canvas,
    double x,
    double y,
    double maxWidth,
  ) {
    if (maxWidth <= 4.0) return;
    final int active = _controller.activeClusters;
    final int culled = _controller.culledClusters;
    final int total = active + culled;
    final double ratio = total > 0 ? (active / total).clamp(0.0, 1.0) : 0.0;

    final Rect track = Rect.fromLTWH(x, y, maxWidth, 6.0);
    final Rect fill = Rect.fromLTWH(x, y, maxWidth * ratio, 6.0);
    canvas.drawRect(track, _barTrackPaint);
    canvas.drawRect(fill, _barFillPaint);
  }
}
