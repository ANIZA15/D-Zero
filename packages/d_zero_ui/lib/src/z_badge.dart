import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active Z-prefixed alias for [ZBadge].
typedef ZNotificationBadge = ZBadge;

/// Deprecated legacy alias for [ZBadge].
@Deprecated('Use ZBadge instead.')
typedef ZeroBadge = ZBadge;

/// A zero-allocation, zero-rebuild notification badge widget.
///
/// Observes a [ValueListenable<int>] (such as [ZeroIntNotifier] or [ValueNotifier<int>])
/// directly inside [RenderZBadge]. When the count changes, only `markNeedsPaint()`
/// is triggered—the child widget and ancestor tree are never rebuilt, and numeric
/// labels (`1`..`99` or `99+`) are rendered via [ZeroNumberPainter] in a single
/// GPU `Canvas.drawRawAtlas` call without allocating any [String] on the Dart heap.
class ZBadge extends ZSingleChildWidget<RenderZBadge> {
  /// Reactive integer count source observed directly by [RenderZBadge].
  final ValueListenable<int> countListenable;

  /// Maximum count displayed before clamping to `<maxCount>+` (e.g., `99+`).
  final int maxCount;

  /// Whether to hide the badge completely when `count <= 0`.
  final bool hideWhenZero;

  /// Whether to render the numeric count inside the badge (`false` renders a small dot).
  final bool showCount;

  /// Fill color of the badge pill/circle.
  final Color badgeColor;

  /// Optional border ring color around the badge (`0` alpha disables border).
  final Color borderColor;

  /// Border stroke width around the badge.
  final double borderWidth;

  /// Text style used by [ZeroNumberPainter] for digits and `'+'`.
  final TextStyle textStyle;

  /// Offset adjustment applied to the top-right badge anchor when wrapping a [child].
  final Offset badgeOffset;

  /// Creates a const [ZBadge].
  const ZBadge({
    super.key,
    super.child,
    required this.countListenable,
    this.maxCount = 99,
    this.hideWhenZero = true,
    this.showCount = true,
    this.badgeColor = const Color(0xFFEF4444),
    this.borderColor = const Color(0xFF0F172A),
    this.borderWidth = 1.5,
    this.textStyle = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 11.0,
      fontWeight: FontWeight.w700,
      fontFamily: 'monospace',
    ),
    this.badgeOffset = const Offset(4.0, -4.0),
  }) : assert(maxCount > 0, 'maxCount must be positive.');

  @override
  RenderZBadge createRenderObject(BuildContext context) {
    return RenderZBadge(
      countListenable: countListenable,
      maxCount: maxCount,
      hideWhenZero: hideWhenZero,
      showCount: showCount,
      badgeColor: badgeColor,
      borderColor: borderColor,
      borderWidth: borderWidth,
      textStyle: textStyle,
      badgeOffset: badgeOffset,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZBadge renderObject) {
    renderObject
      ..countListenable = countListenable
      ..maxCount = maxCount
      ..hideWhenZero = hideWhenZero
      ..showCount = showCount
      ..badgeColor = badgeColor
      ..borderColor = borderColor
      ..borderWidth = borderWidth
      ..textStyle = textStyle
      ..badgeOffset = badgeOffset;
  }
}

/// Custom [RenderShiftedBox] for [ZBadge] that renders a pill or dot notification
/// badge using [ZeroNumberPainter] with 0 String allocations and 0 widget rebuilds.
class RenderZBadge extends RenderShiftedBox {
  ValueListenable<int> _countListenable;
  int _maxCount;
  bool _hideWhenZero;
  bool _showCount;
  Color _badgeColor;
  Color _borderColor;
  double _borderWidth;
  TextStyle _textStyle;
  Offset _badgeOffset;

  final Paint _badgePaint = Paint()..style = PaintingStyle.fill;
  final Paint _borderPaint = Paint()..style = PaintingStyle.stroke;
  late ZeroNumberPainter _numberPainter;

  /// Creates a [RenderZBadge].
  RenderZBadge({
    RenderBox? child,
    required ValueListenable<int> countListenable,
    required int maxCount,
    required bool hideWhenZero,
    required bool showCount,
    required Color badgeColor,
    required Color borderColor,
    required double borderWidth,
    required TextStyle textStyle,
    required Offset badgeOffset,
  })  : _countListenable = countListenable,
        _maxCount = maxCount,
        _hideWhenZero = hideWhenZero,
        _showCount = showCount,
        _badgeColor = badgeColor,
        _borderColor = borderColor,
        _borderWidth = borderWidth,
        _textStyle = textStyle,
        _badgeOffset = badgeOffset,
        super(child) {
    _badgePaint.color = _badgeColor;
    _borderPaint
      ..color = _borderColor
      ..strokeWidth = math.max(0.0, _borderWidth);
    _numberPainter = ZeroNumberPainter(style: _textStyle);
  }

  @override
  bool get isRepaintBoundary => true;

  /// Reactive integer count source.
  ValueListenable<int> get countListenable => _countListenable;
  set countListenable(ValueListenable<int> value) {
    if (identical(_countListenable, value)) return;
    if (attached) {
      _countListenable.removeListener(_onCountChanged);
      value.addListener(_onCountChanged);
    }
    _countListenable = value;
    _onCountChanged();
  }

  /// Maximum count before clamping to `<maxCount>+`.
  int get maxCount => _maxCount;
  set maxCount(int value) {
    if (_maxCount == value) return;
    _maxCount = math.max(1, value);
    markNeedsPaint();
  }

  /// Whether badge is hidden when count <= 0.
  bool get hideWhenZero => _hideWhenZero;
  set hideWhenZero(bool value) {
    if (_hideWhenZero == value) return;
    _hideWhenZero = value;
    markNeedsPaint();
  }

