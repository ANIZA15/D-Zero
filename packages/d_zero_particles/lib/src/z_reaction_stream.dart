import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active alias for [ZReactionStream].
typedef ZFloatingHearts = ZReactionStream;

/// Legacy alias for [ZReactionStream].
@Deprecated('Use ZReactionStream instead.')
typedef ZeroReactionStream = ZReactionStream;

/// Zero-allocation SoA controller for [ZReactionStream] managing floating
/// reaction particles (`x, y, vy, phase, life`) in contiguous `Float32List` arrays.
class ZeroReactionController extends ChangeNotifier {
  final int _capacity;
  late final Float32List _x;
  late final Float32List _y;
  late final Float32List _vy;
  late final Float32List _phase;
  late final Float32List _life;
  late final Uint8List _paletteIdx;
  int _writeCursor = 0;
  int _activeCount = 0;
  bool _isDisposed = false;
  final math.Random _rng;

  /// Creates a [ZeroReactionController] with fixed [capacity].
  ZeroReactionController({int capacity = 128, math.Random? random})
      : _capacity = capacity.clamp(8, 2048),
        _rng = random ?? math.Random(101) {
    _x = Float32List(_capacity);
    _y = Float32List(_capacity);
    _vy = Float32List(_capacity);
    _phase = Float32List(_capacity);
    _life = Float32List(_capacity);
    _paletteIdx = Uint8List(_capacity);
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  @override
  bool get hasListeners => !_isDisposed && super.hasListeners;

  /// Maximum reaction particle capacity.
  int get capacity => _capacity;

  /// Current active floating reaction count (`0` if disposed).
  int get activeCount => _isDisposed ? 0 : _activeCount;

  /// Emits [count] floating reactions from normalized `(originX, originY)` (`0.0 .. 1.0`).
  void emit({int count = 4, double originX = 0.85, double originY = 0.92}) {
    if (_isDisposed) return;
    final int spawnCount = count.clamp(1, _capacity);
    for (int i = 0; i < spawnCount; i++) {
      final int slot = _writeCursor;
      _writeCursor = (_writeCursor + 1) % _capacity;
      _x[slot] = (originX + (_rng.nextDouble() - 0.5) * 0.14).clamp(0.05, 0.95);
      _y[slot] = (originY + (_rng.nextDouble() - 0.5) * 0.06).clamp(0.1, 0.98);
      _vy[slot] = 0.32 + _rng.nextDouble() * 0.38;
      _phase[slot] = _rng.nextDouble() * math.pi * 2.0;
      _life[slot] = 1.0;
      _paletteIdx[slot] = slot & 3;
    }
    _recountActive();
    notifyListeners();
  }

  void _recountActive() {
    int count = 0;
    for (int i = 0; i < _capacity; i++) {
      if (_life[i] > 0.0) count++;
    }
    _activeCount = count;
  }

  /// Steps upward buoyancy and sine-wave horizontal sway in place for [dt] seconds.
  void step(double dt) {
    if (_isDisposed) return;
    int alive = 0;
    for (int i = 0; i < _capacity; i++) {
      final double l = _life[i];
      if (l <= 0.0) continue;
      final double nextLife = l - dt * 0.55;
      if (nextLife <= 0.0) {
        _life[i] = 0.0;
        continue;
      }
      _life[i] = nextLife;
      _phase[i] += dt * 4.5;
      _y[i] -= _vy[i] * dt;
      _x[i] = (_x[i] + math.sin(_phase[i]) * 0.12 * dt).clamp(0.04, 0.96);
      alive++;
    }
    _activeCount = alive;
  }

  /// Reads normalized X (`0.0 .. 1.0`) at [slot].
  double xAt(int slot) => (_isDisposed || slot < 0 || slot >= _capacity) ? 0.0 : _x[slot];

  /// Reads normalized Y (`0.0 .. 1.0`) at [slot].
  double yAt(int slot) => (_isDisposed || slot < 0 || slot >= _capacity) ? 0.0 : _y[slot];

  /// Reads life (`0.0 .. 1.0`) at [slot].
  double lifeAt(int slot) =>
      (_isDisposed || slot < 0 || slot >= _capacity) ? 0.0 : _life[slot];

  /// Reads palette index (`0..3`) at [slot].
  int paletteAt(int slot) =>
      (_isDisposed || slot < 0 || slot >= _capacity) ? 0 : _paletteIdx[slot];

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
    _activeCount = 0;
    _life.fillRange(0, _life.length, 0.0);
    super.dispose();
  }
}

