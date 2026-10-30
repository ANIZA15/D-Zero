import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active Z-prefixed alias for [ZVirtualGrid].
typedef ZTimeSeriesTable = ZVirtualGrid;

/// Deprecated legacy alias for [ZVirtualGrid].
@Deprecated('Use ZVirtualGrid instead.')
typedef ZeroVirtualGrid = ZVirtualGrid;

/// Zero-allocation flat 2D numeric table buffer (`rows * cols`) for [ZVirtualGrid].
///
/// Stores up to [maxAllowedCells] (`1,048,576`) floating-point cells in a single
/// contiguous [Float32List] so that virtualized viewport rendering can read visible
/// `(row, col)` cells in $O(1)$ without creating row/cell widgets or `Element` nodes.
class ZeroVirtualGridController implements Listenable {
  /// Maximum allowed total cell count (`1,048,576`).
  static const int maxAllowedCells = 1048576;

  /// Number of rows in the virtual grid.
  final int rows;

  /// Number of columns in the virtual grid.
  final int cols;

  late final Float32List _cells;
  final ZeroIntNotifier _revision = ZeroIntNotifier(0);
  bool _isDisposed = false;

  /// Creates a [ZeroVirtualGridController] with dimensions `[rows] x [cols]`.
  ZeroVirtualGridController({
    int rows = 1000,
    int cols = 8,
  })  : rows = _clampDim(rows, 1, maxAllowedCells),
        cols = _clampDim(cols, 1, 1024) {
    final int clampedRows =
        (this.rows * this.cols > maxAllowedCells)
            ? (maxAllowedCells ~/ this.cols)
            : this.rows;
    _cells = Float32List(clampedRows * this.cols);
  }

  static int _clampDim(int v, int minVal, int maxVal) {
    if (v < minVal) return minVal;
    if (v > maxVal) return maxVal;
    return v;
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether any listeners are currently registered.
  bool get hasListeners => !_isDisposed && _revision.hasListeners;

  /// Effective number of allocated rows.
  int get allocatedRows => _isDisposed ? 0 : (_cells.length ~/ cols);

  /// Total number of cells (`allocatedRows * cols`), or `0` if disposed.
  int get length => _isDisposed ? 0 : _cells.length;

  /// Reads the cell value at `([row], [col])`, or `0.0` if disposed/out of bounds.
  double cellAt(int row, int col) {
    if (_isDisposed || col < 0 || col >= cols || row < 0) return 0.0;
    final int idx = row * cols + col;
    if (idx < 0 || idx >= _cells.length) return 0.0;
    return _cells[idx];
  }

  /// Sets the cell at `([row], [col])` to [value] and notifies listeners.
  void setCell(int row, int col, double value) {
    if (_isDisposed || col < 0 || col >= cols || row < 0) return;
    final int idx = row * cols + col;
    if (idx < 0 || idx >= _cells.length) return;
    _cells[idx] = value.isNaN || value.isInfinite ? 0.0 : value;
    _revision.add(1);
  }

  /// Updates an entire [row] from [values] and notifies listeners once.
  void updateRow(int row, List<double> values) {
    if (_isDisposed || row < 0) return;
    final int rowStart = row * cols;
    if (rowStart < 0 || rowStart + cols > _cells.length) return;
    final int limit = values.length < cols ? values.length : cols;
    for (int c = 0; c < limit; c++) {
      final double v = values[c];
      _cells[rowStart + c] = v.isNaN || v.isInfinite ? 0.0 : v;
    }
    _revision.add(1);
  }

  /// Clears all cells to `0.0`.
  void clear() {
    if (_isDisposed) return;
    _cells.fillRange(0, _cells.length, 0.0);
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

  /// Disposes this controller and zeros all cells (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _cells.fillRange(0, _cells.length, 0.0);
    _revision.dispose();
  }
}

/// A zero-allocation 2D virtual scrolling numeric data grid widget.
///
/// Bypasses Flutter's `ScrollView`, `Sliver`, and per-cell `Element` hierarchy
/// entirely by computing visible `(row, col)` bounds mathematically inside a
/// single [ZeroRenderBox] and rendering numeric cells directly via
/// [ZeroNumberPainter]'s shared GPU glyph atlas.
class ZVirtualGrid extends ZLeafWidget<RenderZVirtualGrid> {
  /// Backing 2D cell buffer.
  final ZeroVirtualGridController controller;

  /// Preferred viewport size when unconstrained.
  final Size size;

  /// Width of each column cell in logical pixels.
  final double cellWidth;

  /// Height of each row cell in logical pixels.
  final double cellHeight;

