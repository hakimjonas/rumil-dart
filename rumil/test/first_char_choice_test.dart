import 'package:rumil/rumil.dart';
import 'package:test/test.dart';

T _val<T>(Result<Object?, T> r) => switch (r) {
  Success<Object?, T>(:final value) => value,
  Partial<Object?, T>(:final value) => value,
  Failure() => throw StateError('Expected success, got $r'),
};

void main() {
  group('firstCharChoice — explicit builder', () {
    test('dispatches to the parser whose key contains the leading char', () {
      final p = firstCharChoice<String>({
        'a': string('apple'),
        'b': string('banana'),
        'c': string('cherry'),
      });
      expect(_val(p.run('apple')), 'apple');
      expect(_val(p.run('banana')), 'banana');
      expect(_val(p.run('cherry')), 'cherry');
    });

    test('multi-char key binds the same parser to every char', () {
      final p = firstCharChoice<String>({
        'tf': string('true').or(string('false')),
        '0123456789': digit().many1.capture,
      });
      expect(_val(p.run('true')), 'true');
      expect(_val(p.run('false')), 'false');
      expect(_val(p.run('42')), '42');
    });

    test('runs fallback when no leading char matches', () {
      final p = firstCharChoice<String>(
        {'a': string('apple')},
        fallback: string('banana'),
      );
      expect(_val(p.run('apple')), 'apple');
      expect(_val(p.run('banana')), 'banana');
    });

    test('fails with the expected-chars list on miss with no fallback', () {
      final p = firstCharChoice<String>({'a': string('apple')});
      final r = p.run('xenon');
      expect(r, isA<Failure<ParseError, String>>());
      final f = r as Failure<ParseError, String>;
      expect(f.errors.first.toString(), contains('"a"'));
    });

    test('rejects empty dispatch keys at construction', () {
      expect(
        () => firstCharChoice<String>({'': string('x')}),
        throwsArgumentError,
      );
    });

    test('rejects duplicate leading chars across keys', () {
      expect(
        () => firstCharChoice<String>({
          'ab': string('x'),
          'bc': string('y'),
        }),
        throwsArgumentError,
      );
    });
  });

  group('choice — auto-fusion to FirstCharChoice', () {
    test('fuses three+ alternatives with disjoint single-char leads', () {
      final p = choice<ParseError, String>([
        string('apple'),
        string('banana'),
        string('cherry'),
      ]);
      expect(p, isA<FirstCharChoice<ParseError, String>>());
      expect(_val(p.run('apple')), 'apple');
      expect(_val(p.run('banana')), 'banana');
      expect(_val(p.run('cherry')), 'cherry');
    });

    test('does not fuse when alternatives share a leading char', () {
      final p = choice<ParseError, String>([
        string('apple'),
        string('avocado'),
        string('banana'),
      ]);
      expect(p, isA<Choice<ParseError, String>>());
      expect(_val(p.run('apple')), 'apple');
      expect(_val(p.run('avocado')), 'avocado');
    });

    test('does not fuse a 2-way choice', () {
      final p = choice<ParseError, String>([
        string('apple'),
        string('banana'),
      ]);
      expect(p, isA<Choice<ParseError, String>>());
    });

    test('does not fuse when an alternative is undecidable (Defer)', () {
      late Parser<ParseError, String> recursive;
      recursive = string('z');
      final p = choice<ParseError, String>([
        string('apple'),
        string('banana'),
        defer(() => recursive),
      ]);
      expect(p, isA<Choice<ParseError, String>>());
      // Behaviour preserved: matches even though Choice's linear scan
      // is what runs, not FirstCharChoice's table.
      expect(_val(p.run('apple')), 'apple');
      expect(_val(p.run('z')), 'z');
    });

    test('does not fuse when an alternative is undecidable (FlatMap)', () {
      final p = choice<ParseError, String>([
        string('apple'),
        string('banana'),
        char('c').flatMap((_) => string('herry')),
      ]);
      expect(p, isA<Choice<ParseError, String>>());
    });

    test('does not fuse on opaque-predicate Satisfy', () {
      final p = choice<ParseError, String>([
        string('apple'),
        string('banana'),
        satisfy((c) => c.codeUnitAt(0) > 0x60, 'lowercase'),
      ]);
      expect(p, isA<Choice<ParseError, String>>());
    });

    test('peels through Mapped / Named / Expect / LookAhead wrappers', () {
      final p = choice<ParseError, String>([
        string('apple').map((s) => s.toUpperCase()),
        string('banana').named('fruit'),
        string('cherry'),
      ]);
      expect(p, isA<FirstCharChoice<ParseError, String>>());
      expect(_val(p.run('apple')), 'APPLE');
      expect(_val(p.run('banana')), 'banana');
      expect(_val(p.run('cherry')), 'cherry');
    });

    test('handles char(c)-shaped Satisfy via apostrophe-quoted expected', () {
      final p = choice<ParseError, String>([
        char('a').as('A'),
        char('b').as('B'),
        char('c').as('C'),
      ]);
      expect(p, isA<FirstCharChoice<ParseError, String>>());
      expect(_val(p.run('a')), 'A');
      expect(_val(p.run('b')), 'B');
      expect(_val(p.run('c')), 'C');
    });

    test('Or-chains within an alternative contribute all their leading '
        'chars', () {
      final p = choice<ParseError, String>([
        string('ax') | string('ay'),
        string('banana'),
        string('cherry'),
      ]);
      expect(p, isA<FirstCharChoice<ParseError, String>>());
      expect(_val(p.run('ax')), 'ax');
      expect(_val(p.run('ay')), 'ay');
      expect(_val(p.run('banana')), 'banana');
    });
  });

  group('FirstCharChoice — error path', () {
    test('end-of-input failure mentions the expected-chars list', () {
      final p = firstCharChoice<String>({
        'a': string('apple'),
        'b': string('banana'),
      });
      final r = p.run('');
      expect(r, isA<Failure<ParseError, String>>());
      final errs = (r as Failure<ParseError, String>).errors;
      expect(errs.first.toString(), contains('"ab"'));
    });
  });
}
