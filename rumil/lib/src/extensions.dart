/// Combinator DSL — extension methods on [Parser].
library;

import 'combinators.dart' as comb;
import 'errors.dart';
import 'interpreter.dart' as runtime;
import 'memo.dart';
import 'parser.dart';
import 'primitives.dart' as prim;
import 'result.dart';

/// Core combinator extensions.
extension ParserOps<E, A> on Parser<E, A> {
  /// Run this parser on [input].
  Result<E, A> run(String input) => runtime.run<E, A>(this, input);

  /// Transform the result value.
  ///
  /// Consecutive maps are fused into a single [Mapped] node via `applyF`.
  Parser<E, B> map<B>(B Function(A) f) {
    if (this case final Mapped<E, dynamic, A> m) {
      return Mapped(m.source, (Object? v) => f(m.applyF(v)));
    }
    return Mapped<E, A, B>(this, f);
  }

  /// Replace the result value.
  Parser<E, B> as<B>(B value) => map((_) => value);

  /// Chain with a parser-producing function.
  ///
  /// When called on a [Mapped] node, fuses the map into the bind
  /// to eliminate an intermediate interpreter step.
  Parser<E, B> flatMap<B>(Parser<E, B> Function(A) f) {
    if (this case final Mapped<E, dynamic, A> m) {
      return FlatMap(m.source, (Object? v) => f(m.applyF(v)));
    }
    return FlatMap<E, A, B>(this, f);
  }

  /// Run this parser then [other], returning both results as a record.
  Parser<E, (A, B)> zip<B>(Parser<E, B> other) => Zip<E, A, B>(this, other);

  /// Run this parser then [other], keeping only the left result.
  Parser<E, A> thenSkip(Parser<E, Object?> other) =>
      Zip<E, A, Object?>(this, other).map((pair) => pair.$1);

  /// Run this parser then [other], keeping only the right result.
  Parser<E, B> skipThen<B>(Parser<E, B> other) =>
      Zip<E, A, B>(this, other).map((pair) => pair.$2);

  /// Try this parser; on failure, try [other].
  Parser<E, A> or(Parser<E, A> other) => Or<E, A>(this, other);

  /// Alias for [or]. Try this parser; on failure, try [other].
  Parser<E, A> operator |(Parser<E, A> other) => Or<E, A>(this, other);

  /// Zero or more repetitions, collecting results into a list.
  Parser<E, List<A>> get many => Many<E, A>(this);

  /// One or more repetitions, collecting results into a list.
  Parser<E, List<A>> get many1 => Many1<E, A>(this);

  /// Try this parser; succeed with `null` if it fails (without consuming).
  Parser<E, A?> get optional => Optional<E, A>(this);

  /// Zero or more repetitions, discarding results.
  Parser<E, void> get skipMany => SkipMany<E, A>(this);

  /// Run this parser and return the matched input as a string.
  Parser<E, String> get capture => Capture<E, A>(this);

  /// Run this parser, restoring position on failure. Returns the [Result].
  Parser<Never, Result<E, A>> get attempt => Attempt<E, A>(this);

  /// Match between [left] and [right].
  Parser<E, A> between(Parser<E, Object?> left, Parser<E, Object?> right) =>
      left.skipThen<A>(this).thenSkip(right);

  /// Match between the same [delim] on both sides.
  Parser<E, A> surroundedBy(Parser<E, Object?> delim) => between(delim, delim);

  /// Zero or more, separated by [sep].
  Parser<E, List<A>> sepBy(Parser<E, Object?> sep) =>
      sepBy1(sep).or(prim.succeed<E, List<A>>(<A>[]));

  /// One or more, separated by [sep].
  Parser<E, List<A>> sepBy1(Parser<E, Object?> sep) => zip<List<A>>(
    sep.skipThen<A>(this).many,
  ).map((pair) => [pair.$1, ...pair.$2]);

  /// Zero or more, each terminated by [end].
  Parser<E, List<A>> endBy(Parser<E, Object?> end) => thenSkip(end).many;

  /// Exactly [n] occurrences.
  Parser<E, List<A>> times(int n) => comb.count<E, A>(n, this);

  /// At least [n] occurrences.
  Parser<E, List<A>> manyAtLeast(int n) => times(n)
      .zip<List<A>>(many)
      .map(((List<A>, List<A>) pair) => [...pair.$1, ...pair.$2]);

  /// Left-associative binary operator chain.
  ///
  /// Parses `p (op p)*` and folds left: `((a op b) op c) op d`.
  Parser<E, A> chainl1(Parser<E, A Function(A, A)> op) =>
      comb.chainl1<E, A>(this, op);

  /// Right-associative binary operator chain.
  ///
  /// Parses `p (op p)*` and folds right: `a op (b op (c op d))`.
  Parser<E, A> chainr1(Parser<E, A Function(A, A)> op) =>
      comb.chainr1<E, A>(this, op);

  /// On failure, try [recovery] (producing [Partial]).
  Parser<E, A> recover(Parser<E, A> recovery) =>
      RecoverWith<E, A>(this, recovery);

  /// Print a trace message when this parser is tried and when it succeeds/fails.
  Parser<E, A> trace(String label) => Trace<E, A>(this, label);

  /// Print a debug message with the parsed value or error details.
  Parser<E, A> debug(String label) => Debug<E, A>(this, label);

  /// Simple memoization (no left-recursion support).
  Parser<E, A> get memoize =>
      Memo<E, A>(this, MemoKey<E, A>(), enableLR: false);
}

/// Extensions for parsers with [ParseError] error type.
extension ParseErrorOps<A> on Parser<ParseError, A> {
  /// Add [name] to expected-set in error messages on failure.
  Parser<ParseError, A> named(String name) => Named<A>(this, name);

  /// Replace the error message with [message] on failure.
  Parser<ParseError, A> expect(String message) => Expect<A>(this, message);

  /// Succeed (consuming nothing) if this parser would fail at the current position.
  Parser<ParseError, void> get notFollowedBy => NotFollowedBy<A>(this);

  /// Run this parser but consume no input on success (peek).
  Parser<ParseError, A> get lookAhead => LookAhead<ParseError, A>(this);
}
