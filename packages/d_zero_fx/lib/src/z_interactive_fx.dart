import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active alias for [ZSwipeDeck].
typedef ZTinderCards = ZSwipeDeck;

/// Legacy alias for [ZSwipeDeck].
@Deprecated('Use ZSwipeDeck instead.')
typedef ZeroSwipeDeck = ZSwipeDeck;

/// Active alias for [ZScratchCard].
typedef ZScratchOff = ZScratchCard;

/// Legacy alias for [ZScratchCard].
@Deprecated('Use ZScratchCard instead.')
typedef ZeroScratchCard = ZScratchCard;

/// Active alias for [ZBeforeAfterSlider].
typedef ZImageComparison = ZBeforeAfterSlider;

/// Legacy alias for [ZBeforeAfterSlider].
@Deprecated('Use ZBeforeAfterSlider instead.')
typedef ZeroBeforeAfterSlider = ZBeforeAfterSlider;

/// Zero-allocation controller for [ZSwipeDeck] managing card index and drag
/// displacement `(dx, dy)` in a `Float32List(2)`.
class ZeroSwipeDeckController extends ChangeNotifier {
  final int _cardCount;
  final Float32List _drag = Float32List(2);
  int _topIndex = 0;
  bool _isDisposed = false;

  /// Creates a [ZeroSwipeDeckController] with [cardCount] cards.
  ZeroSwipeDeckController({int cardCount = 10})
      : _cardCount = math.max(1, cardCount);

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  @override
  bool get hasListeners => !_isDisposed && super.hasListeners;

  /// Total card count.
  int get cardCount => _cardCount;

  /// Current top card index (`0` if disposed).
  int get topIndex => _isDisposed ? 0 : _topIndex;

  /// Horizontal drag offset (`0.0` if disposed).
  double get dragDx => _isDisposed ? 0.0 : _drag[0];

  /// Vertical drag offset (`0.0` if disposed).
  double get dragDy => _isDisposed ? 0.0 : _drag[1];

  /// Updates drag displacement in place.
  void setDrag(double dx, double dy) {
    if (_isDisposed) return;
    _drag[0] = dx.clamp(-160.0, 160.0);
    _drag[1] = dy.clamp(-80.0, 80.0);
    notifyListeners();
  }

  /// Swipes the current top card and advances to the next card.
  void swipeNext() {
    if (_isDisposed) return;
    _topIndex = (_topIndex + 1) % _cardCount;
    _drag[0] = 0.0;
    _drag[1] = 0.0;
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
    _topIndex = 0;
    _drag[0] = 0.0;
    _drag[1] = 0.0;
    super.dispose();
  }
}

/// A zero-allocation Tinder-style swipe card stack widget.
///
/// Renders background card scale, top card rotation, and directional tint
/// inside a single [ZeroRenderBox] without rebuilding card subtrees.
class ZSwipeDeck extends ZLeafWidget<RenderZSwipeDeck> {
  /// Controller holding top card index and drag offset.
  final ZeroSwipeDeckController controller;

  /// Preferred widget size.
  final Size size;

  /// Creates a const [ZSwipeDeck].
  const ZSwipeDeck({
    super.key,
    required this.controller,
    this.size = const Size(160.0, 110.0),
  });

  @override
  RenderZSwipeDeck createRenderObject(BuildContext context) {
    return RenderZSwipeDeck(controller: controller, preferredSize: size);
  }

  @override
  void updateRenderObject(BuildContext context, RenderZSwipeDeck renderObject) {
    renderObject
      ..controller = controller
      ..preferredSize = size;
  }
}

/// Custom [ZeroRenderBox] for [ZSwipeDeck].
class RenderZSwipeDeck extends ZeroRenderBox {
  ZeroSwipeDeckController _controller;
  Size _preferredSize;
  Offset? _dragStart;

