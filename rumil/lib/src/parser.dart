/// Sealed Parser ADT. Parsers are immutable data; nothing happens until `run()`.
library;

import 'errors.dart';
import 'memo.dart';
import 'pratt_op.dart';
import 'radix.dart';
import 'result.dart';

export 'pratt_op.dart';

/// A parser that consumes input and produces a value of type [A],
/// or fails with an error of type [E].
///
/// Compose parsers using combinators (see `extensions.dart`) to build
/// complex grammars from simple primitives.
sealed class Parser<E, A> {
  /// Base constructor.
  const Parser();

  /// True if this parser cannot consume input on failure.
  /// Used to skip save/restore in Many/Choice/Or loops.
  bool get isSimple => false;
}

// ---------------------------------------------------------------------------
// Terminals
// ---------------------------------------------------------------------------

/// Always succeeds with [value], consuming no input.
final class Succeed<E, A> extends Parser<E, A> {
  /// The value to return.
  final A value;

  /// Creates a parser that always succeeds with [value].
  const Succeed(this.value);

  @override
  bool get isSimple => true;
}

/// Always fails with [error], consuming no input.
final class Fail<E, A> extends Parser<E, A> {
  /// The error to report.
  final E error;

  /// Creates a parser that always fails with [error].
  const Fail(this.error);

  @override
  bool get isSimple => true;
}

/// Matches a single character satisfying [pred].
final class Satisfy extends Parser<ParseError, String> {
  /// The predicate the character must satisfy.
  final bool Function(String) pred;

  /// Description shown in error messages when the predicate fails.
  final String expected;

  /// Creates a character parser with [pred] and [expected] label.
  const Satisfy(this.pred, this.expected);

  @override
  bool get isSimple => true;
}

/// Matches the exact string [target].
final class StringMatch extends Parser<ParseError, String> {
  /// The string to match.
  final String target;

  /// Creates a parser that matches [target] exactly.
  const StringMatch(this.target);

  @override
  bool get isSimple => true;
}

/// Matches one of several string alternatives via a radix tree.
final class StringChoice extends Parser<ParseError, String> {
  /// The radix tree for O(m) matching.
  final RadixNode radix;

  /// The original string alternatives (for error messages).
  final List<String> targets;

  /// Creates a parser matching any of [targets] via [radix] tree.
  const StringChoice(this.radix, this.targets);

  @override
  bool get isSimple => true;
}

/// Matches end of input.
final class Eof<E> extends Parser<E, void> {
  /// Creates an end-of-input parser.
  const Eof();

  @override
  bool get isSimple => true;
}

/// Succeeds without consuming input, yielding the current byte offset.
///
/// Use via [position] in `primitives.dart`. Typically wrapped into span
/// tracking: `position().zip(p).zip(position())` gives the start offset,
/// the parsed value, and the end offset in one pass.
final class GetPosition<E> extends Parser<E, int> {
  /// Creates a position-reading parser.
  const GetPosition();

  @override
  bool get isSimple => true;
}

// ---------------------------------------------------------------------------
// Composition
// ---------------------------------------------------------------------------

/// Transforms the result of [source] using [f].
final class Mapped<E, A, B> extends Parser<E, B> {
  /// The parser whose result is transformed.
  final Parser<E, A> source;

  /// The transformation function.
  final B Function(A) f;

  /// Creates a mapped parser.
  const Mapped(this.source, this.f);

  /// Apply [f] to a type-erased value (used by the trampoline).
  B applyF(Object? value) => f(value as A);

  @override
  bool get isSimple => source.isSimple;

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
  /// The parser to run first.
  final Parser<E, A> source;

  /// Produces the next parser from the first result.
  final Parser<E, B> Function(A) f;

  /// Creates a flat-mapped parser.
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
  /// The first parser.
  final Parser<E, A> left;

  /// The second parser.
  final Parser<E, B> right;

  /// Creates a zip parser.
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
  /// The first alternative.
  final Parser<E, A> left;

  /// The fallback alternative.
  final Parser<E, A> right;

  /// Creates an ordered choice between [left] and [right].
  const Or(this.left, this.right);
}

/// Tries each alternative in order until one succeeds.
final class Choice<E, A> extends Parser<E, A> {
  /// The alternatives to try in order.
  final List<Parser<E, A>> alternatives;

  /// Creates a multi-way choice.
  const Choice(this.alternatives);
}

