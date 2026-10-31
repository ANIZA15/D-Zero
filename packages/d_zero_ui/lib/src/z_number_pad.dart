import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active alias for [ZNumberPad].
typedef ZPinPad = ZNumberPad;

/// Legacy alias for [ZNumberPad].
@Deprecated('Use ZNumberPad instead.')
typedef ZeroNumberPad = ZNumberPad;

/// Zero-allocation controller for [ZNumberPad] storing integer value and digit count
/// without creating intermediate strings on each key press.
class ZeroNumberPadController extends ChangeNotifier {
  final int _maxDigits;
  int _value = 0;
  int _digitCount = 0;
  bool _isDisposed = false;

  /// Creates a [ZeroNumberPadController] with [maxDigits] capacity.
  ZeroNumberPadController({int maxDigits = 6, int initialValue = 0})
      : _maxDigits = maxDigits.clamp(1, 9) {
    if (initialValue > 0) {
      _value = initialValue;
      _digitCount = _countDigits(initialValue);
    }
  }

  static int _countDigits(int v) {
    int count = 0;
    int temp = v.abs();
    while (temp > 0) {
      temp ~/= 10;
      count++;
    }
    return count;
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Maximum allowed digits.
  int get maxDigits => _maxDigits;

  /// Current integer value (`0` if disposed).
  int get value => _isDisposed ? 0 : _value;

  /// Current number of entered digits (`0` if disposed).
  int get digitCount => _isDisposed ? 0 : _digitCount;

  /// Appends a single digit (`0..9`).
  void inputDigit(int digit) {
    if (_isDisposed || _digitCount >= _maxDigits) return;
    final int d = digit.clamp(0, 9);
    _value = _value * 10 + d;
    _digitCount++;
    notifyListeners();
  }

  /// Removes the last entered digit.
  void backspace() {
    if (_isDisposed || _digitCount <= 0) return;
    _value ~/= 10;
    _digitCount--;
    notifyListeners();
  }

  /// Clears all entered digits.
  void clear() {
    if (_isDisposed || (_value == 0 && _digitCount == 0)) return;
    _value = 0;
    _digitCount = 0;
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
    _value = 0;
    _digitCount = 0;
    super.dispose();
  }
}

/// A zero-allocation `3×4` numeric keypad & PIN pad widget.
///
/// Renders the entered value readout, PIN dots, and all 12 keypad buttons inside
/// a single [ZeroRenderBox] using [ZeroNumberPainter] with 0 child widgets.
class ZNumberPad extends ZLeafWidget<RenderZNumberPad> {
  /// Controller holding the current numeric entry.
  final ZeroNumberPadController controller;

  /// Optional callback invoked when the entered value changes.
  final ValueChanged<int>? onValueChanged;

  /// Preferred widget size.
  final Size size;

  /// Accent color for active PIN dots and key highlights.
  final Color accentColor;

  /// Creates a const [ZNumberPad].
  const ZNumberPad({
    super.key,
    required this.controller,
    this.onValueChanged,
    this.size = const Size(200.0, 220.0),
    this.accentColor = const Color(0xFF00E5FF),
  });

  @override
  RenderZNumberPad createRenderObject(BuildContext context) {
    return RenderZNumberPad(
      controller: controller,
      onValueChanged: onValueChanged,
      preferredSize: size,
      accentColor: accentColor,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZNumberPad renderObject) {
    renderObject
      ..controller = controller
      ..onValueChanged = onValueChanged
      ..preferredSize = size
      ..accentColor = accentColor;
  }
}

/// Custom [ZeroRenderBox] for [ZNumberPad].
class RenderZNumberPad extends ZeroRenderBox {
  ZeroNumberPadController _controller;

  /// Callback when value changes.
  ValueChanged<int>? onValueChanged;

  Size _preferredSize;
  int _pressedCell = -1;

  final Paint _cellPaint = Paint()..color = const Color(0xFF162032);
  final Paint _activePaint = Paint()..style = PaintingStyle.fill;
  final Paint _dotIdlePaint = Paint()..color = const Color(0xFF334155);
  final Paint _iconStrokePaint = Paint()
    ..color = const Color(0xFFE2E8F0)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0
    ..strokeCap = StrokeCap.round;
  final ZeroNumberPainter _keyPainter = ZeroNumberPainter(
    style: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: Color(0xFFFFFFFF),
      fontFamily: 'monospace',
    ),
  );

  /// Creates a [RenderZNumberPad].
  RenderZNumberPad({
    required ZeroNumberPadController controller,
    required this.onValueChanged,
    required Size preferredSize,
    required Color accentColor,
  })  : _controller = controller,
        _preferredSize = preferredSize {
    _activePaint.color = accentColor;
  }