/// A zero-allocation live-stream floating hearts / reaction burst widget
/// (Instagram Live / TikTok Live / YouTube Live reaction stream).
///
/// Steps SoA buoyancy physics and batches particles into 4 palette point buffers
/// flushed via `Canvas.drawRawPoints` with 0 widget rebuilds.
class ZReactionStream extends ZLeafWidget<RenderZReactionStream> {
  /// Controller managing active reaction particles.
  final ZeroReactionController controller;

  /// Whether to step physics automatically every V-Sync frame.
  final bool isRunning;

  /// Preferred widget size.
  final Size size;

  /// Creates a const [ZReactionStream].
  const ZReactionStream({
    super.key,
    required this.controller,
    this.isRunning = true,
    this.size = const Size(120.0, 160.0),
  });

  @override
  RenderZReactionStream createRenderObject(BuildContext context) {
    return RenderZReactionStream(
      controller: controller,
      isRunning: isRunning,
      preferredSize: size,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZReactionStream renderObject,
  ) {
    renderObject
      ..controller = controller
      ..isRunning = isRunning
      ..preferredSize = size;
  }
}

/// Custom [ZeroRenderBox] for [ZReactionStream].
class RenderZReactionStream extends ZeroRenderBox {
  ZeroReactionController _controller;
  bool _isRunning;
  Size _preferredSize;
  Duration? _lastElapsed;
  late Float32List _batchCoords;

  static const List<Color> _colors = <Color>[
    Color(0xFFFF1744),
    Color(0xFFFF4081),
    Color(0xFFFFB300),
    Color(0xFF00E5FF),
  ];

  late final List<Paint> _paints;

  /// Creates a [RenderZReactionStream].
  RenderZReactionStream({
    required ZeroReactionController controller,
    required bool isRunning,
    required Size preferredSize,
  })  : _controller = controller,
        _isRunning = isRunning,
        _preferredSize = preferredSize,
        _batchCoords = Float32List(controller.capacity * 2),
        super(animatePerFrame: isRunning) {
    _paints = List<Paint>.generate(_colors.length, (i) {
      return Paint()
        ..color = _colors[i]
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 9.0;
    }, growable: false);
  }

  /// Reaction controller.
  ZeroReactionController get controller => _controller;
  set controller(ZeroReactionController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _controller = value;
    if (_batchCoords.length < value.capacity * 2) {
      _batchCoords = Float32List(value.capacity * 2);
    }
    markDirty();
  }

  /// Whether per-frame stepping is active.
  bool get isRunning => _isRunning;
  set isRunning(bool value) {
    if (_isRunning == value) return;
    _isRunning = value;
    animatePerFrame = value;
    markDirty();
  }

  /// Preferred size.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(markDirty);
  }

  @override
  void detach() {
    _controller.removeListener(markDirty);
    _lastElapsed = null;
    super.detach();
  }

  @override
  void onZeroFrame(Duration elapsed) {
    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    final double dt = prev == null
        ? 0.016
        : ((elapsed - prev).inMicroseconds / 1000000.0).clamp(0.001, 0.05);
    _controller.step(dt);
    markDirty();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent && size.width > 0 && size.height > 0) {
      _controller.emit(
        count: 6,
        originX: event.localPosition.dx / size.width,
        originY: event.localPosition.dy / size.height,
      );
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
    final int cap = _controller.capacity;

    for (int p = 0; p < 4; p++) {
      int count = 0;
      for (int i = 0; i < cap; i++) {
        if (_controller.lifeAt(i) <= 0.0 || _controller.paletteAt(i) != p) {
          continue;
        }
        _batchCoords[count * 2] = offset.dx + _controller.xAt(i) * size.width;
        _batchCoords[count * 2 + 1] = offset.dy + _controller.yAt(i) * size.height;
        count++;
      }
      if (count > 0) {
        canvas.drawRawPoints(
          ui.PointMode.points,
          Float32List.sublistView(_batchCoords, 0, count * 2),
          _paints[p],
        );
      }
    }
  }
}
