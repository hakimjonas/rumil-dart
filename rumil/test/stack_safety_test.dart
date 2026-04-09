import 'package:rumil/rumil.dart';
import 'package:test/test.dart';

void main() {
  group('Stack safety', () {
    test('deep flatMap chain (1000)', () {
      Parser<ParseError, int> p = succeed<ParseError, int>(0);
      for (var i = 0; i < 1000; i++) {
        p = p.flatMap((n) => succeed<ParseError, int>(n + 1));
      }
      final r = p.run('');
      expect(r, isA<Success<ParseError, int>>());
      expect((r as Success<ParseError, int>).value, 1000);
    });

    test('deep flatMap chain (100K) — trampoline', () {
      Parser<ParseError, int> p = succeed<ParseError, int>(0);
      for (var i = 0; i < 100000; i++) {
        p = p.flatMap((n) => succeed<ParseError, int>(n + 1));
      }
      final r = p.run('');
      expect(r, isA<Success<ParseError, int>>());
      expect((r as Success<ParseError, int>).value, 100000);
    });

    test('deep flatMap chain (1M) — trampoline', () {
      Parser<ParseError, int> p = succeed<ParseError, int>(0);
      for (var i = 0; i < 1000000; i++) {
        p = p.flatMap((n) => succeed<ParseError, int>(n + 1));
      }
      final r = p.run('');
      expect(r, isA<Success<ParseError, int>>());
      expect((r as Success<ParseError, int>).value, 1000000);
    });

    test('deep flatMap chain (10M) — trampoline', () {
      Parser<ParseError, int> p = succeed<ParseError, int>(0);
      for (var i = 0; i < 10000000; i++) {
        p = p.flatMap((n) => succeed<ParseError, int>(n + 1));
      }
      final r = p.run('');
      expect(r, isA<Success<ParseError, int>>());
      expect((r as Success<ParseError, int>).value, 10000000);
    });

    test('deep map chain (1000)', () {
      Parser<ParseError, int> p = succeed<ParseError, int>(0);
      for (var i = 0; i < 1000; i++) {
        p = p.map((n) => n + 1);
      }
      final r = p.run('');
      expect(r, isA<Success<ParseError, int>>());
      expect((r as Success<ParseError, int>).value, 1000);
    });

    test('deep or chain (1000 failing branches)', () {
      // 999 failing parsers | one success at the end
      Parser<ParseError, String> p = char('z'); // will fail on 'a'
      for (var i = 0; i < 998; i++) {
        p = p | char('z');
      }
      p = p | char('a');
      final r = p.run('a');
      expect(r, isA<Success<ParseError, String>>());
      expect((r as Success<ParseError, String>).value, 'a');
    });

    test('many with 10000 repetitions', () {
      final input = '1' * 10000;
      final r = digit().many.run(input);
      expect(r, isA<Success<ParseError, List<String>>>());
      expect((r as Success<ParseError, List<String>>).value.length, 10000);
    });

    test('nested many', () {
      // (digit+)+ on '123456789'
      final r = digit().many1.many1.run('123456789');
      expect(r, isA<Success<ParseError, List<List<String>>>>());
    });
  });

  group('Left recursion stress', () {
    test('left-recursive expr with 10 terms', () {
      late final Parser<ParseError, int> expr;
      expr = rule<ParseError, int>(
        () =>
            expr
                .thenSkip(char('+'))
                .zip(digit().map(int.parse))
                .map((pair) => pair.$1 + pair.$2) |
            digit().map(int.parse),
      );

      // 1+2+3+4+5+6+7+8+9+0 = 45
      final r = expr.run('1+2+3+4+5+6+7+8+9+0');
      expect(r, isA<Success<ParseError, int>>());
      expect((r as Success<ParseError, int>).value, 45);
    });

    test('left-recursive expr with 50 terms', () {
      late final Parser<ParseError, int> expr;
      expr = rule<ParseError, int>(
        () =>
            expr
                .thenSkip(char('+'))
                .zip(digit().map(int.parse))
                .map((pair) => pair.$1 + pair.$2) |
            digit().map(int.parse),
      );

      // Build "1+1+1+...+1" (50 ones)
      final input = List<String>.filled(50, '1').join('+');
      final r = expr.run(input);
      expect(r, isA<Success<ParseError, int>>());
      expect((r as Success<ParseError, int>).value, 50);
    });

    test('mutual left recursion', () {
      // expr = term
      // term = term "*" digit | digit
      // This tests that LR works with mutual recursion between rules.

      late final Parser<ParseError, int> expr;
      late final Parser<ParseError, int> term;

      term = rule<ParseError, int>(
        () =>
            term
                .thenSkip(char('*'))
                .zip(digit().map(int.parse))
                .map((pair) => pair.$1 * pair.$2) |
            digit().map(int.parse),
      );

      expr = term;

      final r = expr.run('2*3*4');
      expect(r, isA<Success<ParseError, int>>());
      // Left-associative: (2*3)*4 = 24
      expect((r as Success<ParseError, int>).value, 24);
    });

    test('left recursion with alternation', () {
      // expr = expr "+" digit | expr "-" digit | digit
      late final Parser<ParseError, int> expr;
      expr = rule<ParseError, int>(
        () =>
            expr
                .thenSkip(char('+'))
                .zip(digit().map(int.parse))
                .map((pair) => pair.$1 + pair.$2) |
            expr
                .thenSkip(char('-'))
                .zip(digit().map(int.parse))
                .map((pair) => pair.$1 - pair.$2) |
            digit().map(int.parse),
      );

      final r = expr.run('9-3+2');
      expect(r, isA<Success<ParseError, int>>());
      // Left-associative: (9-3)+2 = 8
      expect((r as Success<ParseError, int>).value, 8);
    });
  });
}
