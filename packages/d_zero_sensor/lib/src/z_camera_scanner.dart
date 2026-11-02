import 'dart:ffi' as ffi;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'camera_state_ffi.dart';

/// Active Z-prefixed alias for [ZCameraScanner].
typedef ZZeroCamera = ZCameraScanner;

/// Low-level C++17 Seqlock Shared-Memory camera & barcode controller.
///
/// Eliminates the 3 main bottlenecks of `nitro_camera`:
/// 1. **Zero Isolate / `TransferableTypedData` Copies**: Processes frames and writes
///    detections directly in a 704-byte cache-aligned C++ shared memory struct.
/// 2. **Zero Per-Frame Heap Allocations**: Reuses a single pre-allocated native scratch
///    buffer (`_payloadScratch` & `_lumaScratch`) across all frames.
/// 3. **Zero Channel / Zero Stream Latency**: Exposes a direct `ffi.Pointer` view
///    polled at VSync by [RenderZCameraScanner] in `0 ns`.
class ZeroCameraController {
  static const int _maxLumaDimension = 2048;

  final ZeroCameraNativeBindings _bindings = ZeroCameraNativeBindings.instance;
  late final ZeroCameraStateView _view;
  late final ffi.Pointer<ffi.Uint8> _payloadScratch;
  ffi.Pointer<ffi.Uint8> _lumaScratch = ffi.nullptr;
  int _lumaScratchCap = 0;

  final ZeroIntNotifier _revision = ZeroIntNotifier(0);
  bool _isDisposed = false;

  /// Creates a [ZeroCameraController] backed by C++17 Seqlock shared memory.
  ZeroCameraController() {
    _view = _bindings.allocateState();
    _payloadScratch =
        pkg_ffi.calloc<ffi.Uint8>(ZeroCameraStateView.maxPayloadBytes + 1);
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether the native C++17 shared library (`libzero_sensor_native`) is active.
  bool get isNativeCppActive =>
      !_isDisposed && _bindings.hasNativeCppLibrary && !_view.allocatedByCalloc;

  /// Raw native memory address of `ZeroCameraSharedState` (`0` if disposed).
  int get stateAddress => _isDisposed ? 0 : _view.pointer.address;

  /// Direct read-only view over the C++ shared memory struct.
  ZeroCameraStateView? get sharedView => _isDisposed ? null : _view;

  /// Current Seqlock sequence number (even = consistent, odd = writing).
  int get seq => _isDisposed ? 0 : _view.seq;

  /// Total camera frames processed.
  int get frameCount => _isDisposed ? 0 : _view.frameCount;

  /// Total QR / barcode frames decoded.
  int get scanCount => _isDisposed ? 0 : _view.scanCount;

  /// Total deduplicated unique QR codes decoded.
  int get uniqueScanCount => _isDisposed ? 0 : _view.uniqueScanCount;

  /// Most recent native C++ decode latency in microseconds.
  int get lastDecodeUs => _isDisposed ? 0 : _view.lastDecodeUs;

  /// Smoothed native camera frame rate.
  double get cameraFps => _isDisposed ? 0.0 : _view.cameraFps;

  /// Mean luminance (`0.0..255.0`) of the active scan ROI.
  double get meanLuma => _isDisposed ? 0.0 : _view.meanLuma;

  /// Number of active detection bounding boxes (`0..16`).
  int get activeBoxCount => _isDisposed ? 0 : _view.activeBoxCount;

  /// FNV-1a 64-bit hash of the most recently decoded payload.
  int get lastPayloadHash => _isDisposed ? 0 : _view.lastPayloadHash;

  /// Whether any listeners are currently attached to this controller.
  bool get hasListeners => !_isDisposed && _revision.hasListeners;

  /// Registers a listener notified when shared state is updated from Dart.
  void addListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.addListener(listener);
  }

