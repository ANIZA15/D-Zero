# ⚡️ d_zero_counter

**A zero-allocation, zero-rebuild high-frequency counter, stopwatch, countdown, odometer, price ticker, and FPS monitor suite for Flutter / Impeller.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](../../LICENSE)
[![Impeller: Vulkan & Metal](https://img.shields.io/badge/Impeller-Vulkan%20%2F%20Metal-red.svg?style=flat-square)](https://flutter.dev/to/impeller)

---

## 📦 Distributed `Z` Widgets

| Widget | Active Alias | Legacy Alias | Description |
| :--- | :--- | :--- | :--- |
| **`ZCounter`** | - | `ZeroCounter` | Renders rapidly updating integer counters directly to the Impeller `Canvas` via `ZeroNumberPainter` (`0` rebuilds, `0` `String` allocations). |
| **`ZStopwatch`** | - | `ZeroStopwatch` | High-precision 120fps V-Sync stopwatch (`MM:SS.cc` or `HH:MM:SS.cc`) driven directly by `ZeroRenderBox`. |
| **`ZCountdown`** | - | `ZeroCountdown` | Zero-allocation countdown timer supporting warning threshold styling (`warningStyle`, `warningThreshold`) and `onFinished` callback. |
| **`ZOdometer`** | `ZAnimatedNumber` | `ZeroOdometer` | Rolling mechanical digit display using vertical `Canvas.clipRect` interpolation without `String` formatting. |
| **`ZPriceTicker`** | `ZCurrencyLabel` | `ZeroPriceTicker` | Financial & telemetry ticker with directional flash background (up/down color decay) and prefix/suffix glyph support (`$`, `¥`, `%`, `+`). |
| **`ZFPSMonitor`** | `ZFrameOverlay` | `ZeroFPSMonitor` | Self-contained 60-frame rolling histogram (`FloatRingBuffer`) and live `FPS` / `ms` HUD overlay. |

---

## 🚀 Installation & Usage

```yaml
dependencies:
  d_zero_counter: ^0.1.0
```

```dart
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';

final counter = ZeroIntNotifier(0);
final btcPrice = ZeroDoubleNotifier(64250.50);
final odometer = ZeroDoubleNotifier(12840.0);

Column(
  children: [
    // 1. Live FPS & Frame Histogram HUD
    const ZFPSMonitor(size: Size(148, 44)),

    // 2. High-Frequency Integer Counter
    ZCounter(
      valueListenable: counter,
      minDigits: 6,
      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
    ),

    // 3. Financial Price Ticker with Directional Flash
    ZPriceTicker(
      valueListenable: btcPrice,
      currencyGlyph: ZeroNumberPainter.glyphDollar,
      fractionDigits: 2,
      style: const TextStyle(fontSize: 24, color: Colors.greenAccent),
    ),

    // 4. Rolling Mechanical Odometer
    ZOdometer(
      valueListenable: odometer,
      minDigits: 5,
      style: const TextStyle(fontSize: 24, color: Colors.cyanAccent),
    ),

    // 5. 120fps V-Sync Stopwatch & Countdown
    const ZStopwatch(isRunning: true, includeHours: true),
    const ZCountdown(duration: Duration(minutes: 5), isRunning: true),
  ],
);
```

---

## 📱 High-Load Comparison Benchmark App (`example/`)

The [`example/`](example) app stresses a 36-cell financial ticker wall + stopwatch + countdown + odometer at 120Hz, comparing `d_zero_counter` (`0` rebuilds, `0` string allocations) against traditional `setState` + `Text(val.toStringAsFixed(2))` with live **FPS, CPU Load (%), RSS Memory (MB), and Rebuild counters**.

```bash
cd packages/d_zero_counter/example
flutter run
```

## 📄 License

MIT License © 2026 fexcy
