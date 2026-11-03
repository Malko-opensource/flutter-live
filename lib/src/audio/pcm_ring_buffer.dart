import 'dart:typed_data';

/// Bounded PCM16 byte ring. Overflow drops oldest complete samples.
class PcmRingBuffer {
  PcmRingBuffer(int capacity)
    : assert(capacity > 0 && capacity.isEven),
      _bytes = Uint8List(capacity);
  final Uint8List _bytes;
  int _head = 0, _length = 0;
  int droppedBytes = 0;
  int get length => _length;
  int get capacity => _bytes.length;
  void write(Uint8List data) {
    if (data.length.isOdd) {
      throw ArgumentError('PCM16 requires complete samples');
    }
    for (var i = 0; i < data.length; i += 2) {
      if (_length + 2 > capacity) {
        discard(2);
        droppedBytes += 2;
      }
      _bytes[(_head + _length) % capacity] = data[i];
      _bytes[(_head + _length + 1) % capacity] = data[i + 1];
      _length += 2;
    }
  }

  Uint8List peek(int count) {
    count = count.clamp(0, _length);
    count -= count % 2;
    return Uint8List.fromList(
      List.generate(count, (i) => _bytes[(_head + i) % capacity]),
    );
  }

  void discard(int count) {
    count = count.clamp(0, _length);
    count -= count % 2;
    _head = (_head + count) % capacity;
    _length -= count;
  }

  Uint8List read(int count) {
    final bytes = peek(count);
    discard(bytes.length);
    return bytes;
  }

  void clear() {
    _head = 0;
    _length = 0;
  }
}
