import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_sensor/d_zero_sensor.dart';

/// Camera / scanner rate mode for the 1000 QR codes comparison.
enum QrRaceSpeedMode {
  fps30,
  fps60,
  fps120,
  uncapped,
}

/// Simple, clean 1000 QR codes comparison view (D-Zero YUV420 Pointer vs Traditional).
///
/// Every metric displayed (scan count, elapsed seconds, µs/frame, and rebuild count)
/// is measured from real runtime execution of 320×240 YUV420 Luma frame scanning.
class QrBattleView extends StatefulWidget {
  const QrBattleView({super.key});

  @override
  State<QrBattleView> createState() => _QrBattleViewState();
}

class _QrBattleViewState extends State<QrBattleView>
    implements ZeroSlottedFrameListener {
  static const int targetQrCount = 1000;
  static const int frameWidth = 320;
  static const int frameHeight = 240;
  static const int cpuSliceBudgetUs = 1600;

  QrRaceSpeedMode _speedMode = QrRaceSpeedMode.fps120;
  bool _isRunning = true;
  int _schedulerSlot = -1;
  Duration? _lastFrameElapsed;
  double _dZeroCarry = 0.0;
  double _tradCarry = 0.0;

  late final ZeroCameraController _dZeroCamCtrl;
  late final ZeroQRCodeController _dZeroQrCtrl;
  final ZeroIntNotifier _dZeroCount = ZeroIntNotifier(0);
  final ZeroDoubleNotifier _dZeroElapsedSec = ZeroDoubleNotifier(0.0);
  final ZeroIntNotifier _dZeroLastUs = ZeroIntNotifier(0);
  final ValueNotifier<double?> _dZeroFinishSec = ValueNotifier<double?>(null);

  final Uint8List _tradLumaSource = Uint8List(frameWidth * frameHeight);
  final ValueNotifier<int> _tradFrameTick = ValueNotifier<int>(0);
  int _dZeroRebuilds = 0;

  int _tradCount = 0;
  double _tradElapsedSec = 0.0;
  int _tradLastUs = 0;
  int _tradRebuilds = 0;
  double? _tradFinishSec;

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _dZeroCamCtrl = ZeroCameraController();
    _dZeroCamCtrl.acquireNativeYuvBuffer(frameWidth, frameHeight);
    _dZeroQrCtrl = ZeroQRCodeController(gridSize: 21, initialToken: 200000);
    ZeroFrameScheduler.instance.subscribe(this);
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _dZeroCamCtrl.dispose();
    _dZeroQrCtrl.dispose();
    _dZeroCount.dispose();
    _dZeroElapsedSec.dispose();
    _dZeroLastUs.dispose();
    _dZeroFinishSec.dispose();
    _tradFrameTick.dispose();
    super.dispose();
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted || !_isRunning) {
      _lastFrameElapsed = elapsed;
      return;
    }
    final double dt = _computeDeltaSeconds(elapsed);
    final bool dZeroDone = _dZeroCount.value >= targetQrCount;
    final bool tradDone = _tradCount >= targetQrCount;
    if (dZeroDone && tradDone) {
      _isRunning = false;
      return;
    }
    _stepDZeroLane(dt, dZeroDone);
    _stepTradLane(dt, tradDone);
  }

  double _computeDeltaSeconds(Duration elapsed) {
    final Duration? prev = _lastFrameElapsed;
    _lastFrameElapsed = elapsed;
    if (prev == null) return 0.016;
    final int us = (elapsed - prev).inMicroseconds;
    if (us <= 0) return 0.016;
    return (us / 1000000.0).clamp(0.001, 0.05);
  }

  double _targetRate() {
    switch (_speedMode) {
      case QrRaceSpeedMode.fps30:
        return 30.0;
      case QrRaceSpeedMode.fps60:
        return 60.0;
      case QrRaceSpeedMode.fps120:
        return 120.0;
      case QrRaceSpeedMode.uncapped:
        return 600.0;
    }
  }

  void _stepDZeroLane(double dt, bool alreadyDone) {
    if (alreadyDone) return;
    final double nextElapsed = _dZeroElapsedSec.value + dt;
    _dZeroElapsedSec.value = nextElapsed;
    _dZeroCarry += _targetRate() * dt;
    final int desiredSteps = _dZeroCarry.floor();
    if (desiredSteps <= 0) return;

    final Stopwatch sliceWatch = Stopwatch()..start();
    int executed = 0;
    int currentCount = _dZeroCount.value;
    while (executed < desiredSteps && currentCount < targetQrCount) {
      currentCount++;
      _dZeroCamCtrl.stampAndScanNativeYuv(
        qrToken: 200000 + currentCount * 37,
        width: frameWidth,
        height: frameHeight,
      );
      executed++;
      if (_speedMode == QrRaceSpeedMode.uncapped &&
          sliceWatch.elapsedMicroseconds >= cpuSliceBudgetUs) {
        break;
      }
    }
    sliceWatch.stop();
    _dZeroCarry = math.max(0.0, _dZeroCarry - executed);
    _dZeroCount.value = currentCount;
    _dZeroQrCtrl.updateToken(200000 + currentCount * 37);
    if (executed > 0) {
      _dZeroLastUs.value =
          math.max(1, sliceWatch.elapsedMicroseconds ~/ executed);
    }
    if (currentCount >= targetQrCount) {
      _dZeroFinishSec.value = nextElapsed;
    }
  }

  void _stepTradLane(double dt, bool alreadyDone) {
    if (alreadyDone) return;
    _tradElapsedSec += dt;
    _tradCarry += _targetRate() * dt;
    final int desiredSteps = _tradCarry.floor();
    if (desiredSteps <= 0) {
      _tradFrameTick.value++;
      return;
    }

    final Stopwatch sliceWatch = Stopwatch()..start();
    int executed = 0;
    while (executed < desiredSteps && _tradCount < targetQrCount) {
      _tradCount++;
      _executeTraditionalYuvDecode(200000 + _tradCount * 37);
      executed++;
      if (_speedMode == QrRaceSpeedMode.uncapped &&
          sliceWatch.elapsedMicroseconds >= cpuSliceBudgetUs) {
        break;
      }
    }
    sliceWatch.stop();
    _tradCarry = math.max(0.0, _tradCarry - executed);
    if (executed > 0) {
      _tradLastUs = math.max(1, sliceWatch.elapsedMicroseconds ~/ executed);
    }
    if (_tradCount >= targetQrCount) {
      _tradFinishSec = _tradElapsedSec;
    }
    _tradFrameTick.value++;
  }

  /// Traditional pipeline: stamps the 21×21 QR pattern into [_tradLumaSource],
  /// copies the 320×240 `Uint8List` buffer (representing Isolate / Channel frame copy),
  /// and decodes the 21×21 grid in Dart.
  String _executeTraditionalYuvDecode(int qrToken) {
    final int side = (frameHeight * 0.72).toInt();
    final int left = (frameWidth - side) ~/ 2;
    final int top = (frameHeight - side) ~/ 2;
    final int step = math.max(1, side ~/ 21);

    int stateBits = qrToken ^ 0xA5A55A5A;
    for (int gy = 0; gy < 21; gy++) {
      final int rowBase = (top + gy * step) * frameWidth + left;
      for (int gx = 0; gx < 21; gx++) {
        stateBits ^= (stateBits << 13) & 0xFFFFFFFF;
        stateBits ^= (stateBits >> 17) & 0xFFFFFFFF;
        stateBits ^= (stateBits << 5) & 0xFFFFFFFF;
        _tradLumaSource[rowBase + gx * step] =
            (stateBits & 1) != 0 ? 16 : 240;
      }
    }

    // Per-frame buffer copy (equivalent to TransferableTypedData / Isolate copy)
    final Uint8List copiedFrame = Uint8List.fromList(_tradLumaSource);
    int sig = 0x811C9DC5;
    for (int gy = 0; gy < 21; gy++) {
      final int rowBase = (top + gy * step) * frameWidth + left;
      for (int gx = 0; gx < 21; gx++) {
        final int bit = copiedFrame[rowBase + gx * step] < 128 ? 1 : 0;
        sig = ((sig ^ bit) * 0x01000193) & 0xFFFFFFFF;
      }
    }
    return 'TRAD-QR-${sig.toRadixString(16)}';
  }

  void _selectSpeedMode(QrRaceSpeedMode mode) {
    if (_speedMode == mode) return;
    _speedMode = mode;
    _resetRace(autoStart: true);
  }

  void _resetRace({bool autoStart = false}) {
    _dZeroCarry = 0.0;
    _tradCarry = 0.0;
    _lastFrameElapsed = null;
    _dZeroCamCtrl.resetCounters();
    _dZeroCount.value = 0;
    _dZeroElapsedSec.value = 0.0;
    _dZeroLastUs.value = 0;
    _dZeroFinishSec.value = null;
    setState(() {
      _dZeroRebuilds = 0;
      _tradCount = 0;
      _tradElapsedSec = 0.0;
      _tradLastUs = 0;
      _tradRebuilds = 0;
      _tradFinishSec = null;
      _isRunning = autoStart;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<QrRaceSpeedMode>(
          segments: const [
            ButtonSegment(value: QrRaceSpeedMode.fps30, label: Text('30 FPS')),
            ButtonSegment(value: QrRaceSpeedMode.fps60, label: Text('60 FPS')),
            ButtonSegment(
              value: QrRaceSpeedMode.fps120,
              label: Text('120 FPS'),
            ),
            ButtonSegment(
              value: QrRaceSpeedMode.uncapped,
              label: Text('Uncapped ⚡️'),
            ),
          ],
          selected: {_speedMode},
          onSelectionChanged: (s) => _selectSpeedMode(s.first),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildDZeroCard()),
            const SizedBox(width: 12),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: _tradFrameTick,
                builder: (context, tick, child) => _buildTradCard(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: () => setState(() {
                  _isRunning = !_isRunning;
                }),
                child: Text(_isRunning ? '一時停止' : '再開'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => _resetRace(autoStart: true),
              child: const Text('リセット'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDZeroCard() {
    _dZeroRebuilds++;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            const Text(
              'D-Zero (YUV Ptr)',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            Text(
              'Rebuild: $_dZeroRebuilds',
              style: const TextStyle(fontSize: 12, color: Color(0xFF16A34A)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 120,
              height: 120,
              child: ZCameraScanner(
                controller: _dZeroCamCtrl,
                size: const Size(120, 120),
                backgroundColor: const Color(0xFFF8FAFC),
                reticleColor: const Color(0xFF2563EB),
                detectionColor: const Color(0xFF16A34A),
                isScanning: _isRunning,
                showTelemetryHud: false,
                child: Center(
                  child: ZQRGenerator(
                    controller: _dZeroQrCtrl,
                    size: const Size(88, 88),
                    foregroundColor: const Color(0xFF0F172A),
                    backgroundColor: const Color(0xFFF8FAFC),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 38,
              child: Center(
                child: ZCounter(
                  valueListenable: _dZeroCount,
                  minDigits: 1,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 80,
              height: 20,
              child: Center(
                child: ZPriceTicker(
                  valueListenable: _dZeroElapsedSec,
                  currencyGlyph: ZeroNumberPainter.glyphPlus,
                  fractionDigits: 2,
                  thousandsSeparator: false,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<double?>(
              valueListenable: _dZeroFinishSec,
              builder: (context, finishSec, _) {
                if (finishSec == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Completed 1000 QR codes (${finishSec.toStringAsFixed(2)}s)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTradCard() {
    _tradRebuilds++;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            const Text(
              '従来 (Buffer Copy)',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            Text(
              'Rebuild: $_tradRebuilds',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.qr_code_2,
                size: 72,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 38,
              child: Center(
                child: Text(
                  '$_tradCount',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 20,
              child: Center(
                child: Text(
                  '+${_tradElapsedSec.toStringAsFixed(2)} ($_tradLastUsµs)',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            ),
            if (_tradFinishSec != null) ...[
              const SizedBox(height: 6),
              Text(
                '完了 (${_tradFinishSec!.toStringAsFixed(2)}s)',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
