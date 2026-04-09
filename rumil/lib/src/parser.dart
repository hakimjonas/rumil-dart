/// Sealed Parser ADT. Parsers are immutable data; nothing happens until `run()`.
library;

import 'errors.dart';
import 'memo.dart';
import 'radix.dart';
import 'result.dart';

/// A parser that consumes input and produces a value of type [A],
/// or fails with an error of type [E].
///
/// Compose parsers using combinators (see `extensions.dart`) to build
/// complex grammars from simple primitives.
sealed class Parser<E, A> {
  const Parser();
}

// ---------------------------------------------------------------------------
// Terminals
// ---------------------------------------------------------------------------

/// Always succeeds with [value], consuming no input.
final class Succeed<E, A> extends Parser<E, A> {
  final A value;
  const Succeed(this.value);
}

/// Always fails with [error], consuming no input.
final class Fail<E, A> extends Parser<E, A> {
  final E error;
  const Fail(this.error);
}

/// Matches a single character satisfying [pred].
final class Satisfy extends Parser<ParseError, String> {
  final bool Function(String) pred;
  final String expected;
  const Satisfy(this.pred, this.expected);
}

/// Matches the exact string [target].
final class StringMatch extends Parser<ParseError, String> {
  final String target;
  const StringMatch(this.target);
}

/// Matches one of several string alternatives via a radix tree.
final class StringChoice extends Parser<ParseError, String> {
  final RadixNode radix;
  final List<String> targets;
  const StringChoice(this.radix, this.targets);
}

/// Matches end of input.
final class Eof<E> extends Parser<E, void> {
  const Eof();
}

// ---------------------------------------------------------------------------
// Composition
// ---------------------------------------------------------------------------

/// Transforms the result of [source] using [f].
final class Mapped<E, A, B> extends Parser<E, B> {
  final Parser<E, A> source;
  final B Function(A) f;
  const Mapped(this.source, this.f);

  /// Apply [f] to a type-erased value (used by the trampoline).
  B applyF(Object? value) => f(value as A);

  /// Dispatch to the interpreter with the inner type in scope.
  Result<E, B> interpretWith(Result<E, T> Function<T>(Parser<E, T>) interpret) {
    final r = interpret<A>(source);
    return switch (r) {
      Success<E, A>(:final value, :final consumed) => Success<E, B>(
        f(value),
        consumed,
      ),
      Partial<E, A>(:final value, :final errorThunk, :final consumed) =>
        Partial<E, B>(f(value), errorThunk, consumed),
      Failure<E, A>(:final errorThunk, :final furthest) => Failure<E, B>(
        errorThunk,
        furthest,
      ),
    };
  }
}

/// Sequences [source] then applies [f] to the result (monadic bind).
final class FlatMap<E, A, B> extends Parser<E, B> {
  final Parser<E, A> source;
  final Parser<E, B> Function(A) f;
  const FlatMap(this.source, this.f);

  /// Apply [f] to a type-erased value (used by the trampoline).
  Parser<E, B> applyF(Object? value) => f(value as A);

  /// Dispatch to the interpreter with the inner type in scope.
  Result<E, B> interpretWith(Result<E, T> Function<T>(Parser<E, T>) interpret) {
    final r = interpret<A>(source);
    return switch (r) {
      Success<E, A>(:final value, :final consumed) => () {
        final r2 = interpret<B>(f(value));
        return switch (r2) {
          Success<E, B>(:final value, consumed: final c2) => Success<E, B>(
            value,
            consumed + c2,
          ),
          Partial<E, B>(:final value, :final errorThunk, consumed: final c2) =>
            Partial<E, B>(value, errorThunk, consumed + c2),
          Failure<E, B>() => r2,
        };
      }(),
      Partial<E, A>(:final value, errorThunk: final mk1, :final consumed) =>
        () {
          final r2 = interpret<B>(f(value));
          return switch (r2) {
            Success<E, B>(:final value, consumed: final c2) => Partial<E, B>(
              value,
              mk1,
              consumed + c2,
            ),
            Partial<E, B>(
              :final value,
              errorThunk: final mk2,
              consumed: final c2,
            ) =>
              Partial<E, B>(value, () => [...mk1(), ...mk2()], consumed + c2),
            Failure<E, B>(errorThunk: final mk2, :final furthest) =>
              Failure<E, B>(() => [...mk1(), ...mk2()], furthest),
          };
        }(),
      Failure<E, A>() => Failure<E, B>(r.errorThunk, r.furthest),
    };
  }
}

