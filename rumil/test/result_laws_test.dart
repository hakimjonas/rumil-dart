import 'package:rumil/rumil.dart';
import 'package:test/test.dart';

/// Test the algebraic laws that Result must satisfy.
///
/// These correspond to Rumil Scala's MonadLaws tests, adapted for Dart.
/// We test directly on Result and on Parser (via run), not through
/// typeclass instances.
void main() {
  // Helper: extract value or throw
  T val<T>(Result<Object?, T> r) => switch (r) {
    Success<Object?, T>(:final value) => value,
    Partial<Object?, T>(:final value) => value,
    Failure() => throw StateError('Expected success, got $r'),
  };

  group('Result.map laws (Functor)', () {
    test('identity: map(id) == id', () {
      const r = Success<String, int>(42, 1);
      final mapped = r.map((x) => x);
      expect(val(mapped), val(r));
      expect((mapped as Success<String, int>).consumed, (r).consumed);
    });

    test('composition: map(f . g) == map(f) . map(g)', () {
      const r = Success<String, int>(10, 1);
      int double_(int x) => x * 2;
      String show(int x) => 'v:$x';

      final composed = r.map((x) => show(double_(x)));
      final chained = r.map(double_).map(show);

      expect(val(composed), val(chained));
    });

    test('identity holds for Partial', () {
      final r = Partial<String, int>(42, () => ['err'], 1);
      final mapped = r.map((x) => x);
      expect(val(mapped), val(r));
    });

    test('identity holds for Failure', () {
      final r = Failure<String, int>.eager(['err'], Location.zero);
      final mapped = r.map((x) => x * 2);
      expect(mapped, isA<Failure<String, int>>());
      expect((mapped as Failure<String, int>).errors, ['err']);
    });

    test('composition holds for Partial', () {
      final r = Partial<String, int>(5, () => ['warn'], 1);
      int inc(int x) => x + 1;
      int double_(int x) => x * 2;

      final composed = r.map((x) => double_(inc(x)));
      final chained = r.map(inc).map(double_);
      expect(val(composed), val(chained));
    });
  });

  group('Parser monad laws (via run)', () {
    // Left identity: succeed(a).flatMap(f) == f(a)
    test('left identity: succeed(a).flatMap(f) == f(a)', () {
      Parser<ParseError, String> f(int n) =>
          succeed<ParseError, String>('n=$n');

      final lhs = succeed<ParseError, int>(42).flatMap(f).run('');
      final rhs = f(42).run('');
      expect(val(lhs), val(rhs));
    });

    // Right identity: p.flatMap(succeed) == p
    test('right identity: p.flatMap(succeed) == p', () {
      final p = string('hello');
      final lhs = p.flatMap((v) => succeed<ParseError, String>(v)).run('hello');
      final rhs = p.run('hello');
      expect(val(lhs), val(rhs));
    });

    // Associativity: p.flatMap(f).flatMap(g) == p.flatMap(a => f(a).flatMap(g))
    test('associativity: flatMap chains are order-independent', () {
      final p = digit().map(int.parse);
      Parser<ParseError, int> f(int n) => succeed<ParseError, int>(n * 2);
      Parser<ParseError, String> g(int n) =>
          succeed<ParseError, String>('result: $n');

      final lhs = p.flatMap(f).flatMap(g).run('5');
      final rhs = p.flatMap((a) => f(a).flatMap(g)).run('5');
      expect(val(lhs), val(rhs));
      expect(val(lhs), 'result: 10');
    });

    test('associativity with actual parsing', () {
      final p = char('a');
      Parser<ParseError, String> f(String c) => char('b').map((b) => c + b);
      Parser<ParseError, int> g(String s) => succeed<ParseError, int>(s.length);

      final lhs = p.flatMap(f).flatMap(g).run('ab');
      final rhs = p.flatMap((a) => f(a).flatMap(g)).run('ab');
      expect(val(lhs), val(rhs));
      expect(val(lhs), 2);
    });
  });

  group('Result extension methods', () {
    test('isSuccess / isPartial / isFailure', () {
      const s = Success<String, int>(1, 0);
      final p = Partial<String, int>(1, () => ['e'], 0);
      final f = Failure<String, int>.eager(['e'], Location.zero);

      expect(s.isSuccess, isTrue);
      expect(s.isPartial, isFalse);
      expect(s.isFailure, isFalse);

      expect(p.isSuccess, isFalse);
      expect(p.isPartial, isTrue);
      expect(p.isFailure, isFalse);

      expect(f.isSuccess, isFalse);
      expect(f.isPartial, isFalse);
      expect(f.isFailure, isTrue);
    });

    test('valueOrNull', () {
      expect(const Success<String, int>(42, 0).valueOrNull, 42);
      expect(Partial<String, int>(42, () => ['e'], 0).valueOrNull, 42);
      expect(
        Failure<String, int>.eager(['e'], Location.zero).valueOrNull,
        isNull,
      );
    });

    test('errors', () {
      expect(const Success<String, int>(42, 0).errors, isEmpty);
      expect(Partial<String, int>(42, () => ['a', 'b'], 0).errors, ['a', 'b']);
      expect(Failure<String, int>.eager(['x'], Location.zero).errors, ['x']);
    });
  });
}
