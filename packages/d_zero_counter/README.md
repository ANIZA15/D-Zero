# ⚡️ d_zero_counter

**A zero-allocation, zero-rebuild high-frequency counter and stopwatch widget suite for Flutter / Impeller.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![Impeller: Vulkan & Metal](https://img.shields.io/badge/Impeller-Vulkan%20%2F%20Metal-red.svg?style=flat-square)](https://flutter.dev/to/impeller)

---

## 📦 Distributed Widgets

* **`ZCounter`** (legacy alias: `ZeroCounter`):
  Renders rapidly updating integer counters directly to the Impeller `Canvas` via `ZeroNumberPainter` with 0 widget rebuilds and 0 string allocations per frame.
* **`ZStopwatch`** (legacy alias: `ZeroStopwatch`):
  High-precision 120fps stopwatch widget (`MM:SS.cc`) driven by a `Ticker` and direct `RenderBox` painting without `setState()`.

---

## 🚀 Usage

```dart
import 'package:flutter/material.dart';
import 'package:d_zero_counter/d_zero_counter.dart';

final counter = ValueNotifier<int>(0);

// Zero-rebuild counter widget
ZCounter(
  valueListenable: counter,
  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
);

// Zero-rebuild 120fps stopwatch widget
const ZStopwatch(
  isRunning: true,
  style: TextStyle(fontSize: 32, color: Colors.cyanAccent),
);
```

## 📄 License

MIT License © 2026 fexcy
