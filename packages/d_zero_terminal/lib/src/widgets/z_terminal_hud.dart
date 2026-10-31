import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';
import '../controller.dart';
import '../terminal_state_ffi.dart';

/// Active Z-prefixed alias for [ZTerminalHud].
typedef ZTerminalTelemetryBar = ZTerminalHud;

/// Deprecated legacy alias for [ZTerminalHud].
@Deprecated('Use ZTerminalHud instead.')
typedef ZeroTerminalHud = ZTerminalHud;

/// Zero-allocation, zero-rebuild FFI Terminal Telemetry HUD widget.
///
/// Directly reads the 128-byte FFI shared memory (`ZeroTerminalState`) and paints
/// live **Throughput (MB/s)**, **Parse Latency (ns/byte)**, **Bytes Processed**,
/// **Escape Sequences Parsed**, **Grid Size (`cols × rows`)**, and **Cursor (`row:col`)**
/// using pre-allocated [ZeroNumberPainter] glyph atlases with 0 `String` allocations.
class ZTerminalHud extends ZLeafWidget<RenderZTerminalHud> {
  /// Backing FFI PTY terminal controller.
  final ZeroPtyController controller;

  /// Preferred HUD box size.
  final Size size;

  /// HUD surface fill color.
  final Color backgroundColor;

  /// Primary metric accent color.
  final Color accentColor;

  /// Creates a const [ZTerminalHud].
  const ZTerminalHud({
    super.key,
    required this.controller,
    this.size = const Size(280.0, 112.0),
    this.backgroundColor = const Color(0xD8090D16),
    this.accentColor = const Color(0xFF39C5BB),
  });

  @override
  RenderZTerminalHud createRenderObject(BuildContext context) {
    return RenderZTerminalHud(
      controller: controller,
      preferredSize: size,
      backgroundColor: backgroundColor,
      accentColor: accentColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZTerminalHud renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..backgroundColor = backgroundColor
      ..accentColor = accentColor;
  }
}

/// Custom [ZeroRenderBox] for [ZTerminalHud].
class RenderZTerminalHud extends ZeroRenderBox {
  ZeroPtyController _controller;
  Size _preferredSize;
  Color _backgroundColor;
  Color _accentColor;

  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  final Paint _statusDotPaint = Paint()..style = PaintingStyle.fill;

  late ZeroNumberPainter _primaryPainter;
  late ZeroNumberPainter _statPainter;
  final List<TextPainter> _labels = <TextPainter>[];

  static const List<String> _labelStrings = <String>[
    'THROUGHPUT (MB/S)',
    'PARSE (NS/B)',
    'BYTES PARSED',
    'ANSI SEQS',
    'GRID COLS',
    'CURSOR ROW',
  ];

  /// Creates a [RenderZTerminalHud].
  RenderZTerminalHud({
    required ZeroPtyController controller,
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
    _initNumberPainters();
    _initStaticLabels();
  }

  void _initStaticLabels() {
    const TextStyle labelStyle = TextStyle(
      color: Color(0xFF8B949E),
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

  void _initNumberPainters() {
    _primaryPainter = ZeroNumberPainter(
      style: TextStyle(
        color: _accentColor,
        fontSize: 15.0,
        fontWeight: FontWeight.w700,
      ),
    );
    _statPainter = ZeroNumberPainter(
      style: const TextStyle(
        color: Color(0xFFE6EDF3),
        fontSize: 12.0,
        fontWeight: FontWeight.w600,
      ),
    );
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

  /// Accent color for primary metrics and border.
  Color get accentColor => _accentColor;
  set accentColor(Color value) {
    if (_accentColor == value) return;
    _accentColor = value;
    _borderPaint.color = value.withValues(alpha: 0.45);
    _primaryPainter.dispose();
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
    _primaryPainter.dispose();
    _statPainter.dispose();
    for (int i = 0; i < _labels.length; i++) {
      _labels[i].dispose();
    }
    _labels.clear();
    super.dispose();
  }

  @override
  bool onFrameTick(Duration elapsed) => _controller.pollNativeUpdates();

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

    if (!_controller.isNativeValid) return;

    final double ox = offset.dx + 12.0;
    final double oy = offset.dy + 8.0;
    final double col2 = ox + 132.0;

    // Row 1: Throughput MB/s & Parse Latency ns/byte
    _labels[0].paint(canvas, Offset(ox, oy));
    _labels[1].paint(canvas, Offset(col2, oy));
    _primaryPainter.paintDouble(
      canvas,
      Offset(ox, oy + 11.0),
      _controller.throughputMbPerSec,
      fractionDigits: 1,
    );
    _statPainter.paintDouble(
      canvas,
      Offset(col2, oy + 13.0),
      _controller.parseLatencyNs,
      fractionDigits: 1,
    );

    // Row 2: Bytes Processed & ANSI Escape Sequences Parsed
    _labels[2].paint(canvas, Offset(ox, oy + 36.0));
    _labels[3].paint(canvas, Offset(col2, oy + 36.0));
    _statPainter.paintInt(
      canvas,
      Offset(ox, oy + 48.0),
      _controller.bytesProcessed,
    );
    _statPainter.paintInt(
      canvas,
      Offset(col2, oy + 48.0),
      _controller.escapeSeqsParsed,
    );

    // Row 3: Grid Cols & Cursor Row + Status LED
    _labels[4].paint(canvas, Offset(ox, oy + 70.0));
    _labels[5].paint(canvas, Offset(col2, oy + 70.0));
    _statPainter.paintInt(
      canvas,
      Offset(ox, oy + 82.0),
      _controller.cols,
    );
    _statPainter.paintInt(
      canvas,
      Offset(col2, oy + 82.0),
      _controller.cursorRow,
    );

    _paintStatusLed(canvas, offset.dx + size.width - 14.0, oy + 6.0);
  }

  void _paintStatusLed(Canvas canvas, double cx, double cy) {
    final status = _controller.status;
    if (status == ZeroTerminalStatus.ptyRunning) {
      _statusDotPaint.color = const Color(0xFF4ECDC4);
    } else if (status == ZeroTerminalStatus.streamOnly) {
      _statusDotPaint.color = const Color(0xFF58A6FF);
    } else if (status == ZeroTerminalStatus.error) {
      _statusDotPaint.color = const Color(0xFFFF6B6B);
    } else {
      _statusDotPaint.color = const Color(0xFF6E7681);
    }
    canvas.drawCircle(Offset(cx, cy), 4.0, _statusDotPaint);
  }
}
