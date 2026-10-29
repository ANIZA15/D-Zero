import 'dart:typed_data';
import 'package:flutter/rendering.dart';

/// A zero-allocation number painter that paints integer numbers, timestamps, and timecodes
/// directly to the Canvas without allocating any [String] or [TextSpan] on the Dart heap.
class ZeroNumberPainter {
  final TextStyle style;
  final TextDirection textDirection;

  // Cached TextPainters for digits '0'..'9' and separators
  final List<TextPainter> _digitPainters = List.generate(
    10,
    (index) => TextPainter(textDirection: TextDirection.ltr),
  );
  late final TextPainter _colonPainter;
  late final TextPainter _dotPainter;
  late final TextPainter _dashPainter;
  late final TextPainter _slashPainter;
  late final TextPainter _spaceSlashSpacePainter;

  // Cached dimensions
  final Float64List _digitWidths = Float64List(10);
  double _digitHeight = 0.0;
  double _colonWidth = 0.0;
  double _dotWidth = 0.0;
  double _dashWidth = 0.0;
  double _slashWidth = 0.0;
  double _spaceSlashSpaceWidth = 0.0;
  double _maxDigitWidth = 0.0;

  // Reusable scratch buffer for digit extraction (up to 32 digits, never reallocated)
  final Uint8List _digitBuffer = Uint8List(32);
  bool _isDisposed = false;

  /// Whether this painter has been disposed.
  bool get isDisposed => _isDisposed;

