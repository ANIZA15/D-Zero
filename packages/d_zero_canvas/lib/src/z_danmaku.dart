import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active Z-prefixed alias for [ZDanmaku].
typedef ZChatStream = ZDanmaku;

/// Deprecated legacy alias for [ZDanmaku].
@Deprecated('Use ZDanmaku instead.')
typedef ZeroDanmaku = ZDanmaku;

/// Fixed-capacity Structure-of-Arrays (SoA) controller for bullet comments (danmaku).
///
/// Pools up to [capacity] concurrent comments using contiguous [Float32List] arrays
/// (`x`, `y`, `speed`, `width`) and pre-allocated [TextPainter] slots so that
/// stepping and rendering frames allocate 0 widgets and 0 heap objects per frame.
class ZeroDanmakuController {
  /// Maximum number of simultaneous active bullet comments.
  final int capacity;

  /// Default text style applied to emitted bullet comments.
  final TextStyle textStyle;

  final Float32List _x;
  final Float32List _y;
  final Float32List _speed;
  final Float32List _width;
  final Uint8List _active;
  final List<TextPainter> _painters;
  final ZeroIntNotifier _revision = ZeroIntNotifier(0);

  int _writeCursor = 0;
  int _laneCursor = 0;
  int _activeCount = 0;
  double _viewportWidth = 360.0;
  double _viewportHeight = 200.0;
  bool _isDisposed = false;

  /// Creates a [ZeroDanmakuController] with a fixed [capacity] (default 64).
  ZeroDanmakuController({
    this.capacity = 64,
    this.textStyle = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 14.0,
      fontWeight: FontWeight.w600,
    ),
  })  : assert(capacity > 0),
        _x = Float32List(capacity),
        _y = Float32List(capacity),
        _speed = Float32List(capacity),
        _width = Float32List(capacity),
        _active = Uint8List(capacity),
        _painters = List<TextPainter>.generate(
          capacity,
          (_) => TextPainter(textDirection: TextDirection.ltr),
          growable: false,
        );

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Number of currently active bullet comments on screen.
  int get activeCount => _isDisposed ? 0 : _activeCount;

  /// Registers a listener notified when comments are emitted or cleared.
  void addListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.addListener(listener);
  }

  /// Removes a previously registered listener.
  void removeListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.removeListener(listener);
  }

  /// Updates the viewport dimensions used to spawn new comments at the right edge.
  void configureViewport(double width, double height) {
    if (_isDisposed) return;
    if (width > 0.0) _viewportWidth = width;
    if (height > 0.0) _viewportHeight = height;
  }

  /// Emits a new bullet comment [text] moving from right to left at [speed] px/s.
  void emit(String text, {double speed = 120.0}) {
    if (_isDisposed || text.isEmpty) return;
    final int slot = _writeCursor;
    _writeCursor = (slot + 1) % capacity;

    final TextPainter tp = _painters[slot]
      ..text = TextSpan(text: text, style: textStyle)
      ..layout();

    if (_active[slot] == 0) {
      _active[slot] = 1;
      _activeCount++;
    }

    final int laneCount = (_viewportHeight ~/ 24.0).clamp(1, 16);
    final int lane = _laneCursor % laneCount;
    _laneCursor++;

    _x[slot] = _viewportWidth;
    _y[slot] = 8.0 + lane * 24.0;
    _speed[slot] = speed;
    _width[slot] = tp.width;
    _revision.add(1);
  }

  /// Steps all active bullet comments by [dt] seconds.
  /// Returns `true` if any comment was active during this step.
  bool step(double dt) {
    if (_isDisposed || _activeCount == 0 || dt <= 0.0) return false;
    for (int i = 0; i < capacity; i++) {
      if (_active[i] != 0) {
        _stepSlot(i, dt);
      }
    }
    return true;
  }

  void _stepSlot(int index, double dt) {
    final double nextX = _x[index] - _speed[index] * dt;
    if (nextX + _width[index] < 0.0) {
      _active[index] = 0;
      _activeCount--;
    } else {
      _x[index] = nextX;
    }
  }

  /// Returns whether slot [index] is currently active.
  bool isActiveAt(int index) {
    if (_isDisposed || index < 0 || index >= capacity) return false;
    return _active[index] != 0;
  }

  /// Returns the X coordinate of slot [index].
  double xAt(int index) {
    if (_isDisposed || index < 0 || index >= capacity) return 0.0;
    return _x[index];
  }

  /// Returns the Y coordinate of slot [index].
  double yAt(int index) {
    if (_isDisposed || index < 0 || index >= capacity) return 0.0;
    return _y[index];
  }

  /// Paints active slot [index] onto [canvas] shifted by [offset].
  void paintSlot(Canvas canvas, Offset offset, int index) {
    if (!isActiveAt(index)) return;
    _painters[index].paint(
      canvas,
      Offset(offset.dx + _x[index], offset.dy + _y[index]),
    );
  }

  /// Clears all active bullet comments immediately.
  void clear() {
    if (_isDisposed) return;
    _active.fillRange(0, capacity, 0);
    _activeCount = 0;
    _writeCursor = 0;
    _revision.add(1);
  }

  /// Disposes all pooled [TextPainter] instances and listeners (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _activeCount = 0;
    for (int i = 0; i < capacity; i++) {
      _painters[i].dispose();
    }
    _revision.dispose();
  }
}