  /// Number of decimal places rendered per numeric cell (`0..4`).
  final int fractionDigits;

  /// Background color of the grid viewport.
  final Color backgroundColor;

  /// Alternate row stripe color.
  final Color alternateRowColor;

  /// Grid line divider color.
  final Color gridLineColor;

  /// Text style used for numeric cell rendering.
  final TextStyle textStyle;

  /// Creates a const [ZVirtualGrid] widget.
  const ZVirtualGrid({
    super.key,
    required this.controller,
    this.size = const Size(360.0, 220.0),
    this.cellWidth = 84.0,
    this.cellHeight = 26.0,
    this.fractionDigits = 2,
    this.backgroundColor = const Color(0xFF0B1120),
    this.alternateRowColor = const Color(0xFF111827),
    this.gridLineColor = const Color(0xFF1E293B),
    this.textStyle = const TextStyle(
      color: Color(0xFFE2E8F0),
      fontSize: 12.0,
      fontWeight: FontWeight.w500,
    ),
  });

  @override
  RenderZVirtualGrid createRenderObject(BuildContext context) {
    return RenderZVirtualGrid(
      controller: controller,
      preferredSize: size,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
      fractionDigits: fractionDigits,
      backgroundColor: backgroundColor,
      alternateRowColor: alternateRowColor,
      gridLineColor: gridLineColor,
      textStyle: textStyle,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZVirtualGrid renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..cellWidth = cellWidth
      ..cellHeight = cellHeight
      ..fractionDigits = fractionDigits
      ..backgroundColor = backgroundColor
      ..alternateRowColor = alternateRowColor
      ..gridLineColor = gridLineColor
      ..textStyle = textStyle;
  }
}

/// Custom [ZeroRenderBox] that culls and paints visible cells of [ZVirtualGrid]
/// in $O(\text{visible cells})$ time with zero widget or string allocations.
class RenderZVirtualGrid extends ZeroRenderBox {
  ZeroVirtualGridController _controller;
  Size _preferredSize;
  double _cellWidth;
  double _cellHeight;
  int _fractionDigits;
  Color _backgroundColor;
  Color _alternateRowColor;
  Color _gridLineColor;
  TextStyle _textStyle;

  late ZeroNumberPainter _numberPainter;
  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _altRowPaint = Paint()..style = PaintingStyle.fill;
  final Paint _linePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  double _scrollX = 0.0;
  double _scrollY = 0.0;

  /// Creates a [RenderZVirtualGrid].
  RenderZVirtualGrid({
    required ZeroVirtualGridController controller,
    required Size preferredSize,
    required double cellWidth,
    required double cellHeight,
    required int fractionDigits,
    required Color backgroundColor,
    required Color alternateRowColor,
    required Color gridLineColor,
    required TextStyle textStyle,
  })  : _controller = controller,
        _preferredSize = preferredSize,
        _cellWidth = cellWidth > 24.0 ? cellWidth : 24.0,
        _cellHeight = cellHeight > 14.0 ? cellHeight : 14.0,
        _fractionDigits = fractionDigits.clamp(0, 4),
        _backgroundColor = backgroundColor,
        _alternateRowColor = alternateRowColor,
        _gridLineColor = gridLineColor,
        _textStyle = textStyle {
    _bgPaint.color = _backgroundColor;
    _altRowPaint.color = _alternateRowColor;
    _linePaint.color = _gridLineColor;
    _numberPainter = ZeroNumberPainter(style: _textStyle);
  }

  /// Backing grid controller.
  ZeroVirtualGridController get controller => _controller;
  set controller(ZeroVirtualGridController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
    }
    _controller = value;
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

  /// Width of each column cell.
  double get cellWidth => _cellWidth;
  set cellWidth(double value) {
    final double clamped = value > 24.0 ? value : 24.0;
    if (_cellWidth == clamped) return;
    _cellWidth = clamped;
    markDirty();
  }

  /// Height of each row cell.
  double get cellHeight => _cellHeight;
  set cellHeight(double value) {
    final double clamped = value > 14.0 ? value : 14.0;
    if (_cellHeight == clamped) return;
    _cellHeight = clamped;
    markDirty();
  }

  /// Number of decimal digits displayed per cell.
  int get fractionDigits => _fractionDigits;
  set fractionDigits(int value) {
    final int clamped = value.clamp(0, 4);
    if (_fractionDigits == clamped) return;
    _fractionDigits = clamped;
    markDirty();
  }

  /// Background color of the grid.
  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    _bgPaint.color = value;
    markDirty();
  }

  /// Alternating row background color.
  Color get alternateRowColor => _alternateRowColor;
  set alternateRowColor(Color value) {
    if (_alternateRowColor == value) return;
    _alternateRowColor = value;
    _altRowPaint.color = value;
    markDirty();
  }

