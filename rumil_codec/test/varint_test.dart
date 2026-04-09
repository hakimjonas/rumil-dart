import 'dart:typed_data';

import 'package:rumil_codec/rumil_codec.dart';
import 'package:test/test.dart';

Uint8List _writeVarint(int value) {
  final writer = ByteWriter();
  Varint.write(writer, value);
  return writer.toBytes();
}

int _readVarint(List<int> bytes) {
  final reader = ByteReader(Uint8List.fromList(bytes));
  return Varint.read(reader);
}

void main() {
  // Cross-language validation: these byte sequences must match Sarati (Scala).
  group('Varint encode (Sarati-compatible)', () {
    test('single-byte values', () {
      expect(_writeVarint(0), [0x00]);
      expect(_writeVarint(1), [0x01]);
      expect(_writeVarint(127), [0x7f]);
    });

    test('multi-byte values', () {
      expect(_writeVarint(128), [0x80, 0x01]);
      expect(_writeVarint(255), [0xff, 0x01]);
      expect(_writeVarint(256), [0x80, 0x02]);
      expect(_writeVarint(300), [0xac, 0x02]);
      expect(_writeVarint(16384), [0x80, 0x80, 0x01]);
    });
  });

  group('Varint decode (Sarati-compatible)', () {
    test('single-byte values', () {
      expect(_readVarint([0x00]), 0);
      expect(_readVarint([0x01]), 1);
      expect(_readVarint([0x7f]), 127);
    });

    test('multi-byte values', () {
      expect(_readVarint([0x80, 0x01]), 128);
      expect(_readVarint([0xff, 0x01]), 255);
      expect(_readVarint([0x80, 0x02]), 256);
      expect(_readVarint([0xac, 0x02]), 300);
      expect(_readVarint([0x80, 0x80, 0x01]), 16384);
    });
  });

  group('Varint round-trip', () {
    test('round-trips all test values', () {
      final values = [
        0,
        1,
        127,
        128,
        255,
        256,
        300,
        1000,
        10000,
        100000,
        1000000,
      ];
      for (final v in values) {
        final bytes = _writeVarint(v);
        final reader = ByteReader(bytes);
        expect(Varint.read(reader), v);
        expect(reader.isExhausted, true);
      }
    });
  });

  group('Varint trailing bytes', () {
    test('consumes only varint bytes', () {
      final reader = ByteReader(Uint8List.fromList([0x7f, 0xff, 0xff]));
      expect(Varint.read(reader), 127);
      expect(reader.remaining, 2);
    });
  });

  group('Varint errors', () {
    test('empty input throws UnexpectedEof', () {
      final reader = ByteReader(Uint8List(0));
      expect(() => Varint.read(reader), throwsA(isA<UnexpectedEof>()));
    });

    test('truncated varint throws UnexpectedEof', () {
      final reader = ByteReader(Uint8List.fromList([0x80]));
      expect(() => Varint.read(reader), throwsA(isA<UnexpectedEof>()));
    });

    test('double-truncated varint throws UnexpectedEof', () {
      final reader = ByteReader(Uint8List.fromList([0x80, 0x80]));
      expect(() => Varint.read(reader), throwsA(isA<UnexpectedEof>()));
    });
  });
}
