import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_waveform/d_zero_waveform.dart';

void main() {
  runApp(const DZeroWaveformBenchmarkApp());
}

enum WaveformBenchMode { dZero, traditional }

class DZeroWaveformBenchmarkApp extends StatelessWidget {
  const DZeroWaveformBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'オーディオ波形',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
          scrolledUnderElevation: 0.5,
          centerTitle: false,
        ),
      ),
      home: const WaveformBenchmarkScreen(),
    );
  }
}

class WaveformBenchmarkScreen extends StatefulWidget {
  const WaveformBenchmarkScreen({super.key});

  @override
  State<WaveformBenchmarkScreen> createState() =>
      _WaveformBenchmarkScreenState();
}

class _WaveformBenchmarkScreenState extends State<WaveformBenchmarkScreen>
    implements ZeroSlottedFrameListener {
  static const int _binCount = 24;

  WaveformBenchMode _mode = WaveformBenchMode.dZero;
  int _schedulerSlot = -1;
  double _phase = 0.0;
  int _tradRebuilds = 0;

  late final ZeroWaveformController _waveformCtrl;
  late final ZeroSpectrumController _spectrumCtrl;
  late final ZeroAudioMeterController _meterCtrl;
  final List<double> _scratchBins = List<double>.filled(
    _binCount,
    0.0,
    growable: false,
  );
  double _leftRms = 0.6;
  double _rightRms = 0.6;

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _waveformCtrl = ZeroWaveformController(capacity: 128);
    _spectrumCtrl = ZeroSpectrumController(binCount: _binCount);
    _meterCtrl = ZeroAudioMeterController();
    ZeroFrameScheduler.instance.subscribe(this);
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    _phase += 0.08;
    final double sample =
        (math.sin(_phase * 3.5) * 0.6 + math.cos(_phase * 8.0) * 0.35)
            .clamp(-1.0, 1.0);
    _waveformCtrl.pushSample(sample);

    for (int i = 0; i < _binCount; i++) {
      _scratchBins[i] =
          (0.45 + 0.45 * math.sin(_phase * 2.1 + i * 0.28)).clamp(0.05, 0.98);
    }
    _spectrumCtrl.updateBins(_scratchBins);

    _leftRms = (0.55 + 0.40 * math.sin(_phase * 1.8)).clamp(0.05, 0.98);
    _rightRms = (0.52 + 0.42 * math.cos(_phase * 2.0)).clamp(0.05, 0.98);
    _meterCtrl.updateLevels(leftRms: _leftRms, rightRms: _rightRms);

    if (_mode == WaveformBenchMode.traditional) {
      _tradRebuilds++;
      setState(() {});
    }
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _waveformCtrl.dispose();
    _spectrumCtrl.dispose();
    _meterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDZero = _mode == WaveformBenchMode.dZero;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'オーディオ波形',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<WaveformBenchMode>(
                    segments: const [
                      ButtonSegment(
                        value: WaveformBenchMode.dZero,
                        label: Text('D-Zero'),
                      ),
                      ButtonSegment(
                        value: WaveformBenchMode.traditional,
                        label: Text('従来'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) =>
                        setState(() => _mode = s.first),
                  ),
                  const SizedBox(height: 16),
                  isDZero ? _buildDZeroCard() : _buildTradCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDZeroCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'D-Zero 波形 & スペクトラム',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'Rebuild: 0',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 85,
                child: ZWaveform(
                  controller: _waveformCtrl,
                  backgroundColor: const Color(0xFF0F172A),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 85,
                child: ZSpectrumAnalyzer(
                  controller: _spectrumCtrl,
                  backgroundColor: const Color(0xFF0F172A),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(height: 36, child: ZAudioMeter(controller: _meterCtrl)),
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
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '従来 (setState + Container)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'Rebuild: $_tradRebuilds',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              height: 85,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (int i = 0; i < _binCount; i++)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        height: 64.0 * _scratchBins[i],
                        color: const Color(0xFF2563EB),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(value: _leftRms),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _rightRms),
          ],
        ),
      ),
    );
  }
}
