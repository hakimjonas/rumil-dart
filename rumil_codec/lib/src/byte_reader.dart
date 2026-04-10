/// Sequential byte buffer reader.
library;

import 'dart:typed_data';

import 'errors.dart';

/// Reads values sequentially from a byte buffer, tracking position.
final class ByteReader {
  final Uint8List _bytes;
  int _offset;

  /// Creates a reader over [_bytes], starting at [_offset].
  ByteReader(this._bytes, [this._offset = 0]);

  /// Read a single byte. Throws [UnexpectedEof] if exhausted.
  int readByte() {
    if (_offset >= _bytes.length) throw UnexpectedEof(_offset);
    return _bytes[_offset++];
  }

  /// Read [count] bytes. Throws [UnexpectedEof] if not enough remain.
  Uint8List readBytes(int count) {
    if (_offset + count > _bytes.length) throw UnexpectedEof(_offset);
    final result = Uint8List.sublistView(_bytes, _offset, _offset + count);
    _offset += count;
    return result;
  }

  /// Read a 64-bit IEEE 754 double in big-endian byte order.
  double readFloat64() {
    if (_offset + 8 > _bytes.length) throw UnexpectedEof(_offset);
    final data = ByteData.sublistView(_bytes, _offset, _offset + 8);
    _offset += 8;
    return data.getFloat64(0, Endian.big);
  }

  /// True if all bytes have been consumed.
  bool get isExhausted => _offset >= _bytes.length;

  /// Number of bytes remaining.
  int get remaining => _bytes.length - _offset;

  /// Current byte offset.
  int get offset => _offset;
}
