import 'package:flutter/foundation.dart';

/// Base listener registry using a flat array with index-based dispatch and
/// tombstone compaction (zero iterator or closure allocations during notifications).
abstract class _ZeroNotifierBase {
  List<VoidCallback?> _listeners = List<VoidCallback?>.filled(4, null, growable: true);
  int _length = 0;
  int _activeCount = 0;
  int _notifyDepth = 0;
  bool _needsCompaction = false;
  bool _isDisposed = false;

  /// Whether this notifier has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether any listeners are currently registered.
  bool get hasListeners => _activeCount > 0;

  void addListener(VoidCallback listener) {
    if (_isDisposed) return;
    if (_length == _listeners.length) {
      _listeners.add(listener);
      _length++;
    } else {
      _listeners[_length++] = listener;
    }
    _activeCount++;
  }

  void removeListener(VoidCallback listener) {
    if (_isDisposed) return;
    for (int i = 0; i < _length; i++) {
      if (_listeners[i] == listener) {
        _activeCount--;
        if (_notifyDepth > 0) {
          _listeners[i] = null;
          _needsCompaction = true;
        } else {
          _removeAtFast(i);
        }
        return;
      }
    }
  }

  void _removeAtFast(int index) {
    final int last = _length - 1;
    for (int i = index; i < last; i++) {
      _listeners[i] = _listeners[i + 1];
    }
    _listeners[last] = null;
    _length = last;
  }

  @pragma('vm:prefer-inline')
  void notifyListeners() {
    if (_isDisposed || _activeCount == 0) return;
    _notifyDepth++;
    final int end = _length;
    for (int i = 0; i < end; i++) {
      _listeners[i]?.call();
    }
    _notifyDepth--;
    if (_notifyDepth == 0 && _needsCompaction) {
      _compact();
    }
  }

  void _compact() {
    _needsCompaction = false;
    int write = 0;
    for (int read = 0; read < _length; read++) {
      final VoidCallback? cb = _listeners[read];
      if (cb != null) {
        _listeners[write++] = cb;
      }
    }
    for (int i = write; i < _length; i++) {
      _listeners[i] = null;
    }
    _length = write;
  }

  /// Clears all listeners and marks this notifier as disposed (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    for (int i = 0; i < _length; i++) {
      _listeners[i] = null;
    }
    _length = 0;
    _activeCount = 0;
  }
}

/// An unboxed, zero-allocation reactive integer holder implementing [ValueListenable<int>].
///
/// Unlike `ValueNotifier<int>`, which stores its value in a generic field `T _value`
/// (subject to boxing across generic boundaries), [ZeroIntNotifier] stores an unboxed
/// 64-bit `int` field and dispatches listeners via a flat index loop.
class ZeroIntNotifier extends _ZeroNotifierBase implements ValueListenable<int> {
  int _value;

  /// Creates a [ZeroIntNotifier] with the initial [_value].
  ZeroIntNotifier(this._value);

  @override
  @pragma('vm:prefer-inline')
  int get value => _value;

  @pragma('vm:prefer-inline')
  set value(int newValue) {
    if (_value == newValue || _isDisposed) return;
    _value = newValue;
    notifyListeners();
  }

  /// Increments the value by [delta] and notifies listeners if non-zero.
  @pragma('vm:prefer-inline')
  void add(int delta) {
    if (delta == 0 || _isDisposed) return;
    _value += delta;
    notifyListeners();
  }
}

/// An unboxed, zero-allocation reactive double holder implementing [ValueListenable<double>].
class ZeroDoubleNotifier extends _ZeroNotifierBase implements ValueListenable<double> {
  double _value;

  /// Creates a [ZeroDoubleNotifier] with the initial [_value].
  ZeroDoubleNotifier(this._value);

  @override
  @pragma('vm:prefer-inline')
  double get value => _value;

  @pragma('vm:prefer-inline')
  set value(double newValue) {
    if (_value == newValue || _isDisposed) return;
    _value = newValue;
    notifyListeners();
  }

  /// Adds [delta] to the current value and notifies listeners if changed.
  @pragma('vm:prefer-inline')
  void add(double delta) {
    if (delta == 0.0 || _isDisposed) return;
    _value += delta;
    notifyListeners();
  }
}
