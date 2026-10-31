import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active alias for [ZStreamingMarkdown].
typedef ZTokenStream = ZStreamingMarkdown;

/// Legacy alias for [ZStreamingMarkdown].
@Deprecated('Use ZStreamingMarkdown instead.')
typedef ZeroStreamingMarkdown = ZStreamingMarkdown;

/// Zero-allocation controller for [ZStreamingMarkdown] that stores incoming AI/LLM
/// tokens in a fixed `Uint16List` ring buffer without concatenating strings per token.
class ZeroTokenStreamController extends ChangeNotifier {
  final int _maxLines;
  final int _maxCols;
  late final Uint16List _cells;
  late final Uint8List _lineStyles;
  int _cursorRow = 0;
  int _cursorCol = 0;
  int _totalTokens = 0;
  bool _isDisposed = false;

  /// Style constant for normal body text.
  static const int styleNormal = 0;

  /// Style constant for heading (`#`) lines.
  static const int styleHeading = 1;

  /// Style constant for code/bullet (`>` or `-`) lines.
  static const int styleCode = 2;

  /// Creates a [ZeroTokenStreamController] with fixed [maxLines] and [maxCols].
  ZeroTokenStreamController({int maxLines = 6, int maxCols = 44})
      : _maxLines = math.max(1, maxLines),
        _maxCols = math.max(8, maxCols) {
    _cells = Uint16List(_maxLines * _maxCols);
    _lineStyles = Uint8List(_maxLines);
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Maximum buffered lines.
  int get maxLines => _maxLines;

  /// Maximum columns per line.
  int get maxCols => _maxCols;

  /// Total tokens appended (`0` if disposed).
  int get totalTokens => _isDisposed ? 0 : _totalTokens;

  /// Current active cursor row.
  int get cursorRow => _isDisposed ? 0 : _cursorRow;

  /// Current active cursor column.
  int get cursorCol => _isDisposed ? 0 : _cursorCol;

  /// Reads ASCII code unit at [row], [col].
  int charAt(int row, int col) {
    if (_isDisposed) return 0;
    return _cells[row * _maxCols + col];
  }

  /// Reads line style at [row].
  int styleAt(int row) => _isDisposed ? 0 : _lineStyles[row];

  /// Appends a streamed token chunk into the ring buffer without allocating strings.
  void appendToken(String token) {
    if (_isDisposed || token.isEmpty) return;
    _totalTokens++;
    for (int i = 0; i < token.length; i++) {
      final int cu = token.codeUnitAt(i);
      if (cu == 10) {
        _advanceLine();
      } else {
        _putChar(cu);
      }
    }
    notifyListeners();
  }

  void _putChar(int codeUnit) {
    if (_cursorCol == 0) {
      if (codeUnit == 35) {
        _lineStyles[_cursorRow] = styleHeading;
      } else if (codeUnit == 62 || codeUnit == 96 || codeUnit == 45) {
        _lineStyles[_cursorRow] = styleCode;
      }
    }
    if (_cursorCol >= _maxCols) {
      _advanceLine();
    }
    _cells[_cursorRow * _maxCols + _cursorCol] = codeUnit;
    _cursorCol++;
  }

  void _advanceLine() {
    if (_cursorRow + 1 < _maxLines) {
      _cursorRow++;
      _cursorCol = 0;
      return;
    }
    // Shift rows up in-place inside the fixed buffer
    final int stride = _maxCols;
    _cells.setRange(0, (_maxLines - 1) * stride, _cells, stride);
    _cells.fillRange((_maxLines - 1) * stride, _maxLines * stride, 0);
    _lineStyles.setRange(0, _maxLines - 1, _lineStyles, 1);
    _lineStyles[_maxLines - 1] = styleNormal;
    _cursorCol = 0;
  }

  /// Clears the token buffer.
  void clear() {
    if (_isDisposed) return;
    _cells.fillRange(0, _cells.length, 0);
    _lineStyles.fillRange(0, _lineStyles.length, 0);
    _cursorRow = 0;
    _cursorCol = 0;
    _totalTokens = 0;
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
    _cells.fillRange(0, _cells.length, 0);
    super.dispose();
  }
}

/// A zero-allocation AI/LLM token streaming markdown surface widget
/// (ChatGPT / Claude / Gemini live response renderer).
///
/// Renders headings, code blocks, and body text with a live token counter and
/// blinking cursor directly from a `Uint16List` grid without rebuilding `RichText`.
class ZStreamingMarkdown extends ZLeafWidget<RenderZStreamingMarkdown> {
  /// Controller holding the streamed token buffer.
  final ZeroTokenStreamController controller;

