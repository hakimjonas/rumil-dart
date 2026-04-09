/// Sequential byte buffer reader.
library;

import 'dart:typed_data';

import 'errors.dart';

/// Reads values sequentially from a byte buffer, tracking position.
final class ByteReader {
  final Uint8List _bytes;
  int _offset;

  ByteReader(this._bytes, [this._offset = 0]);

  int readByte() {
    if (_offset >= _bytes.length) throw UnexpectedEof(_offset);
    return _bytes[_offset++];
  }

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

  bool get isExhausted => _offset >= _bytes.length;
  int get remaining => _bytes.length - _offset;
  int get offset => _offset;
}
