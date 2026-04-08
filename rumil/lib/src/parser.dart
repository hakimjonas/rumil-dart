/// The Parser ADT — a pure, immutable description of a parsing computation.
///
/// Parsers are data: they describe *what* to parse, not *how*. No side effects
/// occur until a parser is executed via `run()`. This separation enables
/// composition, memoization, and left-recursion analysis.
///
/// The hierarchy is sealed with 26 final subtypes, each representing a
/// distinct parsing operation. The interpreter pattern-matches exhaustively
/// over all cases.
library;

import 'errors.dart';
import 'memo.dart';
import 'result.dart';

/// A parser that consumes input and produces a value of type [A],
/// or fails with an error of type [E].
///
/// Parsers are pure and lazy — no computation occurs until [run] is called.
/// Compose parsers using combinators (see `extensions.dart`) to build
/// complex grammars from simple primitives.
///
/// Type parameters:
/// - [E]: error type. Use [ParseError] for standard parsers, [Never] for
///   infallible ones.
/// - [A]: the type of value this parser produces on success.
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
///
/// [expected] is used in error messages (e.g. `"digit"`, `"letter"`).
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
///
/// Built automatically by the [choice] combinator when all alternatives
/// are [StringMatch]. O(m) matching where m = matched string length,
/// regardless of the number of alternatives.
final class StringChoice extends Parser<ParseError, String> {
  final Object radix; // RadixNode — forward reference, typed as Object internally
  final List<String> targets;
  const StringChoice(this.radix, this.targets);
}

/// Matches end of input. Fails if any input remains.
final class Eof<E> extends Parser<E, void> {
  const Eof();
}

// ---------------------------------------------------------------------------
// Composition
// ---------------------------------------------------------------------------

/// Transforms the result of [source] using [f].
///
/// `parser.map(f)` — the functor operation.
///
/// Named `Mapped` to avoid collision with `dart:core` `Map`.
final class Mapped<E, A, B> extends Parser<E, B> {
  final Parser<E, A> source;
  final B Function(A) f;
  const Mapped(this.source, this.f);

  /// Thread the existential type [A] through a generic interpreter.
  ///
  /// This is a type-threading helper, not interpretation logic. It preserves
  /// the [A]→[B] relationship that is existential from the outside, allowing
  /// the external interpreter to call back with the correct type.
  Result<E, B> interpretWith(Result<E, T> Function<T>(Parser<E, T>) interpret) {
    final r = interpret<A>(source);
    return switch (r) {
      Success<E, A>(:final value, :final consumed) =>
        Success<E, B>(f(value), consumed),
      Partial<E, A>(:final value, :final errorThunk, :final consumed) =>
        Partial<E, B>(f(value), errorThunk, consumed),
      Failure<E, A>(:final errorThunk, :final furthest) =>
        Failure<E, B>(errorThunk, furthest),
    };
  }
}

/// Sequences [source] with a parser-producing function [f].
///
/// `parser.flatMap(f)` — the monad bind operation. The function [f]
/// receives the result of [source] and returns a new parser.
final class FlatMap<E, A, B> extends Parser<E, B> {
  final Parser<E, A> source;
  final Parser<E, B> Function(A) f;
  const FlatMap(this.source, this.f);

