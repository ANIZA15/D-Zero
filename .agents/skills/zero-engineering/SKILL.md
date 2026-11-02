---
name: zero-engineering
description: >-
  Guide for developing, refactoring, and verifying high-performance components in D-Zero.
  Enforces Z-prefix Widget naming, Cyclomatic Complexity limits, and strict memory/lifecycle testing.
---

# D-Zero Engineering & Quality Guide

This skill provides step-by-step guidance for implementing and validating widgets, render boxes, and native FFI bindings in the `D-Zero` monorepo.

---

## 1. Z-Prefix Widget Guidelines

All public widgets intended for consumer apps must be prefixed with `Z`:
* Public Widgets: `ZPlayer`, `ZCounter`, `ZStopwatch`, `ZDirectSeekBar`, `ZDirectTimeLabel`.
* Backwards Compatibility: Whenever renaming, provide deprecated typedefs for legacy names:
  ```dart
  @Deprecated('Use ZPlayer instead.')
  typedef ZeroPlayerView = ZPlayer;
  ```
* RenderBox Class: Render objects created by widgets should follow `RenderZ...` or standard descriptive naming (e.g. `RenderZCounter` or `RenderZeroCounter`).

---

## 2. Cyclomatic Complexity (CC) Enforcement

1. **Thresholds**:
   * **Target / Ideal**: CC <= 10.
   * **Strict Maximum**: CC <= 15. Any function or method with CC > 15 must be refactored before merging.

2. **Refactoring Patterns to Reduce Complexity**:
   * **Guard Clauses (Early Return)**: Replace nested `if-else` blocks with upfront guard returns.
   * **Table-Driven / Map Lookup**: Replace multi-case switch statements or cascaded conditions with static lookup maps.
   * **Helper Decomposition**: Break large paint routines or event handlers into small, single-responsibility private methods.

3. **Running the Complexity Checker**:
   ```bash
   # From root:
   dart run tool/check_complexity.dart
   # Or via Melos:
   melos run complexity
   ```

---

## 3. Strict Memory & Lifecycle Testing

In zero-allocation and FFI projects, typical functional tests are insufficient. Every widget and controller must pass strict memory and lifecycle tests:

### 3.1 Widget Unmount & Lifecycle Verification
Verify that unmounting a widget clears all resources:
```dart
testWidgets('ZCounter cancels subscription and stops ticker on unmount', (tester) async {
  final notifier = ValueNotifier<int>(0);
  await tester.pumpWidget(ZCounter(valueListenable: notifier));

  // Unmount widget
  await tester.pumpWidget(const SizedBox.shrink());

  // Mutating notifier afterwards must not cause setState or memory leaks
  expect(() => notifier.value = 999, returnsNormally);
});
```

### 3.2 Native Memory & Double-Free / Use-After-Free Resilience
```dart
test('Controller survives double dispose and post-dispose access', () {
  final controller = ZeroPlayerController.simulated();
  controller.dispose();
  // Double-free should be a no-op
  expect(() => controller.dispose(), returnsNormally);
  // Reading properties post-dispose must return defaults rather than crash
  expect(controller.positionMs, equals(0));
});
```

### 3.3 Zero-Allocation in Paint Loop
* Hot paths must never instantiate new `Paint`, `Path`, `String`, or closures.
* Assert that painters reuse pre-allocated buffers and glyph caches (`ZeroNumberPainter`).

---

## 4. Sample App UI Design & True Telemetry Rule

### 4.1 Simple ToDo-App Style UI
All `packages/*/example` and `apps/*` sample apps must follow a clean, everyday **ToDo-app style** aesthetic without visual clutter:
1. **Clean Material 3 Light Theme**: Use light gray backgrounds (`#F8FAFC`), flat white `Card` containers (`elevation: 0`, `1px` `#E2E8F0` border), dark slate typography (`#0F172A` / `#475569`), and calm blue (`#2563EB`) / green (`#16A34A`) accents.
2. **No Neon / Cyber Clutter**: Avoid dark neon themes, verbose technical spec banners, or crowded multi-row telemetry HUDs.
3. **Minimal Layout**: Keep screens focused on a clean `AppBar`, a simple `D-Zero` vs `従来` `SegmentedButton`, a clean white `Card` showcasing the widget, and only essential metrics (e.g., FPS / CPU usage / Rebuild count).

### 4.2 Fair Comparison & Strict Prohibition of Fake or Hardcoded Telemetry
Benchmarks and sample apps must compare an **optimized, idiomatic Traditional Flutter implementation** against **D-Zero** under completely fair conditions, and displaying fake, hardcoded, or artificially inflated/deflated metrics is strictly forbidden:
1. **Fair & Optimized Traditional Baseline**: The Traditional (`従来`) mode must be implemented in a properly optimized state (e.g., reusing a pre-allocated `Paint` field outside loops in `CustomPainter`, avoiding artificial inner-loop allocations or dummy work) so that comparisons reflect the genuine architectural difference between well-written standard Flutter (`List<Object> + setState + CustomPainter`) and D-Zero (`SoA Buffer + SIMD + ZeroRenderBox + batch draw`).
2. **No Hardcoded `"Rebuild: 0"` Strings**: Never hardcode `'Rebuild: 0'` or `'0 (Zero Rebuild)'`. Always count actual widget `build()` / `setState()` invocations at runtime for **both** D-Zero and Traditional modes (e.g. `'Rebuild: $_dZeroRebuilds'`) so any accidental rebuild in D-Zero mode is immediately visible.
3. **No Artificial CPU Overhead or Rate Handicaps**: Never add mode-dependent fake `overhead` constants to CPU usage calculations, never assign hardcoded CPU percentages (such as `3.4%` vs `18.5%`), and never throttle Traditional mode's target simulation rate.
4. **Genuine Runtime Measurements Only**: All displayed telemetry (FPS, CPU frame load via `SchedulerBinding.instance.addTimingsCallback` / `Stopwatch`, rebuild counters, allocation counters, RSS memory) must be derived strictly from real runtime measurements so true bottlenecks and optimization opportunities are surfaced.

---

## 5. Pre-Commit Verification & Documentation Sync Checklist

Whenever adding or renaming any public `Z` widget, you **must** update in the same commit:
1. `packages/<pkg>/README.md` (Widget table & usage snippet — rendered directly on `pub.dev`).
2. `packages/<pkg>/pubspec.yaml` (`description` metadata shown on `pub.dev`).
3. Root `README.md` and `README_EN.md` package summary tables.
4. `CHANGELOG.md` and `packages/<pkg>/CHANGELOG.md`.

Before opening a PR or completing a task, execute:
1. `melos run analyze` -> Zero issues.
2. `melos run complexity` -> 0 warnings (no function with CC > 15).
3. `melos run distribute:sync` -> Verifies Z-Prefix compliance and confirms every exported `Z` widget is documented in package and root `README.md` files.
4. `melos run test` -> All unit, memory, and widget lifecycle tests pass.
