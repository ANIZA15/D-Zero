import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active alias for [ZContributionGraph].
typedef ZHabitGrid = ZContributionGraph;

/// Legacy alias for [ZContributionGraph].
@Deprecated('Use ZContributionGraph instead.')
typedef ZeroContributionGraph = ZContributionGraph;

/// Zero-allocation controller for [ZContributionGraph] storing activity intensity
/// levels (`0..4`) in a compact `Uint8List` grid (`weeks × 7 days`).
class ZeroContributionBuffer extends ChangeNotifier {
  final int _weeks;
  static const int _daysPerWeek = 7;
  late final Uint8List _levels;
  int _activeCount = 0;
  bool _isDisposed = false;

  /// Creates a [ZeroContributionBuffer] with [weeks] columns (`4..52`).
  ZeroContributionBuffer({int weeks = 16}) : _weeks = weeks.clamp(4, 52) {
    _levels = Uint8List(_weeks * _daysPerWeek);
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  @override
  bool get hasListeners => !_isDisposed && super.hasListeners;

  /// Number of week columns.
  int get weeks => _weeks;

  /// Number of day rows (`7`).
  int get daysPerWeek => _daysPerWeek;

  /// Total active days (`level > 0`, or `0` if disposed).
  int get activeCount => _isDisposed ? 0 : _activeCount;

  bool _isValidCell(int week, int day) =>
      !_isDisposed &&
      week >= 0 &&
      week < _weeks &&
      day >= 0 &&
      day < _daysPerWeek;

  /// Reads intensity level (`0..4`) at [week], [day].
  int levelAt(int week, int day) {
    if (!_isValidCell(week, day)) return 0;
    return _levels[week * _daysPerWeek + day];
  }

  /// Sets intensity level (`0..4`) at [week], [day] in place.
  void setLevel(int week, int day, int level) {
    if (!_isValidCell(week, day)) return;
    final int idx = week * _daysPerWeek + day;
    final int prev = _levels[idx];
    final int next = level.clamp(0, 4);
    if (prev == next) return;
    _activeCount += (next > 0 ? 1 : 0) - (prev > 0 ? 1 : 0);
    _levels[idx] = next;
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
    _activeCount = 0;
    _levels.fillRange(0, _levels.length, 0);
    super.dispose();
  }
}

/// A zero-allocation GitHub-style contribution & habit streak grid widget.
///
/// Renders `weeks × 7` rounded cells with a pre-baked 5-level `Paint` palette
/// and an active-day counter via [ZeroNumberPainter] inside a single [ZeroRenderBox].
class ZContributionGraph extends ZLeafWidget<RenderZContributionGraph> {
  /// Buffer storing `0..4` contribution levels.
  final ZeroContributionBuffer buffer;

  /// Preferred widget size.
  final Size size;

  /// Creates a const [ZContributionGraph].
  const ZContributionGraph({
    super.key,
    required this.buffer,
    this.size = const Size(240.0, 96.0),
  });

  @override
  RenderZContributionGraph createRenderObject(BuildContext context) {
    return RenderZContributionGraph(
      buffer: buffer,
      preferredSize: size,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZContributionGraph renderObject,
  ) {
    renderObject
      ..buffer = buffer
      ..preferredSize = size;
  }
}

/// Custom [ZeroRenderBox] for [ZContributionGraph].
class RenderZContributionGraph extends ZeroRenderBox {
  ZeroContributionBuffer _buffer;
  Size _preferredSize;

  static const List<Color> _levelColors = <Color>[
    Color(0xFF161B22),
    Color(0xFF0E4429),
    Color(0xFF006D32),
    Color(0xFF26A641),
    Color(0xFF39D353),
  ];

  late final List<Paint> _levelPaints;
  final ZeroNumberPainter _streakPainter = ZeroNumberPainter(
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: Color(0xFF39D353),
      fontFamily: 'monospace',
    ),
  );

  /// Creates a [RenderZContributionGraph].
  RenderZContributionGraph({
    required ZeroContributionBuffer buffer,
    required Size preferredSize,
  })  : _buffer = buffer,
        _preferredSize = preferredSize {
    _levelPaints = List<Paint>.generate(_levelColors.length, (i) {
      return Paint()
        ..color = _levelColors[i]
        ..style = PaintingStyle.fill;
    }, growable: false);
  }

  /// Contribution buffer.
  ZeroContributionBuffer get buffer => _buffer;
  set buffer(ZeroContributionBuffer value) {
    if (identical(_buffer, value)) return;
    if (attached) {
      _buffer.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _buffer = value;
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
    _buffer.addListener(markDirty);
  }

  @override
  void detach() {
    _buffer.removeListener(markDirty);
    super.detach();
  }

  @override
  void dispose() {
    _streakPainter.dispose();
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
    const double headerH = 18.0;
    const double gap = 2.0;
    final int weeks = _buffer.weeks;
    final int days = _buffer.daysPerWeek;
    final double cellW = math.max(2.0, (size.width - (weeks - 1) * gap) / weeks);
    final double cellH =
        math.max(2.0, (size.height - headerH - (days - 1) * gap) / days);
    const Radius r = Radius.circular(2.0);

    _streakPainter.paintInt(
      canvas,
      Offset(offset.dx + 2.0, offset.dy),
      _buffer.activeCount,
      minDigits: 3,
    );

    for (int w = 0; w < weeks; w++) {
      final double x = offset.dx + w * (cellW + gap);
      for (int d = 0; d < days; d++) {
        final double y = offset.dy + headerH + d * (cellH + gap);
        final int lvl = _buffer.levelAt(w, d);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, y, cellW, cellH), r),
          _levelPaints[lvl],
        );
      }
    }
  }
}
