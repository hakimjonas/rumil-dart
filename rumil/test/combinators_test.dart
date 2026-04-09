import 'package:rumil/rumil.dart' hide fail;
import 'package:test/test.dart';

T val<T>(Result<Object?, T> r) => switch (r) {
  Success<Object?, T>(:final value) => value,
  Partial<Object?, T>(:final value) => value,
  Failure() => throw StateError('Expected success, got $r'),
};

void main() {
  group('chainl1', () {
    test('left-associative addition', () {
      final num = digit().map(int.parse);
      final add = char('+').as<int Function(int, int)>((a, b) => a + b);
      expect(val(chainl1(num, add).run('1+2+3')), 6);
    });

    test('left-associative subtraction', () {
      final num = digit().map(int.parse);
      final sub = char('-').as<int Function(int, int)>((a, b) => a - b);
      // (5-3)-1 = 1
      expect(val(chainl1(num, sub).run('5-3-1')), 1);
    });

    test('single value (no operator)', () {
      final num = digit().map(int.parse);
      final add = char('+').as<int Function(int, int)>((a, b) => a + b);
      expect(val(chainl1(num, add).run('7')), 7);
    });

    test('via extension method', () {
      final num = digit().map(int.parse);
      final mul = char('*').as<int Function(int, int)>((a, b) => a * b);
      // (2*3)*4 = 24
      expect(val(num.chainl1(mul).run('2*3*4')), 24);
    });
  });

  group('chainr1', () {
    test('right-associative power', () {
      final num = digit().map(int.parse);
      final pow = char('^').as<int Function(int, int)>((a, b) {
        var result = 1;
        for (var i = 0; i < b; i++) {
          result *= a;
        }
        return result;
      });
      // 2^(3^2) = 2^9 = 512
      expect(val(chainr1(num, pow).run('2^3^2')), 512);
    });

    test('single value', () {
      final num = digit().map(int.parse);
      final pow = char('^').as<int Function(int, int)>((a, b) => a);
      expect(val(chainr1(num, pow).run('5')), 5);
    });
  });

  group('count/times', () {
    test('exactly n', () {
      expect(val(digit().times(3).run('12345')), ['1', '2', '3']);
    });

    test('count 0 returns empty', () {
      expect(val(digit().times(0).run('abc')), <String>[]);
    });

    test('fails if not enough', () {
      final r = digit().times(3).run('12');
      expect(r, isA<Failure<ParseError, List<String>>>());
    });
  });

  group('endBy', () {
    test('semicolon-terminated statements', () {
      final stmt = digit().endBy(char(';'));
      expect(val(stmt.run('1;2;3;')), ['1', '2', '3']);
    });

    test('empty input returns empty', () {
      expect(val(digit().endBy(char(';')).run('')), <String>[]);
    });
  });

  group('manyAtLeast', () {
    test('at least 2', () {
      expect(val(digit().manyAtLeast(2).run('1234')), ['1', '2', '3', '4']);
    });

    test('fails if fewer than n', () {
      final r = digit().manyAtLeast(3).run('12');
      expect(r, isA<Failure<ParseError, List<String>>>());
    });
  });

  group('capture', () {
    test('captures consumed input as string', () {
      final p = digit().many1.capture;
      expect(val(p.run('123abc')), '123');
    });
  });

  group('surroundedBy', () {
    test('between same delimiter', () {
      final p = digit().surroundedBy(char('|'));
      expect(val(p.run('|5|')), '5');
    });
  });

  group('stringIn', () {
    test('matches keywords', () {
      final p = stringIn(['true', 'false', 'null']);
      expect(val(p.run('true')), 'true');
      expect(val(p.run('false')), 'false');
    });

    test('keywords with values', () {
      final p = keywords({'true': true, 'false': false});
      expect(val(p.run('true')), true);
      expect(val(p.run('false')), false);
    });
  });

  group('lexeme / symbol', () {
    test('lexeme consumes trailing whitespace', () {
      final p = lexeme(digit()).zip(digit());
      expect(val(p.run('1  2')), ('1', '2'));
    });

    test('symbol matches string + whitespace', () {
      final p = symbol('let').zip(letter());
      expect(val(p.run('let x')), ('let', 'x'));
    });
  });
}