  /// Grid line color.
  Color get gridLineColor => _gridLineColor;
  set gridLineColor(Color value) {
    if (_gridLineColor == value) return;
    _gridLineColor = value;
    _linePaint.color = value;
    markDirty();
  }

  /// Numeric cell text style.
  TextStyle get textStyle => _textStyle;
  set textStyle(TextStyle value) {
    if (_textStyle == value) return;
    _textStyle = value;
    _numberPainter.dispose();
    _numberPainter = ZeroNumberPainter(style: _textStyle);
    markDirty();
  }

  /// Current horizontal scroll offset.
  double get scrollX => _scrollX;

  /// Current vertical scroll offset.
  double get scrollY => _scrollY;

  /// Programmatically jumps to `([x], [y])` within valid scroll bounds.
  void jumpTo(double x, double y) {
    _applyScrollTarget(x, y);
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
    _numberPainter.dispose();
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
      _applyScrollTarget(_scrollX - event.delta.dx, _scrollY - event.delta.dy);
    } else if (event is PointerScrollEvent) {
      _applyScrollTarget(
        _scrollX + event.scrollDelta.dx,
        _scrollY + event.scrollDelta.dy,
      );
    }
  }

  void _applyScrollTarget(double targetX, double targetY) {
    if (!hasSize) return;
    final double maxW =
        (_controller.cols * _cellWidth - size.width).clamp(0.0, double.infinity);
    final double maxH =
        (_controller.allocatedRows * _cellHeight - size.height)
            .clamp(0.0, double.infinity);
    final double nx = targetX.isNaN ? 0.0 : targetX.clamp(0.0, maxW);
    final double ny = targetY.isNaN ? 0.0 : targetY.clamp(0.0, maxH);
    if ((nx - _scrollX).abs() > 0.1 || (ny - _scrollY).abs() > 0.1) {
      _scrollX = nx;
      _scrollY = ny;
      markDirty();
    }
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect bounds = offset & size;
    canvas.drawRect(bounds, _bgPaint);
    final int totalRows = _controller.allocatedRows;
    final int totalCols = _controller.cols;
    if (_controller.isDisposed || totalRows <= 0 || totalCols <= 0) return;

    final int firstRow = (_scrollY ~/ _cellHeight).clamp(0, totalRows - 1);
    final int endRow =
        (firstRow + (size.height ~/ _cellHeight) + 2).clamp(0, totalRows);
    final int firstCol = (_scrollX ~/ _cellWidth).clamp(0, totalCols - 1);
    final int endCol =
        (firstCol + (size.width ~/ _cellWidth) + 2).clamp(0, totalCols);

    canvas.save();
    canvas.clipRect(bounds);
    _paintVisibleRows(
      canvas: canvas,
      offset: offset,
      firstRow: firstRow,
      endRow: endRow,
      firstCol: firstCol,
      endCol: endCol,
    );
    _paintColumnLines(canvas, offset, firstCol, endCol);
    canvas.restore();
  }

  void _paintVisibleRows({
    required Canvas canvas,
    required Offset offset,
    required int firstRow,
    required int endRow,
    required int firstCol,
    required int endCol,
  }) {
    final double textPadY = (_cellHeight - _numberPainter.height) * 0.5;
    for (int r = firstRow; r < endRow; r++) {
      final double ry = offset.dy + (r * _cellHeight) - _scrollY;
      if (r.isOdd) {
        canvas.drawRect(
          Rect.fromLTWH(offset.dx, ry, size.width, _cellHeight),
          _altRowPaint,
        );
      }
      for (int c = firstCol; c < endCol; c++) {
        final double cx = offset.dx + (c * _cellWidth) - _scrollX;
        final double val = _controller.cellAt(r, c);
        _numberPainter.paintDouble(
          canvas,
          Offset(cx + 6.0, ry + textPadY),
          val,
          fractionDigits: _fractionDigits,
        );
      }
      canvas.drawLine(
        Offset(offset.dx, ry + _cellHeight),
        Offset(offset.dx + size.width, ry + _cellHeight),
        _linePaint,
      );
    }
  }

  void _paintColumnLines(
    Canvas canvas,
    Offset offset,
    int firstCol,
    int endCol,
  ) {
    for (int c = firstCol; c <= endCol; c++) {
      final double cx = offset.dx + (c * _cellWidth) - _scrollX;
      canvas.drawLine(
        Offset(cx, offset.dy),
        Offset(cx, offset.dy + size.height),
        _linePaint,
      );
    }
  }
}
