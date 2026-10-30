import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active Z-prefixed alias for [Z3DPointCloud].
typedef ZLidarView = Z3DPointCloud;

/// Deprecated legacy alias for [Z3DPointCloud].
@Deprecated('Use Z3DPointCloud instead.')
typedef Zero3DPointCloud = Z3DPointCloud;

/// Zero-allocation Structure-of-Arrays (SoA) 3D point cloud & camera depth controller.
///
/// Stores up to [maxAllowedPoints] (`16,384`) 3D metric coordinates `(X, Y, Z)` in meters
/// inside contiguous [Float32List] buffers. Supports:
/// - Direct 3D point insertion ([setPoint], [addPoint])
/// - 2D Camera / LiDAR / ARCore / ARKit depth-map unprojection ([ingestDepthFrame])
///   converting pixel `(u, v, depthMeters)` to metric 3D `(X, Y, Z)` via pinhole intrinsics
/// - Real-time metric distance measurement ([centerDistanceMeters], [distanceAtPoint],
///   [measureDistanceBetween]).
class ZeroPointCloudController implements Listenable {
  /// Maximum allowed point capacity (`16,384`).
  static const int maxAllowedPoints = 16384;

  /// Maximum number of 3D points stored in this controller.
  final int maxPoints;

  late final Float32List _x;
  late final Float32List _y;
  late final Float32List _z;
  final ZeroIntNotifier _revision = ZeroIntNotifier(0);

  int _pointCount = 0;
  double _centerDistanceMeters = 0.0;
  bool _isDisposed = false;

