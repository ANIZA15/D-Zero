/// A lightweight, zero-allocation object pool for recycling objects
/// to eliminate garbage collection pressure during high-throughput loops.
class ZeroPool<T> {
  final List<T?> _pool;
  final T Function() _factory;
  final void Function(T item)? _reset;
  final int maxCapacity;
  int _count = 0;

  /// Creates a [ZeroPool] with an initial pre-allocation [initialCapacity] and [maxCapacity].
  ZeroPool({
    required T Function() factory,
    void Function(T item)? reset,
    int initialCapacity = 16,
    int maxCapacity = 256,
  })  : _factory = factory,
        _reset = reset,
        maxCapacity = maxCapacity < initialCapacity ? initialCapacity : maxCapacity,
        _pool = List<T?>.filled(
          maxCapacity < initialCapacity ? initialCapacity : maxCapacity,
          null,
        ) {
    for (int i = 0; i < initialCapacity; i++) {
      _pool[i] = factory();
    }
    _count = initialCapacity;
  }

  /// Current number of available recycled items in the pool.
  @pragma('vm:prefer-inline')
  int get availableCount => _count;

  /// Total capacity of the pool.
  int get capacity => maxCapacity;

  /// Acquires an instance from the pool, or creates one if empty.
  @pragma('vm:prefer-inline')
  T acquire() {
    if (_count > 0) {
      _count--;
      final item = _pool[_count];
      _pool[_count] = null;
      return item!;
    }
    return _factory();
  }

  /// Releases an instance back into the pool for future reuse.
  @pragma('vm:prefer-inline')
  void release(T item) {
    if (_count < maxCapacity) {
      final reset = _reset;
      if (reset != null) {
        reset(item);
      }
      _pool[_count] = item;
      _count++;
    }
  }

  /// Releases multiple items back into the pool for future reuse.
  void releaseAll(Iterable<T> items) {
    for (final item in items) {
      release(item);
    }
  }

  /// Clears the pool and removes references to cached objects.
  void clear() {
    _pool.fillRange(0, _count, null);
    _count = 0;
  }
}

