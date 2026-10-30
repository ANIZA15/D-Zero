# Contributing to D-Zero

Thank you for your interest in contributing to **D-Zero**!  
`D-Zero` is an ultra-high-performance, zero-allocation, zero-rebuild widget suite engineered for Flutter and Impeller (60fps / 120fps ProMotion).

Every contribution must strictly adhere to the architectural and quality standards below.

---

## 🛠️ Development Environment Setup

### Prerequisites
* **Flutter SDK**: `>=3.24.0` (Dart SDK `>=3.5.0 <4.0.0`)
* **Melos**: Workspace task runner (`dart pub global activate melos`)

### Bootstrap Workspace
```bash
# Resolve all workspace packages via Dart Pub Workspaces
flutter pub get
```

---

## 📏 Core Engineering Rules

### 1. Z-Prefix Widget Naming Rule
* Every public widget class distributed to external developers **must start with `Z`** (e.g., `ZPlayer`, `ZCounter`, `ZSparkline`, `ZParticles`, `ZSlider`).
* When renaming or aliasing a widget, provide a `@Deprecated` typedef for backwards compatibility.
* Internal `RenderBox` implementations should be named `RenderZ...` (e.g., `RenderZCounter`, `RenderZSparkline`) and extend `ZeroRenderBox`.

### 2. Zero Rebuild & Zero Allocation Hot Paths
* **Never call `State.setState()` on hot paths** (60Hz/120Hz timers, video frames, audio samples, pointer move events).
* All visual updates must flow through `ZLeafWidget` / `ZSingleChildWidget` + `ZeroRenderBox.markDirty()` (`markNeedsPaint()`), with `isRepaintBoundary = true`.
* **Zero Per-Frame Heap Allocations**:
  * Do not allocate `String` (`int.toString()`, string interpolation), `Paint`, `Path`, `TextPainter`, or closures inside `paint()` or `onZeroFrame()`.
  * Render dynamic numbers, currencies, percentages, and timecodes using `ZeroNumberPainter` (shared GPU glyph atlas via `Canvas.drawRawAtlas`).
  * Use contiguous typed buffers (`Float32List`, `FloatRingBuffer`, `ZeroPool<T>`) for simulation and streaming state.

### 3. Cyclomatic Complexity Limit (CC <= 15)
* **Recommended**: Keep cyclomatic complexity (McCabe metric) **$\le 10$** per method/function.
* **Strict Hard Limit**: No method or function may exceed **15** (`CC > 15` fails CI).
* Use guard clauses (early returns), helper extraction, and lookup tables to keep `paint()` and gesture handlers simple.

### 4. Strict Memory & Lifecycle Tests
Every new widget or controller must include tests in `packages/<package>/test/` covering:
1. **Unmount & Listener Cleanup**: Verify that unmounting the widget (`await tester.pumpWidget(const SizedBox.shrink())`) unsubscribes from `ZeroFrameScheduler` and `ValueListenable` without throwing on subsequent notifications.
2. **Idempotent `dispose()` (Double-Free Resilience)**: Verify that calling `dispose()` multiple times consecutively is a safe no-op.
3. **Post-Dispose Access (Use-After-Free Resilience)**: Verify that reading properties or invoking methods after `dispose()` returns safe fallback values rather than crashing.

---

## ✅ Pre-Pull Request Quality Gates

Before submitting a Pull Request, run all four verification commands from the repository root and ensure they pass with zero warnings or errors:

```bash
# 1. Static Analysis across all packages and examples
flutter analyze

# 2. Cyclomatic Complexity Check (enforces CC <= 15 on all functions)
dart run tool/check_complexity.dart

# 3. Unit, Widget Lifecycle & Memory Safety Tests
flutter test packages/d_zero_core/test packages/d_zero_counter/test packages/d_zero_player/test packages/d_zero_ui/test packages/d_zero_chart/test packages/d_zero_waveform/test packages/d_zero_particles/test packages/d_zero_fx/test packages/d_zero_canvas/test packages/d_zero_sensor/test

# 4. Distribution & Z-Prefix Audit (Dry-Run)
dart run tool/distribute_widgets.dart --sync-only

# 5. Terminal Microbenchmarks (Optional / Recommended for core changes)
dart run benchmarks/run_benchmarks.dart
```