  /// Creates a [ZeroPointCloudController] with capacity for [maxPoints] 3D points.
  ZeroPointCloudController({int maxPoints = 2048})
      : maxPoints = maxPoints.clamp(1, maxAllowedPoints) {
    _x = Float32List(this.maxPoints);
    _y = Float32List(this.maxPoints);
    _z = Float32List(this.maxPoints);
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether any listeners are currently registered.
  bool get hasListeners => !_isDisposed && _revision.hasListeners;

  /// Number of active 3D points currently in the cloud.
  int get pointCount => _isDisposed ? 0 : _pointCount;

  /// Measured metric distance (in meters) at the camera center crosshair.
  double get centerDistanceMeters => _isDisposed ? 0.0 : _centerDistanceMeters;

  /// Appends a 3D point `([x], [y], [z])` in meters to the cloud.
  void addPoint(double x, double y, double z) {
    if (_isDisposed || _pointCount >= maxPoints) return;
    if (x.isNaN || y.isNaN || z.isNaN) return;
    final int idx = _pointCount++;
    _x[idx] = x;
    _y[idx] = y;
    _z[idx] = z;
    if (idx == 0) {
      _centerDistanceMeters = math.sqrt(x * x + y * y + z * z);
    }
    _revision.add(1);
  }

  /// Updates an existing 3D point at [index] in-place.
  void setPoint(int index, double x, double y, double z) {
    if (_isDisposed || index < 0 || index >= _pointCount) return;
    if (x.isNaN || y.isNaN || z.isNaN) return;
    _x[index] = x;
    _y[index] = y;
    _z[index] = z;
    _revision.add(1);
  }

  /// Unprojects a 2D camera/LiDAR depth frame [depthMeters] (`[width] x [height]`)
  /// into 3D metric coordinates `(X, Y, Z)` in meters using pinhole camera intrinsics.
  ///
  /// Works with iOS ARKit (`ARFrame.sceneDepth`), TrueDepth disparity, and Android
  /// ARCore Raw Depth API (`acquireDepthImage16Bits` converted to meters).
  void ingestDepthFrame(
    List<double> depthMeters, {
    required int width,
    required int height,
    double fovRadians = 1.0472, // ~60 degrees horizontal FOV
    double maxRangeMeters = 8.0,
  }) {
    if (_isDisposed || width <= 0 || height <= 0) return;
    final double halfFov = (fovRadians.clamp(0.2, 2.6)) * 0.5;
    final double fx = (width * 0.5) / math.tan(halfFov);
    final double fy = fx;
    final double cx = (width - 1) * 0.5;
    final double cy = (height - 1) * 0.5;

    final int totalPixels = width * height;
    final int step = totalPixels > maxPoints ? (totalPixels ~/ maxPoints) : 1;

    _updateCenterCrosshairDistance(depthMeters, width, height);
    _unprojectDepthPixels(
      depthMeters: depthMeters,
      width: width,
      height: height,
      step: step,
      fx: fx,
      fy: fy,
      cx: cx,
      cy: cy,
      maxRangeMeters: maxRangeMeters,
    );
    _revision.add(1);
  }

  void _updateCenterCrosshairDistance(
    List<double> depthMeters,
    int width,
    int height,
  ) {
    final int centerIdx = (height ~/ 2) * width + (width ~/ 2);
    if (centerIdx >= 0 && centerIdx < depthMeters.length) {
      final double d = depthMeters[centerIdx];
      _centerDistanceMeters = (d.isFinite && d > 0.0) ? d : 0.0;
    }
  }

  void _unprojectDepthPixels({
    required List<double> depthMeters,
    required int width,
    required int height,
    required int step,
    required double fx,
    required double fy,
    required double cx,
    required double cy,
    required double maxRangeMeters,
  }) {
    final int srcLen = depthMeters.length;
    final int total = width * height;
    int count = 0;

    for (int p = 0; p < total && count < maxPoints; p += step) {
      if (p >= srcLen) break;
      final double z = depthMeters[p];
      if (!z.isFinite || z <= 0.05 || z > maxRangeMeters) continue;

      final int v = p ~/ width;
      final int u = p - v * width;
      _x[count] = ((u - cx) * z) / fx;
      _y[count] = ((cy - v) * z) / fy;
      _z[count] = z;
      count++;
    }
    _pointCount = count;
  }

  /// Returns the Euclidean distance $\sqrt{X^2 + Y^2 + Z^2}$ in meters from the
  /// camera origin `(0, 0, 0)` to the 3D point at [index].
  double distanceAtPoint(int index) {
    if (_isDisposed || index < 0 || index >= _pointCount) return 0.0;
    final double px = _x[index];
    final double py = _y[index];
    final double pz = _z[index];
    return math.sqrt(px * px + py * py + pz * pz);
  }

  /// Measures the 3D Euclidean distance in meters between point [indexA] and [indexB]
  /// (spatial AR tape-measure between two scanned 3D points).
  double measureDistanceBetween(int indexA, int indexB) {
    if (_isDisposed ||
        indexA < 0 ||
        indexA >= _pointCount ||
        indexB < 0 ||
        indexB >= _pointCount) {
      return 0.0;
    }
    final double dx = _x[indexB] - _x[indexA];
    final double dy = _y[indexB] - _y[indexA];
    final double dz = _z[indexB] - _z[indexA];
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  /// Clears all points and resets distance readouts.
  void clear() {
    if (_isDisposed) return;
    _pointCount = 0;
    _centerDistanceMeters = 0.0;
    _revision.add(1);
  }

  @override
  void addListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.removeListener(listener);
  }

  /// Disposes the controller and zeros all coordinate buffers (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _pointCount = 0;
    _centerDistanceMeters = 0.0;
    _x.fillRange(0, _x.length, 0.0);
    _y.fillRange(0, _y.length, 0.0);
    _z.fillRange(0, _z.length, 0.0);
    _revision.dispose();
  }
}

/// A zero-allocation 3D LiDAR / depth-camera point cloud & metric rangefinder widget.
///
/// Projects up to 16,384 3D points `(X, Y, Z)` into 4 depth-sorted color/size buckets,
/// batch-renders each depth band via [Canvas.drawRawPoints], and overlays a live
/// zero-allocation crosshair distance readout in meters via [ZeroNumberPainter].
class Z3DPointCloud extends ZLeafWidget<RenderZ3DPointCloud> {
  /// Backing 3D point cloud and depth sensor controller.
  final ZeroPointCloudController controller;

  /// Preferred viewport size when unconstrained.
  final Size size;

  /// Color for near-range 3D points.
  final Color nearColor;

  /// Color for far-range 3D points.
  final Color farColor;

  /// Viewport background color.
  final Color backgroundColor;

  /// Horizontal yaw orbit angle in radians.
  final double yaw;

  /// Vertical pitch orbit angle in radians.
  final double pitch;

  /// Whether to render the center crosshair & metric distance readout.
  final bool showDistanceHud;

