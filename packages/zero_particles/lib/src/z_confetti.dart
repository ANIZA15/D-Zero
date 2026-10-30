import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';

/// Controller managing Structure-of-Arrays (SoA) confetti simulation state.
///
/// Pre-allocates all [Float32List] and [Int32List] buffers at construction time:
/// - Zero per-frame heap allocations during physics steps and batch rendering.
/// - Safe against double-[dispose] and post-dispose calls.
class ZeroConfettiController with ChangeNotifier {
  /// Number of pre-baked confetti palette buckets for batched `drawRawPoints` calls.
  static const int paletteCount = 6;

  /// Pre-allocated palette colors for zero-allocation batch rendering.
  static const List<Color> paletteColors = <Color>[
    Color(0xFFFF5252),
    Color(0xFFFFD740),
    Color(0xFF00E676),
    Color(0xFF40C4FF),
    Color(0xFFE040FB),
    Color(0xFFFF6E40),
  ];

  static final Float32List _emptyFloat32 = Float32List(0);
  static final Int32List _emptyInt32 = Int32List(0);

  /// Maximum number of confetti pieces managed by this controller.
  final int capacity;

  late Float32List _x;
  late Float32List _y;
  late Float32List _vx;
  late Float32List _vy;
  late Float32List _angle;
  late Float32List _angularVelocity;
  late Float32List _size;
  late Float32List _life;
  late Int32List _colors;
  late List<Float32List> _bucketSegments;

  final Random _rng;
  int _spawnCursor = 0;
  int _activeCount = 0;
  double _lastWidth = 400.0;
  double _lastHeight = 300.0;
  bool _isDisposed = false;

  /// Creates a [ZeroConfettiController] with pre-allocated SoA buffers for [capacity] pieces.
  ZeroConfettiController({
    this.capacity = 240,
    Random? random,
  }) : _rng = random ?? Random() {
    final int safeCap = capacity > 0 ? capacity : 0;
    _x = Float32List(safeCap);
    _y = Float32List(safeCap);
    _vx = Float32List(safeCap);
    _vy = Float32List(safeCap);
    _angle = Float32List(safeCap);
    _angularVelocity = Float32List(safeCap);
    _size = Float32List(safeCap);
    _life = Float32List(safeCap);
    _colors = Int32List(safeCap);
    _initBuckets(safeCap);
  }

