import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

A val_<A>(Result<ParseError, A> r) => switch (r) {
  Success<ParseError, A>(:final value) => value,
  Partial<ParseError, A>(:final value) => value,
  Failure() => throw StateError('Expected success, got ${r.errors}'),
};

void main() {
  group('common.signedInt', () {
    test('positive integer', () {
      expect(val_(signedInt().run('42')), 42);
    });

    test('negative integer', () {
      expect(val_(signedInt().run('-17')), -17);
    });

    test('explicit positive sign', () {
      expect(val_(signedInt().run('+5')), 5);
    });

    test('zero', () {
      expect(val_(signedInt().run('0')), 0);
    });
  });

  group('common.floatingPoint', () {
    test('decimal', () {
      expect(val_(floatingPoint().run('3.14')), 3.14);
    });

    test('integer-shaped (no decimal)', () {
      expect(val_(floatingPoint().run('42')), 42.0);
    });

    test('negative with decimal', () {
      expect(val_(floatingPoint().run('-2.5')), -2.5);
    });

    test('positive exponent', () {
      expect(val_(floatingPoint().run('1.5e3')), 1.5e3);
    });

    test('negative exponent', () {
      expect(val_(floatingPoint().run('1.5e-3')), 1.5e-3);
    });

    test('precision: 1e-323 matches double.parse', () {
      // Sanity check at a subnormal value. Both the old pow-based
      // shape and the new capture-based shape happen to round to the
      // same result here; the load-bearing regression test is the
      // 5e-324 case below.
      expect(val_(floatingPoint().run('1e-323')), double.parse('1e-323'));
    });

    test('precision: 5e-324 (smallest positive double) is non-zero', () {
      // Regression: the prior shape computed `1.0 * math.pow(10, -324)`
      // which rounded to `0.0` (losing the smallest positive subnormal
      // entirely). Capture-based parsing delegates to `double.parse`
      // on the source slice and gets the correctly-rounded result.
      final parsed = val_(floatingPoint().run('5e-324'));
      expect(parsed, double.parse('5e-324'));
      expect(parsed, isNot(0.0));
    });
  });
}