  /// Creates a const [Z3DPointCloud] widget.
  const Z3DPointCloud({
    super.key,
    required this.controller,
    this.size = const Size(320.0, 220.0),
    this.nearColor = const Color(0xFF00F5D4),
    this.farColor = const Color(0xFF3B82F6),
    this.backgroundColor = const Color(0xFF070B14),
    this.yaw = 0.0,
    this.pitch = 0.2,
    this.showDistanceHud = true,
  });

  @override
  RenderZ3DPointCloud createRenderObject(BuildContext context) {
    return RenderZ3DPointCloud(
      controller: controller,
      preferredSize: size,
      nearColor: nearColor,
      farColor: farColor,
      backgroundColor: backgroundColor,
      yaw: yaw,
      pitch: pitch,
      showDistanceHud: showDistanceHud,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZ3DPointCloud renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..nearColor = nearColor
      ..farColor = farColor
      ..backgroundColor = backgroundColor
      ..yaw = yaw
      ..pitch = pitch
      ..showDistanceHud = showDistanceHud;
  }
}

/// Custom [ZeroRenderBox] for [Z3DPointCloud].
class RenderZ3DPointCloud extends ZeroRenderBox {
  static const int _bucketCount = 4;

  ZeroPointCloudController _controller;
  Size _preferredSize;
  Color _nearColor;
  Color _farColor;
  Color _backgroundColor;
  double _yaw;
  double _pitch;
  bool _showDistanceHud;

  late List<Float32List> _bucketFloats;
  final Int32List _bucketCounts = Int32List(_bucketCount);
  final List<Paint> _bucketPaints = List<Paint>.generate(
    _bucketCount,
    (int i) => Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.5 - i * 0.85,
    growable: false,
  );
  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _reticlePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..color = const Color(0x9900F5D4);
  late final ZeroNumberPainter _distancePainter;

  /// Creates a [RenderZ3DPointCloud].
  RenderZ3DPointCloud({
    required ZeroPointCloudController controller,
    required Size preferredSize,
    required Color nearColor,
    required Color farColor,
    required Color backgroundColor,
    required double yaw,
    required double pitch,
    required bool showDistanceHud,
  })  : _controller = controller,
        _preferredSize = preferredSize,
        _nearColor = nearColor,
        _farColor = farColor,
        _backgroundColor = backgroundColor,
        _yaw = yaw,
        _pitch = pitch.clamp(-1.2, 1.2),
        _showDistanceHud = showDistanceHud {
    _bgPaint.color = _backgroundColor;
    _distancePainter = ZeroNumberPainter(
      style: const TextStyle(
        color: Color(0xFF00F5D4),
        fontSize: 13.0,
        fontWeight: FontWeight.w700,
      ),
    );
    _allocateBuckets(_controller.maxPoints);
    _rebuildBucketPaints();
  }

  void _allocateBuckets(int maxPts) {
    _bucketFloats = List<Float32List>.generate(
      _bucketCount,
      (_) => Float32List(maxPts * 2),
      growable: false,
    );
  }

  void _rebuildBucketPaints() {
    for (int i = 0; i < _bucketCount; i++) {
      final double t = i / (_bucketCount - 1);
      _bucketPaints[i].color = Color.lerp(_nearColor, _farColor, t)!;
    }
  }

  /// Backing point cloud controller.
  ZeroPointCloudController get controller => _controller;
  set controller(ZeroPointCloudController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
    }
    _controller = value;
    if (_bucketFloats[0].length < _controller.maxPoints * 2) {
      _allocateBuckets(_controller.maxPoints);
    }
    if (attached) {
      _controller.addListener(markDirty);
    }
    markDirty();
  }

  /// Preferred viewport size.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// Near-range point color.
  Color get nearColor => _nearColor;
  set nearColor(Color value) {
    if (_nearColor == value) return;
    _nearColor = value;
    _rebuildBucketPaints();
    markDirty();
  }

  /// Far-range point color.
  Color get farColor => _farColor;
  set farColor(Color value) {
    if (_farColor == value) return;
    _farColor = value;
    _rebuildBucketPaints();
    markDirty();
  }

