import 'dart:typed_data';

/// A fixed-capacity, zero-allocation ring buffer for 64-bit floating point numbers.
///
/// Pre-allocates a double-length [Float64List] (`2 * capacity`) and mirrors every
/// write into both halves (`_data[_head]` and `_data[_head + capacity]`), plus
/// pre-allocates all [Float64List.sublistView] slices at construction time.
/// This allows:
/// - Branch-only wrap-around on [push] and `operator[]` (no integer modulo `%`),
/// - Bulk `memcpy`-backed [pushAll] via [Float64List.setRange],
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

  /// Returns the oldest element currently in the buffer, or `0.0` if empty.
  @pragma('vm:prefer-inline')
  double get oldest {
    if (_length == 0) return 0.0;
    final int idx = _length < capacity ? 0 : _head;
    return _data[idx];
  }

  /// Returns the most recently pushed element in the buffer, or `0.0` if empty.
  @pragma('vm:prefer-inline')
  double get latest {
    if (_length == 0) return 0.0;
    final int idx = _head == 0 ? capacity - 1 : _head - 1;
    return _data[idx];
  }

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

  /// Pushes multiple values from [source] using bulk [Float64List.setRange] copies.
  void pushAll(List<double> source) {
    final int n = source.length;
    if (n == 0) return;
    final int cap = capacity;
    if (n >= cap) {
      final int srcOffset = n - cap;
      _data.setRange(0, cap, source, srcOffset);
      _data.setRange(cap, cap * 2, source, srcOffset);
      _head = 0;
      _length = cap;
      return;
    }
    _pushSlice(source, n, cap);
  }

  void _pushSlice(List<double> source, int n, int cap) {
    final int h = _head;
    final int firstPart = (h + n <= cap) ? n : (cap - h);
    _data.setRange(h, h + firstPart, source, 0);
    _data.setRange(h + cap, h + cap + firstPart, source, 0);
    final int secondPart = n - firstPart;
    if (secondPart > 0) {
      _data.setRange(0, secondPart, source, firstPart);
      _data.setRange(cap, cap + secondPart, source, firstPart);
      _head = secondPart;
    } else {
      final int next = h + firstPart;
      _head = next == cap ? 0 : next;
    }
    final int newLen = _length + n;
    _length = newLen < cap ? newLen : cap;
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

  /// Copies currently stored elements (oldest to newest) into [dest] at [destOffset].
  /// Returns the number of elements copied.
  int copyInto(List<double> dest, [int destOffset = 0]) {
    final int len = _length;
    if (len == 0) return 0;
    final int start = len < capacity ? 0 : _head;
    dest.setRange(destOffset, destOffset + len, _data, start);
    return len;
  }

  /// Computes the arithmetic mean of all currently stored elements (zero allocation).
  double get average {
    final int len = _length;
    if (len == 0) return 0.0;
    final int start = len < capacity ? 0 : _head;
    final int end = start + len;
    double sum = 0.0;
    for (int i = start; i < end; i++) {
      sum += _data[i];
    }
    return sum / len;
  }

  /// Returns the minimum value currently stored in the buffer, or `0.0` if empty.
  double get min {
    final int len = _length;
    if (len == 0) return 0.0;
    final int start = len < capacity ? 0 : _head;
    final int end = start + len;
    double m = _data[start];
    for (int i = start + 1; i < end; i++) {
      final double v = _data[i];
      if (v < m) m = v;
    }
    return m;
  }

  /// Returns the maximum value currently stored in the buffer, or `0.0` if empty.
  double get max {
    final int len = _length;
    if (len == 0) return 0.0;
    final int start = len < capacity ? 0 : _head;
    final int end = start + len;
    double m = _data[start];
    for (int i = start + 1; i < end; i++) {
      final double v = _data[i];
      if (v > m) m = v;
    }
    return m;
  }

  /// Retrieves the raw first-half buffer of length [capacity].
  Float64List get rawData => _rawView;

  /// Returns a contiguous view of all currently stored elements in oldest-to-newest order.
  Float64List get contiguousView {
    if (_length == capacity) {
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

  /// Returns the oldest element currently in the buffer, or `0.0` if empty.
  @pragma('vm:prefer-inline')
  double get oldest {
    if (_length == 0) return 0.0;
    final int idx = _length < capacity ? 0 : _head;
    return _data[idx];
  }

  /// Returns the most recently pushed element in the buffer, or `0.0` if empty.
  @pragma('vm:prefer-inline')
  double get latest {
    if (_length == 0) return 0.0;
    final int idx = _head == 0 ? capacity - 1 : _head - 1;
    return _data[idx];
  }

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

  /// Pushes multiple values from [source] using bulk [Float32List.setRange] copies.
  void pushAll(List<double> source) {
    final int n = source.length;
    if (n == 0) return;
    final int cap = capacity;
    if (n >= cap) {
      final int srcOffset = n - cap;
      _data.setRange(0, cap, source, srcOffset);
      _data.setRange(cap, cap * 2, source, srcOffset);
      _head = 0;
      _length = cap;
      return;
    }
    _pushSlice(source, n, cap);
  }

  void _pushSlice(List<double> source, int n, int cap) {
    final int h = _head;
    final int firstPart = (h + n <= cap) ? n : (cap - h);
    _data.setRange(h, h + firstPart, source, 0);
    _data.setRange(h + cap, h + cap + firstPart, source, 0);
    final int secondPart = n - firstPart;
    if (secondPart > 0) {
      _data.setRange(0, secondPart, source, firstPart);
      _data.setRange(cap, cap + secondPart, source, firstPart);
      _head = secondPart;
    } else {
      final int next = h + firstPart;
      _head = next == cap ? 0 : next;
    }
    final int newLen = _length + n;
    _length = newLen < cap ? newLen : cap;
  }

  @pragma('vm:prefer-inline')
  double operator [](int index) {
    if (index < 0 || index >= _length) {
      throw RangeError.index(index, this, 'index', 'Index out of bounds', _length);
    }
    final int start = _length < capacity ? 0 : _head;
    return _data[start + index];
  }

  /// Copies currently stored elements (oldest to newest) into [dest] at [destOffset].
  /// Returns the number of elements copied.
  int copyInto(List<double> dest, [int destOffset = 0]) {
    final int len = _length;
    if (len == 0) return 0;
    final int start = len < capacity ? 0 : _head;
    dest.setRange(destOffset, destOffset + len, _data, start);
    return len;
  }

  /// Computes the arithmetic mean of all currently stored elements (zero allocation).
  double get average {
    final int len = _length;
    if (len == 0) return 0.0;
    final int start = len < capacity ? 0 : _head;
    final int end = start + len;
    double sum = 0.0;
    for (int i = start; i < end; i++) {
      sum += _data[i];
    }
    return sum / len;
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