  ZeroNumberPainter({
    this.style = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 14.0,
      fontFamily: 'monospace',
    ),
    this.textDirection = TextDirection.ltr,
  }) {
    _colonPainter = TextPainter(textDirection: textDirection);
    _dotPainter = TextPainter(textDirection: textDirection);
    _dashPainter = TextPainter(textDirection: textDirection);
    _slashPainter = TextPainter(textDirection: textDirection);
    _spaceSlashSpacePainter = TextPainter(textDirection: textDirection);
    _initPainters();
  }

  void _initPainters() {
    _maxDigitWidth = 0.0;
    for (int i = 0; i < 10; i++) {
      _digitPainters[i].text = TextSpan(text: i.toString(), style: style);
      _digitPainters[i].layout();
      final width = _digitPainters[i].width;
      _digitWidths[i] = width;
      if (width > _maxDigitWidth) {
        _maxDigitWidth = width;
      }
      if (_digitPainters[i].height > _digitHeight) {
        _digitHeight = _digitPainters[i].height;
      }
    }

    _colonPainter.text = TextSpan(text: ':', style: style);
    _colonPainter.layout();
    _colonWidth = _colonPainter.width;

    _dotPainter.text = TextSpan(text: '.', style: style);
    _dotPainter.layout();
    _dotWidth = _dotPainter.width;

    _dashPainter.text = TextSpan(text: '-', style: style);
    _dashPainter.layout();
    _dashWidth = _dashPainter.width;

    _slashPainter.text = TextSpan(text: '/', style: style);
    _slashPainter.layout();
    _slashWidth = _slashPainter.width;

    _spaceSlashSpacePainter.text = TextSpan(text: ' / ', style: style);
    _spaceSlashSpacePainter.layout();
    _spaceSlashSpaceWidth = _spaceSlashSpacePainter.width;
  }

  /// Height of the rendered digits.
  double get height => _digitHeight;

  /// Max width of a single digit (useful for fixed-pitch spacing).
  double get maxDigitWidth => _maxDigitWidth;

  /// Width of "." delimiter.
  double get dotWidth => _dotWidth;

  /// Width of "/" delimiter.
  double get slashWidth => _slashWidth;

  /// Width of " / " delimiter.
  double get spaceSlashSpaceWidth => _spaceSlashSpaceWidth;

  /// Calculates expected width for a timecode formatted as "MM:SS / MM:SS".
  double estimateTimeProgressWidth({bool includeHours = false}) {
    final timeWidth = estimateTimecodeWidth(includeHours: includeHours);
    return timeWidth * 2 + _spaceSlashSpaceWidth;
  }

  /// Calculates expected width for a single timecode "MM:SS" (or "HH:MM:SS").
  double estimateTimecodeWidth({bool includeHours = false}) {
    if (includeHours) {
      return (_maxDigitWidth * 6) + (_colonWidth * 2);
    }
    return (_maxDigitWidth * 4) + _colonWidth;
  }

  /// Paints an integer [value] onto [canvas] at [offset].
  ///
  /// Zero-allocation: extracts digits purely via modulo and integer division into a reusable buffer.
  /// [minDigits] pads with leading zeros if specified.
  /// Returns the total painted width.
  double paintInt(
    Canvas canvas,
    Offset offset,
    int value, {
    int minDigits = 1,
    bool monospaceAlignment = true,
  }) {
    if (value < 0) {
      _dashPainter.paint(canvas, offset);
      final double dashW = monospaceAlignment ? _maxDigitWidth : _dashWidth;
      return dashW +
          paintInt(
            canvas,
            Offset(offset.dx + dashW, offset.dy),
            -value,
            minDigits: minDigits,
            monospaceAlignment: monospaceAlignment,
          );
    }

    int count = 0;
    int temp = value;
    if (temp == 0) {
      _digitBuffer[0] = 0;
      count = 1;
    } else {
      while (temp > 0) {
        _digitBuffer[count++] = temp % 10;
        temp ~/= 10;
      }
    }

    while (count < minDigits && count < _digitBuffer.length) {
      _digitBuffer[count++] = 0;
    }

    double currentX = offset.dx;
    // Digits were pushed LSD first, so read backwards for MSD first
    for (int i = count - 1; i >= 0; i--) {
      final digit = _digitBuffer[i];
      final painter = _digitPainters[digit];
      painter.paint(canvas, Offset(currentX, offset.dy));
      currentX += monospaceAlignment ? _maxDigitWidth : _digitWidths[digit];
    }

    return currentX - offset.dx;
  }

  /// Paints a timecode in format "MM:SS" or "HH:MM:SS" (if [includeHours] is true)
  /// given [milliseconds]. Completely allocation-free.
  double paintTimecode(
    Canvas canvas,
    Offset offset,
    int milliseconds, {
    bool includeHours = false,
  }) {
    final totalSec = milliseconds ~/ 1000;
    final hours = totalSec ~/ 3600;
    final minutes = (totalSec % 3600) ~/ 60;
    final seconds = totalSec % 60;

    double currentX = offset.dx;

    if (includeHours || hours > 0) {
      currentX += paintInt(canvas, Offset(currentX, offset.dy), hours, minDigits: 2);
      _colonPainter.paint(canvas, Offset(currentX, offset.dy));
      currentX += _colonWidth;
    }

    currentX += paintInt(canvas, Offset(currentX, offset.dy), minutes, minDigits: 2);
    _colonPainter.paint(canvas, Offset(currentX, offset.dy));
    currentX += _colonWidth;

    currentX += paintInt(canvas, Offset(currentX, offset.dy), seconds, minDigits: 2);

    return currentX - offset.dx;
  }

  /// Paints position and total duration in format "MM:SS / MM:SS".
  /// 100% Zero-allocation on the Dart heap.
  double paintTimeProgress(
    Canvas canvas,
    Offset offset,
    int positionMs,
    int durationMs, {
    bool includeHours = false,
  }) {
    double currentX = offset.dx;
    currentX += paintTimecode(canvas, Offset(currentX, offset.dy), positionMs, includeHours: includeHours);
    _spaceSlashSpacePainter.paint(canvas, Offset(currentX, offset.dy));
    currentX += _spaceSlashSpaceWidth;
    currentX += paintTimecode(canvas, Offset(currentX, offset.dy), durationMs, includeHours: includeHours);
    return currentX - offset.dx;
  }

  /// Disposes all underlying painters safely.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    for (final p in _digitPainters) {
      p.dispose();
    }
    _colonPainter.dispose();
    _dotPainter.dispose();
    _dashPainter.dispose();
    _slashPainter.dispose();
    _spaceSlashSpacePainter.dispose();
  }
}
