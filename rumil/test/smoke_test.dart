import 'package:rumil/rumil.dart';
import 'package:test/test.dart';

/// Helper to extract value from a successful result.
T successValue<T>(Result<Object?, T> r) {
  expect(r, isA<Success<Object?, T>>());
  return (r as Success<Object?, T>).value;
}

/// Helper to assert failure.
void expectFailure(Result<Object?, Object?> r) {
  expect(r, isA<Failure<Object?, Object?>>());
}

void main() {
  group('Terminals', () {
    test('char succeeds on match', () {
      final r = char('a').run('abc');
      expect(successValue(r), 'a');
      expect((r as Success<ParseError, String>).consumed, 1);
    });

    test('char fails on mismatch', () {
      expectFailure(char('a').run('xyz'));
    });

    test('string matches exact', () {
      final r = string('hello').run('hello world');
      expect(successValue(r), 'hello');
      expect((r as Success<ParseError, String>).consumed, 5);
    });

    test('digit parses 0-9', () {
      expect(successValue(digit().run('7abc')), '7');
    });

    test('eof succeeds at end', () {
      final r = eof().run('');
      expect(r, isA<Success<ParseError, void>>());
    });

    test('eof fails with remaining input', () {
      expectFailure(eof().run('x'));
    });

    test('position at start yields 0', () {
      final r = position<ParseError>().run('abc');
      expect(successValue(r), 0);
      expect((r as Success<ParseError, int>).consumed, 0);
    });

    test('position after consumption yields offset', () {
      final r = string('abc').skipThen(position<ParseError>()).run('abcdef');
      expect(successValue(r), 3);
    });

    test('position captures span around a parser', () {
      final spanned = spaces()
          .skipThen(position<ParseError>())
          .zip(string('hello'))
          .zip(position<ParseError>());
      final r = spanned.run('  hello!');
      expect(r, isA<Success<ParseError, ((int, String), int)>>());
      final s = r as Success<ParseError, ((int, String), int)>;
      expect(s.value.$1.$1, 2);
      expect(s.value.$1.$2, 'hello');
      expect(s.value.$2, 7);
    });
  });

  group('Composition', () {
    test('map transforms result', () {
      expect(successValue(digit().map(int.parse).run('5')), 5);
    });

    test('seq (zip) returns record', () {
      expect(successValue(char('a').zip(char('b')).run('ab')), ('a', 'b'));
    });

    test('thenSkip keeps left', () {
      expect(successValue(char('a').thenSkip(char('b')).run('ab')), 'a');
    });

    test('then_ keeps right', () {
      expect(successValue(char('a').skipThen(char('b')).run('ab')), 'b');
    });

    test('flatMap chains', () {
      final p = digit().flatMap((d) => string('+').map((_) => int.parse(d)));
      expect(successValue(p.run('5+')), 5);
    });
  });

  group('Alternation', () {
    test('| tries second on failure', () {
      expect(successValue((char('a') | char('b')).run('b')), 'b');
    });

    test('| returns first on success', () {
      expect(successValue((char('a') | char('b')).run('a')), 'a');
    });
  });

  group('Repetition', () {
    test('many returns list', () {
      expect(successValue(digit().many.run('123abc')), ['1', '2', '3']);
    });

    test('many returns empty on no match', () {
      expect(successValue(digit().many.run('abc')), <String>[]);
    });

    test('many1 fails on no match', () {
      expectFailure(digit().many1.run('abc'));
    });

    test('many1 returns list on match', () {
      expect(successValue(digit().many1.run('42abc')), ['4', '2']);
    });
  });

  group('Left recursion (Warth seed-growth)', () {
    test('expr -> expr "+" digit | digit', () {
      // The signature test: left-recursive grammar without transformation.
      // 1+2+3 should parse as (1+2)+3 = 6

      late final Parser<ParseError, int> expr;
      expr = rule<ParseError, int>(
        () =>
            expr
                .thenSkip(char('+'))
                .zip(digit().map(int.parse))
                .map((pair) => pair.$1 + pair.$2) |
            digit().map(int.parse),
      );

      expect(successValue(expr.run('1+2+3')), 6);
    });

    test('simple direct left recursion', () {
      // expr = expr "a" | "b"
      // "baaa" should parse as (((b)a)a)a

      late final Parser<ParseError, String> expr;
      expr = rule<ParseError, String>(
        () =>
            expr.zip(char('a')).map((pair) => '(${pair.$1}${pair.$2})') |
            char('b'),
      );

      expect(successValue(expr.run('baaa')), '(((ba)a)a)');
    });

    test('non-recursive memoized parser', () {
      expect(successValue(digit().memoize.run('5')), '5');
    });
  });

  group('Error handling', () {
    test('failure has location info', () {
      final r = char('a').run('xyz');
      final f = r as Failure<ParseError, String>;
      expect(f.errors.length, 1);
      final u = f.errors.first as Unexpected;
      expect(u.found, 'x');
      expect(u.expected, {"'a'"});
      expect(u.location.line, 1);
      expect(u.location.column, 1);
      expect(u.location.offset, 0);
    });

    test('or success path does not need error materialization', () {
      final r = (char('a') | char('b')).run('b');
      expect(successValue(r), 'b');
    });
  });
}