/// Dispatches to one of [dispatch]'s parsers based on the leading code
/// unit at the current position. O(1) lookup vs `Or` / `Choice`'s linear
/// scan, useful for value-alternatives in formats with disjoint leading
/// characters (JSON values: `n`/`t`/`f`/digits/`"`/`[`/`{`).
///
/// On no leading-char match, runs [fallback] if provided, else fails
/// with an error listing the dispatch keys.
final class FirstCharChoice<E, A> extends Parser<E, A> {
  /// Code-unit-keyed dispatch table.
  final Map<int, Parser<E, A>> dispatch;

  /// Optional fallback parser tried when no leading char matches.
  final Parser<E, A>? fallback;

  /// String of unique leading chars (in declaration order) for error
  /// messages on dispatch miss.
  final String expectedChars;

  /// Creates a first-char dispatch parser.
  const FirstCharChoice(this.dispatch, this.expectedChars, {this.fallback});
}

// ---------------------------------------------------------------------------
// Repetition
// ---------------------------------------------------------------------------

/// Matches [parser] zero or more times.
final class Many<E, A> extends Parser<E, List<A>> {
  /// The parser to repeat.
  final Parser<E, A> parser;

  /// Creates a zero-or-more repetition.
  const Many(this.parser);

  /// Dispatch to the interpreter with the element type in scope.
  Result<E, List<A>> interpretWith(
    Result<E, List<T>> Function<T>(Parser<E, T>) interpret,
  ) => interpret<A>(parser);
}

/// Matches [parser] one or more times.
final class Many1<E, A> extends Parser<E, List<A>> {
  /// The parser to repeat.
  final Parser<E, A> parser;

  /// Creates a one-or-more repetition.
  const Many1(this.parser);

  /// Dispatch to the interpreter with the element type in scope.
  Result<E, List<A>> interpretWith(
    Result<E, List<T>> Function<T>(Parser<E, T>) interpret,
  ) => interpret<A>(parser);
}

/// Matches [parser] zero or more times, discarding results.
final class SkipMany<E, A> extends Parser<E, void> {
  /// The parser to repeat.
  final Parser<E, A> parser;

  /// Creates a skip-many repetition.
  const SkipMany(this.parser);

  /// Dispatch to the interpreter with the element type in scope.
  Result<E, void> interpretWith(
    Result<E, void> Function<T>(Parser<E, T>) interpret,
  ) => interpret<A>(parser);
}

/// Left-associative binary operator chain: `p (op p)*` folded as
/// `((a op b) op c) op d`.
///
/// The interpreter handles this iteratively rather than via the recursive
/// `Or` + `FlatMap` expansion that a hand-rolled definition would use, so
/// chain depth does not consume Dart call frames.
final class Chainl1<E, A> extends Parser<E, A> {
  /// The element parser.
  final Parser<E, A> p;

  /// The operator parser yielding a 2-arg combiner.
  final Parser<E, A Function(A, A)> op;

  /// Creates a left-associative chain.
  const Chainl1(this.p, this.op);

  /// Dispatch to the interpreter with the element type in scope.
  Result<E, A> interpretWith(
    Result<E, T> Function<T>(Parser<E, T> p, Parser<E, T Function(T, T)> op)
    run,
  ) => run<A>(p, op);
}

/// Right-associative binary operator chain: `p (op p)*` folded as
/// `a op (b op (c op d))`.
///
/// The interpreter parses all elements and operators iteratively into two
/// lists, then folds right at the end, so chain depth does not consume
/// Dart call frames.
final class Chainr1<E, A> extends Parser<E, A> {
  /// The element parser.
  final Parser<E, A> p;

  /// The operator parser yielding a 2-arg combiner.
  final Parser<E, A Function(A, A)> op;

  /// Creates a right-associative chain.
  const Chainr1(this.p, this.op);

  /// Dispatch to the interpreter with the element type in scope.
  Result<E, A> interpretWith(
    Result<E, T> Function<T>(Parser<E, T> p, Parser<E, T Function(T, T)> op)
    run,
  ) => run<A>(p, op);
}

/// Matches [parser] and returns the consumed input as a string.
final class Capture<E, A> extends Parser<E, String> {
  /// The parser whose matched input is captured.
  final Parser<E, A> parser;

  /// Creates a capture parser.
  const Capture(this.parser);

