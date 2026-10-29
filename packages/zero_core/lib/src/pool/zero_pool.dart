/// A lightweight, zero-allocation object pool for recycling objects
/// to eliminate garbage collection pressure during high-throughput loops.
class ZeroPool<T> {
  final List<T> _pool;
  final T Function() _factory;
  final void Function(T item)? _reset;
  final int maxCapacity;

  /// Creates a [ZeroPool] with an initial pre-allocation [initialCapacity] and [maxCapacity].
  ZeroPool({
    required T Function() factory,
    void Function(T item)? reset,
    int initialCapacity = 16,
    this.maxCapacity = 256,
  })  : _factory = factory,
        _reset = reset,
        _pool = List<T>.generate(initialCapacity, (_) => factory(), growable: true);

  /// Current number of available recycled items in the pool.
  int get availableCount => _pool.length;

  /// Acquires an instance from the pool, or creates one if empty.
  T acquire() {
    if (_pool.isNotEmpty) {
      return _pool.removeLast();
    }
    return _factory();
  }

  /// Releases an instance back into the pool for future reuse.
  void release(T item) {
    if (_pool.length < maxCapacity) {
      _reset?.call(item);
      _pool.add(item);
    }
  }

  /// Clears the pool.
  void clear() {
    _pool.clear();
  }
}