  final Paint _backCardPaint = Paint()..color = const Color(0xFF1E293B);
  final Paint _topCardPaint = Paint()..color = const Color(0xFF0F172A);
  final Paint _borderPaint = Paint()
    ..color = const Color(0xFF00E5FF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  final Paint _likePaint = Paint()..color = const Color(0x8800FF88);
  final Paint _nopePaint = Paint()..color = const Color(0x88FF1744);
  final ZeroNumberPainter _cardNumPainter = ZeroNumberPainter(
    style: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: Color(0xFF00E5FF),
      fontFamily: 'monospace',
    ),
  );

  /// Creates a [RenderZSwipeDeck].
  RenderZSwipeDeck({
    required ZeroSwipeDeckController controller,
    required Size preferredSize,
  })  : _controller = controller,
        _preferredSize = preferredSize;

  /// Swipe deck controller.
  ZeroSwipeDeckController get controller => _controller;
  set controller(ZeroSwipeDeckController value) {
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
    _cardNumPainter.dispose();
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      _dragStart = event.localPosition;
    } else if (event is PointerMoveEvent && _dragStart != null) {
      final Offset delta = event.localPosition - _dragStart!;
      _controller.setDrag(delta.dx, delta.dy);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _dragStart = null;
      if (_controller.dragDx.abs() > 36.0) {
        _controller.swipeNext();
      } else {
        _controller.setDrag(0.0, 0.0);
      }
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
    final Rect baseRect = Rect.fromLTWH(
      offset.dx + 14.0,
      offset.dy + 10.0,
      size.width - 28.0,
      size.height - 20.0,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(baseRect.inflate(-4.0), const Radius.circular(10.0)),
      _backCardPaint,
    );

    final double dx = _controller.dragDx;
    final double dy = _controller.dragDy;
    final Offset center = baseRect.center + Offset(dx * 0.35, dy * 0.25);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(dx * 0.0025);
    final Rect cardLocal = Rect.fromCenter(
      center: Offset.zero,
      width: baseRect.width,
      height: baseRect.height,
    );
    final RRect rrect = RRect.fromRectAndRadius(cardLocal, const Radius.circular(10.0));
    canvas.drawRRect(rrect, _topCardPaint);
    if (dx.abs() > 8.0) {
      canvas.drawRRect(rrect, dx > 0 ? _likePaint : _nopePaint);
    }
    canvas.drawRRect(rrect, _borderPaint);
    _cardNumPainter.paintInt(
      canvas,
      Offset(-_cardNumPainter.maxDigitWidth, -_cardNumPainter.height * 0.5),
      _controller.topIndex + 1,
      minDigits: 2,
    );
    canvas.restore();
  }
}

/// Zero-allocation controller for [ZScratchCard] tracking scratched grid cells
/// in a compact `Uint8List` without `saveLayer` or growing `Path` objects.
class ZeroScratchCardController extends ChangeNotifier {
  final int _cols;
  final int _rows;
  late final Uint8List _scratched;
  int _scratchedCount = 0;
  bool _isDisposed = false;

  /// Creates a [ZeroScratchCardController] with [cols] × [rows] scratch cells.
  ZeroScratchCardController({int cols = 12, int rows = 8})
      : _cols = cols.clamp(4, 32),
        _rows = rows.clamp(4, 32) {
    _scratched = Uint8List(_cols * _rows);
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  @override
  bool get hasListeners => !_isDisposed && super.hasListeners;

  /// Number of columns.
  int get cols => _cols;

  /// Number of rows.
  int get rows => _rows;

  /// Scratched completion percentage (`0.0 .. 100.0`, or `0.0` if disposed).
  double get scratchPercent {
    if (_isDisposed) return 0.0;
    return (_scratchedCount / (_cols * _rows)) * 100.0;
  }

  /// Checks if cell `(col, row)` is scratched.
  bool isScratched(int col, int row) {
    if (_isDisposed || col < 0 || col >= _cols || row < 0 || row >= _rows) {
      return false;
    }
    return _scratched[row * _cols + col] != 0;
  }

  /// Scratches cell at normalized coordinates `(nx, ny)` in `0.0 .. 1.0`.
  void scratchAtNormalized(double nx, double ny) {
    if (_isDisposed) return;
    final int c = (nx * _cols).floor().clamp(0, _cols - 1);
    final int r = (ny * _rows).floor().clamp(0, _rows - 1);
    final int idx = r * _cols + c;
    if (_scratched[idx] != 0) return;
    _scratched[idx] = 1;
    _scratchedCount++;
    notifyListeners();
  }

  /// Resets the scratch foil.
  void reset() {
    if (_isDisposed || _scratchedCount == 0) return;
    _scratched.fillRange(0, _scratched.length, 0);
    _scratchedCount = 0;
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
    _scratchedCount = 0;
    _scratched.fillRange(0, _scratched.length, 0);
    super.dispose();
  }
}

/// A zero-`saveLayer`, zero-allocation scratch-off lottery / coupon card widget.
///
/// Renders prize layer, remaining foil cells, and live scratched percentage
/// via [ZeroNumberPainter] without `BlendMode.clear` offscreen buffers.
class ZScratchCard extends ZLeafWidget<RenderZScratchCard> {
  /// Controller tracking scratched cells.
  final ZeroScratchCardController controller;