  /// Removes a previously registered listener.
  void removeListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.removeListener(listener);
  }

  /// Reads the latest UTF-8 decoded payload string from C++ shared memory.
  String readLatestPayload() {
    if (_isDisposed) return '';
    return _view.readPayloadString();
  }

  /// Writes a single detection bounding box and payload into C++ Seqlock shared
  /// memory with zero Dart heap allocations.
  void recordNativeDetection({
    required double left,
    required double top,
    required double right,
    required double bottom,
    double confidence = 99.0,
    String payload = '',
    int decodeMicros = 6,
  }) {
    if (_isDisposed) return;
    _bindings.beginDetections(_view);
    _bindings.setDetectionBox(_view, 0, left, top, right, bottom, confidence);
    final int len = _copyAsciiPayloadToScratch(payload);
    _bindings.commitDetectionPayload(_view, _payloadScratch, len, decodeMicros);
    _revision.add(1);
  }

  /// Begins a multi-box Seqlock write batch in C++ shared memory.
  void beginDetectionBatch() {
    if (_isDisposed) return;
    _bindings.beginDetections(_view);
  }

  /// Sets bounding box [index] (`0..15`) within the current Seqlock batch.
  void setBatchDetectionBox(
    int index,
    double left,
    double top,
    double right,
    double bottom,
    double confidence,
  ) {
    if (_isDisposed) return;
    _bindings.setDetectionBox(
      _view,
      index,
      left,
      top,
      right,
      bottom,
      confidence,
    );
  }

  /// Commits a multi-box Seqlock batch with [payload] and [decodeMicros].
  void commitDetectionBatch({String payload = '', int decodeMicros = 6}) {
    if (_isDisposed) return;
    final int len = _copyAsciiPayloadToScratch(payload);
    _bindings.commitDetectionPayload(_view, _payloadScratch, len, decodeMicros);
    _revision.add(1);
  }

  int _copyAsciiPayloadToScratch(String text) {
    final int limit = math.min(
      text.length,
      ZeroCameraStateView.maxPayloadBytes,
    );
    for (int i = 0; i < limit; i++) {
      _payloadScratch[i] = text.codeUnitAt(i) & 0xFF;
    }
    _payloadScratch[limit] = 0;
    return limit;
  }

  /// Runs the C++17 zero-allocation YUV420 Luma frame scanner (`zero_camera_scan_luma_frame`)
  /// without spawning an Isolate, allocating `TransferableTypedData`, or creating `Uint8List` copies.
  int scanLumaPlaneZeroCopy(
    Uint8List lumaBytes, {
    required int width,
    required int height,
    int rowStride = 0,
    double windowFraction = 0.72,
  }) {
    if (_isDisposed || width < 21 || height < 21) return 0;
    final int clampedW = width.clamp(21, _maxLumaDimension);
    final int clampedH = height.clamp(21, _maxLumaDimension);
    final int effStride = rowStride >= clampedW ? rowStride : clampedW;
    final int requiredBytes = effStride * clampedH;
    if (lumaBytes.length < requiredBytes) return 0;

    _ensureLumaScratchCapacity(requiredBytes);
    final Uint8List nativeView = _lumaScratch.asTypedList(requiredBytes);
    nativeView.setRange(0, requiredBytes, lumaBytes);

    final int hit = _bindings.scanLumaFrame(
      _view,
      _lumaScratch,
      clampedW,
      clampedH,
      effStride,
      windowFraction,
    );
    if (hit != 0) {
      _revision.add(1);
    }
    return hit;
  }

  void _ensureLumaScratchCapacity(int requiredBytes) {
    if (_lumaScratchCap >= requiredBytes && _lumaScratch.address != 0) return;
    if (_lumaScratch.address != 0) {
      pkg_ffi.calloc.free(_lumaScratch);
    }
    _lumaScratch = pkg_ffi.calloc<ffi.Uint8>(requiredBytes);
    _lumaScratchCap = requiredBytes;
  }

  /// Resets all frame/scan counters and active bounding boxes in shared memory.
  void resetCounters() {
    if (_isDisposed) return;
    _bindings.resetCounters(_view);
    _revision.add(1);
  }

  /// Disposes the controller and frees all native C++ shared memory (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    if (_lumaScratch.address != 0) {
      pkg_ffi.calloc.free(_lumaScratch);
      _lumaScratch = ffi.nullptr;
      _lumaScratchCap = 0;
    }
    if (_payloadScratch.address != 0) {
      pkg_ffi.calloc.free(_payloadScratch);
    }
    _bindings.freeState(_view);
    _revision.dispose();
  }
}

/// A zero-allocation FFI camera & QR/barcode scanner widget powered by C++17
/// Seqlock shared memory ([ZeroCameraController]).
///
/// Wraps an optional camera preview [child] (such as a GPU `Texture` or platform
/// camera feed) and paints corner reticles, a sweeping laser line, SoA detection
/// boxes, and live C++ decode telemetry (`µs` & scan count) directly onto the
/// Impeller [Canvas] with `0` widget rebuilds and `0` string allocations.
class ZCameraScanner extends ZSingleChildWidget<RenderZCameraScanner> {
  /// Low-level C++ shared-memory camera controller.
  final ZeroCameraController controller;

  /// Target viewport size.
  final Size size;

  /// Color of the corner reticle and laser scan line.
  final Color reticleColor;

  /// Color of detected QR / barcode bounding boxes.
  final Color detectionColor;

  /// Background tint when no [child] preview is provided.
  final Color backgroundColor;

  /// Whether the laser scan line sweeps and polls C++ shared memory at VSync.
  final bool isScanning;