  /// Dispatch to the interpreter with the inner type in scope.
  Result<E, String> interpretWith(
    Result<E, String> Function(Parser<E, A>) interpret,
  ) => interpret(parser);
}

// ---------------------------------------------------------------------------
// Optional / Lookahead / Negation
// ---------------------------------------------------------------------------

/// Matches [parser] zero or one times. Returns `null` on no match.
final class Optional<E, A> extends Parser<E, A?> {
  /// The parser to optionally match.
  final Parser<E, A> parser;

  /// Creates an optional parser.
  const Optional(this.parser);

  /// Dispatch to the interpreter with the inner type in scope.
  Result<E, A?> interpretWith(
    Result<E, T?> Function<T>(Parser<E, T>) interpret,
  ) => interpret<A>(parser);
}

/// Wraps the outcome of [parser] in a [Result], always succeeding.
final class Attempt<E, A> extends Parser<Never, Result<E, A>> {
  /// The parser to attempt.
  final Parser<E, A> parser;

  /// Creates an attempt parser.
  const Attempt(this.parser);

  /// Dispatch to the interpreter with the inner type in scope.
  Result<Never, Result<E, A>> interpretWith(
    Result<Never, Result<E, A>> Function(Parser<E, A>) interpret,
  ) => interpret(parser);
}

/// Matches without consuming input (positive lookahead).
final class LookAhead<E, A> extends Parser<E, A> {
  /// The parser to look ahead with.
  final Parser<E, A> parser;

  /// Creates a lookahead parser.
  const LookAhead(this.parser);

  @override
  bool get isSimple => true;
}

/// Succeeds only if [parser] would fail (negative lookahead).
final class NotFollowedBy<A> extends Parser<ParseError, void> {
  /// The parser that must not match.
  final Parser<ParseError, A> parser;

  /// Creates a negative lookahead parser.
  const NotFollowedBy(this.parser);

  @override
  bool get isSimple => true;
}

// ---------------------------------------------------------------------------
// Error handling
// ---------------------------------------------------------------------------

/// On failure, tries [recovery]. Success via recovery produces [Partial].
final class RecoverWith<E, A> extends Parser<E, A> {
  /// The primary parser.
  final Parser<E, A> parser;

  /// The fallback parser tried on failure.
  final Parser<E, A> recovery;

  /// Creates a recovery parser.
  const RecoverWith(this.parser, this.recovery);
}

/// Replaces the error message on failure with [message].
final class Expect<A> extends Parser<ParseError, A> {
  /// The wrapped parser.
  final Parser<ParseError, A> parser;

  /// The replacement error message.
  final String message;

  /// Creates an expect parser.
  const Expect(this.parser, this.message);

  @override
  bool get isSimple => parser.isSimple;
}

// ---------------------------------------------------------------------------
// Naming / Debugging
// ---------------------------------------------------------------------------

/// Attaches [name] to error messages on failure.
final class Named<A> extends Parser<ParseError, A> {
  /// The wrapped parser.
  final Parser<ParseError, A> parser;

  /// The name added to expected-set in errors.
  final String name;

  /// Creates a named parser.
  const Named(this.parser, this.name);

  @override
  bool get isSimple => parser.isSimple;
}

/// Prints trace output on enter/exit. No effect on results.
final class Trace<E, A> extends Parser<E, A> {
  /// The wrapped parser.
  final Parser<E, A> parser;

  /// The label printed in trace output.
  final String label;

  /// Creates a trace parser.
  const Trace(this.parser, this.label);
}

/// Prints verbose debug output on enter/exit. No effect on results.
final class Debug<E, A> extends Parser<E, A> {
  /// The wrapped parser.
  final Parser<E, A> parser;

  /// The label printed in debug output.
  final String label;

  /// Creates a debug parser.
  const Debug(this.parser, this.label);
}

// ---------------------------------------------------------------------------
// Laziness / Memoization / Left Recursion
// ---------------------------------------------------------------------------

/// Defers parser construction until first use.
///
/// Required for recursive grammars.
final class Defer<E, A> extends Parser<E, A> {
  /// The thunk that produces the parser on first use.
  final Parser<E, A> Function() thunk;

  /// Creates a deferred parser.
  const Defer(this.thunk);
}

/// Memoized parser with optional left-recursion support.
///
/// With [enableLR], uses Warth et al. seed-growth for left-recursive
/// grammars. Without it, uses simple memoization (faster).
///
/// Created via [rule] (LR-enabled) or `.memoize` (simple).
final class Memo<E, A> extends Parser<E, A> {
  /// The parser to memoize.
  final Parser<E, A> inner;

