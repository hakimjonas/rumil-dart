import 'package:rumil_codec/rumil_codec.dart';
import 'package:test/test.dart';

void main() {
  group('ZigZag encode', () {
    test('maps signed to unsigned', () {
      expect(ZigZag.encode(0), 0);
      expect(ZigZag.encode(-1), 1);
      expect(ZigZag.encode(1), 2);
      expect(ZigZag.encode(-2), 3);
      expect(ZigZag.encode(2), 4);
    });

    test('boundary values', () {
      // MinValue maps to -1 (0xFFFFFFFFFFFFFFFF unsigned)
      expect(ZigZag.encode(-9223372036854775808), -1);
      // MaxValue maps to -2 (0xFFFFFFFFFFFFFFFE unsigned)
      expect(ZigZag.encode(9223372036854775807), -2);
    });
  });

  group('ZigZag decode', () {
    test('reverses encode', () {
      expect(ZigZag.decode(0), 0);
      expect(ZigZag.decode(1), -1);
      expect(ZigZag.decode(2), 1);
      expect(ZigZag.decode(3), -2);
      expect(ZigZag.decode(4), 2);
    });
  });

  group('ZigZag round-trip', () {
    test('round-trips all test values', () {
      final values = [
        0,
        1,
        -1,
        2,
        -2,
        127,
        -128,
        32767,
        -32768,
        -9223372036854775808,
        9223372036854775807,
      ];
      for (final v in values) {
        expect(ZigZag.decode(ZigZag.encode(v)), v);
      }
    });
  });
}
