import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';

/// Active Z-prefixed alias for [ZBarcodeScanner].
typedef ZCameraPreview = ZBarcodeScanner;

/// Deprecated legacy alias for [ZBarcodeScanner].
@Deprecated('Use ZBarcodeScanner instead.')
typedef ZeroBarcodeScanner = ZBarcodeScanner;

/// Fixed-capacity Structure-of-Arrays (SoA) controller for barcode / object detections.
///
/// Stores up to [capacity] detections in a flat [Float32List] of
/// `[left, top, right, bottom, confidence]` (5 floats per slot) with zero heap
/// allocations per update.
class ZeroDetectionController {
  static const int _floatsPerBox = 5;

  /// Maximum number of concurrent detection boxes.
  final int capacity;

  /// Flat SoA buffer storing `[left, top, right, bottom, confidence]` per slot.
  final Float32List boxes;
  final Uint8List _active;
  final ZeroIntNotifier _revision = ZeroIntNotifier(0);

  int _activeCount = 0;
  bool _isDisposed = false;

  /// Creates a [ZeroDetectionController] with fixed [capacity] (default 16).
  ZeroDetectionController({this.capacity = 16})
      : assert(capacity > 0),
        boxes = Float32List(capacity * _floatsPerBox),
        _active = Uint8List(capacity);

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Number of currently active detection bounding boxes.
  int get activeCount => _isDisposed ? 0 : _activeCount;

  /// Registers a listener notified when detections change.
  void addListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.addListener(listener);
  }

  /// Removes a previously registered listener.
  void removeListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.removeListener(listener);
  }

  /// Sets or updates the detection bounding box at [index] (`0..<capacity`).
  ///
  /// Coordinates ([l], [t], [r], [b]) are in local viewport pixels, and
  /// [confidence] is in `0.0..1.0` (or `0.0..100.0`).
  void setDetection(
    int index,
    double l,
    double t,
    double r,
    double b,
    double confidence,
  ) {
    if (_isDisposed || index < 0 || index >= capacity) return;
    if (_active[index] == 0) {
      _active[index] = 1;
      _activeCount++;
    }
    final int base = index * _floatsPerBox;
    boxes[base] = l;
    boxes[base + 1] = t;
    boxes[base + 2] = r;
    boxes[base + 3] = b;
    boxes[base + 4] = confidence <= 1.0 ? confidence * 100.0 : confidence;
    _revision.add(1);
  }

  /// Returns whether detection slot [index] is active.
  bool isActiveAt(int index) {
    if (_isDisposed || index < 0 || index >= capacity) return false;
    return _active[index] != 0;
  }

  /// Clears all active detections immediately.
  void clearDetections() {
    if (_isDisposed) return;
    _active.fillRange(0, capacity, 0);
    boxes.fillRange(0, boxes.length, 0.0);
    _activeCount = 0;
    _revision.add(1);
  }

  /// Disposes the controller and clears listeners (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _activeCount = 0;
    _revision.dispose();
  }
}

/// A zero-allocation barcode & ML bounding-box scanner overlay widget.
///
/// Renders corner reticles, an animated laser scan line, active detection boxes,
/// and confidence percentage labels ([ZeroNumberPainter.paintPercent]) directly
/// on the [Canvas] without creating per-box widgets or strings.
class ZBarcodeScanner extends ZLeafWidget<RenderZBarcodeScanner> {
  /// Controller holding the flat SoA detection boxes.
  final ZeroDetectionController controller;

  /// Target size of the scanner overlay.
  final Size size;

  /// Color of the animated laser scan line and reticle corners.
  final Color reticleColor;

  /// Color of detected bounding boxes.
  final Color detectionColor;

  /// Background tint of the scanner viewport.
  final Color backgroundColor;

  /// Whether the laser scan line sweeps continuously.
  final bool isScanning;

  /// Creates a const [ZBarcodeScanner] widget.
  const ZBarcodeScanner({
    super.key,
    required this.controller,
    this.size = const Size(320.0, 220.0),
    this.reticleColor = const Color(0xFF38BDF8),
    this.detectionColor = const Color(0xFF22C55E),
    this.backgroundColor = const Color(0xFF090D16),
    this.isScanning = true,
  });

  @override
  RenderZBarcodeScanner createRenderObject(BuildContext context) {
    return RenderZBarcodeScanner(
      controller: controller,
      boxSize: size,
      reticleColor: reticleColor,
      detectionColor: detectionColor,
      backgroundColor: backgroundColor,
      isScanning: isScanning,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZBarcodeScanner renderObject,
  ) {
    renderObject
      ..controller = controller
      ..boxSize = size
      ..reticleColor = reticleColor
      ..detectionColor = detectionColor
      ..backgroundColor = backgroundColor
      ..isScanning = isScanning;
  }
}

/// RenderBox for [ZBarcodeScanner] that draws corner reticles, a sweeping laser
/// line, and SoA detection bounding boxes with zero heap allocations.
class RenderZBarcodeScanner extends ZeroRenderBox {
  ZeroDetectionController _controller;
  Size _boxSize;
  Color _reticleColor;
  Color _detectionColor;
  Color _backgroundColor;
  bool _isScanning;

  double _scanPhase = 0.0;
  Duration? _lastElapsed;
  ZeroNumberPainter? _confidencePainter;