/// A zero-allocation live bullet comment (danmaku) stream widget.
///
/// Renders up to [ZeroDanmakuController.capacity] simultaneous scrolling comments
/// inside a single [ZeroRenderBox] without creating per-comment widgets or elements.
class ZDanmaku extends ZLeafWidget<RenderZDanmaku> {
  /// Controller managing the pooled SoA bullet comments.
  final ZeroDanmakuController controller;

  /// Target size of the danmaku overlay canvas.
  final Size size;

  /// Optional background color of the overlay stage.
  final Color backgroundColor;

  /// Creates a const [ZDanmaku] widget.
  const ZDanmaku({
    super.key,
    required this.controller,
    this.size = const Size(360.0, 180.0),
    this.backgroundColor = const Color(0xFF0F172A),
  });

  @override
  RenderZDanmaku createRenderObject(BuildContext context) {
    return RenderZDanmaku(
      controller: controller,
      boxSize: size,
      backgroundColor: backgroundColor,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZDanmaku renderObject) {
    renderObject
      ..controller = controller
      ..boxSize = size
      ..backgroundColor = backgroundColor;
  }
}

/// RenderBox for [ZDanmaku] that steps and draws pooled bullet comments at 120fps.
class RenderZDanmaku extends ZeroRenderBox {
  ZeroDanmakuController _controller;
  Size _boxSize;
  Color _backgroundColor;
  Duration? _lastElapsed;

  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;

  /// Creates a [RenderZDanmaku].
  RenderZDanmaku({
    required ZeroDanmakuController controller,
    required Size boxSize,
    required Color backgroundColor,
  })  : _controller = controller,
        _boxSize = boxSize,
        _backgroundColor = backgroundColor,
        super(animatePerFrame: true) {
    _bgPaint.color = _backgroundColor;
  }

  /// Active danmaku controller.
  ZeroDanmakuController get controller => _controller;
  set controller(ZeroDanmakuController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(_onControllerUpdated);
    }
    _controller = value;
    if (attached) {
      _controller.addListener(_onControllerUpdated);
    }
    markDirty();
  }

  /// Target size of the danmaku viewport.
  Size get boxSize => _boxSize;
  set boxSize(Size value) {
    if (_boxSize == value) return;
    _boxSize = value;
    markNeedsLayout();
  }

  /// Background color of the danmaku viewport.
  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    _bgPaint.color = value;
    markDirty();
  }

  void _onControllerUpdated() {
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(_onControllerUpdated);
  }

  @override
  void detach() {
    _controller.removeListener(_onControllerUpdated);
    super.detach();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdated);
    super.dispose();
  }

  @override
  bool onFrameTick(Duration elapsed) {
    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    if (prev == null) return _controller.activeCount > 0;
    final int deltaUs = (elapsed - prev).inMicroseconds;
    if (deltaUs <= 0) return false;
    return _controller.step(deltaUs / 1000000.0);
  }

  @override
  void performLayout() {
    size = constraints.constrain(_boxSize);
    _controller.configureViewport(size.width, size.height);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect rect = offset & size;
    canvas.drawRect(rect, _bgPaint);
    if (_controller.activeCount == 0) return;

    canvas.save();
    canvas.clipRect(rect);
    final int cap = _controller.capacity;
    for (int i = 0; i < cap; i++) {
      _controller.paintSlot(canvas, offset, i);
    }
    canvas.restore();
  }
}
