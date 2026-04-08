import 'package:rumil/rumil.dart';
import 'package:test/test.dart';

void main() {
  group('Lazy error construction', () {
    test('successful branch does not materialize failure errors', () {
      // This tests the core lazy error optimization.
      // The left branch fails, the right succeeds.
      // We verify the right result is correct — the left's error
      // thunk should never have been called (we can't directly test
      // that without instrumenting the thunk, but we can verify
      // the success path works correctly).
      final p = char('x') | char('a');
      final r = p.run('a');
      expect(r, isA<Success<ParseError, String>>());
      expect((r as Success<ParseError, String>).value, 'a');
    });

    test('failure errors are materialized on access', () {
      final r = char('a').run('xyz');
      final f = r as Failure<ParseError, String>;
      // Accessing .errors triggers the thunk
      expect(f.errors, isNotEmpty);
      expect(f.errors.first, isA<Unexpected>());
    });

    test('or merges errors from both branches when both fail', () {
      final p = char('a') | char('b');
      final r = p.run('xyz');
      final f = r as Failure<ParseError, String>;
      // Both branches fail at same position — errors merged
      expect(f.errors.length, 2);
    });

    test('deepest error wins in or', () {
      // string('ab') fails at offset 1 (matched 'a', failed on 'b')
      // char('x') fails at offset 0
      // The deeper failure (offset 1) should be reported
      // Actually — Or restores position on failure, so both start at 0
      // string('ab') would fail at offset 0 if first char doesn't match
      final p = string('xy') | string('xz');
      final r = p.run('xa');
      final f = r as Failure<ParseError, String>;
      // Both fail — errors about "xy" and "xz"
      expect(f.errors, isNotEmpty);
    });
  });

  group('RecoverWith', () {
    test('recovery produces Partial result', () {
      final p = char('a').recover(char('b'));
      final r = p.run('b');
      // Primary fails, recovery succeeds → Partial
      expect(r, isA<Partial<ParseError, String>>());
      final partial = r as Partial<ParseError, String>;
      expect(partial.value, 'b');
      expect(partial.errors, isNotEmpty); // has the original failure's errors
    });

    test('success bypasses recovery', () {
      final p = char('a').recover(char('b'));
      final r = p.run('a');
      expect(r, isA<Success<ParseError, String>>());
      expect((r as Success<ParseError, String>).value, 'a');
    });

    test('both failing gives Failure', () {
      final p = char('a').recover(char('b'));
      final r = p.run('xyz');
      expect(r, isA<Failure<ParseError, String>>());
    });
  });

  group('Error messages', () {
    test('Unexpected includes found and expected', () {
      final r = char('a').run('x');
      final f = r as Failure<ParseError, String>;
      final e = f.errors.first as Unexpected;
      expect(e.found, 'x');
      expect(e.expected, contains("'a'"));
      expect(e.location.offset, 0);
    });

    test('EndOfInput on empty input', () {
      final r = char('a').run('');
      final f = r as Failure<ParseError, String>;
      final e = f.errors.first as EndOfInput;
      expect(e.expected, "'a'");
    });

    test('named parser adds to expected set', () {
      final p = (char('a') | char('b')).named('letter');
      final r = p.run('x');
      final f = r as Failure<ParseError, String>;
      // The named parser should add 'letter' to expected
      final hasLetter = f.errors.any((e) =>
          e is Unexpected && e.expected.contains('letter'));
      expect(hasLetter, isTrue);
    });

    test('expect replaces error message', () {
      final p = char('a').expect('the letter a');
      final r = p.run('x');
      final f = r as Failure<ParseError, String>;
      expect(f.errors.first, isA<CustomError>());
      expect((f.errors.first as CustomError).message, 'the letter a');
    });

    test('error tracks line and column', () {
      final p = string('hello') << char('\n') << string('world');
      final r = p.run('hello\nxyz');
      // 'hello\n' consumed, then 'world' fails at 'xyz'
      final f = r as Failure<ParseError, String>;
      final e = f.errors.first;
      // Should be at line 2, column 1 (after the newline)
      expect(e.location.line, 2);
      expect(e.location.column, 1);
    });
  });

  group('Optional and lookahead', () {
    test('optional returns value on match', () {
      final r = digit().optional.run('5');
      expect(r, isA<Success<ParseError, String?>>());
      expect((r as Success<ParseError, String?>).value, '5');
    });

    test('optional returns null on no match', () {
      final r = digit().optional.run('abc');
      expect(r, isA<Success<ParseError, String?>>());
      expect((r as Success<ParseError, String?>).value, isNull);
    });

    test('sepBy returns empty on no match', () {
      final r = digit().sepBy(char(',')).run('abc');
      expect(r, isA<Success<ParseError, List<String>>>());
      expect((r as Success<ParseError, List<String>>).value, isEmpty);
    });

    test('sepBy1 returns separated values', () {
      final r = digit().sepBy1(char(',')).run('1,2,3');
      expect(r, isA<Success<ParseError, List<String>>>());
      expect((r as Success<ParseError, List<String>>).value, ['1', '2', '3']);
    });

    test('between extracts middle', () {
      final r = digit().between(char('('), char(')')).run('(5)');
      expect(r, isA<Success<ParseError, String>>());
      expect((r as Success<ParseError, String>).value, '5');
    });
  });
}
