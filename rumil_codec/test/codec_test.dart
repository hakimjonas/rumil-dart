import 'dart:typed_data';

import 'package:rumil_codec/rumil_codec.dart';
import 'package:test/test.dart';

void _roundTrip<A>(BinaryCodec<A> codec, A value, {Matcher? byteMatcher}) {
  final bytes = codec.encode(value);
  if (byteMatcher != null) expect(bytes, byteMatcher);
  final decoded = codec.decode(bytes);
  expect(decoded, value);
}

void main() {
  // Cross-language validation: int codec = ZigZag + Varint.
  group('intCodec (Sarati-compatible)', () {
    test(
      'encodes 0',
      () => _roundTrip(intCodec, 0, byteMatcher: equals([0x00])),
    );
    test(
      'encodes -1',
      () => _roundTrip(intCodec, -1, byteMatcher: equals([0x01])),
    );
    test(
      'encodes 1',
      () => _roundTrip(intCodec, 1, byteMatcher: equals([0x02])),
    );
    test(
      'encodes 42',
      () => _roundTrip(intCodec, 42, byteMatcher: equals([0x54])),
    );

    test('round-trips boundary values', () {
      for (final v in [0, 1, -1, 127, -128, 32767, -32768]) {
        _roundTrip(intCodec, v);
      }
    });

    test('round-trips large values', () {
      _roundTrip(intCodec, 9223372036854775807); // maxInt
      _roundTrip(intCodec, -9223372036854775808); // minInt
    });
  });

  group('doubleCodec', () {
    test('round-trips normal values', () {
      for (final v in [0.0, 1.0, -1.0, 3.14159, double.maxFinite]) {
        _roundTrip(doubleCodec, v);
      }
    });

    test('round-trips infinity', () {
      _roundTrip(doubleCodec, double.infinity);
      _roundTrip(doubleCodec, double.negativeInfinity);
    });

    test('round-trips NaN', () {
      final bytes = doubleCodec.encode(double.nan);
      expect(doubleCodec.decode(bytes), isNaN);
    });

    test('always 8 bytes', () {
      expect(doubleCodec.encode(0.0).length, 8);
      expect(doubleCodec.encode(double.maxFinite).length, 8);
    });
  });

  group('boolCodec', () {
    test('true encodes to 0x01', () {
      expect(boolCodec.encode(true), [0x01]);
    });

    test('false encodes to 0x00', () {
      expect(boolCodec.encode(false), [0x00]);
    });

    test('round-trips', () {
      _roundTrip(boolCodec, true);
      _roundTrip(boolCodec, false);
    });

    test('invalid byte throws', () {
      expect(
        () => boolCodec.decode(Uint8List.fromList([0x02])),
        throwsA(isA<InvalidBool>()),
      );
    });
  });

  group('stringCodec', () {
    test('empty string', () {
      _roundTrip(stringCodec, '');
      expect(stringCodec.encode('').length, 1); // just varint 0
    });

    test('ascii string', () => _roundTrip(stringCodec, 'hello'));
    test('unicode string', () => _roundTrip(stringCodec, 'é è ê'));
    test('emoji string', () => _roundTrip(stringCodec, 'Fungal 🍄'));

    test('long string', () => _roundTrip(stringCodec, 'a' * 1000));
  });

  group('bytesCodec', () {
    test('empty bytes', () {
      _roundTrip(bytesCodec, Uint8List(0));
    });

    test('round-trips data', () {
      _roundTrip(bytesCodec, Uint8List.fromList([1, 2, 3, 4, 5]));
    });
  });

  group('dateTimeCodec', () {
    test('round-trips UTC', () {
      _roundTrip(dateTimeCodec, DateTime.utc(2026, 4, 16, 12, 30));
    });

    test('round-trips local', () {
      final local = DateTime(2026, 4, 16, 12, 30);
      final bytes = dateTimeCodec.encode(local);
      final decoded = dateTimeCodec.decode(bytes);
      expect(decoded, local);
      expect(decoded.isUtc, false);
    });

    test('preserves UTC flag', () {
      final utc = DateTime.utc(2024, 1, 1);
      final local = DateTime(2024, 1, 1);
      expect(dateTimeCodec.decode(dateTimeCodec.encode(utc)).isUtc, true);
      expect(dateTimeCodec.decode(dateTimeCodec.encode(local)).isUtc, false);
    });

    test('round-trips epoch zero', () {
      _roundTrip(
        dateTimeCodec,
        DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true),
      );
    });

    test('round-trips negative epoch', () {
      _roundTrip(dateTimeCodec, DateTime.utc(1969, 7, 20, 20, 17));
    });

    test('microsecond precision', () {
      final dt = DateTime.utc(2026, 4, 16, 12, 30, 45, 123, 456);
      _roundTrip(dateTimeCodec, dt);
    });
  });

  group('bigIntCodec', () {
    test('round-trips zero', () {
      _roundTrip(bigIntCodec, BigInt.zero);
    });

    test('round-trips small positive', () {
      _roundTrip(bigIntCodec, BigInt.from(42));
    });

    test('round-trips small negative', () {
      _roundTrip(bigIntCodec, BigInt.from(-42));
    });

    test('round-trips large values', () {
      _roundTrip(bigIntCodec, BigInt.parse('999999999999999999999999999999'));
      _roundTrip(bigIntCodec, BigInt.parse('-999999999999999999999999999999'));
    });

    test('round-trips powers of two', () {
      _roundTrip(bigIntCodec, BigInt.two.pow(128));
      _roundTrip(bigIntCodec, BigInt.two.pow(256));
    });

    test('round-trips one', () {
      _roundTrip(bigIntCodec, BigInt.one);
      _roundTrip(bigIntCodec, -BigInt.one);
    });
  });

  group('enumCodec', () {
    test('round-trips values', () {
      final codec = enumCodec(_TestColor.values);
      _roundTrip(codec, _TestColor.red);
      _roundTrip(codec, _TestColor.green);
      _roundTrip(codec, _TestColor.blue);
    });

    test('ordinals match index', () {
      final codec = enumCodec(_TestColor.values);
      expect(codec.encode(_TestColor.red), intCodec.encode(0));
      expect(codec.encode(_TestColor.green), intCodec.encode(1));
      expect(codec.encode(_TestColor.blue), intCodec.encode(2));
    });

    test('invalid ordinal throws', () {
      final codec = enumCodec(_TestColor.values);
      final bytes = intCodec.encode(99);
      expect(() => codec.decode(bytes), throwsA(isA<InvalidOrdinal>()));
    });
  });

  group('error handling', () {
    test('truncated int throws UnexpectedEof', () {
      expect(
        () => intCodec.decode(Uint8List(0)),
        throwsA(isA<UnexpectedEof>()),
      );
    });

    test('truncated string throws UnexpectedEof', () {
      // Varint says 10 bytes but only 3 follow
      final w = ByteWriter();
      Varint.write(w, 10);
      w.writeBytes(Uint8List.fromList([1, 2, 3]));
      expect(
        () => stringCodec.decode(w.toBytes()),
        throwsA(isA<UnexpectedEof>()),
      );
    });
  });
}

enum _TestColor { red, green, blue }