  void _initBuckets(int safeCap) {
    final int perBucket = (safeCap + paletteCount - 1) ~/ paletteCount;
    _bucketSegments = List<Float32List>.generate(
      paletteCount,
      (_) => Float32List(perBucket * 4),
      growable: false,
    );
    for (int i = 0; i < safeCap; i++) {
      final int b = i % paletteCount;
      _colors[i] = paletteColors[b].toARGB32();
      _hideSegment(i);
    }
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Number of currently active confetti pieces (`life > 0`).
  int get activeCount => _isDisposed ? 0 : _activeCount;

  /// X positions of confetti pieces.
  Float32List get x => _isDisposed ? _emptyFloat32 : _x;

  /// Y positions of confetti pieces.
  Float32List get y => _isDisposed ? _emptyFloat32 : _y;

  /// Horizontal velocities of confetti pieces.
  Float32List get vx => _isDisposed ? _emptyFloat32 : _vx;

  /// Vertical velocities of confetti pieces.
  Float32List get vy => _isDisposed ? _emptyFloat32 : _vy;

  /// Rotation angles (radians) of confetti pieces.
  Float32List get angle => _isDisposed ? _emptyFloat32 : _angle;

  /// Angular velocities (radians/s) of confetti pieces.
  Float32List get angularVelocity => _isDisposed ? _emptyFloat32 : _angularVelocity;

  /// Ribbon half-lengths of confetti pieces.
  Float32List get size => _isDisposed ? _emptyFloat32 : _size;

  /// Remaining normalized life (`1.0` down to `0.0`) of confetti pieces.
  Float32List get life => _isDisposed ? _emptyFloat32 : _life;

  /// ARGB32 color values of confetti pieces.
  Int32List get colors => _isDisposed ? _emptyInt32 : _colors;

  /// Returns the pre-allocated line-segment buffer (`[x0, y0, x1, y1, ...]`) for [bucketIndex].
  Float32List bucketSegments(int bucketIndex) {
    if (_isDisposed || bucketIndex < 0 || bucketIndex >= paletteCount) {
      return _emptyFloat32;
    }
    return _bucketSegments[bucketIndex];
  }

  /// Spawns [count] confetti pieces bursting outward from [origin].
  ///
  /// If [origin] is omitted, bursts from the center of the last known canvas bounds.
  void burst({Offset? origin, int count = 60}) {
    if (_isDisposed || capacity <= 0 || count <= 0) return;
    final double ox = origin != null ? origin.dx : _lastWidth * 0.5;
    final double oy = origin != null ? origin.dy : _lastHeight * 0.35;
    final int spawnTotal = count < capacity ? count : capacity;

    for (int n = 0; n < spawnTotal; n++) {
      _spawnSinglePiece(_spawnCursor, ox, oy);
      _spawnCursor = (_spawnCursor + 1) % capacity;
    }
    _recountActive();
    notifyListeners();
  }

  void _spawnSinglePiece(int idx, double ox, double oy) {
    final double theta = -pi * 0.15 - _rng.nextDouble() * pi * 0.7;
    final double speed = 140.0 + _rng.nextDouble() * 280.0;
    _x[idx] = ox;
    _y[idx] = oy;
    _vx[idx] = cos(theta) * speed + (_rng.nextDouble() - 0.5) * 90.0;
    _vy[idx] = sin(theta) * speed;
    _angle[idx] = _rng.nextDouble() * pi * 2.0;
    _angularVelocity[idx] = (_rng.nextDouble() - 0.5) * 14.0;
    _size[idx] = 4.0 + _rng.nextDouble() * 4.5;
    _life[idx] = 0.85 + _rng.nextDouble() * 0.45;
    _updateSegmentGeometry(idx);
  }

  void _recountActive() {
    int alive = 0;
    for (int i = 0; i < capacity; i++) {
      if (_life[i] > 0.0) alive++;
    }
    _activeCount = alive;
  }

  /// Advances confetti physics by [dt] seconds with gravity, air drag, flutter, and rotation.
  void step({
    required double dt,
    required double width,
    required double height,
    double gravity = 320.0,
    double drag = 0.985,
  }) {
    if (_isDisposed || capacity <= 0) return;
    if (width > 0) _lastWidth = width;
    if (height > 0) _lastHeight = height;
    if (_activeCount <= 0) return;

    int alive = 0;
    final double decay = dt * 0.55;
    final double gravDt = gravity * dt;

    for (int i = 0; i < capacity; i++) {
      if (_stepSinglePiece(i, dt, gravDt, drag, decay)) {
        alive++;
      }
    }
    _activeCount = alive;
  }

  bool _stepSinglePiece(
    int i,
    double dt,
    double gravDt,
    double drag,
    double decay,
  ) {
    final double currentLife = _life[i];
    if (currentLife <= 0.0) return false;

    final double nextLife = currentLife - decay;
    if (nextLife <= 0.0) {
      _life[i] = 0.0;
      _hideSegment(i);
      return false;
    }

    _life[i] = nextLife;
    final double nextAngle = _angle[i] + _angularVelocity[i] * dt;
    _angle[i] = nextAngle;

    final double flutter = sin(nextAngle * 2.0) * 18.0 * dt;
    final double vxNext = (_vx[i] + flutter) * drag;
    final double vyNext = (_vy[i] + gravDt) * drag;
    _vx[i] = vxNext;
    _vy[i] = vyNext;
    _x[i] += vxNext * dt;
    _y[i] += vyNext * dt;

    _updateSegmentGeometry(i);
    return true;
  }

  void _updateSegmentGeometry(int i) {
    final int b = i % paletteCount;
    final int base = (i ~/ paletteCount) << 2;
    final Float32List segs = _bucketSegments[b];

    final double ang = _angle[i];
    final double halfLen = _size[i];
    final double dx = cos(ang) * halfLen;
    final double dy = sin(ang) * halfLen;
    final double cx = _x[i];
    final double cy = _y[i];

    segs[base] = cx - dx;
    segs[base + 1] = cy - dy;
    segs[base + 2] = cx + dx;
    segs[base + 3] = cy + dy;
  }

  void _hideSegment(int i) {
    final int b = i % paletteCount;
    final int base = (i ~/ paletteCount) << 2;
    final Float32List segs = _bucketSegments[b];
    segs[base] = -1000.0;
    segs[base + 1] = -1000.0;
    segs[base + 2] = -1000.0;
    segs[base + 3] = -1000.0;
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _activeCount = 0;
    _x = _emptyFloat32;
    _y = _emptyFloat32;
    _vx = _emptyFloat32;
    _vy = _emptyFloat32;
    _angle = _emptyFloat32;
    _angularVelocity = _emptyFloat32;
    _size = _emptyFloat32;
    _life = _emptyFloat32;
    _colors = _emptyInt32;
    super.dispose();
  }
}

/// A zero-allocation, physics-driven confetti burst widget.
///
/// Steps [ZeroConfettiController] on VSync ticks while particles are active and
/// batch-draws oriented confetti ribbons via [Canvas.drawRawPoints] (`PointMode.lines`)
/// without any per-frame object allocations or widget rebuilds.
class ZConfetti extends ZLeafWidget<RenderZConfetti> {
  /// The controller managing the confetti SoA buffers and bursts.
  final ZeroConfettiController controller;

