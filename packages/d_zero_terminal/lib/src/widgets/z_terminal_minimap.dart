import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';
import '../controller.dart';
import '../terminal_state_ffi.dart';

/// Active Z-prefixed alias for [ZTerminalMinimap].
typedef ZScrollbackRadar = ZTerminalMinimap;

/// Deprecated legacy alias for [ZTerminalMinimap].
@Deprecated('Use ZTerminalMinimap instead.')
typedef ZeroTerminalMinimap = ZTerminalMinimap;

/// Zero-allocation scrollback minimap & radar scrollbar for [ZPtyTerminal].
///
/// Reads the 256-bin C++ `minimapColors` and `minimapFill` zero-copy arrays directly
/// and supports drag-to-scrub through the terminal scrollback ring buffer.
class ZTerminalMinimap extends ZLeafWidget<RenderZTerminalMinimap> {
  /// Backing FFI PTY terminal controller.
  final ZeroPtyController controller;

  /// Minimap strip width in logical pixels.
  final double width;

  /// Background track color.
  final Color backgroundColor;

  /// Active viewport lens highlight color.
  final Color viewportThumbColor;

  /// Creates a const [ZTerminalMinimap].
  const ZTerminalMinimap({
    super.key,
    required this.controller,
    this.width = 44.0,
    this.backgroundColor = const Color(0xFF090D14),
    this.viewportThumbColor = const Color(0x4458A6FF),
  });

  @override
  RenderZTerminalMinimap createRenderObject(BuildContext context) {
    return RenderZTerminalMinimap(
      controller: controller,
      stripWidth: width,
      backgroundColor: backgroundColor,
      viewportThumbColor: viewportThumbColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZTerminalMinimap renderObject,
  ) {
    renderObject
      ..controller = controller
      ..stripWidth = width
      ..backgroundColor = backgroundColor
      ..viewportThumbColor = viewportThumbColor;
  }
}

/// Custom [ZeroRenderBox] for [ZTerminalMinimap].
class RenderZTerminalMinimap extends ZeroRenderBox {
  ZeroPtyController _controller;
  double _stripWidth;
  Color _backgroundColor;
  Color _viewportThumbColor;

  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _barPaint = Paint()..style = PaintingStyle.fill;
  final Paint _thumbFillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _thumbBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  /// Creates a [RenderZTerminalMinimap].
  RenderZTerminalMinimap({
    required ZeroPtyController controller,
    required double stripWidth,
    required Color backgroundColor,
    required Color viewportThumbColor,
  })  : _controller = controller,
        _stripWidth = stripWidth,
        _backgroundColor = backgroundColor,
        _viewportThumbColor = viewportThumbColor,
        super(animatePerFrame: false) {
    _bgPaint.color = _backgroundColor;
    _thumbFillPaint.color = _viewportThumbColor;
    _thumbBorderPaint.color = _viewportThumbColor.withValues(alpha: 0.85);
  }

  /// Backing terminal controller.
  ZeroPtyController get controller => _controller;
  set controller(ZeroPtyController value) {
    if (identical(_controller, value)) return;
    if (attached) _controller.removeListener(markDirty);
    _controller = value;
    if (attached) _controller.addListener(markDirty);
    markDirty();
  }

  /// Minimap strip width in logical pixels.
  double get stripWidth => _stripWidth;
  set stripWidth(double value) {
    if (_stripWidth == value) return;
    _stripWidth = value;
    markNeedsLayout();
  }

  /// Background track color.
  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    _bgPaint.color = value;
    markDirty();
  }

  /// Active viewport lens highlight color.
  Color get viewportThumbColor => _viewportThumbColor;
  set viewportThumbColor(Color value) {
    if (_viewportThumbColor == value) return;
    _viewportThumbColor = value;
    _thumbFillPaint.color = value;
    _thumbBorderPaint.color = value.withValues(alpha: 0.85);
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
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent || event is PointerMoveEvent) {
      _scrubToY(event.localPosition.dy);
    }
  }

  void _scrubToY(double localY) {
    if (!_controller.isNativeValid || size.height <= 0) return;
    final int total = _controller.totalLines;
    final int rows = _controller.rows;
    final int maxScroll = math.max(0, total - rows);
    if (maxScroll == 0) return;
    final double norm = (localY / size.height).clamp(0.0, 1.0);
    final int targetOffset = ((1.0 - norm) * maxScroll).round();
    _controller.setScrollOffset(targetOffset);
  }

  @override
  void performLayout() {
    final double h =
        constraints.hasBoundedHeight ? constraints.maxHeight : 320.0;
    size = constraints.constrain(Size(_stripWidth, h));
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final RRect track = RRect.fromRectAndRadius(
      offset & size,
      const Radius.circular(6.0),
    );
    canvas.drawRRect(track, _bgPaint);

    if (!_controller.isNativeValid) return;
    _paintDensityBins(canvas, offset);
    _paintViewportLens(canvas, offset);
  }

  void _paintDensityBins(Canvas canvas, Offset offset) {
    final Uint32List colors = _controller.minimapColors;
    final Uint8List fills = _controller.minimapFill;
    if (colors.isEmpty || fills.isEmpty) return;

    const int step = 2;
    const int binCount = ZeroTerminalStateView.minimapBinCount;
    final double availW = math.max(4.0, size.width - 8.0);
    final double binH = size.height / (binCount / step);

    for (int i = 0; i < binCount; i += step) {
      final int fill = fills[i];
      if (fill <= 0) continue;
      final double barW = (fill / 255.0) * availW;
      final double y = offset.dy + (i / binCount) * size.height;
      _barPaint.color = Color(colors[i]).withValues(alpha: 0.72);
      canvas.drawRect(
        Rect.fromLTWH(offset.dx + 4.0, y, barW, math.max(1.2, binH - 0.5)),
        _barPaint,
      );
    }
  }

  void _paintViewportLens(Canvas canvas, Offset offset) {
    final int total = math.max(1, _controller.totalLines);
    final int rows = math.max(1, _controller.rows);
    final int scrollOff = _controller.scrollOffset;

    final double lensRatio = (rows / total).clamp(0.08, 1.0);
    final double lensH = size.height * lensRatio;
    final int maxScroll = math.max(1, total - rows);
    final double scrollFrac =
        total > rows ? (scrollOff / maxScroll).clamp(0.0, 1.0) : 0.0;
    final double lensY =
        offset.dy + (1.0 - scrollFrac) * (size.height - lensH);

    final RRect lensRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(offset.dx + 1.0, lensY, size.width - 2.0, lensH),
      const Radius.circular(4.0),
    );
    canvas.drawRRect(lensRect, _thumbFillPaint);
    canvas.drawRRect(lensRect, _thumbBorderPaint);
  }
}
