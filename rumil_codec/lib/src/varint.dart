/// LEB128 variable-length integer encoding.
library;

import 'byte_reader.dart';
import 'byte_writer.dart';
import 'errors.dart';

abstract final class Varint {
  /// Encode an unsigned integer as LEB128 bytes.
  static void write(ByteWriter writer, int value) {
    var v = value;
    do {
      var byte = v & 0x7f;
      v >>>= 7;
      if (v != 0) byte |= 0x80;
      writer.writeByte(byte);
    } while (v != 0);
  }

  /// Decode an unsigned LEB128 integer.
  static int read(ByteReader reader) {
    var value = 0;
    var shift = 0;
    while (true) {
      if (reader.isExhausted) throw UnexpectedEof(reader.offset);
      final byte = reader.readByte();
      value |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return value;
      shift += 7;
      if (shift >= 64) throw VarintOverflow(reader.offset);
    }
  }
}
