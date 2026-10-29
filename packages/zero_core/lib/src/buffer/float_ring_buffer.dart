import 'dart:typed_data';

/// A fixed-capacity, zero-allocation ring buffer for 64-bit floating point numbers.
///
/// Pre-allocates a double-length [Float64List] (`2 * capacity`) and mirrors every
/// write into both halves (`_data[_head]` and `_data[_head + capacity]`), plus
/// pre-allocates all [Float64List.sublistView] slices at construction time.
/// This allows:
/// - Branch-only wrap-around on [push] and `operator[]` (no integer modulo `%`),
/// - Zero-allocation [contiguousView] returning the elements in oldest-to-newest
///   order for direct batch consumption.
class FloatRingBuffer {
  final Float64List _data;
  final Float64List _rawView;
  final List<Float64List> _fullViews;
  final int capacity;
  int _head = 0;
  int _length = 0;

  /// Creates a [FloatRingBuffer] with the specified fixed [capacity].
  factory FloatRingBuffer(int capacity) {
    final int cap = _validateCapacity(capacity);
    final Float64List backing = Float64List(cap * 2);
    final Float64List raw = Float64List.sublistView(backing, 0, cap);
    final List<Float64List> views = List<Float64List>.generate(
      cap,
      (int start) => Float64List.sublistView(backing, start, start + cap),
      growable: false,
    );
    return FloatRingBuffer._internal(cap, backing, raw, views);
  }

  FloatRingBuffer._internal(
    this.capacity,
    this._data,
    this._rawView,
    this._fullViews,
  );

  static int _validateCapacity(int capacity) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'Capacity must be greater than zero.');
    }
    return capacity;
  }

  /// Number of elements currently stored.
  @pragma('vm:prefer-inline')
  int get length => _length;

  /// Whether the buffer has reached maximum capacity.
  @pragma('vm:prefer-inline')
  bool get isFull => _length == capacity;

  /// Whether the buffer is empty.
  @pragma('vm:prefer-inline')
  bool get isEmpty => _length == 0;

  /// Pushes a new value into the buffer. If full, overwrites the oldest element.
  ///
  /// Uses a single comparison branch instead of integer modulo (`%`).
  @pragma('vm:prefer-inline')
  void push(double value) {
    final int h = _head;
    _data[h] = value;
    _data[h + capacity] = value;
    final int next = h + 1;
    _head = next == capacity ? 0 : next;
    if (_length < capacity) {
      _length++;
    }
  }

  /// Pushes multiple values into the buffer from an existing [source] array.
  void pushAll(List<double> source) {
    final int n = source.length;
    for (int i = 0; i < n; i++) {
      push(source[i]);
    }
  }

  /// Retrieves the element at [index], where 0 is the oldest element currently in the buffer.
  @pragma('vm:prefer-inline')
  double operator [](int index) {
    if (index < 0 || index >= _length) {
      throw RangeError.index(index, this, 'index', 'Index out of bounds', _length);
    }
    final int start = _length < capacity ? 0 : _head;
    return _data[start + index];
  }

  /// Retrieves the raw first-half buffer of length [capacity].
  Float64List get rawData =>
      _rawView.length == capacity ? _rawView : Float64List.sublistView(_data, 0, capacity);

  /// Returns a contiguous view of all currently stored elements in oldest-to-newest order.
  Float64List get contiguousView {
    if (_length == capacity && _fullViews.isNotEmpty) {
      return _fullViews[_head];
    }
    final int start = _length < capacity ? 0 : _head;
    return Float64List.sublistView(_data, start, start + _length);
  }

  /// Clears all elements without releasing the underlying allocated memory.
  void clear() {
    _head = 0;
    _length = 0;
  }
}

/// A fixed-capacity, zero-allocation ring buffer for 32-bit floating point numbers
/// (ideal for shader uniforms and `Canvas.drawRawPoints`).
///
/// Mirrors writes into a `2 * capacity` [Float32List] and pre-allocates views so
/// [contiguousView] is 100% allocation-free once the buffer is full.
class Float32RingBuffer {
  final Float32List _data;
  final Float32List _rawView;
  final List<Float32List> _fullViews;
  final int capacity;
  int _head = 0;
  int _length = 0;

  /// Creates a [Float32RingBuffer] with the specified fixed [capacity].
  factory Float32RingBuffer(int capacity) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'Capacity must be greater than zero.');
    }
    final Float32List backing = Float32List(capacity * 2);
    final Float32List raw = Float32List.sublistView(backing, 0, capacity);
    final List<Float32List> views = List<Float32List>.generate(
      capacity,
      (int start) => Float32List.sublistView(backing, start, start + capacity),
      growable: false,
    );
    return Float32RingBuffer._(capacity, backing, raw, views);
  }

  Float32RingBuffer._(
    this.capacity,
    this._data,
    this._rawView,
    this._fullViews,
  );

  @pragma('vm:prefer-inline')
  int get length => _length;

  @pragma('vm:prefer-inline')
  bool get isFull => _length == capacity;

  @pragma('vm:prefer-inline')
  bool get isEmpty => _length == 0;

  /// Pushes a new value into the buffer without integer modulo (`%`).
  @pragma('vm:prefer-inline')
  void push(double value) {
    final int h = _head;
    _data[h] = value;
    _data[h + capacity] = value;
    final int next = h + 1;
    _head = next == capacity ? 0 : next;
    if (_length < capacity) {
      _length++;
    }
  }

  /// Pushes multiple values into the buffer from an existing [source] array.
  void pushAll(List<double> source) {
    final int n = source.length;
    for (int i = 0; i < n; i++) {
      push(source[i]);
    }
  }

  @pragma('vm:prefer-inline')
  double operator [](int index) {
    if (index < 0 || index >= _length) {
      throw RangeError.index(index, this, 'index', 'Index out of bounds', _length);
    }
    final int start = _length < capacity ? 0 : _head;
    return _data[start + index];
  }

  /// Retrieves the raw first-half buffer of length [capacity].
  Float32List get rawData => _rawView;

  /// Returns a pre-allocated contiguous [Float32List] view in oldest-to-newest order
  /// (zero heap allocations when the buffer is full).
  Float32List get contiguousView {
    if (_length == capacity) {
      return _fullViews[_head];
    }
    return Float32List.sublistView(_data, 0, _length);
  }

  void clear() {
    _head = 0;
    _length = 0;
  }
}