  /// Preferred widget size.
  final Size size;

  /// Background surface color.
  final Color backgroundColor;

  /// Creates a const [ZStreamingMarkdown].
  const ZStreamingMarkdown({
    super.key,
    required this.controller,
    this.size = const Size(280.0, 110.0),
    this.backgroundColor = const Color(0xFF0B111E),
  });

  @override
  RenderZStreamingMarkdown createRenderObject(BuildContext context) {
    return RenderZStreamingMarkdown(
      controller: controller,
      preferredSize: size,
      backgroundColor: backgroundColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZStreamingMarkdown renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..backgroundColor = backgroundColor;
  }
}

/// Custom [ZeroRenderBox] for [ZStreamingMarkdown].
class RenderZStreamingMarkdown extends ZeroRenderBox {
  ZeroTokenStreamController _controller;
  Size _preferredSize;

  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _codeBgPaint = Paint()..color = const Color(0xFF162238);
  final Paint _cursorPaint = Paint()..color = const Color(0xFF00FF88);
  final Paint _glyphBarPaint = Paint()..color = const Color(0xFF94A3B8);
  final Paint _headingPaint = Paint()..color = const Color(0xFF00E5FF);
  final Paint _codeTextPaint = Paint()..color = const Color(0xFF00FF88);
  final ZeroNumberPainter _tokenCounterPainter = ZeroNumberPainter(
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: Color(0xFF00FF88),
      fontFamily: 'monospace',
    ),
  );

  /// Creates a [RenderZStreamingMarkdown].
  RenderZStreamingMarkdown({
    required ZeroTokenStreamController controller,
    required Size preferredSize,
    required Color backgroundColor,
  })  : _controller = controller,
        _preferredSize = preferredSize {
    _bgPaint.color = backgroundColor;
  }

  /// Token stream controller.
  ZeroTokenStreamController get controller => _controller;
  set controller(ZeroTokenStreamController value) {
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

  /// Surface background color.
  Color get backgroundColor => _bgPaint.color;
  set backgroundColor(Color value) {
    if (_bgPaint.color == value) return;
    _bgPaint.color = value;
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
    _tokenCounterPainter.dispose();
    super.dispose();
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
    final RRect rrect = RRect.fromRectAndRadius(
      offset & size,
      const Radius.circular(10.0),
    );
    canvas.drawRRect(rrect, _bgPaint);

    final int rows = _controller.maxLines;
    final int cols = _controller.maxCols;
    final double lineH = math.max(12.0, (size.height - 16.0) / rows);
    const double charW = 5.4;

    for (int r = 0; r < rows; r++) {
      final double ly = offset.dy + 8.0 + r * lineH;
      final int style = _controller.styleAt(r);
      if (style == ZeroTokenStreamController.styleCode) {
        canvas.drawRect(
          Rect.fromLTWH(offset.dx + 6.0, ly, size.width - 12.0, lineH - 2.0),
          _codeBgPaint,
        );
      }
      _paintRowTokens(canvas, offset.dx + 10.0, ly, r, cols, charW, lineH, style);
    }

    final double cx = offset.dx + 10.0 + _controller.cursorCol * charW;
    final double cy = offset.dy + 8.0 + _controller.cursorRow * lineH;
    if (cx < offset.dx + size.width - 12.0) {
      canvas.drawRect(Rect.fromLTWH(cx, cy + 2.0, 5.0, lineH - 4.0), _cursorPaint);
    }

    _tokenCounterPainter.paintInt(
      canvas,
      Offset(offset.dx + size.width - 48.0, offset.dy + 6.0),
      _controller.totalTokens,
      minDigits: 3,
    );
  }

  void _paintRowTokens(
    Canvas canvas,
    double startX,
    double ly,
    int row,
    int cols,
    double charW,
    double lineH,
    int style,
  ) {
    final Paint paint = style == ZeroTokenStreamController.styleHeading
        ? _headingPaint
        : (style == ZeroTokenStreamController.styleCode
            ? _codeTextPaint
            : _glyphBarPaint);

    for (int c = 0; c < cols; c++) {
      final int cu = _controller.charAt(row, c);
      if (cu <= 32) continue;
      final double x = startX + c * charW;
      if (x + charW > startX + size.width - 60.0) break;
      final double h = (cu >= 65 && cu <= 90) ? lineH * 0.55 : lineH * 0.42;
      canvas.drawRect(
        Rect.fromLTWH(x, ly + (lineH - h) * 0.5, charW - 1.2, h),
        paint,
      );
    }
  }
}
