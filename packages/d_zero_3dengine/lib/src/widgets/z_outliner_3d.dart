import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';
import '../controller.dart';

/// Active Z-prefixed alias for [ZOutliner3D].
typedef ZEntityOutliner3D = ZOutliner3D;

/// Deprecated legacy alias for [ZOutliner3D].
@Deprecated('Use ZOutliner3D instead.')
typedef ZeroOutliner3D = ZOutliner3D;

/// A zero-allocation, zero-rebuild 3D World Outliner & Frame-Time Sparkline HUD.
///
/// Displays live **ECS Entity Count**, **Selected Entity ID**, and a 60-sample
/// lock-free **Frame Time History Graph (`ms`)** directly from C++ shared memory.
class ZOutliner3D extends ZLeafWidget<RenderZOutliner3D> {
  /// Backing 3D engine controller.
  final Zero3DEngineController controller;

  /// Preferred outliner panel size.
  final Size size;

  /// Panel background color.
  final Color backgroundColor;

  /// Primary sparkline and selection accent color.
  final Color accentColor;

  /// Creates a const [ZOutliner3D].
  const ZOutliner3D({
    super.key,
    required this.controller,
    this.size = const Size(240.0, 96.0),
    this.backgroundColor = const Color(0xD8090D16),
    this.accentColor = const Color(0xFFA855F7),
  });

  @override
  RenderZOutliner3D createRenderObject(BuildContext context) {
    return RenderZOutliner3D(
      controller: controller,
      preferredSize: size,
      backgroundColor: backgroundColor,
      accentColor: accentColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZOutliner3D renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..backgroundColor = backgroundColor
      ..accentColor = accentColor;
  }
}

/// Custom [ZeroRenderBox] for [ZOutliner3D].
class RenderZOutliner3D extends ZeroRenderBox {
  static const int _historyLength = 48;

  Zero3DEngineController _controller;
  Size _preferredSize;
  Color _backgroundColor;
  Color _accentColor;

  final Float32List _frameMsHistory = Float32List(_historyLength);
  int _historyCursor = 0;

  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  final Paint _graphPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6;
  final Path _graphPath = Path();

  late ZeroNumberPainter _numPainter;
  final List<TextPainter> _labels = <TextPainter>[];

  static const List<String> _labelStrings = <String>[
    'ECS ENTITIES',
    'SELECTED ID',
    'FRAME TIME (MS)',
  ];

  /// Creates a [RenderZOutliner3D].
  RenderZOutliner3D({
    required Zero3DEngineController controller,
    required Size preferredSize,
    required Color backgroundColor,
    required Color accentColor,
  })  : _controller = controller,
        _preferredSize = preferredSize,
        _backgroundColor = backgroundColor,
        _accentColor = accentColor,
        super(animatePerFrame: true) {
    _bgPaint.color = _backgroundColor;
    _borderPaint.color = _accentColor.withValues(alpha: 0.45);
    _graphPaint.color = _accentColor;
    _initNumberPainter();
    _initLabels();
  }

  void _initNumberPainter() {
    _numPainter = ZeroNumberPainter(
      style: TextStyle(
        color: _accentColor,
        fontSize: 13.0,
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
    for (int i = 0; i < _labelStrings.length; i++) {
      final TextPainter tp = TextPainter(
        text: TextSpan(text: _labelStrings[i], style: style),
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

  /// Preferred outliner panel size.
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

  /// Accent color for sparkline and numbers.
  Color get accentColor => _accentColor;
  set accentColor(Color value) {
    if (_accentColor == value) return;
    _accentColor = value;
    _borderPaint.color = value.withValues(alpha: 0.45);
    _graphPaint.color = value;
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
    if (event is PointerDownEvent) {
      final int count = _controller.spawnedEntityCount;
      if (count > 0) {
        final int nextId = (_controller.selectedEntityId + 1) % count;
        _controller.selectEntity(nextId);
      }
    }
  }

  @override
  bool onFrameTick(Duration elapsed) {
    if (_controller.isDisposed) return false;
    _frameMsHistory[_historyCursor] = _controller.frameTimeMs;
    _historyCursor = (_historyCursor + 1) % _historyLength;
    return true;
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

    final double ox = offset.dx + 12.0;
    final double oy = offset.dy + 8.0;

    _labels[0].paint(canvas, Offset(ox, oy));
    _labels[1].paint(canvas, Offset(ox + 112.0, oy));
    _numPainter.paintInt(
      canvas,
      Offset(ox, oy + 12.0),
      _controller.spawnedEntityCount,
    );
    _numPainter.paintInt(
      canvas,
      Offset(ox + 112.0, oy + 12.0),
      _controller.selectedEntityId >= 0 ? _controller.selectedEntityId : 0,
    );

    _labels[2].paint(canvas, Offset(ox, oy + 38.0));
    _numPainter.paintDouble(
      canvas,
      Offset(ox, oy + 50.0),
      _controller.frameTimeMs,
      fractionDigits: 2,
    );
    _paintFrameTimeGraph(canvas, ox + 78.0, oy + 50.0, size.width - 96.0, 26.0);
  }

  void _paintFrameTimeGraph(
    Canvas canvas,
    double x,
    double y,
    double w,
    double h,
  ) {
    if (w <= 8.0) return;
    _graphPath.reset();
    final double stepX = w / (_historyLength - 1);
    for (int i = 0; i < _historyLength; i++) {
      final int idx = (_historyCursor + i) % _historyLength;
      final double ms = _frameMsHistory[idx].clamp(0.0, 20.0);
      final double px = x + i * stepX;
      final double py = y + h - (ms / 20.0) * h;
      if (i == 0) {
        _graphPath.moveTo(px, py);
      } else {
        _graphPath.lineTo(px, py);
      }
    }
    canvas.drawPath(_graphPath, _graphPaint);
  }
}