  /// Thread the existential type [A] through a generic interpreter.
  Result<E, B> interpretWith(Result<E, T> Function<T>(Parser<E, T>) interpret) {
    final r = interpret<A>(source);
    return switch (r) {
      Success<E, A>(:final value, :final consumed) => () {
          final r2 = interpret<B>(f(value));
          return switch (r2) {
            Success<E, B>(:final value, consumed: final c2) =>
              Success<E, B>(value, consumed + c2),
            Partial<E, B>(:final value, :final errorThunk, consumed: final c2) =>
              Partial<E, B>(value, errorThunk, consumed + c2),
            Failure<E, B>() => r2,
          };
        }(),
      Partial<E, A>(:final value, errorThunk: final mk1, :final consumed) => () {
          final r2 = interpret<B>(f(value));
          return switch (r2) {
            Success<E, B>(:final value, consumed: final c2) =>
              Partial<E, B>(value, mk1, consumed + c2),
            Partial<E, B>(:final value, errorThunk: final mk2, consumed: final c2) =>
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

  /// Thread the existential types [A] and [B] through a generic interpreter.
  Result<E, (A, B)> interpretWith(Result<E, T> Function<T>(Parser<E, T>) interpret) {
    final r1 = interpret<A>(left);
    return switch (r1) {
      Success<E, A>(value: final a, consumed: final c1) => () {
          final r2 = interpret<B>(right);
          return switch (r2) {
            Success<E, B>(value: final b, consumed: final c2) =>
              Success<E, (A, B)>((a, b), c1 + c2),
            Partial<E, B>(value: final b, :final errorThunk, consumed: final c2) =>
              Partial<E, (A, B)>((a, b), errorThunk, c1 + c2),
            Failure<E, B>() => Failure<E, (A, B)>(r2.errorThunk, r2.furthest),
          };
        }(),
      Partial<E, A>(value: final a, errorThunk: final mk1, consumed: final c1) => () {
          final r2 = interpret<B>(right);
          return switch (r2) {
            Success<E, B>(value: final b, consumed: final c2) =>
              Partial<E, (A, B)>((a, b), mk1, c1 + c2),
            Partial<E, B>(value: final b, errorThunk: final mk2, consumed: final c2) =>
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

/// Tries [left]; on failure (without consuming input), tries [right].
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

/// Matches [parser] zero or more times, collecting results in a list.
final class Many<E, A> extends Parser<E, List<A>> {
  final Parser<E, A> parser;
  const Many(this.parser);

  /// Thread the inner [A] through a generic interpreter.
  Result<E, List<A>> interpretWith(
    Result<E, List<T>> Function<T>(Parser<E, T>) interpret,
  ) =>
      interpret<A>(parser);
}

/// Matches [parser] one or more times, collecting results in a list.
final class Many1<E, A> extends Parser<E, List<A>> {
  final Parser<E, A> parser;
  const Many1(this.parser);

  /// Thread the inner [A] through a generic interpreter.
  Result<E, List<A>> interpretWith(
    Result<E, List<T>> Function<T>(Parser<E, T>) interpret,
  ) =>
      interpret<A>(parser);
}

/// Matches [parser] zero or more times, discarding results.
final class SkipMany<E, A> extends Parser<E, void> {
  final Parser<E, A> parser;
  const SkipMany(this.parser);

  /// Thread the inner [A] through a generic interpreter.
  Result<E, void> interpretWith(
    Result<E, void> Function<T>(Parser<E, T>) interpret,
  ) =>
      interpret<A>(parser);
}

/// Matches [parser] and returns the consumed input as a string,
/// discarding the parsed value.
final class Capture<E, A> extends Parser<E, String> {
  final Parser<E, A> parser;
  const Capture(this.parser);

  /// Thread the inner [A] through the interpreter.
  Result<E, String> interpretWith(
    Result<E, String> Function(Parser<E, A>) interpretCapture,
  ) =>
      interpretCapture(parser);
}

// ---------------------------------------------------------------------------
// Optional / Lookahead / Negation
// ---------------------------------------------------------------------------

/// Matches [parser] zero or one times. Returns `null` on no match.
final class Optional<E, A> extends Parser<E, A?> {
  final Parser<E, A> parser;
  const Optional(this.parser);

  /// Thread the inner [A] through a generic interpreter.
  Result<E, A?> interpretWith(
    Result<E, T?> Function<T>(Parser<E, T>) interpret,
  ) =>
      interpret<A>(parser);
}

/// Runs [parser] and wraps the outcome in a [Result], always succeeding.
///
/// This never fails — it captures the inner result as a value.
final class Attempt<E, A> extends Parser<Never, Result<E, A>> {
  final Parser<E, A> parser;
  const Attempt(this.parser);

  /// Thread the inner [E, A] through the interpreter.
  Result<Never, Result<E, A>> interpretWith(
    Result<Never, Result<E, A>> Function(Parser<E, A>) interpretAttempt,
  ) =>
      interpretAttempt(parser);
}

/// Matches [parser] without consuming input. Succeeds with the value
/// if [parser] would succeed at the current position.
final class LookAhead<E, A> extends Parser<E, A> {
  final Parser<E, A> parser;
  const LookAhead(this.parser);
}

/// Succeeds (consuming nothing) only if [parser] would fail at the
/// current position. A negative lookahead.
final class NotFollowedBy<A> extends Parser<ParseError, void> {
  final Parser<ParseError, A> parser;
  const NotFollowedBy(this.parser);
}

// ---------------------------------------------------------------------------
// Error handling / Recovery
// ---------------------------------------------------------------------------

/// Tries [parser]; on failure, tries [recovery] from the same position.
///
/// If [recovery] succeeds, the result is [Partial] — a value was produced
/// but errors were accumulated. This enables resilient/IDE-grade parsing.
final class RecoverWith<E, A> extends Parser<E, A> {
  final Parser<E, A> parser;
  final Parser<E, A> recovery;
  const RecoverWith(this.parser, this.recovery);
}

/// Replaces the error message of [parser] with [message] on failure.
final class Expect<A> extends Parser<ParseError, A> {
  final Parser<ParseError, A> parser;
  final String message;
  const Expect(this.parser, this.message);
}

// ---------------------------------------------------------------------------
// Naming / Debugging
// ---------------------------------------------------------------------------

/// Attaches a [name] to [parser] for error messages.
///
/// When the parser fails, the error says "expected [name]" instead of
/// the underlying parser's description.
final class Named<A> extends Parser<ParseError, A> {
  final Parser<ParseError, A> parser;
  final String name;
  const Named(this.parser, this.name);
}

/// Prints trace information when [parser] is entered/exited.
/// For debugging only — has no effect on parse results.
final class Trace<E, A> extends Parser<E, A> {
  final Parser<E, A> parser;
  final String label;
  const Trace(this.parser, this.label);
}

/// Like [Trace] but with more verbose output.
/// For debugging only — has no effect on parse results.
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
/// Required for recursive grammars: without [Defer], a recursive parser
/// definition would cause infinite initialization.
///
/// ```dart
/// late final expr = rule(() => (expr << char('+')) & digit | digit);
/// ```
final class Defer<E, A> extends Parser<E, A> {
  final Parser<E, A> Function() thunk;
  const Defer(this.thunk);
}

/// Memoized parser with optional left-recursion support.
///
/// When [enableLR] is `true`, the Warth et al. seed-growth algorithm
/// is used to handle left-recursive grammars. This is Rumil's signature
/// feature — left-recursive rules like `expr -> expr '+' term | term`
/// work without grammar transformation.
///
/// When [enableLR] is `false`, simple memoization is used (faster,
/// but left recursion will diverge).
///
/// Created via [rule] (LR-enabled) or `.memoize` (simple).
final class Memo<E, A> extends Parser<E, A> {
  final Parser<E, A> inner;
  final MemoKey<E, A> key;
  final bool enableLR;
  const Memo(this.inner, this.key, {required this.enableLR});
}