  /// Whether to render the zero-allocation C++ telemetry bar (`decode µs` & `scans`).
  final bool showTelemetryHud;

  /// Creates a const [ZCameraScanner].
  const ZCameraScanner({
    super.key,
    required this.controller,
    super.child,
    this.size = const Size(320.0, 240.0),
    this.reticleColor = const Color(0xFF00E5FF),
    this.detectionColor = const Color(0xFF00FF88),
    this.backgroundColor = const Color(0xFF080D16),
    this.isScanning = true,
    this.showTelemetryHud = true,
  });

  @override
  RenderZCameraScanner createRenderObject(BuildContext context) {
    return RenderZCameraScanner(
      controller: controller,
      boxSize: size,
      reticleColor: reticleColor,
      detectionColor: detectionColor,
      backgroundColor: backgroundColor,
      isScanning: isScanning,
      showTelemetryHud: showTelemetryHud,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZCameraScanner renderObject,
  ) {
    renderObject
      ..controller = controller
      ..boxSize = size
      ..reticleColor = reticleColor
      ..detectionColor = detectionColor
      ..backgroundColor = backgroundColor
      ..isScanning = isScanning
      ..showTelemetryHud = showTelemetryHud;
  }
}

/// Custom [ZeroRenderBox] for [ZCameraScanner] reading directly from C++
/// `ZeroCameraSharedState` via Seqlock verification.
class RenderZCameraScanner extends ZeroRenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  ZeroCameraController _controller;
  Size _boxSize;
  Color _reticleColor;
  Color _detectionColor;
  Color _backgroundColor;
  bool _isScanning;
  bool _showTelemetryHud;

  int _lastSeenSeq = -1;
  double _scanPhase = 0.0;
  Duration? _lastElapsed;

  ZeroNumberPainter? _hudPainter;
  final Float32List _reticleLines = Float32List(32);
  final Float32List _boxSnapshot = Float32List(
    ZeroCameraStateView.maxDetections * ZeroCameraStateView.floatsPerBox,
  );

  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _hudBgPaint = Paint()
    ..color = const Color(0xCC070B14)
    ..style = PaintingStyle.fill;
  final Paint _reticlePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round;
  final Paint _boxPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;
  final Paint _laserPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  /// Creates a [RenderZCameraScanner].
  RenderZCameraScanner({
    required ZeroCameraController controller,
    required Size boxSize,
    required Color reticleColor,
    required Color detectionColor,
    required Color backgroundColor,
    required bool isScanning,
    required bool showTelemetryHud,
  })  : _controller = controller,
        _boxSize = boxSize,
        _reticleColor = reticleColor,
        _detectionColor = detectionColor,
        _backgroundColor = backgroundColor,
        _isScanning = isScanning,
        _showTelemetryHud = showTelemetryHud,
        super(animatePerFrame: isScanning) {
    _syncPaintColors();
    _hudPainter = ZeroNumberPainter(
      style: TextStyle(
        color: _detectionColor,
        fontSize: 11.5,
        fontWeight: FontWeight.bold,
        fontFamily: 'monospace',
      ),
    );
  }

  /// Active low-level camera controller.
  ZeroCameraController get controller => _controller;
  set controller(ZeroCameraController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _controller = value;
    _lastSeenSeq = -1;
    markDirty();
  }

  /// Target viewport size.
  Size get boxSize => _boxSize;
  set boxSize(Size value) {
    if (_boxSize == value) return;
    _boxSize = value;
    markNeedsLayout();
  }

  /// Reticle and laser color.
  Color get reticleColor => _reticleColor;
  set reticleColor(Color value) {
    if (_reticleColor == value) return;
    _reticleColor = value;
    _syncPaintColors();
    markDirty();
  }

  /// Bounding box and telemetry color.
  Color get detectionColor => _detectionColor;
  set detectionColor(Color value) {
    if (_detectionColor == value) return;
    _detectionColor = value;
    _syncPaintColors();
    markDirty();
  }

