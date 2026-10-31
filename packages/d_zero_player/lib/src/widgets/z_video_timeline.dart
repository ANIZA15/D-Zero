import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active alias for [ZVideoTimeline].
typedef ZThumbnailScrubber = ZVideoTimeline;

/// Legacy alias for [ZVideoTimeline].
@Deprecated('Use ZVideoTimeline instead.')
typedef ZeroVideoTimeline = ZVideoTimeline;

/// Zero-allocation controller for [ZVideoTimeline] storing playhead position,
/// trim `inPoint` / `outPoint`, and frame waveform/luma heights in a `Float32List`.
class ZeroTimelineController extends ChangeNotifier {
  final int _slotCount;
  final int _durationMs;
  late final Float32List _lumaSlots;
  double _playheadRatio = 0.0;
  double _trimStart = 0.1;
  double _trimEnd = 0.9;
  bool _isDisposed = false;

  /// Creates a [ZeroTimelineController] with [slotCount] thumbnail slots.
  ZeroTimelineController({
    int slotCount = 16,
    int durationMs = 60000,
  })  : _slotCount = slotCount.clamp(4, 64),
        _durationMs = math.max(1000, durationMs) {
    _lumaSlots = Float32List(_slotCount);
    for (int i = 0; i < _slotCount; i++) {
      _lumaSlots[i] = 0.35 + 0.55 * math.sin(i * 0.55).abs();
    }
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  @override
  bool get hasListeners => !_isDisposed && super.hasListeners;

  /// Number of thumbnail slots.
  int get slotCount => _slotCount;

  /// Total timeline duration in milliseconds (`0` if disposed).
  int get durationMs => _isDisposed ? 0 : _durationMs;

  /// Current playhead ratio (`0.0 .. 1.0`, or `0.0` if disposed).
  double get playheadRatio => _isDisposed ? 0.0 : _playheadRatio;

  /// Current playhead time in milliseconds (`0` if disposed).
  int get playheadMs =>
      _isDisposed ? 0 : (_playheadRatio * _durationMs).round();

  /// Trim start ratio (`0.0 .. trimEnd`).
  double get trimStart => _isDisposed ? 0.0 : _trimStart;

  /// Trim end ratio (`trimStart .. 1.0`).
  double get trimEnd => _isDisposed ? 0.0 : _trimEnd;

  /// Reads luma bar height (`0.0 .. 1.0`) at [slot].
  double lumaAt(int slot) =>
      (_isDisposed || slot < 0 || slot >= _slotCount) ? 0.0 : _lumaSlots[slot];

  /// Updates the playhead ratio (`0.0 .. 1.0`) in place.
  void setPlayhead(double ratio) {
    if (_isDisposed) return;
    final double clamped = ratio.clamp(0.0, 1.0);
    if (_playheadRatio == clamped) return;
    _playheadRatio = clamped;
    notifyListeners();
  }

  /// Updates the trim `[start, end]` window in place.
  void setTrimRange(double start, double end) {
    if (_isDisposed) return;
    final double s = math.min(start, end).clamp(0.0, 0.95);
    final double e = math.max(start, end).clamp(s + 0.05, 1.0);
    if (_trimStart == s && _trimEnd == e) return;
    _trimStart = s;
    _trimEnd = e;
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    if (_isDisposed) return;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_isDisposed) return;
    super.removeListener(listener);
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _playheadRatio = 0.0;
    _lumaSlots.fillRange(0, _lumaSlots.length, 0.0);
    super.dispose();
  }
}

/// A zero-allocation video editor timeline & thumbnail scrubber widget
/// (CapCut / Reels / Shorts trim & scrub bar).
///
/// Renders frame slots, active trim window handles, playhead needle, and
/// [ZeroNumberPainter.paintTimecode] readout inside a single [ZeroRenderBox].
class ZVideoTimeline extends ZLeafWidget<RenderZVideoTimeline> {
  /// Controller holding playhead and trim state.
  final ZeroTimelineController controller;

  /// Preferred widget size.
  final Size size;

  /// Trim frame highlight color.
  final Color trimColor;

  /// Creates a const [ZVideoTimeline].
  const ZVideoTimeline({
    super.key,
    required this.controller,
    this.size = const Size(280.0, 56.0),
    this.trimColor = const Color(0xFFFFB300),
  });

  @override
  RenderZVideoTimeline createRenderObject(BuildContext context) {
    return RenderZVideoTimeline(
      controller: controller,
      preferredSize: size,
      trimColor: trimColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZVideoTimeline renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..trimColor = trimColor;
  }
}

/// Custom [ZeroRenderBox] for [ZVideoTimeline].
class RenderZVideoTimeline extends ZeroRenderBox {
  ZeroTimelineController _controller;
  Size _preferredSize;

  final Paint _bgPaint = Paint()..color = const Color(0xFF0D131F);
  final Paint _slotPaint = Paint()..color = const Color(0xFF1E293B);
  final Paint _trimBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;
  final Paint _playheadPaint = Paint()
    ..color = const Color(0xFFFF0055)
    ..strokeWidth = 2.5;
  final ZeroNumberPainter _timePainter = ZeroNumberPainter(
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: Color(0xFFFFFFFF),
      fontFamily: 'monospace',
    ),
  );

  /// Creates a [RenderZVideoTimeline].
  RenderZVideoTimeline({
    required ZeroTimelineController controller,
    required Size preferredSize,
    required Color trimColor,
  })  : _controller = controller,
        _preferredSize = preferredSize {
    _trimBorderPaint.color = trimColor;
  }

  /// Timeline controller.
  ZeroTimelineController get controller => _controller;
  set controller(ZeroTimelineController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _controller = value;
    markDirty();
  }

  /// Preferred size.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// Trim border color.
  Color get trimColor => _trimBorderPaint.color;
  set trimColor(Color value) {
    if (_trimBorderPaint.color == value) return;
    _trimBorderPaint.color = value;
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
    _timePainter.dispose();
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if ((event is PointerDownEvent || event is PointerMoveEvent) &&
        size.width > 0) {
      _controller.setPlayhead(event.localPosition.dx / size.width);
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_preferredSize);

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect bounds = offset & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(8.0)),
      _bgPaint,
    );

    const double topBar = 16.0;
    final double trackH = math.max(12.0, size.height - topBar - 4.0);
    final double trackY = offset.dy + topBar;
    final int slots = _controller.slotCount;
    final double slotW = size.width / slots;

    for (int i = 0; i < slots; i++) {
      final double h = trackH * _controller.lumaAt(i);
      final Rect slotRect = Rect.fromLTWH(
        offset.dx + i * slotW + 1.0,
        trackY + (trackH - h) * 0.5,
        math.max(1.0, slotW - 2.0),
        h,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(slotRect, const Radius.circular(3.0)),
        _slotPaint,
      );
    }

    final Rect trimRect = Rect.fromLTWH(
      offset.dx + _controller.trimStart * size.width,
      trackY,
      (_controller.trimEnd - _controller.trimStart) * size.width,
      trackH,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(trimRect, const Radius.circular(4.0)),
      _trimBorderPaint,
    );

    final double playX = offset.dx + _controller.playheadRatio * size.width;
    canvas.drawLine(
      Offset(playX, offset.dy + 2.0),
      Offset(playX, offset.dy + size.height - 2.0),
      _playheadPaint,
    );

    _timePainter.paintTimecode(
      canvas,
      Offset(offset.dx + 6.0, offset.dy + 1.0),
      _controller.playheadMs,
    );
  }
}
