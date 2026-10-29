import 'package:flutter/scheduler.dart';

/// A subscriber driven by [ZeroFrameScheduler] once per VSync.
abstract interface class ZeroFrameListener {
  /// Called once per frame while subscribed.
  void onZeroFrame(Duration elapsed);
}

/// A single shared VSync driver for every d-zero per-frame render object.
///
/// Instead of each [RenderBox] owning its own [Ticker] (N tickers =
/// N frame-callback registrations per frame), all subscribers are multiplexed
/// onto **one** [Ticker]. The ticker is created when the first subscriber
/// arrives and disposed when the last one leaves, so the engine is allowed to
/// go fully idle (no frames scheduled) when nothing animates.
///
/// Hot path guarantees:
/// - Dispatch iterates a pre-sized list by index (no iterator / closure allocation).
/// - Subscribing / unsubscribing during dispatch is safe: removals are tombstoned
///   and compacted after the frame; additions are appended and start next frame.
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
    if (_indexOf(listener) >= 0) return;
    _listeners.add(listener);
    _activeCount++;
    _ensureTicking();
  }

  /// Unregisters [listener]. Unknown listeners are ignored.
  void unsubscribe(ZeroFrameListener listener) {
    final int index = _indexOf(listener);
    if (index < 0) return;
    _activeCount--;
    if (_dispatching) {
      _listeners[index] = null;
      _needsCompaction = true;
    } else {
      _listeners.removeAt(index);
    }
    if (_activeCount == 0) _stopTicking();
  }

  int _indexOf(ZeroFrameListener listener) {
    for (int i = 0; i < _listeners.length; i++) {
      if (identical(_listeners[i], listener)) return i;
    }
    return -1;
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
    // Snapshot length: listeners added during dispatch begin next frame.
    final int count = _listeners.length;
    for (int i = 0; i < count; i++) {
      _listeners[i]?.onZeroFrame(elapsed);
    }
    _dispatching = false;
    if (_needsCompaction) _compact();
  }

  void _compact() {
    _needsCompaction = false;
    _listeners.removeWhere(_isNull);
  }

  static bool _isNull(ZeroFrameListener? l) => l == null;
}
