# ⚡️ d_zero_waveform

**Zero-allocation real-time audio waveform, FFT spectrum analyzer, and VU peak meter widgets for Flutter and Impeller.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](../../LICENSE)
[![Impeller: Vulkan & Metal](https://img.shields.io/badge/Impeller-Vulkan%20%2F%20Metal-red.svg?style=flat-square)](https://flutter.dev/to/impeller)

---

## 📦 Distributed `Z` Widgets & Controllers

| Widget | Active Alias | Controller | Zero-Allocation Architecture |
| :--- | :--- | :--- | :--- |
| **`ZWaveform`** | `ZAudioVisualizer` | `ZeroWaveformController` | Backed by a fixed-capacity `FloatRingBuffer` (`-1.0..1.0` PCM amplitudes) and rendered in a single `Canvas.drawRawPoints(PointMode.lines)` batch with `ZeroNumberPainter` peak readout. |
| **`ZSpectrumAnalyzer`** | - | `ZeroSpectrumController` | Contiguous `Float32List` FFT magnitude bins + peak-hold decay buffer rendered with pre-allocated `Paint` instances (`0` widget rebuilds). |
| **`ZAudioMeter`** | `ZVUMeter` | `ZeroAudioMeterController` | Stereo L/R RMS & peak-hold VU meter with segmented green/yellow/red zones and `ZeroNumberPainter` dB readout. |

---

## 🚀 Installation & Usage

```yaml
dependencies:
  d_zero_waveform: ^0.1.0
```

```dart
import 'package:flutter/material.dart';
import 'package:d_zero_waveform/d_zero_waveform.dart';

final waveformCtrl = ZeroWaveformController(capacity: 128)..pushSample(0.45);
final spectrumCtrl = ZeroSpectrumController(binCount: 32);
final meterCtrl = ZeroAudioMeterController()..updateLevels(leftRms: 0.72, rightRms: 0.68);

Column(
  children: [
    SizedBox(height: 80, child: ZWaveform(controller: waveformCtrl)),
    SizedBox(height: 80, child: ZSpectrumAnalyzer(controller: spectrumCtrl)),
    SizedBox(height: 40, child: ZAudioMeter(controller: meterCtrl)),
  ],
);
```

---

## 📱 High-Load Comparison Benchmark App (`example/`)

The [`example/`](example) app streams 120Hz PCM samples, 32-bin FFT magnitudes, and stereo RMS levels simultaneously, comparing `d_zero_waveform` against traditional `Row`/`Container` FFT bars and `LinearProgressIndicator` meters with live **FPS, UI CPU Load (%), RSS Memory (MB), and Rebuild counters**.

```bash
cd packages/d_zero_waveform/example
flutter run
```

## 📄 License

MIT License © 2026 fexcy