  /// Whether numeric count is drawn inside the badge.
  bool get showCount => _showCount;
  set showCount(bool value) {
    if (_showCount == value) return;
    _showCount = value;
    if (child == null) markNeedsLayout();
    markNeedsPaint();
  }

  /// Badge background color.
  Color get badgeColor => _badgeColor;
  set badgeColor(Color value) {
    if (_badgeColor == value) return;
    _badgeColor = value;
    _badgePaint.color = value;
    markNeedsPaint();
  }

  /// Badge border stroke color.
  Color get borderColor => _borderColor;
  set borderColor(Color value) {
    if (_borderColor == value) return;
    _borderColor = value;
    _borderPaint.color = value;
    markNeedsPaint();
  }

  /// Badge border stroke width.
  double get borderWidth => _borderWidth;
  set borderWidth(double value) {
    if (_borderWidth == value) return;
    _borderWidth = value;
    _borderPaint.strokeWidth = math.max(0.0, value);
    markNeedsPaint();
  }

  /// Badge digit text style.
  TextStyle get textStyle => _textStyle;
  set textStyle(TextStyle value) {
    if (_textStyle == value) return;
    _textStyle = value;
    _numberPainter.dispose();
    _numberPainter = ZeroNumberPainter(style: _textStyle);
    if (child == null) markNeedsLayout();
    markNeedsPaint();
  }

  /// Top-right anchor offset when wrapping a child.
  Offset get badgeOffset => _badgeOffset;
  set badgeOffset(Offset value) {
    if (_badgeOffset == value) return;
    _badgeOffset = value;
    markNeedsPaint();
  }

  void _onCountChanged() {
    if (child == null) {
      markNeedsLayout();
    }
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _countListenable.addListener(_onCountChanged);
  }

  @override
  void detach() {
    _countListenable.removeListener(_onCountChanged);
    super.detach();
  }

  @override
  void dispose() {
    _numberPainter.dispose();
    super.dispose();
  }

  Size _computeBadgeMetrics(int count) {
    if (!_showCount) {
      return const Size(10.0, 10.0);
    }
    final double h = math.max(18.0, _numberPainter.height + 6.0);
    final double textW = _measureCountWidth(count);
    final double w = math.max(h, textW + 10.0);
    return Size(w, h);
  }

  double _measureCountWidth(int count) {
    final int clamped = math.max(0, count);
    if (clamped > _maxCount) {
      final int digits = _digitCount(_maxCount);
      final double plusW =
          _numberPainter.glyphWidth(ZeroNumberPainter.glyphPlus);
      return digits * _numberPainter.maxDigitWidth + plusW;
    }
    return _digitCount(clamped) * _numberPainter.maxDigitWidth;
  }

  static int _digitCount(int nonNeg) {
    if (nonNeg < 10) return 1;
    if (nonNeg < 100) return 2;
    if (nonNeg < 1000) return 3;
    int n = nonNeg;
    int digits = 0;
    while (n > 0) {
      n ~/= 10;
      digits++;
    }
    return digits;
  }

  @override
  void performLayout() {
    final RenderBox? childBox = child;
    if (childBox != null) {
      childBox.layout(constraints, parentUsesSize: true);
      final BoxParentData childParentData =
          childBox.parentData! as BoxParentData;
      childParentData.offset = Offset.zero;
      size = constraints.constrain(childBox.size);
      return;
    }
    final Size badgeSize = _computeBadgeMetrics(_countListenable.value);
    size = constraints.constrain(badgeSize);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final RenderBox? childBox = child;
    if (childBox != null) {
      final BoxParentData childParentData =
          childBox.parentData! as BoxParentData;
      context.paintChild(childBox, childParentData.offset + offset);
    }

    final int count = _countListenable.value;
    if (_hideWhenZero && count <= 0) return;

    final Size badgeSize = _computeBadgeMetrics(count);
    final Rect badgeRect = _resolveBadgeRect(offset, badgeSize, childBox != null);
    _paintBadgePill(context.canvas, badgeRect, count);
  }

  Rect _resolveBadgeRect(Offset offset, Size badgeSize, bool hasChild) {
    if (!hasChild) {
      final double dx = offset.dx + (size.width - badgeSize.width) * 0.5;
      final double dy = offset.dy + (size.height - badgeSize.height) * 0.5;
      return Rect.fromLTWH(dx, dy, badgeSize.width, badgeSize.height);
    }
    final double right = offset.dx + size.width + _badgeOffset.dx;
    final double top = offset.dy + _badgeOffset.dy;
    return Rect.fromLTWH(
      right - badgeSize.width,
      top,
      badgeSize.width,
      badgeSize.height,
    );
  }

  void _paintBadgePill(Canvas canvas, Rect badgeRect, int count) {
    final RRect pill = RRect.fromRectAndRadius(
      badgeRect,
      Radius.circular(badgeRect.height * 0.5),
    );
    canvas.drawRRect(pill, _badgePaint);
    if (_borderWidth > 0.0) {
      canvas.drawRRect(pill, _borderPaint);
    }
    if (!_showCount) return;

    final int displayCount = math.max(0, count);
    final double textW = _measureCountWidth(displayCount);
    final double textX = badgeRect.left + (badgeRect.width - textW) * 0.5;
    final double textY =
        badgeRect.top + (badgeRect.height - _numberPainter.height) * 0.5;
    final Offset textOffset = Offset(textX, textY);

    if (displayCount > _maxCount) {
      _numberPainter.paintWithSuffix(
        canvas,
        textOffset,
        _maxCount.toDouble(),
        suffixGlyph: ZeroNumberPainter.glyphPlus,
        fractionDigits: 0,
      );
    } else {
      _numberPainter.paintInt(canvas, textOffset, displayCount);
    }
  }
}