/// Sequences [left] then [right], returning both results as a record.
final class Zip<E, A, B> extends Parser<E, (A, B)> {
  final Parser<E, A> left;
  final Parser<E, B> right;
  const Zip(this.left, this.right);

  /// Dispatch to the interpreter with both inner types in scope.
  Result<E, (A, B)> interpretWith(
    Result<E, T> Function<T>(Parser<E, T>) interpret,
  ) {
    final r1 = interpret<A>(left);
    return switch (r1) {
      Success<E, A>(value: final a, consumed: final c1) => () {
        final r2 = interpret<B>(right);
        return switch (r2) {
          Success<E, B>(value: final b, consumed: final c2) =>
            Success<E, (A, B)>((a, b), c1 + c2),
          Partial<E, B>(
            value: final b,
            :final errorThunk,
            consumed: final c2,
          ) =>
            Partial<E, (A, B)>((a, b), errorThunk, c1 + c2),
          Failure<E, B>() => Failure<E, (A, B)>(r2.errorThunk, r2.furthest),
        };
      }(),
      Partial<E, A>(
        value: final a,
        errorThunk: final mk1,
        consumed: final c1,
      ) =>
        () {
          final r2 = interpret<B>(right);
          return switch (r2) {
            Success<E, B>(value: final b, consumed: final c2) =>
              Partial<E, (A, B)>((a, b), mk1, c1 + c2),
            Partial<E, B>(
              value: final b,
              errorThunk: final mk2,
              consumed: final c2,
            ) =>
              Partial<E, (A, B)>((a, b), () => [...mk1(), ...mk2()], c1 + c2),
            Failure<E, B>() => Failure<E, (A, B)>(r2.errorThunk, r2.furthest),
          };
        }(),
      Failure<E, A>() => Failure<E, (A, B)>(r1.errorThunk, r1.furthest),
    };
  }
}

// ---------------------------------------------------------------------------
// Alternation
// ---------------------------------------------------------------------------

/// Tries [left]; on failure (without consuming), tries [right].
final class Or<E, A> extends Parser<E, A> {
  final Parser<E, A> left;
  final Parser<E, A> right;
  const Or(this.left, this.right);
}

/// Tries each alternative in order until one succeeds.
final class Choice<E, A> extends Parser<E, A> {
  final List<Parser<E, A>> alternatives;
  const Choice(this.alternatives);
}

// ---------------------------------------------------------------------------
// Repetition
// ---------------------------------------------------------------------------

/// Matches [parser] zero or more times.
final class Many<E, A> extends Parser<E, List<A>> {
  final Parser<E, A> parser;
  const Many(this.parser);

  Result<E, List<A>> interpretWith(
    Result<E, List<T>> Function<T>(Parser<E, T>) interpret,
  ) => interpret<A>(parser);
}

/// Matches [parser] one or more times.
final class Many1<E, A> extends Parser<E, List<A>> {
  final Parser<E, A> parser;
  const Many1(this.parser);

  Result<E, List<A>> interpretWith(
    Result<E, List<T>> Function<T>(Parser<E, T>) interpret,
  ) => interpret<A>(parser);
}

/// Matches [parser] zero or more times, discarding results.
final class SkipMany<E, A> extends Parser<E, void> {
  final Parser<E, A> parser;
  const SkipMany(this.parser);

