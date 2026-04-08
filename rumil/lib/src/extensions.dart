/// Combinator DSL — extension methods on [Parser] for ergonomic composition.
///
/// Operator choices were decided by writing real parser definitions:
/// - `|` for alternation (universal convention)
/// - `&` for sequencing/zip (same type only — use [seq] for mixed)
/// - `<<` for keep-left
/// - Method `.then_()` for keep-right (Dart `>>` can't have type params)
library;

import 'errors.dart';
import 'interpreter.dart' as runtime;
import 'memo.dart';
import 'parser.dart';
import 'primitives.dart' as prim;
import 'result.dart';

/// Core combinator extensions on [Parser].
extension ParserOps<E, A> on Parser<E, A> {
  /// Run this parser on [input], returning a [Result].
  Result<E, A> run(String input) => runtime.run<E, A>(this, input);

  /// Transform the result value with [f]. The functor `map` operation.
  Parser<E, B> map<B>(B Function(A) f) => Mapped<E, A, B>(this, f);

  /// Replace the result value with [value], discarding the parsed value.
  Parser<E, B> as<B>(B value) => map((_) => value);

  /// Chain with a parser-producing function. The monad `flatMap`/`bind`.
  Parser<E, B> flatMap<B>(Parser<E, B> Function(A) f) =>
      FlatMap<E, A, B>(this, f);

  // ---- Sequencing ----

  /// Sequence this parser with [other], returning both results as a record.
  ///
  /// Both parsers must have the same result type for operator syntax.
  /// For mixed types, use [seq].
  ///
  /// ```dart
  /// (digit() & digit()).run('12') // Success(('1', '2'), consumed: 2)
  /// ```
  Parser<E, (A, A)> operator &(Parser<E, A> other) =>
      Zip<E, A, A>(this, other);

  /// Sequence this with [other], returning both results as a record.
  ///
  /// Works with different result types (unlike `&`).
  ///
  /// ```dart
  /// digit().seq(char('+')).run('1+') // Success(('1', '+'), consumed: 2)
  /// ```
  Parser<E, (A, B)> seq<B>(Parser<E, B> other) =>
      Zip<E, A, B>(this, other);

  /// Sequence this with [other], keeping only the left result.
  ///
  /// ```dart
  /// (char('a') << char('b')).run('ab') // Success('a', consumed: 2)
  /// ```
  Parser<E, A> operator <<(Parser<E, Object?> other) =>
      Zip<E, A, Object?>(this, other).map((pair) => pair.$1);

  /// Sequence this with [other], keeping only the right result.
  ///
  /// ```dart
  /// char('a').then_(char('b')).run('ab') // Success('b', consumed: 2)
  /// ```
  Parser<E, B> then_<B>(Parser<E, B> other) =>
      Zip<E, A, B>(this, other).map((pair) => pair.$2);

  // ---- Alternation ----

  /// Try this parser; on failure (without consuming), try [other].
  ///
  /// ```dart
  /// (char('a') | char('b')).run('b') // Success('b', consumed: 1)
  /// ```
  Parser<E, A> operator |(Parser<E, A> other) => Or<E, A>(this, other);

  // ---- Repetition ----

  /// Match zero or more times, collecting results in a list.
  Parser<E, List<A>> get many => Many<E, A>(this);

  /// Match one or more times, collecting results in a list.
  Parser<E, List<A>> get many1 => Many1<E, A>(this);

  /// Match zero or one times. Returns `null` on no match.
  Parser<E, A?> get optional => Optional<E, A>(this);

  /// Match zero or more times, discarding results.
  Parser<E, void> get skipMany => SkipMany<E, A>(this);

  // ---- Bracketing ----

  /// Match this parser between [left] and [right].
  ///
  /// ```dart
  /// digit().between(char('('), char(')')).run('(5)') // Success('5', consumed: 3)
  /// ```
  Parser<E, A> between(Parser<E, Object?> left, Parser<E, Object?> right) =>
      left.then_<A>(this) << right;

  // ---- Separated lists ----

  /// Match zero or more times, separated by [sep].
  Parser<E, List<A>> sepBy(Parser<E, Object?> sep) =>
      sepBy1(sep) | prim.succeed<E, List<A>>(<A>[]);

  /// Match one or more times, separated by [sep].
  Parser<E, List<A>> sepBy1(Parser<E, Object?> sep) =>
      seq<List<A>>(sep.then_<A>(this).many)
          .map((pair) => [pair.$1, ...pair.$2]);

  // ---- Error handling ----

  /// Try this parser; on failure, try [recovery] (producing a Partial result).
  Parser<E, A> recover(Parser<E, A> recovery) =>
      RecoverWith<E, A>(this, recovery);

  // ---- Naming / Debugging ----

  /// Attach a debug trace label.
  Parser<E, A> trace(String label) => Trace<E, A>(this, label);

  /// Attach a verbose debug label.
  Parser<E, A> debug(String label) => Debug<E, A>(this, label);

  /// Simple memoization (no left-recursion support, faster cache hits).
  Parser<E, A> get memoize =>
      Memo<E, A>(this, MemoKey<E, A>(), enableLR: false);
}

/// Extensions specific to parsers with [ParseError] error type.
extension ParseErrorOps<A> on Parser<ParseError, A> {
  /// Attach a name for error messages.
  Parser<ParseError, A> named(String name) => Named<A>(this, name);

  /// Replace the error message on failure with [message].
  Parser<ParseError, A> expect(String message) => Expect<A>(this, message);

  /// Negative lookahead: succeed only if this parser would fail.
  Parser<ParseError, void> get notFollowedBy => NotFollowedBy<A>(this);

  /// Lookahead: match without consuming input.
  Parser<ParseError, A> get lookAhead => LookAhead<ParseError, A>(this);
}
