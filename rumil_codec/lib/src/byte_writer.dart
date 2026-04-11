/// Sequential byte buffer writer.
library;

import 'dart:typed_data';

/// Builds a byte sequence by appending values sequentially.
final class ByteWriter {
  /// Creates an empty byte writer.
  ByteWriter();

  final BytesBuilder _builder = BytesBuilder(copy: false);

  /// Append a single byte.
  void writeByte(int byte) => _builder.addByte(byte);

  /// Append raw bytes.
  void writeBytes(Uint8List bytes) => _builder.add(bytes);

  /// Write a 64-bit IEEE 754 double in big-endian byte order.
  void writeFloat64(double value) {
    final data = ByteData(8)..setFloat64(0, value, Endian.big);
    _builder.add(data.buffer.asUint8List());
  }

  /// Return the accumulated bytes.
  Uint8List toBytes() => _builder.toBytes();

  /// Number of bytes written so far.
  int get length => _builder.length;
}