  Result<E, void> interpretWith(
    Result<E, void> Function<T>(Parser<E, T>) interpret,
  ) => interpret<A>(parser);
}

/// Matches [parser] and returns the consumed input as a string.
final class Capture<E, A> extends Parser<E, String> {
  final Parser<E, A> parser;
  const Capture(this.parser);

  Result<E, String> interpretWith(
    Result<E, String> Function(Parser<E, A>) interpret,
  ) => interpret(parser);
}

// ---------------------------------------------------------------------------
// Optional / Lookahead / Negation
// ---------------------------------------------------------------------------

/// Matches [parser] zero or one times. Returns `null` on no match.
final class Optional<E, A> extends Parser<E, A?> {
  final Parser<E, A> parser;
  const Optional(this.parser);

  Result<E, A?> interpretWith(
    Result<E, T?> Function<T>(Parser<E, T>) interpret,
  ) => interpret<A>(parser);
}

/// Wraps the outcome of [parser] in a [Result], always succeeding.
final class Attempt<E, A> extends Parser<Never, Result<E, A>> {
  final Parser<E, A> parser;
  const Attempt(this.parser);

  Result<Never, Result<E, A>> interpretWith(
    Result<Never, Result<E, A>> Function(Parser<E, A>) interpret,
  ) => interpret(parser);
}

/// Matches without consuming input (positive lookahead).
final class LookAhead<E, A> extends Parser<E, A> {
  final Parser<E, A> parser;
  const LookAhead(this.parser);
}

/// Succeeds only if [parser] would fail (negative lookahead).
final class NotFollowedBy<A> extends Parser<ParseError, void> {
  final Parser<ParseError, A> parser;
  const NotFollowedBy(this.parser);
}

// ---------------------------------------------------------------------------
// Error handling
// ---------------------------------------------------------------------------

/// On failure, tries [recovery]. Success via recovery produces [Partial].
final class RecoverWith<E, A> extends Parser<E, A> {
  final Parser<E, A> parser;
  final Parser<E, A> recovery;
  const RecoverWith(this.parser, this.recovery);
}

/// Replaces the error message on failure with [message].
final class Expect<A> extends Parser<ParseError, A> {
  final Parser<ParseError, A> parser;
  final String message;
  const Expect(this.parser, this.message);
}

// ---------------------------------------------------------------------------
// Naming / Debugging
// ---------------------------------------------------------------------------

/// Attaches [name] to error messages on failure.
final class Named<A> extends Parser<ParseError, A> {
  final Parser<ParseError, A> parser;
  final String name;
  const Named(this.parser, this.name);
}

/// Prints trace output on enter/exit. No effect on results.
final class Trace<E, A> extends Parser<E, A> {
  final Parser<E, A> parser;
  final String label;
  const Trace(this.parser, this.label);
}

/// Prints verbose debug output on enter/exit. No effect on results.
final class Debug<E, A> extends Parser<E, A> {
  final Parser<E, A> parser;
  final String label;
  const Debug(this.parser, this.label);
}

// ---------------------------------------------------------------------------
// Laziness / Memoization / Left Recursion
// ---------------------------------------------------------------------------

/// Defers parser construction until first use.
///
/// Required for recursive grammars.
final class Defer<E, A> extends Parser<E, A> {
  final Parser<E, A> Function() thunk;
  const Defer(this.thunk);
}

/// Memoized parser with optional left-recursion support.
///
/// With [enableLR], uses Warth et al. seed-growth for left-recursive
/// grammars. Without it, uses simple memoization (faster).
///
/// Created via [rule] (LR-enabled) or `.memoize` (simple).
final class Memo<E, A> extends Parser<E, A> {
  final Parser<E, A> inner;
  final MemoKey<E, A> key;
  final bool enableLR;
  const Memo(this.inner, this.key, {required this.enableLR});
}
