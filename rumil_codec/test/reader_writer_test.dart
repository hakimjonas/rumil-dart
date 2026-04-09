import 'dart:typed_data';

import 'package:rumil_codec/rumil_codec.dart';
import 'package:test/test.dart';

void main() {
  group('ByteWriter', () {
    test('writeByte', () {
      final w = ByteWriter();
      w.writeByte(0x42);
      expect(w.toBytes(), [0x42]);
    });

    test('writeBytes', () {
      final w = ByteWriter();
      w.writeBytes(Uint8List.fromList([1, 2, 3]));
      expect(w.toBytes(), [1, 2, 3]);
    });

    test('writeFloat64 big-endian', () {
      final w = ByteWriter();
      w.writeFloat64(1.0);
      final bytes = w.toBytes();
      expect(bytes.length, 8);
      // IEEE 754 big-endian for 1.0: 0x3FF0000000000000
      expect(bytes[0], 0x3f);
      expect(bytes[1], 0xf0);
      expect(bytes.sublist(2), everyElement(0));
    });

    test('length tracks written bytes', () {
      final w = ByteWriter();
      expect(w.length, 0);
      w.writeByte(1);
      expect(w.length, 1);
      w.writeFloat64(0.0);
      expect(w.length, 9);
    });
  });

  group('ByteReader', () {
    test('readByte', () {
      final r = ByteReader(Uint8List.fromList([0x42]));
      expect(r.readByte(), 0x42);
      expect(r.isExhausted, true);
    });

    test('readBytes', () {
      final r = ByteReader(Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(r.readBytes(3), [1, 2, 3]);
      expect(r.remaining, 2);
    });

    test('readFloat64 big-endian round-trip', () {
      final values = [
        0.0,
        1.0,
        -1.0,
        3.14159,
        double.maxFinite,
        double.minPositive,
      ];
      for (final v in values) {
        final w = ByteWriter()..writeFloat64(v);
        final r = ByteReader(w.toBytes());
        expect(r.readFloat64(), v);
      }
    });

    test('readFloat64 special values', () {
      for (final v in [double.infinity, double.negativeInfinity]) {
        final w = ByteWriter()..writeFloat64(v);
        final r = ByteReader(w.toBytes());
        expect(r.readFloat64(), v);
      }

      final w = ByteWriter()..writeFloat64(double.nan);
      final r = ByteReader(w.toBytes());
      expect(r.readFloat64(), isNaN);
    });

    test('offset tracks position', () {
      final r = ByteReader(Uint8List.fromList([1, 2, 3]));
      expect(r.offset, 0);
      r.readByte();
      expect(r.offset, 1);
      r.readByte();
      expect(r.offset, 2);
    });

    test('readByte past end throws UnexpectedEof', () {
      final r = ByteReader(Uint8List(0));
      expect(r.readByte, throwsA(isA<UnexpectedEof>()));
    });

    test('readBytes past end throws UnexpectedEof', () {
      final r = ByteReader(Uint8List.fromList([1, 2]));
      expect(() => r.readBytes(5), throwsA(isA<UnexpectedEof>()));
    });

    test('readFloat64 past end throws UnexpectedEof', () {
      final r = ByteReader(Uint8List.fromList([1, 2, 3]));
      expect(r.readFloat64, throwsA(isA<UnexpectedEof>()));
    });
  });
}
