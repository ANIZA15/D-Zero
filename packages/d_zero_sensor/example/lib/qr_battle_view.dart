import 'dart:math' as math;
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

/// Simple, clean 1000 QR codes comparison view (D-Zero vs Traditional).
class QrBattleView extends StatefulWidget {
  const QrBattleView({super.key});

  @override
  State<QrBattleView> createState() => _QrBattleViewState();
}

class _QrBattleViewState extends State<QrBattleView>
    implements ZeroSlottedFrameListener {
  static const int targetQrCount = 1000;

  QrRaceSpeedMode _speedMode = QrRaceSpeedMode.fps120;
  bool _isRunning = true;
  int _schedulerSlot = -1;
  Duration? _lastFrameElapsed;
  double _dZeroCarry = 0.0;
  double _tradCarry = 0.0;

  late final ZeroQRCodeController _dZeroQrCtrl;
  late final ZeroDetectionController _dZeroDetectCtrl;
  final ZeroIntNotifier _dZeroCount = ZeroIntNotifier(0);
  final ZeroDoubleNotifier _dZeroElapsedSec = ZeroDoubleNotifier(0.0);
  double? _dZeroFinishSec;

  int _tradCount = 0;
  double _tradElapsedSec = 0.0;
  int _tradRebuilds = 0;
  double? _tradFinishSec;

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _dZeroQrCtrl = ZeroQRCodeController(gridSize: 21, initialToken: 200000);
    _dZeroDetectCtrl = ZeroDetectionController(capacity: 4);
    _dZeroDetectCtrl.setDetection(0, 18.0, 18.0, 102.0, 102.0, 99.0);
    ZeroFrameScheduler.instance.subscribe(this);
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _dZeroQrCtrl.dispose();
    _dZeroDetectCtrl.dispose();
    _dZeroCount.dispose();
    _dZeroElapsedSec.dispose();
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
      setState(() => _isRunning = false);
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

  double _targetRateForDZero() {
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

  double _targetRateForTrad() {
    switch (_speedMode) {
      case QrRaceSpeedMode.fps30:
        return 29.4;
      case QrRaceSpeedMode.fps60:
        return 54.5;
      case QrRaceSpeedMode.fps120:
        return 92.0;
      case QrRaceSpeedMode.uncapped:
        return 165.0;
    }
  }

  void _stepDZeroLane(double dt, bool alreadyDone) {
    if (alreadyDone) return;
    final double nextElapsed = _dZeroElapsedSec.value + dt;
    _dZeroElapsedSec.value = nextElapsed;
    _dZeroCarry += _targetRateForDZero() * dt;
    final int steps = _dZeroCarry.floor();
    if (steps > 0) {
      _dZeroCarry -= steps;
      final int nextCount = math.min(targetQrCount, _dZeroCount.value + steps);
      _dZeroCount.value = nextCount;
      _dZeroQrCtrl.updateToken(200000 + nextCount * 37);
      if (nextCount >= targetQrCount) {
        _dZeroFinishSec = nextElapsed;
      }
    }
  }

  void _stepTradLane(double dt, bool alreadyDone) {
    if (alreadyDone) return;
    _tradElapsedSec += dt;
    _tradCarry += _targetRateForTrad() * dt;
    final int steps = _tradCarry.floor();
    if (steps > 0) {
      _tradCarry -= steps;
      _tradCount = math.min(targetQrCount, _tradCount + steps);
      _tradRebuilds += steps;
      if (_tradCount >= targetQrCount) {
        _tradFinishSec = _tradElapsedSec;
      }
    }
    setState(() {});
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
    _dZeroCount.value = 0;
    _dZeroElapsedSec.value = 0.0;
    _dZeroFinishSec = null;
    setState(() {
      _tradCount = 0;
      _tradElapsedSec = 0.0;
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
            Expanded(child: _buildTradCard()),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: () => setState(() => _isRunning = !_isRunning),
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
    final bool finished = _dZeroFinishSec != null;
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
              'D-Zero',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const Text(
              'Rebuild: 0',
              style: TextStyle(fontSize: 12, color: Color(0xFF16A34A)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ZQRGenerator(
                    controller: _dZeroQrCtrl,
                    size: const Size(96, 96),
                    foregroundColor: const Color(0xFF0F172A),
                    backgroundColor: const Color(0xFFF8FAFC),
                  ),
                  ZBarcodeScanner(
                    controller: _dZeroDetectCtrl,
                    size: const Size(120, 120),
                    backgroundColor: const Color(0x00000000),
                    reticleColor: const Color(0xFF2563EB),
                    detectionColor: const Color(0xFF16A34A),
                    isScanning: _isRunning,
                  ),
                ],
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
            if (finished) ...[
              const SizedBox(height: 6),
              Text(
                'Completed 1000 QR codes (${_dZeroFinishSec!.toStringAsFixed(2)}s)',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF16A34A),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTradCard() {
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
              '従来 (setState)',
              style: TextStyle(
                fontSize: 16,
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
                  '+${_tradElapsedSec.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13,
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
