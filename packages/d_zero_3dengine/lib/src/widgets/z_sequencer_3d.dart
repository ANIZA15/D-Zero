import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';
import '../controller.dart';

/// Active Z-prefixed alias for [ZSequencer3D].
typedef ZTimelineSequencer3D = ZSequencer3D;

/// Deprecated legacy alias for [ZSequencer3D].
@Deprecated('Use ZSequencer3D instead.')
typedef ZeroSequencer3D = ZSequencer3D;

/// A zero-allocation, zero-rebuild 3D Keyframe Timeline Sequencer & OBJ Mesh Telemetry Bar.
///
/// Allows interactive scrubbing of the `0.0s .. 30.0s` 3D scene timeline,
/// Play/Pause toggling, and live display of **Built Nanite Meshlets** and **Loaded OBJ Triangles**.
class ZSequencer3D extends ZLeafWidget<RenderZSequencer3D> {
  /// Backing 3D engine controller.
  final Zero3DEngineController controller;

  /// Preferred sequencer bar size.
  final Size size;

  /// Bar background color.
  final Color backgroundColor;

  /// Primary playhead and scrubber accent color.
  final Color accentColor;

  /// Creates a const [ZSequencer3D].
  const ZSequencer3D({
    super.key,
    required this.controller,
    this.size = const Size(520.0, 52.0),
    this.backgroundColor = const Color(0xDF090D16),
    this.accentColor = const Color(0xFF10B981),
  });

  @override
  RenderZSequencer3D createRenderObject(BuildContext context) {
    return RenderZSequencer3D(
      controller: controller,
      preferredSize: size,
      backgroundColor: backgroundColor,
      accentColor: accentColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZSequencer3D renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..backgroundColor = backgroundColor
      ..accentColor = accentColor;
  }
}

/// Custom [ZeroRenderBox] for [ZSequencer3D].
class RenderZSequencer3D extends ZeroRenderBox {
  static const List<String> _labelStrings = <String>[
    'SEQUENCER TIMELINE (30S)',
    'MESHLETS',
    'OBJ TRIS',
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

  /// Creates a [RenderZSequencer3D].
  RenderZSequencer3D({
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
    _fillPaint.color = _accentColor;
    _initNumberPainter();
    _initLabels();
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

  void _initLabels() {
    const TextStyle style = TextStyle(
      color: Color(0xFF94A3B8),
      fontSize: 8.5,
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

  /// Preferred sequencer bar size.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// Bar background color.
  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    _bgPaint.color = value;
    markDirty();
  }

  /// Accent color for timeline bar and readouts.
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
    if (event is PointerDownEvent && event.localPosition.dx < 36.0) {
      _controller.setSequencerState(playing: !_controller.isSequencerPlaying);
      return;
    }
    if (event is PointerDownEvent && event.localPosition.dx > size.width - 130.0) {
      _controller.loadBuiltinObjPreset(presetId: 1);
      return;
    }
    if (event is PointerDownEvent || event is PointerMoveEvent) {
      final double trackW = size.width - 210.0;
      if (trackW <= 20.0) return;
      final double norm = ((event.localPosition.dx - 42.0) / trackW).clamp(0.0, 1.0);
      _controller.setSequencerState(timeSec: norm * 30.0);
    }
  }

  @override
  bool onFrameTick(Duration elapsed) => !_controller.isDisposed;

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

    // Play/Pause indicator circle
    final double cx = offset.dx + 20.0;
    final double cy = offset.dy + size.height * 0.5;
    canvas.drawCircle(
      Offset(cx, cy),
      8.0,
      _controller.isSequencerPlaying ? _fillPaint : _trackPaint,
    );

    final double sx = offset.dx + 42.0;
    final double sy = offset.dy + 9.0;
    final double trackW = (size.width - 220.0).clamp(24.0, 2000.0);
    final double norm = (_controller.sequencerTimeSec / 30.0).clamp(0.0, 1.0);

    _labels[0].paint(canvas, Offset(sx, sy));
    final double barY = sy + 18.0;
    canvas.drawRect(Rect.fromLTWH(sx, barY, trackW, 6.0), _trackPaint);
    canvas.drawRect(Rect.fromLTWH(sx, barY, trackW * norm, 6.0), _fillPaint);
    canvas.drawCircle(Offset(sx + trackW * norm, barY + 3.0), 5.0, _thumbPaint);

    _numPainter.paintDouble(
      canvas,
      Offset(sx + trackW + 10.0, barY - 4.0),
      _controller.sequencerTimeSec,
      fractionDigits: 1,
    );

    final double statX = sx + trackW + 58.0;
    _labels[1].paint(canvas, Offset(statX, sy));
    _numPainter.paintInt(
      canvas,
      Offset(statX, sy + 13.0),
      _controller.builtMeshletCount,
    );
    _labels[2].paint(canvas, Offset(statX + 62.0, sy));
    _numPainter.paintInt(
      canvas,
      Offset(statX + 62.0, sy + 13.0),
      _controller.loadedObjTriangles,
    );
  }
}