  /// Whether the confetti simulation is active.
  final bool isRunning;

  /// Stroke thickness of each confetti ribbon in logical pixels.
  final double ribbonThickness;

  const ZConfetti({
    super.key,
    required this.controller,
    this.isRunning = true,
    this.ribbonThickness = 3.5,
  });

  @override
  RenderZConfetti createRenderObject(BuildContext context) {
    return RenderZConfetti(
      controller: controller,
      isRunning: isRunning,
      ribbonThickness: ribbonThickness,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZConfetti renderObject) {
    renderObject
      ..controller = controller
      ..isRunning = isRunning
      ..ribbonThickness = ribbonThickness;
  }
}

/// Backward compatibility alias for [ZConfetti].
@Deprecated('Use ZConfetti instead.')
typedef ZeroConfetti = ZConfetti;

/// Internal RenderBox for [ZConfetti] performing batched zero-allocation confetti rendering.
class RenderZConfetti extends ZeroRenderBox {
  ZeroConfettiController _controller;
  bool _isRunning;
  double _ribbonThickness;

  final Paint _ribbonPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;

  Duration _lastElapsed = Duration.zero;

  RenderZConfetti({
    required ZeroConfettiController controller,
    required bool isRunning,
    required double ribbonThickness,
  })  : _controller = controller,
        _isRunning = isRunning,
        _ribbonThickness = ribbonThickness,
        super(animatePerFrame: isRunning) {
    _ribbonPaint.strokeWidth = _ribbonThickness;
  }

  ZeroConfettiController get controller => _controller;
  set controller(ZeroConfettiController value) {
    if (_controller == value) return;
    if (attached) {
      _controller.removeListener(_onControllerBurst);
      value.addListener(_onControllerBurst);
    }
    _controller = value;
    _onControllerBurst();
  }

  bool get isRunning => _isRunning;
  set isRunning(bool value) {
    if (_isRunning == value) return;
    _isRunning = value;
    animatePerFrame = value;
    markDirty();
  }

  double get ribbonThickness => _ribbonThickness;
  set ribbonThickness(double value) {
    if (_ribbonThickness == value) return;
    _ribbonThickness = value;
    _ribbonPaint.strokeWidth = value;
    markDirty();
  }

  void _onControllerBurst() {
    if (_isRunning && !_controller.isDisposed) {
      animatePerFrame = true;
    }
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(_onControllerBurst);
  }

  @override
  void detach() {
    _controller.removeListener(_onControllerBurst);
    _lastElapsed = Duration.zero;
    super.detach();
  }

  @override
  bool onFrameTick(Duration elapsed) {
    if (!_isRunning || _controller.isDisposed) return false;
    final double dt = _calculateDeltaSeconds(elapsed);
    _lastElapsed = elapsed;

    final double renderW = size.width > 0 ? size.width : 400.0;
    final double renderH = size.height > 0 ? size.height : 300.0;

    if (_controller.activeCount <= 0) {
      return false;
    }

    _controller.step(
      dt: dt,
      width: renderW,
      height: renderH,
    );
    return true;
  }

  double _calculateDeltaSeconds(Duration elapsed) {
    if (_lastElapsed == Duration.zero) return 1.0 / 60.0;
    final int microDelta = (elapsed - _lastElapsed).inMicroseconds;
    if (microDelta <= 0) return 1.0 / 60.0;
    final double dt = microDelta / 1000000.0;
    return dt > 0.1 ? 0.1 : dt;
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    if (_controller.isDisposed || _controller.activeCount <= 0) return;

    final Canvas canvas = context.canvas;
    canvas.save();
    canvas.clipRect(offset & size);
    if (offset != Offset.zero) {
      canvas.translate(offset.dx, offset.dy);
    }

    for (int b = 0; b < ZeroConfettiController.paletteCount; b++) {
      _ribbonPaint.color = ZeroConfettiController.paletteColors[b];
      canvas.drawRawPoints(
        PointMode.lines,
        _controller.bucketSegments(b),
        _ribbonPaint,
      );
    }

    canvas.restore();
  }
}
