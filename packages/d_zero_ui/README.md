# ⚡️ d_zero_ui

**Zero-allocation, zero-rebuild high-frequency UI controls (cards, badges, buttons, switches, sliders, gauges, progress bars, marquee, typewriter, joystick, rotary knob) for Flutter and Impeller.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](../../LICENSE)
[![Impeller: Vulkan & Metal](https://img.shields.io/badge/Impeller-Vulkan%20%2F%20Metal-red.svg?style=flat-square)](https://flutter.dev/to/impeller)

---

## 📦 Distributed `Z` Widgets (22 Widgets + 17 Active Aliases)

| Widget | Active `Z` Alias | Key Zero-Allocation Mechanism |
| :--- | :--- | :--- |
| **`ZTerminal`** | `ZLogStream` | Single-pass GPU glyph atlas (`Canvas.drawRawAtlas`) monospace terminal / log viewer backed by a circular `Uint16List` ring buffer (`0` `String` / `TextPainter` allocations per frame). |
| **`ZWheelPicker`** | `ZDrumRollPicker` | 3D cylindrical drum-roll picker (`ZeroWheelPickerController`) using cosine depth scaling and `ZeroNumberPainter` with `0` `ListWheelScrollView` child rebuilds. |
| **`ZSegmentedControl`** | `ZSlidingTabBar` | Continuous spring-interpolated sliding pill indicator (`ValueListenable<double>`) with pre-laid-out label painters (`0` `TabBar` rebuilds). |
| **`ZPageIndicator`** | `ZWormIndicator` | Expanding worm-style carousel page indicator rendered directly in `ZeroRenderBox` (`0` dot widget allocations). |
| **`ZRatingBar`** | `ZStarRating` | Fractional 5-star rating bar using a single cached star path and `Canvas.clipRect` partial fill (`0` icon rebuilds). |
| **`ZPullToRefresh`** | `ZRefreshHeader` | Interactive pull-to-refresh header arc (`ValueListenable<double>`) with `ZeroNumberPainter.paintPercent` readout. |
| **`ZNumberPad`** | `ZPinPad` | Zero-rebuild 4x3 numeric keypad + PIN indicator dots (`ZeroNumberPadController`) using `ZeroNumberPainter` (`0` button widgets). |
| **`ZStoryProgressBar`** | `ZSegmentedProgress` | Multi-segment story progress bar (`ZeroStoryProgressController`) with 120fps active segment fill (`0` `Row`/`LinearProgressIndicator` rebuilds). |
| **`ZStreamingMarkdown`** | `ZTokenStream` | AI LLM streaming token view (`ZeroTokenStreamController`) backed by a circular `Uint16List` glyph ring buffer and `Canvas.drawRawAtlas` (`0` `String` concatenations per token). |
| **`ZCard`** | `ZSurfaceCard` | Single-`RenderBox` surface container with pre-baked elevation bands, border, and pointer highlight (`0` `saveLayer`). |
| **`ZBadge`** | `ZNotificationBadge` | Renders `1..99` and `99+` notification counts via `ZeroNumberPainter` with `0` `String` allocations. |
| **`ZButton`** | `ZActionButton` | Direct pointer hit-testing and `ZeroFrameScheduler` splash animation with reactive `enabledListenable`. |
| **`ZSwitch`** | `ZToggle` | Pre-allocated 16-step track/thumb `Paint` palette interpolation with `0` widget rebuilds. |
| **`ZSlider`** | - | Direct `RenderBox` pointer drag with optional `ZeroNumberPainter.paintDouble` readout. |
| **`ZRangeSlider`** | - | Dual-thumb range slider driven by `ZeroRangeValuesController` with zero rebuilds. |
| **`ZLinearProgress`** | - | Direct track/bar renderer with optional `ZeroNumberPainter.paintPercent` readout. |
| **`ZCircularProgress`** | - | Radial arc progress indicator with centered `ZeroNumberPainter.paintPercent` label. |
| **`ZGauge`** | `ZSpeedometer` | Caches dial tick marks in a GPU `ui.Picture` and draws active needle + `ZeroNumberPainter` readout. |
| **`ZJoystick`** | `ZVirtualPad` | Virtual 2D analog stick backed by `ZeroJoystickController` (`Float32List(2)` vector, `0` `Offset` heap allocations). |
| **`ZKnob`** | `ZRotaryDial` | DAW-style vertical drag rotary dial with `ZeroNumberPainter` center value. |
| **`ZMarquee`** | `ZRollingText` | Infinite smooth-scrolling banner using a single cached `TextPainter` tiled horizontally (`0` allocations/frame). |
| **`ZTypewriterText`** | - | Progressive character reveal using `TextPainter.getOffsetForCaret` + `Canvas.clipRect` (`0` `substring()` allocations). |

---

## 🚀 Installation & Usage

```yaml
dependencies:
  d_zero_ui: ^0.1.0
```

```dart
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_ui/d_zero_ui.dart';

final badgeCount = ZeroIntNotifier(5);
final toggleState = ValueNotifier<bool>(true);
final sliderValue = ValueNotifier<double>(0.65);
final rangeCtrl = ZeroRangeValuesController(0.2, 0.8);
final speedValue = ZeroDoubleNotifier(78.5);
final joystickCtrl = ZeroJoystickController();

ZCard(
  padding: const EdgeInsets.all(16),
  child: Column(
    children: [
      const SizedBox(height: 24, child: ZMarquee(text: '⚡️ Zero-Rebuild UI Controls   ')),
      const SizedBox(height: 24, child: ZTypewriterText(text: 'Revealed without substring()!')),
      Row(
        children: [
          ZBadge(
            countListenable: badgeCount,
            child: ZButton(label: 'Increment', onPressed: () => badgeCount.add(1)),
          ),
          ZSwitch(controller: toggleState),
        ],
      ),
      SizedBox(height: 28, child: ZSlider(controller: sliderValue)),
      SizedBox(height: 28, child: ZRangeSlider(controller: rangeCtrl)),
      SizedBox(height: 16, child: ZLinearProgress(valueListenable: sliderValue, showPercentage: true)),
      Row(
        children: [
          SizedBox(width: 96, height: 96, child: ZGauge(valueListenable: speedValue, min: 0, max: 100)),
          ZKnob(controller: sliderValue, min: 0, max: 1),
          ZJoystick(controller: joystickCtrl),
        ],
      ),
    ],
  ),
);
```

---

## 📱 High-Load Comparison Benchmark App (`example/`)

The [`example/`](example) app modulates 20+ progress bars, gauges, knobs, sliders, badges, and text animations at 120Hz, comparing `d_zero_ui` against Material widgets with live **FPS, UI CPU Load (%), RSS Memory (MB), Rebuilds, and Allocations**.

```bash
cd packages/d_zero_ui/example
flutter run
```

## 📄 License

MIT License © 2026 fexcy
