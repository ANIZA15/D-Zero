# ⚡️ d_zero_ui

**Zero-allocation, zero-rebuild high-frequency UI controls (sliders, gauges, progress, marquee, typewriter, joystick, knob) for Flutter and Impeller.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![Impeller: Vulkan & Metal](https://img.shields.io/badge/Impeller-Vulkan%20%2F%20Metal-red.svg?style=flat-square)](https://flutter.dev/to/impeller)

---

## 📦 Widgets

* **`ZMarquee` (`ZRollingText`)**: Infinite smooth scrolling text with a single cached `TextPainter` and 0 per-frame allocations.
* **`ZTypewriterText`**: Progressive character reveal via `Canvas.clipRect` and `getOffsetForCaret` with zero `substring()` allocations.
* **`ZLinearProgress` & `ZCircularProgress`**: Direct-to-Canvas progress indicators with `ZeroNumberPainter.paintPercent`.
* **`ZSlider` & `ZRangeSlider`**: Zero-rebuild pointer-driven sliders and `ZeroRangeValuesController`.
* **`ZGauge` (`ZSpeedometer`)**: Radial speedometer with `ui.Picture`-cached dial ticks and `ZeroNumberPainter` readout.
* **`ZJoystick` (`ZVirtualPad`)**: `Float32List`-backed virtual analog stick (`ZeroJoystickController`) with zero `Offset` allocations on hot paths.
* **`ZKnob` (`ZRotaryDial`)**: DAW-style rotary dial with vertical drag and zero-allocation center value rendering.

## 📄 License

MIT License © 2026 fexcy
