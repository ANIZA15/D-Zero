import 'dart:typed_data';

/// A fixed-capacity, zero-allocation ring buffer for 64-bit floating point numbers.
/// Pre-allocates a [Float64List] and circular-writes data without resizing or GC overhead.
class FloatRingBuffer {
  final Float64List _data;
  final int capacity;
  int _head = 0;
  int _length = 0;

  /// Creates a [FloatRingBuffer] with the specified fixed [capacity].
  FloatRingBuffer(this.capacity) : _data = Float64List(capacity) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'Capacity must be greater than zero.');
    }
  }

  /// Number of elements currently stored.
  int get length => _length;

  /// Whether the buffer has reached maximum capacity.
  bool get isFull => _length == capacity;

  /// Whether the buffer is empty.
  bool get isEmpty => _length == 0;

  /// Pushes a new value into the buffer. If full, overwrites the oldest element.
  void push(double value) {
    _data[_head] = value;
    _head = (_head + 1) % capacity;
    if (_length < capacity) {
      _length++;
    }
  }

  /// Pushes multiple values into the buffer from an existing [source] array.
  void pushAll(List<double> source) {
    for (int i = 0; i < source.length; i++) {
      push(source[i]);
    }
  }

  /// Retrieves the element at [index], where 0 is the oldest element currently in the buffer.
  double operator [](int index) {
    if (index < 0 || index >= _length) {
      throw RangeError.index(index, this, 'index', 'Index out of bounds', _length);
    }
    final actualIndex = (_head - _length + index + capacity) % capacity;
    return _data[actualIndex];
  }

  /// Retrieves the raw underlying buffer.
  Float64List get rawData => _data;

  /// Clears all elements without releasing the underlying allocated memory.
  void clear() {
    _head = 0;
    _length = 0;
  }
}

/// A fixed-capacity, zero-allocation ring buffer for 32-bit floating point numbers (ideal for shader uniforms).
class Float32RingBuffer {
  final Float32List _data;
  final int capacity;
  int _head = 0;
  int _length = 0;

  /// Creates a [Float32RingBuffer] with the specified fixed [capacity].
  Float32RingBuffer(this.capacity) : _data = Float32List(capacity) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'Capacity must be greater than zero.');
    }
  }

  int get length => _length;
  bool get isFull => _length == capacity;
  bool get isEmpty => _length == 0;

  void push(double value) {
    _data[_head] = value;
    _head = (_head + 1) % capacity;
    if (_length < capacity) {
      _length++;
    }
  }

  double operator [](int index) {
    if (index < 0 || index >= _length) {
      throw RangeError.index(index, this, 'index', 'Index out of bounds', _length);
    }
    final actualIndex = (_head - _length + index + capacity) % capacity;
    return _data[actualIndex];
  }

  Float32List get rawData => _data;

  void clear() {
    _head = 0;
    _length = 0;
  }
}
