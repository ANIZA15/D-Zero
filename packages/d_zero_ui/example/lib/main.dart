import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_ui/d_zero_ui.dart';

void main() {
  runApp(const DZeroUiBenchmarkApp());
}

enum UiBenchMode { dZero, traditional }

class DZeroUiBenchmarkApp extends StatelessWidget {
  const DZeroUiBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UI コンポーネント',
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
      home: const UiBenchmarkScreen(),
    );
  }
}

class UiBenchmarkScreen extends StatefulWidget {
  const UiBenchmarkScreen({super.key});

  @override
  State<UiBenchmarkScreen> createState() => _UiBenchmarkScreenState();
}

class _UiBenchmarkScreenState extends State<UiBenchmarkScreen>
    implements ZeroSlottedFrameListener {
  UiBenchMode _mode = UiBenchMode.dZero;
  int _schedulerSlot = -1;
  double _phase = 0.0;
  int _dZeroRebuilds = 0;
  int _tradRebuilds = 0;
  bool _resettingMode = true;

  final ZeroIntNotifier _badgeCount = ZeroIntNotifier(3);
  final ValueNotifier<bool> _switchVal = ValueNotifier<bool>(true);
  final ValueNotifier<double> _sliderVal = ValueNotifier<double>(0.65);
  final ZeroDoubleNotifier _gaugeVal = ZeroDoubleNotifier(72.0);
  final ValueNotifier<double> _knobVal = ValueNotifier<double>(0.5);
  final ZeroDoubleNotifier _tabPos = ZeroDoubleNotifier(0.0);
  final ZeroDoubleNotifier _ratingVal = ZeroDoubleNotifier(4.5);
  final ZeroDoubleNotifier _progressVal = ZeroDoubleNotifier(0.65);
  late final ZeroRangeValuesController _rangeCtrl;
  late final ZeroStoryProgressController _storyCtrl;

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _rangeCtrl = ZeroRangeValuesController(0.2, 0.8);
    _storyCtrl = ZeroStoryProgressController(segmentCount: 4);
    ZeroFrameScheduler.instance.subscribe(this);
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    _phase += 0.04;
    _gaugeVal.value = 50.0 + math.sin(_phase) * 40.0;
    _progressVal.value = (0.5 + 0.45 * math.sin(_phase)).clamp(0.05, 0.95);
    _storyCtrl.advance(0.006);

    if (_mode == UiBenchMode.traditional) {
      setState(() {});
    }
  }

  void _recordRebuild(bool isDZero) {
    if (_resettingMode) {
      _resettingMode = false;
      return;
    }
    if (isDZero) {
      _dZeroRebuilds++;
    } else {
      _tradRebuilds++;
    }
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _badgeCount.dispose();
    _switchVal.dispose();
    _sliderVal.dispose();
    _gaugeVal.dispose();
    _knobVal.dispose();
    _tabPos.dispose();
    _ratingVal.dispose();
    _progressVal.dispose();
    _rangeCtrl.dispose();
    _storyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDZero = _mode == UiBenchMode.dZero;
    _recordRebuild(isDZero);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'UI コンポーネント',
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
                  SegmentedButton<UiBenchMode>(
                    segments: const [
                      ButtonSegment(
                        value: UiBenchMode.dZero,
                        label: Text('D-Zero'),
                      ),
                      ButtonSegment(
                        value: UiBenchMode.traditional,
                        label: Text('従来'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() {
                      _mode = s.first;
                      _resettingMode = true;
                    }),
                  ),
                  const SizedBox(height: 16),
                  isDZero ? _buildDZeroUiCard() : _buildTraditionalUiCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDZeroUiCard() {
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
                  'D-Zero コントロール',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'Rebuild: $_dZeroRebuilds',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ZStoryProgressBar(controller: _storyCtrl),
            const SizedBox(height: 16),
            ZSegmentedControl(
              segments: const ['すべて', '進行中', '完了'],
              positionListenable: _tabPos,
            ),
            const Divider(height: 24, color: Color(0xFFF1F5F9)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '通知スイッチ (ZSwitch)',
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF475569)),
                ),
                ZSwitch(valueListenable: _switchVal, controller: _switchVal),
              ],
            ),
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '評価 (ZRatingBar)',
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF475569)),
                ),
                ZRatingBar(ratingListenable: _ratingVal),
              ],
            ),
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'バッジ & ボタン',
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF475569)),
                ),
                ZBadge(
                  countListenable: _badgeCount,
                  child: ZButton(
                    label: '+1 追加',
                    onPressed: () => _badgeCount.add(1),
                  ),
                ),
              ],
            ),
            const Divider(height: 24, color: Color(0xFFF1F5F9)),
            const Text(
              'スライダー (ZSlider / ZRangeSlider)',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 28,
              child: ZSlider(
                valueListenable: _sliderVal,
                controller: _sliderVal,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 28,
              child: ZRangeSlider(controller: _rangeCtrl),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 18,
              child: ZLinearProgress(
                valueListenable: _progressVal,
                showPercentage: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTraditionalUiCard() {
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
                  '従来 (Material Widgets)',
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
            const Divider(height: 24, color: Color(0xFFF1F5F9)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '通知スイッチ',
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF475569)),
                ),
                Switch(
                  value: _switchVal.value,
                  onChanged: (v) => setState(() => _switchVal.value = v),
                ),
              ],
            ),
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'バッジ & ボタン',
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF475569)),
                ),
                Badge(
                  label: Text('${_badgeCount.value}'),
                  child: FilledButton.tonal(
                    onPressed: () => setState(() => _badgeCount.add(1)),
                    child: const Text('+1 追加'),
                  ),
                ),
              ],
            ),
            const Divider(height: 24, color: Color(0xFFF1F5F9)),
            Slider(
              value: _sliderVal.value,
              onChanged: (v) => setState(() => _sliderVal.value = v),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _progressVal.value),
          ],
        ),
      ),
    );
  }
}