  /// Preferred widget size.
  final Size size;

  /// Creates a const [ZScratchCard].
  const ZScratchCard({
    super.key,
    required this.controller,
    this.size = const Size(160.0, 96.0),
  });

  @override
  RenderZScratchCard createRenderObject(BuildContext context) {
    return RenderZScratchCard(controller: controller, preferredSize: size);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZScratchCard renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size;
  }
}

/// Custom [ZeroRenderBox] for [ZScratchCard].
class RenderZScratchCard extends ZeroRenderBox {
  ZeroScratchCardController _controller;
  Size _preferredSize;

  final Paint _prizePaint = Paint()..color = const Color(0xFF0B2922);
  final Paint _foilPaint = Paint()..color = const Color(0xFF475569);
  final ZeroNumberPainter _pctPainter = ZeroNumberPainter(
    style: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: Color(0xFF00FF88),
      fontFamily: 'monospace',
    ),
  );

  /// Creates a [RenderZScratchCard].
  RenderZScratchCard({
    required ZeroScratchCardController controller,
    required Size preferredSize,
  })  : _controller = controller,
        _preferredSize = preferredSize;

  /// Scratch card controller.
  ZeroScratchCardController get controller => _controller;
  set controller(ZeroScratchCardController value) {
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
    _pctPainter.dispose();
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if ((event is PointerDownEvent || event is PointerMoveEvent) &&
        size.width > 0 &&
        size.height > 0) {
      _controller.scratchAtNormalized(
        event.localPosition.dx / size.width,
        event.localPosition.dy / size.height,
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
    final Rect bounds = offset & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(10.0)),
      _prizePaint,
    );

    _pctPainter.paintPercent(
      canvas,
      Offset(
        offset.dx + (size.width - _pctPainter.maxDigitWidth * 4.5) * 0.5,
        offset.dy + (size.height - _pctPainter.height) * 0.5,
      ),
      _controller.scratchPercent,
      fractionDigits: 0,
    );

    final int cols = _controller.cols;
    final int rows = _controller.rows;
    final double cw = size.width / cols;
    final double ch = size.height / rows;

    for (int r = 0; r < rows; r++) {
      final double y = offset.dy + r * ch;
      for (int c = 0; c < cols; c++) {
        if (_controller.isScratched(c, r)) continue;
        canvas.drawRect(Rect.fromLTWH(offset.dx + c * cw, y, cw + 0.5, ch + 0.5), _foilPaint);
      }
    }
  }
}

/// A zero-allocation before/after split comparison slider widget.
///
/// Updates the split curtain position via `Canvas.clipRect` and [ZeroNumberPainter]
/// on pointer drag without rebuilding widget subtrees.
class ZBeforeAfterSlider extends ZLeafWidget<RenderZBeforeAfterSlider> {
  /// Split ratio listenable (`0.0 .. 1.0`).
  final ValueListenable<double> splitListenable;

  /// Optional mutable split ratio controller updated on pointer drag.
  final ValueNotifier<double>? controller;

