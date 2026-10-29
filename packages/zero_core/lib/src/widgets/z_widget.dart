import 'package:flutter/widgets.dart';
import '../rendering/zero_render_box.dart';

/// Marker interface and base class for all d-zero zero-allocation widgets.
///
/// [ZWidget] instances are designed to be constructed with `const` and bound to
/// reactive sources (such as [ValueListenable], signals, or native FFI pointers).
/// They bypass traditional `setState` and `build(BuildContext)` cycles entirely,
/// eliminating ephemeral widget heap allocations on the UI thread during updates.
abstract class ZWidget implements Widget {
  /// Whether this widget guarantees zero heap allocations during runtime updates.
  bool get isZeroAllocation => true;
}

/// A leaf [ZWidget] that renders directly to a [RenderBox] (such as [ZeroRenderBox]) without child widgets.
///
/// Hot-path widgets such as counters, stopwatches, wave displays, and status badges
/// should extend [ZLeafWidget] and ensure their constructors are declared as `const`.
abstract class ZLeafWidget<T extends RenderBox> extends LeafRenderObjectWidget implements ZWidget {
  /// Creates a const [ZLeafWidget].
  const ZLeafWidget({super.key});

  @override
  bool get isZeroAllocation => true;

  @override
  T createRenderObject(BuildContext context);

  @override
  void updateRenderObject(BuildContext context, covariant T renderObject);
}

/// A single-child [ZWidget] wrapper that hosts a [RenderBox] (such as [ZeroRenderBox]).
///
/// Used for zero-allocation containers, clipping, coordinate transformations,
/// and reactive overlays.
abstract class ZSingleChildWidget<T extends RenderBox> extends SingleChildRenderObjectWidget implements ZWidget {
  /// Creates a const [ZSingleChildWidget].
  const ZSingleChildWidget({
    super.key,
    super.child,
  });

  @override
  bool get isZeroAllocation => true;

  @override
  T createRenderObject(BuildContext context);

  @override
  void updateRenderObject(BuildContext context, covariant T renderObject);
}