  /// The memoization key (identity-based).
  final MemoKey<E, A> key;

  /// Whether to use left-recursion support.
  final bool enableLR;

  /// Creates a memoized parser.
  const Memo(this.inner, this.key, {required this.enableLR});
}

/// Prefix operator descriptor stored on a [Pratt] node for stack-safe
/// dispatch. The combinator builder pre-decomposes user-supplied
/// `Prefix(symbol, bp, fn)` operators into this form so the interpreter
/// can detect prefixes by running [symbol] directly, push a pending-apply
/// frame, and continue iteratively — without recursing through `nud`.
final class PrattPrefix<E, A> {
  /// Parser for the prefix operator's symbol.
  final Parser<E, Object?> symbol;

  /// Binding power claimed for the operand subparse.
  final int bp;

  /// Transforms the parsed operand into the result.
  final A Function(A) fn;

  /// Creates a prefix descriptor.
  const PrattPrefix(this.symbol, this.bp, this.fn);
}

/// Top-Down Operator Precedence (Pratt) parser node.
///
/// The evaluation loop parses an `atom` (optionally preceded by chained
/// [prefixes]) to establish the LHS accumulator, then repeatedly consults
/// `getOp` (or, when populated, a direct char dispatch via `opTable`) to
/// decide whether to fold in another operator. Each infix operator adopted
/// at `lbp > minBp` parses an RHS at `rbp` and combines; each postfix at
/// `bp > minBp` applies in place. Prefixes are parsed by running their
/// symbol parser directly: on a hit, a pending-apply frame is pushed and
/// the loop continues at `prefix.bp`.
///
/// The interpreter uses an explicit operator stack rather than recursion,
/// so unbounded right-associative chains and prefix chains do not consume
/// Dart call frames. This mirrors the stack-safety of the `_runTrampoline`
/// path used by [FlatMap]/[Mapped]/[Zip].
///
/// `minBp` is a construction-time parameter: set to 0 at the public entry
/// point. Inner Pratt nodes are no longer constructed for prefix operands;
/// prefixes are encoded as [PrattPrefix] entries the interpreter consumes
/// directly.
///
/// `opTable` is a speed/allocation shortcut populated by the public builder
/// when every operator's symbol is a literal-prefix parser. On a hit, the
/// interpreter dispatches via a code-unit array lookup without running the
/// general `getOp` parser.
final class Pratt<E, A> extends Parser<E, A> {
  /// Atom parser invoked once any leading prefixes have been consumed.
  final Parser<E, A> atom;

  /// Prefix operators recognised at the start of (and recursively inside)
  /// an operand subparse. Empty when the grammar has no prefix operators.
  final List<PrattPrefix<E, A>> prefixes;

  /// Operator-dispatch parser: returns a PrattOp and consumes the operator tokens.
  final Parser<E, PrattOp<A>> getOp;

  /// Initial binding-power threshold; the loop terminates when no operator
  /// has `lbp > minBp`.
  final int minBp;

  /// Pre-compiled char dispatch, if every operator has a literal-prefix symbol.
  /// Null means the interpreter must run `getOp`.
  final PrattOpTable<A>? opTable;

  /// Creates a Pratt parser node.
  const Pratt(this.atom, this.prefixes, this.getOp, this.minBp, this.opTable);

  /// Dispatch to the Pratt loop with type parameter [A] reified.
  ///
  /// Mirrors the `interpretWith` pattern used by [Mapped], [FlatMap], and
  /// [Zip]: the trampoline routes through `interpretI` with `A=dynamic`, so
  /// a field destructure there would see `PrattOp<dynamic>` and
  /// `combine`/`apply` would widen to `dynamic Function(...)` — incompatible
  /// with the user's precise types under Dart's function-argument
  /// contravariance. Routing through this instance method preserves the
  /// receiver's generic parameter [A] at runtime.
  Result<E, A> interpretWith(
    Result<E, T> Function<T>(
      Parser<E, T> atom,
      List<PrattPrefix<E, T>> prefixes,
      Parser<E, PrattOp<T>> getOp,
      int minBp,
      PrattOpTable<T>? opTable,
    )
    run,
  ) => run<A>(atom, prefixes, getOp, minBp, opTable);
}