  /// Preferred widget size.
  final Size size;

  /// Left ("Before") surface color.
  final Color beforeColor;

  /// Right ("After") surface color.
  final Color afterColor;

  /// Creates a const [ZBeforeAfterSlider].
  const ZBeforeAfterSlider({
    super.key,
    required this.splitListenable,
    this.controller,
    this.size = const Size(160.0, 96.0),
    this.beforeColor = const Color(0xFF1E293B),
    this.afterColor = const Color(0xFF004D40),
  });

  @override
  RenderZBeforeAfterSlider createRenderObject(BuildContext context) {
    return RenderZBeforeAfterSlider(
      splitListenable: splitListenable,
      controller: controller,
      preferredSize: size,
      beforeColor: beforeColor,
      afterColor: afterColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZBeforeAfterSlider renderObject,
  ) {
    renderObject
      ..splitListenable = splitListenable
      ..controller = controller
      ..preferredSize = size
      ..beforeColor = beforeColor
      ..afterColor = afterColor;
  }
}

/// Custom [ZeroRenderBox] for [ZBeforeAfterSlider].
class RenderZBeforeAfterSlider extends ZeroRenderBox {
  ValueListenable<double> _splitListenable;

  /// Optional mutable split ratio notifier.
  ValueNotifier<double>? controller;

  Size _preferredSize;
  final Paint _beforePaint = Paint()..style = PaintingStyle.fill;
  final Paint _afterPaint = Paint()..style = PaintingStyle.fill;
  final Paint _dividerPaint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..strokeWidth = 2.0;
  final ZeroNumberPainter _pctPainter = ZeroNumberPainter();

  /// Creates a [RenderZBeforeAfterSlider].
  RenderZBeforeAfterSlider({
    required ValueListenable<double> splitListenable,
    required this.controller,
    required Size preferredSize,
    required Color beforeColor,
    required Color afterColor,
  })  : _splitListenable = splitListenable,
        _preferredSize = preferredSize {
    _beforePaint.color = beforeColor;
    _afterPaint.color = afterColor;
  }

  /// Split ratio listenable.
  ValueListenable<double> get splitListenable => _splitListenable;
  set splitListenable(ValueListenable<double> value) {
    if (identical(_splitListenable, value)) return;
    if (attached) {
      _splitListenable.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _splitListenable = value;
    markDirty();
  }

  /// Preferred size.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// Before side color.
  Color get beforeColor => _beforePaint.color;
  set beforeColor(Color value) {
    if (_beforePaint.color == value) return;
    _beforePaint.color = value;
    markDirty();
  }

  /// After side color.
  Color get afterColor => _afterPaint.color;
  set afterColor(Color value) {
    if (_afterPaint.color == value) return;
    _afterPaint.color = value;
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _splitListenable.addListener(markDirty);
  }

  @override
  void detach() {
    _splitListenable.removeListener(markDirty);
    super.detach();
  }

  @override
  void dispose() {
    _pctPainter.dispose();
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if ((event is PointerDownEvent || event is PointerMoveEvent) &&
        size.width > 0) {
      final double ratio = (event.localPosition.dx / size.width).clamp(0.05, 0.95);
      controller?.value = ratio;
      markDirty();
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
    final double ratio = _splitListenable.value.clamp(0.0, 1.0);
    final double splitX = offset.dx + size.width * ratio;

    canvas.drawRect(bounds, _afterPaint);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(offset.dx, offset.dy, size.width * ratio, size.height));
    canvas.drawRect(bounds, _beforePaint);
    canvas.restore();

    canvas.drawLine(
      Offset(splitX, offset.dy),
      Offset(splitX, offset.dy + size.height),
      _dividerPaint,
    );
    canvas.drawCircle(
      Offset(splitX, offset.dy + size.height * 0.5),
      9.0,
      _dividerPaint,
    );
    _pctPainter.paintPercent(
      canvas,
      Offset(offset.dx + 6.0, offset.dy + 6.0),
      ratio * 100.0,
      fractionDigits: 0,
    );
  }
}
