import 'package:flutter/scheduler.dart';

/// A subscriber driven by [ZeroFrameScheduler] once per VSync.
abstract interface class ZeroFrameListener {
  /// Called once per frame while subscribed.
  void onZeroFrame(Duration elapsed);
}

/// Optional intrusive slot mixin/interface allowing $O(1)$ registration and removal
/// in [ZeroFrameScheduler] without linear search.
abstract interface class ZeroSlottedFrameListener implements ZeroFrameListener {
  /// Internal scheduler slot index (`-1` when unsubscribed).
  int get zeroSchedulerSlot;
  set zeroSchedulerSlot(int slot);
}

/// A single shared VSync driver for every D-Zero per-frame render object.
///
/// Instead of each [RenderBox] owning its own [Ticker] (N tickers =
/// N frame-callback registrations per frame), all subscribers are multiplexed
/// onto **one** [Ticker]. The ticker is created when the first subscriber
/// arrives and disposed when the last one leaves, so the engine is allowed to
/// go fully idle (no frames scheduled) when nothing animates.
///
/// Hot path guarantees:
/// - $O(1)$ slot registration and removal for [ZeroSlottedFrameListener] (including `ZeroRenderBox`).
/// - Dispatch iterates a flat array by index (no iterator / closure allocation).
/// - Compaction uses a two-pointer in-place loop without `removeWhere` closures.
class ZeroFrameScheduler {
  ZeroFrameScheduler._();

  /// The process-wide scheduler instance.
  static final ZeroFrameScheduler instance = ZeroFrameScheduler._();

  final List<ZeroFrameListener?> _listeners = <ZeroFrameListener?>[];
  Ticker? _ticker;
  bool _dispatching = false;
  bool _needsCompaction = false;
  int _activeCount = 0;

  /// Number of active subscribers.
  int get subscriberCount => _activeCount;

  /// Whether the shared ticker is currently running.
  bool get isTicking => _ticker?.isActive ?? false;

  /// Registers [listener] to be called every frame. Duplicate registration is ignored.
  void subscribe(ZeroFrameListener listener) {
    if (_resolveSlot(listener) >= 0) return;
    final int slot = _listeners.length;
    _listeners.add(listener);
    _assignSlot(listener, slot);
    _activeCount++;
    _ensureTicking();
  }

  /// Unregisters [listener] in $O(1)$ when slotted. Unknown listeners are ignored.
  void unsubscribe(ZeroFrameListener listener) {
    final int index = _resolveSlot(listener);
    if (index < 0) return;
    _assignSlot(listener, -1);
    _activeCount--;
    if (_dispatching) {
      _listeners[index] = null;
      _needsCompaction = true;
    } else {
      _removeSlotImmediate(index);
    }
    if (_activeCount == 0) _stopTicking();
  }

  int _resolveSlot(ZeroFrameListener listener) {
    if (listener is ZeroSlottedFrameListener) {
      final int slot = listener.zeroSchedulerSlot;
      if (slot >= 0 && slot < _listeners.length && identical(_listeners[slot], listener)) {
        return slot;
      }
      return -1;
    }
    for (int i = 0; i < _listeners.length; i++) {
      if (identical(_listeners[i], listener)) return i;
    }
    return -1;
  }

  void _assignSlot(ZeroFrameListener listener, int slot) {
    if (listener is ZeroSlottedFrameListener) {
      listener.zeroSchedulerSlot = slot;
    }
  }

  void _removeSlotImmediate(int index) {
    final int lastIdx = _listeners.length - 1;
    if (index != lastIdx) {
      final ZeroFrameListener? moved = _listeners[lastIdx];
      _listeners[index] = moved;
      if (moved != null) {
        _assignSlot(moved, index);
      }
    }
    _listeners.removeLast();
  }

  void _ensureTicking() {
    if (_ticker != null) return;
    _ticker = Ticker(_onTick, debugLabel: 'ZeroFrameScheduler')..start();
  }

  void _stopTicking() {
    final Ticker? ticker = _ticker;
    if (ticker == null) return;
    _ticker = null;
    ticker.dispose();
  }

  void _onTick(Duration elapsed) {
    _dispatching = true;
    final int count = _listeners.length;
    for (int i = 0; i < count; i++) {
      _listeners[i]?.onZeroFrame(elapsed);
    }
    _dispatching = false;
    if (_needsCompaction) _compactInPlace();
  }

  void _compactInPlace() {
    _needsCompaction = false;
    int write = 0;
    final int len = _listeners.length;
    for (int read = 0; read < len; read++) {
      final ZeroFrameListener? item = _listeners[read];
      if (item != null) {
        if (write != read) {
          _listeners[write] = item;
        }
        _assignSlot(item, write);
        write++;
      }
    }
    _listeners.length = write;
  }
}