  /// Background color.
  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    _bgPaint.color = value;
    markDirty();
  }

  /// Horizontal yaw orbit angle in radians.
  double get yaw => _yaw;
  set yaw(double value) {
    if (_yaw == value || value.isNaN) return;
    _yaw = value;
    markDirty();
  }

  /// Vertical pitch orbit angle in radians.
  double get pitch => _pitch;
  set pitch(double value) {
    if (value.isNaN) return;
    final double clamped = value.clamp(-1.2, 1.2);
    if (_pitch == clamped) return;
    _pitch = clamped;
    markDirty();
  }

  /// Whether the crosshair and metric distance HUD are displayed.
  bool get showDistanceHud => _showDistanceHud;
  set showDistanceHud(bool value) {
    if (_showDistanceHud == value) return;
    _showDistanceHud = value;
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
    _distancePainter.dispose();
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
    if (event is PointerMoveEvent) {
      _yaw = (_yaw + event.delta.dx * 0.01) % (math.pi * 2.0);
      _pitch = (_pitch + event.delta.dy * 0.008).clamp(-1.2, 1.2);
      markDirty();
    }
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect bounds = offset & size;
    canvas.drawRect(bounds, _bgPaint);
    if (_controller.isDisposed) return;

    canvas.save();
    canvas.clipRect(bounds);
    if (_controller.pointCount > 0) {
      _projectPointsIntoDepthBuckets(offset);
      for (int b = _bucketCount - 1; b >= 0; b--) {
        final int count = _bucketCounts[b];
        if (count <= 0) continue;
        canvas.drawRawPoints(
          ui.PointMode.points,
          Float32List.sublistView(_bucketFloats[b], 0, count << 1),
          _bucketPaints[b],
        );
      }
    }
    if (_showDistanceHud) {
      _paintRangefinderHud(canvas, offset);
    }
    canvas.restore();
  }

  void _projectPointsIntoDepthBuckets(Offset offset) {
    _bucketCounts.fillRange(0, _bucketCount, 0);
    final double cx = offset.dx + size.width * 0.5;
    final double cy = offset.dy + size.height * 0.5;
    final double focal =
        (size.width < size.height ? size.width : size.height) * 0.95;

    final double cosY = math.cos(_yaw), sinY = math.sin(_yaw);
    final double cosP = math.cos(_pitch), sinP = math.sin(_pitch);
    final int n = _controller.pointCount;

    for (int i = 0; i < n; i++) {
      final double x = _controller._x[i];
      final double y = _controller._y[i];
      final double z = _controller._z[i] - 2.0; // Orbit around z = 2.0m

      final double rx = x * cosY - z * sinY;
      final double rz0 = x * sinY + z * cosY;
      final double ry = y * cosP - rz0 * sinP;
      final double rz = (y * sinP + rz0 * cosP) + 2.5;
      if (rz <= 0.15) continue;

      final double invZ = focal / rz;
      final double sx = cx + rx * invZ;
      final double sy = cy - ry * invZ;

      final int bucket = ((rz - 0.5) * 0.65).floor().clamp(0, _bucketCount - 1);
      final int idx = _bucketCounts[bucket];
      final int fIdx = idx << 1;
      _bucketFloats[bucket][fIdx] = sx;
      _bucketFloats[bucket][fIdx + 1] = sy;
      _bucketCounts[bucket] = idx + 1;
    }
  }

  void _paintRangefinderHud(Canvas canvas, Offset offset) {
    final double cx = offset.dx + size.width * 0.5;
    final double cy = offset.dy + size.height * 0.5;
    canvas.drawCircle(Offset(cx, cy), 12.0, _reticlePaint);
    canvas.drawLine(Offset(cx - 18.0, cy), Offset(cx - 6.0, cy), _reticlePaint);
    canvas.drawLine(Offset(cx + 6.0, cy), Offset(cx + 18.0, cy), _reticlePaint);
    canvas.drawLine(Offset(cx, cy - 18.0), Offset(cx, cy - 6.0), _reticlePaint);
    canvas.drawLine(Offset(cx, cy + 6.0), Offset(cx, cy + 18.0), _reticlePaint);

    _distancePainter.paintDouble(
      canvas,
      Offset(offset.dx + 10.0, offset.dy + 10.0),
      _controller.centerDistanceMeters,
      fractionDigits: 2,
    );
  }
}