  /// Keypad controller.
  ZeroNumberPadController get controller => _controller;
  set controller(ZeroNumberPadController value) {
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

  /// Accent color.
  Color get accentColor => _activePaint.color;
  set accentColor(Color value) {
    if (_activePaint.color == value) return;
    _activePaint.color = value;
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
    _keyPainter.dispose();
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      _handleCellTap(event.localPosition);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (_pressedCell != -1) {
        _pressedCell = -1;
        markDirty();
      }
    }
  }

  void _handleCellTap(Offset localPos) {
    const double headerH = 36.0;
    if (localPos.dy < headerH || size.width <= 0 || size.height <= headerH) {
      return;
    }
    final int col = ((localPos.dx / size.width) * 3).floor().clamp(0, 2);
    final int row =
        (((localPos.dy - headerH) / (size.height - headerH)) * 4).floor().clamp(0, 3);
    final int cell = row * 3 + col;
    _pressedCell = cell;
    _applyCellAction(cell);
    onValueChanged?.call(_controller.value);
    markDirty();
  }

  void _applyCellAction(int cell) {
    if (cell < 9) {
      _controller.inputDigit(cell + 1);
    } else if (cell == 9) {
      _controller.clear();
    } else if (cell == 10) {
      _controller.inputDigit(0);
    } else {
      _controller.backspace();
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
    const double headerH = 36.0;
    _paintHeader(canvas, offset, headerH);
    _paintGrid(canvas, offset, headerH);
  }

  void _paintHeader(Canvas canvas, Offset offset, double headerH) {
    final int maxD = _controller.maxDigits;
    final int curD = _controller.digitCount;
    for (int i = 0; i < maxD; i++) {
      final double dx = offset.dx + 10.0 + i * 12.0;
      final double dy = offset.dy + headerH * 0.5;
      canvas.drawCircle(
        Offset(dx, dy),
        4.0,
        i < curD ? _activePaint : _dotIdlePaint,
      );
    }
    final double numX = offset.dx + size.width - _keyPainter.maxDigitWidth * (maxD + 0.5);
    final double numY = offset.dy + (headerH - _keyPainter.height) * 0.5;
    _keyPainter.paintInt(canvas, Offset(numX, numY), _controller.value);
  }

  void _paintGrid(Canvas canvas, Offset offset, double headerH) {
    const double gap = 4.0;
    final double cellW = (size.width - gap * 2.0) / 3.0;
    final double cellH = (size.height - headerH - gap * 3.0) / 4.0;

    for (int i = 0; i < 12; i++) {
      final int col = i % 3;
      final int row = i ~/ 3;
      final double cx = offset.dx + col * (cellW + gap);
      final double cy = offset.dy + headerH + row * (cellH + gap);
      final RRect rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx, cy, cellW, cellH),
        const Radius.circular(6.0),
      );
      canvas.drawRRect(rrect, i == _pressedCell ? _activePaint : _cellPaint);
      _paintCellLabel(canvas, i, cx, cy, cellW, cellH);
    }
  }

  void _paintCellLabel(
    Canvas canvas,
    int cell,
    double cx,
    double cy,
    double cellW,
    double cellH,
  ) {
    final double tx = cx + (cellW - _keyPainter.maxDigitWidth) * 0.5;
    final double ty = cy + (cellH - _keyPainter.height) * 0.5;
    if (cell < 9) {
      _keyPainter.paintInt(canvas, Offset(tx, ty), cell + 1);
    } else if (cell == 9) {
      final double mx = cx + cellW * 0.5;
      final double my = cy + cellH * 0.5;
      canvas.drawLine(
        Offset(mx - 4.0, my - 4.0),
        Offset(mx + 4.0, my + 4.0),
        _iconStrokePaint,
      );
      canvas.drawLine(
        Offset(mx + 4.0, my - 4.0),
        Offset(mx - 4.0, my + 4.0),
        _iconStrokePaint,
      );
    } else if (cell == 10) {
      _keyPainter.paintInt(canvas, Offset(tx, ty), 0);
    } else {
      final double mx = cx + cellW * 0.5;
      final double my = cy + cellH * 0.5;
      canvas.drawLine(
        Offset(mx - 5.0, my),
        Offset(mx + 5.0, my),
        _iconStrokePaint,
      );
      canvas.drawLine(
        Offset(mx - 5.0, my),
        Offset(mx - 1.0, my - 3.5),
        _iconStrokePaint,
      );
      canvas.drawLine(
        Offset(mx - 5.0, my),
        Offset(mx - 1.0, my + 3.5),
        _iconStrokePaint,
      );
    }
  }
}
