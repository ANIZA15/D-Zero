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

## 4. Pre-Commit Verification Checklist

Before opening a PR or completing a task, execute:
1. `melos run analyze` -> Zero issues.
2. `melos run complexity` -> 0 warnings (no function with CC > 15).
3. `melos run test` -> All unit, memory, and widget lifecycle tests pass.