  /// Background color when no child texture is present.
  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    _syncPaintColors();
    markDirty();
  }

  /// Whether scanning animation and VSync Seqlock polling are active.
  bool get isScanning => _isScanning;
  set isScanning(bool value) {
    if (_isScanning == value) return;
    _isScanning = value;
    _lastElapsed = null;
    animatePerFrame = value;
    markDirty();
  }

  /// Whether the C++ telemetry HUD strip is drawn.
  bool get showTelemetryHud => _showTelemetryHud;
  set showTelemetryHud(bool value) {
    if (_showTelemetryHud == value) return;
    _showTelemetryHud = value;
    markDirty();
  }

  void _syncPaintColors() {
    _bgPaint.color = _backgroundColor;
    _reticlePaint.color = _reticleColor;
    _laserPaint.color = _reticleColor;
    _boxPaint.color = _detectionColor;
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
    _hudPainter?.dispose();
    _hudPainter = null;
    super.dispose();
  }

  @override
  bool onFrameTick(Duration elapsed) {
    bool dirty = false;
    final int currentSeq = _controller.seq;
    if (currentSeq != _lastSeenSeq && (currentSeq & 1) == 0) {
      _lastSeenSeq = currentSeq;
      dirty = true;
    }
    if (_isScanning) {
      final Duration? prev = _lastElapsed;
      _lastElapsed = elapsed;
      if (prev != null) {
        final int dtUs = (elapsed - prev).inMicroseconds;
        if (dtUs > 0) {
          _scanPhase = (_scanPhase + (dtUs / 1000000.0) * 0.85) % 1.0;
          dirty = true;
        }
      }
    }
    return dirty;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_boxSize);

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
    child?.layout(BoxConstraints.tight(size), parentUsesSize: false);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect viewport = offset & size;
    if (child != null) {
      context.paintChild(child!, offset);
    } else if (_backgroundColor.a > 0.0) {
      canvas.drawRect(viewport, _bgPaint);
    }

    final Rect reticleRect = viewport.deflate(22.0);
    _paintReticle(canvas, reticleRect);
    if (_isScanning) {
      final double y = reticleRect.top + reticleRect.height * _scanPhase;
      canvas.drawLine(
        Offset(reticleRect.left + 6.0, y),
        Offset(reticleRect.right - 6.0, y),
        _laserPaint,
      );
    }
    _paintSharedMemoryDetections(canvas, offset);
    if (_showTelemetryHud) {
      _paintTelemetryStrip(canvas, viewport);
    }
  }

  void _paintReticle(Canvas canvas, Rect r) {
    const double s = 18.0;
    _setSeg(0, r.left, r.top, r.left + s, r.top);
    _setSeg(4, r.left, r.top, r.left, r.top + s);
    _setSeg(8, r.right - s, r.top, r.right, r.top);
    _setSeg(12, r.right, r.top, r.right, r.top + s);
    _setSeg(16, r.left, r.bottom - s, r.left, r.bottom);
    _setSeg(20, r.left, r.bottom, r.left + s, r.bottom);
    _setSeg(24, r.right - s, r.bottom, r.right, r.bottom);
    _setSeg(28, r.right, r.bottom - s, r.right, r.bottom);
    canvas.drawRawPoints(ui.PointMode.lines, _reticleLines, _reticlePaint);
  }

  void _setSeg(int base, double x0, double y0, double x1, double y1) {
    _reticleLines[base] = x0;
    _reticleLines[base + 1] = y0;
    _reticleLines[base + 2] = x1;
    _reticleLines[base + 3] = y1;
  }

  void _paintSharedMemoryDetections(Canvas canvas, Offset offset) {
    final ZeroCameraStateView? view = _controller.sharedView;
    if (view == null) return;
    final int count = view.copyBoxesInto(_boxSnapshot);
    if (count <= 0) return;

    final ZeroNumberPainter? painter = _hudPainter;
    for (int i = 0; i < count; i++) {
      final int b = i * ZeroCameraStateView.floatsPerBox;
      final double left = offset.dx + _boxSnapshot[b];
      final double top = offset.dy + _boxSnapshot[b + 1];
      final double right = offset.dx + _boxSnapshot[b + 2];
      final double bottom = offset.dy + _boxSnapshot[b + 3];
      final double conf = _boxSnapshot[b + 4];
      canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), _boxPaint);
      painter?.paintPercent(
        canvas,
        Offset(left + 4.0, top + 4.0),
        conf,
        fractionDigits: 0,
      );
    }
  }

  void _paintTelemetryStrip(Canvas canvas, Rect viewport) {
    final ZeroNumberPainter? painter = _hudPainter;
    if (painter == null) return;
    final Rect strip = Rect.fromLTWH(
      viewport.left + 8.0,
      viewport.top + 8.0,
      viewport.width - 16.0,
      22.0,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(strip, const Radius.circular(5.0)),
      _hudBgPaint,
    );
    painter.paintInt(
      canvas,
      Offset(strip.left + 8.0, strip.top + 4.0),
      _controller.scanCount,
      minDigits: 4,
    );
    final double decodeMs = _controller.lastDecodeUs / 1000.0;
    painter.paintWithSuffix(
      canvas,
      Offset(strip.right - 74.0, strip.top + 4.0),
      decodeMs,
      suffixGlyph: ZeroNumberPainter.glyphMs,
      fractionDigits: 3,
    );
  }
}