  // 8 corner segments * 4 floats = 32 floats
  final Float32List _reticleLines = Float32List(32);
  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _reticlePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round;
  final Paint _boxPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  final Paint _laserPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  /// Creates a [RenderZBarcodeScanner].
  RenderZBarcodeScanner({
    required ZeroDetectionController controller,
    required Size boxSize,
    required Color reticleColor,
    required Color detectionColor,
    required Color backgroundColor,
    required bool isScanning,
  })  : _controller = controller,
        _boxSize = boxSize,
        _reticleColor = reticleColor,
        _detectionColor = detectionColor,
        _backgroundColor = backgroundColor,
        _isScanning = isScanning,
        super(animatePerFrame: isScanning) {
    _rebuildPaints();
    _confidencePainter = ZeroNumberPainter(
      style: TextStyle(
        color: _detectionColor,
        fontSize: 12.0,
        fontWeight: FontWeight.bold,
        fontFamily: 'monospace',
      ),
    );
  }

  /// Active detection controller.
  ZeroDetectionController get controller => _controller;
  set controller(ZeroDetectionController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(_onDetectionsUpdated);
    }
    _controller = value;
    if (attached) {
      _controller.addListener(_onDetectionsUpdated);
    }
    markDirty();
  }

  /// Target scanner viewport size.
  Size get boxSize => _boxSize;
  set boxSize(Size value) {
    if (_boxSize == value) return;
    _boxSize = value;
    markNeedsLayout();
  }

  /// Reticle and scan line color.
  Color get reticleColor => _reticleColor;
  set reticleColor(Color value) {
    if (_reticleColor == value) return;
    _reticleColor = value;
    _rebuildPaints();
    markDirty();
  }

  /// Bounding box and confidence readout color.
  Color get detectionColor => _detectionColor;
  set detectionColor(Color value) {
    if (_detectionColor == value) return;
    _detectionColor = value;
    _rebuildPaints();
    markDirty();
  }

  /// Viewport background color.
  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    _rebuildPaints();
    markDirty();
  }

  /// Whether the laser scan line is animating.
  bool get isScanning => _isScanning;
  set isScanning(bool value) {
    if (_isScanning == value) return;
    _isScanning = value;
    _lastElapsed = null;
    animatePerFrame = value;
    markDirty();
  }

  void _rebuildPaints() {
    _bgPaint.color = _backgroundColor;
    _reticlePaint.color = _reticleColor;
    _laserPaint.color = _reticleColor;
    _boxPaint.color = _detectionColor;
  }

  void _onDetectionsUpdated() {
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(_onDetectionsUpdated);
  }

  @override
  void detach() {
    _controller.removeListener(_onDetectionsUpdated);
    super.detach();
  }

  @override
  void dispose() {
    _controller.removeListener(_onDetectionsUpdated);
    _confidencePainter?.dispose();
    _confidencePainter = null;
    super.dispose();
  }

  @override
  bool onFrameTick(Duration elapsed) {
    if (!_isScanning) return false;
    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    if (prev == null) return true;
    final int deltaUs = (elapsed - prev).inMicroseconds;
    if (deltaUs <= 0) return false;
    _scanPhase = (_scanPhase + (deltaUs / 1000000.0) * 0.75) % 1.0;
    return true;
  }

  @override
  void performLayout() {
    size = constraints.constrain(_boxSize);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect rect = offset & size;
    canvas.drawRect(rect, _bgPaint);

    final Rect frame = rect.deflate(20.0);
    _paintReticleCorners(canvas, frame);
    if (_isScanning) {
      final double scanY = frame.top + frame.height * _scanPhase;
      canvas.drawLine(
        Offset(frame.left + 6.0, scanY),
        Offset(frame.right - 6.0, scanY),
        _laserPaint,
      );
    }
    _paintDetections(canvas, offset);
  }

  void _paintReticleCorners(Canvas canvas, Rect frame) {
    const double len = 18.0;
    final double l = frame.left;
    final double t = frame.top;
    final double r = frame.right;
    final double b = frame.bottom;

    _stageSegment(0, l, t, l + len, t);
    _stageSegment(4, l, t, l, t + len);
    _stageSegment(8, r - len, t, r, t);
    _stageSegment(12, r, t, r, t + len);
    _stageSegment(16, l, b - len, l, b);
    _stageSegment(20, l, b, l + len, b);
    _stageSegment(24, r - len, b, r, b);
    _stageSegment(28, r, b - len, r, b);

    canvas.drawRawPoints(ui.PointMode.lines, _reticleLines, _reticlePaint);
  }

  void _stageSegment(int base, double x0, double y0, double x1, double y1) {
    _reticleLines[base] = x0;
    _reticleLines[base + 1] = y0;
    _reticleLines[base + 2] = x1;
    _reticleLines[base + 3] = y1;
  }

  void _paintDetections(Canvas canvas, Offset offset) {
    if (_controller.activeCount == 0) return;
    final Float32List boxes = _controller.boxes;
    final int cap = _controller.capacity;
    final ZeroNumberPainter? painter = _confidencePainter;

    for (int i = 0; i < cap; i++) {
      if (_controller.isActiveAt(i)) {
        final int base = i * 5;
        final double l = offset.dx + boxes[base];
        final double t = offset.dy + boxes[base + 1];
        final double r = offset.dx + boxes[base + 2];
        final double b = offset.dy + boxes[base + 3];
        final double conf = boxes[base + 4];
        canvas.drawRect(Rect.fromLTRB(l, t, r, b), _boxPaint);
        painter?.paintPercent(
          canvas,
          Offset(l + 4.0, t + 4.0),
          conf,
          fractionDigits: 0,
        );
      }
    }
  }
}
