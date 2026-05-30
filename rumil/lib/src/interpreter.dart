/// Core interpreter for the Parser ADT.
library;

import 'dart:math' as math;

import 'errors.dart';
import 'green_cache.dart';
import 'green_node.dart';
import 'location.dart';
import 'memo.dart';
import 'parser.dart';
import 'radix.dart';
import 'result.dart';
import 'state.dart';

// ===========================================================================
// Public API
// ===========================================================================

/// Run a parser on [input], returning a [Result].
///
/// Stack-safe for arbitrarily deep FlatMap/Map/Zip chains.
Result<E, A> run<E, A>(Parser<E, A> parser, String input) {
  final state = ParserState(input);
  return interpretI(parser, state);
}

/// Run without the trampoline (direct recursion).
Result<E, A> runRecursive<E, A>(Parser<E, A> parser, String input) {
  final state = ParserState(input);
  return interpretI(parser, state);
}

// ===========================================================================
// Defunctionalized trampoline
// ===========================================================================
//
// THE ERASED-DRIVER BOUNDARY CONVENTION
// -------------------------------------
// The trampoline drives every sub-parse type-erased: the working result is
// `Result<Object?, Object?>` and `currentParser` is `Parser<dynamic, dynamic>`,
// so the continuation frames stay non-generic (E/A are recovered once at
// `_ContEnd`). Dart reifies generics, so a user combiner like
// `int Function(int, int)` is NOT assignable to `dynamic Function(dynamic,
// dynamic)` — widening a *typed function* is a contravariant cast that throws.
//
// Every place a node hands typed work to this erased driver therefore follows
// ONE convention: the node exposes a method that takes/returns `Object?` and
// confines the `as A` cast INSIDE the typed class, where `A` is in scope and
// reified from the receiver's runtime type (the same shape as
// `FlatMap.applyF(Object? v) => f(v as A)`). The driver only ever moves
// `Object?` values and erased child parsers; it never casts or invokes a
// function whose type it cannot name. Three physical forms of the one rule:
//
//   1. Self-applying operator nodes — the operator carries its own typed fn and
//      applies itself to erased operands: `PrattOpInfix.combineWith`,
//      `PrattOpPostfix.applyTo`, `PrattPrefix.applyTo`. The frame stores the
//      OPERATOR NODE, not a bare `Function`.
//   2. Parsed-combiner fold nodes — the combiner is a parsed *value* (`Object?`)
//      the node never sees, so the node hands out a bound reifier closure that
//      casts the combiner to its true `A Function(A, A)` shape inside the typed
//      class: `Chainl1.combineStep` / `Chainr1.combineStep` (the
//      `_ChainCombineStep` a chain frame captures at push time).
//   3. Collection reifiers — rebuild an erased accumulator into the node's real
//      element type: `Many.buildList` / `Many1.buildList`.
//
// Descending into a child parser is NOT erasure: `elementParser` / `opParser` /
// `getOpErased` are cast-free *covariant value-type* upcasts (`Parser<E, A>` ->
// `Parser<E, Object?>`), the ordinary way every combinator hands a child to the
// driver. They carry no function-type cast and no dynamic call.

sealed class _Cont {
  const _Cont();
}

final class _ContEnd extends _Cont {
  const _ContEnd();
}

final class _ContFlatMap extends _Cont {
  final FlatMap<dynamic, dynamic, dynamic> node;
  final _Cont next;
  const _ContFlatMap(this.node, this.next);
}

final class _ContMap extends _Cont {
  final Mapped<dynamic, dynamic, dynamic> node;
  final _Cont next;
  const _ContMap(this.node, this.next);
}

final class _ContZipRight extends _Cont {
  final Parser<dynamic, dynamic> right;
  final _Cont next;
  _ContZipRight(this.right, this.next);
}

final class _ContZipCombine extends _Cont {
  final Object? leftValue;
  final int leftConsumed;
  final _Cont next;
  const _ContZipCombine(this.leftValue, this.leftConsumed, this.next);
}

/// Awaiting the left side of a `SkipLeft`/`SkipRight`. [keepLeft] true means
/// keep the left value (thenSkip), false means discard it (skipThen). On
/// success, descend into `right` under a [_ContSkipRightSide].
final class _ContSkipLeftSide extends _Cont {
  final Parser<dynamic, dynamic> right;
  final bool keepLeft;
  final _Cont next;
  const _ContSkipLeftSide(this.right, this.keepLeft, this.next);
}

/// Awaiting the right side of a `SkipLeft`/`SkipRight`. Combines consumed counts
/// and yields either [leftValue] (keepLeft) or the right value — no `(a, b)`
/// record is ever built.
final class _ContSkipRightSide extends _Cont {
  final Object? leftValue;
  final int leftConsumed;
  final bool keepLeft;
  final _Cont next;
  const _ContSkipRightSide(
    this.leftValue,
    this.leftConsumed,
    this.keepLeft,
    this.next,
  );
}

final class _ContPartial extends _Cont {
  final List<Object?> Function() mkErrors;
  final _Cont next;
  const _ContPartial(this.mkErrors, this.next);
}

final class _ContPartialConsumed extends _Cont {
  final int extraConsumed;
  final _Cont next;
  const _ContPartialConsumed(this.extraConsumed, this.next);
}

// --- Frames added for stack-safe combinator nesting ---
// Each frame replaces a recursive `interpretI(child)` call inside a
// sub-parse-taking combinator with a heap continuation, so nesting depth
// lives in the (heap-allocated) continuation chain rather than the Dart call
// stack. See `_drive`.

/// Awaiting the left branch of an `Or`. On non-failure, propagate it; on
/// failure, restore and try [right] under a [_ContOrRight].
final class _ContOrLeft extends _Cont {
  final Parser<dynamic, dynamic> right;
  final int snapshot;
  final bool simple;
  final _Cont next;
  const _ContOrLeft(this.right, this.snapshot, this.simple, this.next);
}

/// Awaiting the right branch of an `Or` whose left already failed. Merges the
/// two failures if the right also fails.
final class _ContOrRight extends _Cont {
  final Failure<dynamic, dynamic> leftFailure;
  final _Cont next;
  const _ContOrRight(this.leftFailure, this.next);
}

/// Awaiting one alternative of a `Choice`. On non-failure, propagate; on
/// failure, restore and try the next alternative (or fail with merged errors).
final class _ContChoice extends _Cont {
  final List<Parser<dynamic, dynamic>> alternatives;
  final int index;
  final int snapshot;
  final List<Object?> Function() accMkErrors;
  final Location furthest;
  final _Cont next;
  const _ContChoice(
    this.alternatives,
    this.index,
    this.snapshot,
    this.accMkErrors,
    this.furthest,
    this.next,
  );
}

/// Looper for `Many`/`Many1`/`SkipMany` with a complex (sub-parsing) element.
/// [kind]: 0 = Many, 1 = SkipMany. (Many1 reuses kind 0 once its first element
/// has been accepted.) [acc] is null for SkipMany.
///
/// [rebuild] reifies the accumulator into a correctly-typed `List<A>` on
/// finalize (null for SkipMany, whose result is `void`); see [Many.buildList].
final class _ContMany extends _Cont {
  final Parser<dynamic, dynamic> element;
  final List<Object?>? acc;
  final List<Object?> Function(List<Object?>)? rebuild;
  final List<List<Object?> Function()> errThunks;
  final bool simple;
  final int totalConsumed;
  final int iterSnapshot;
  final int kind;
  final _Cont next;
  const _ContMany(
    this.element,
    this.acc,
    this.rebuild,
    this.errThunks,
    this.simple,
    this.totalConsumed,
    this.iterSnapshot,
    this.kind,
    this.next,
  );
}

/// Awaiting the mandatory first element of a `Many1`. On failure, propagate
/// (a Many1 with zero matches fails); on success, begin the `Many` loop.
final class _ContMany1First extends _Cont {
  final Parser<dynamic, dynamic> element;
  final List<Object?> Function(List<Object?>) rebuild;
  final bool simple;
  final _Cont next;
  const _ContMany1First(this.element, this.rebuild, this.simple, this.next);
}

/// Awaiting the inner parser of an `Optional`. On failure, restore and yield
/// `Success(null)`; otherwise pass the value through (the static type is `A?`).
final class _ContOptional extends _Cont {
  final int snapshot;
  final bool simple;
  final _Cont next;
  const _ContOptional(this.snapshot, this.simple, this.next);
}

/// Awaiting the inner parser of a `Capture`. Replaces the value with the
/// consumed source slice.
final class _ContCapture extends _Cont {
  final int startOffset;
  final _Cont next;
  const _ContCapture(this.startOffset, this.next);
}

/// Awaiting the inner parser of a `Named`. On failure, augments `Unexpected`
/// errors with the rule [name].
final class _ContNamed extends _Cont {
  final String name;
  final _Cont next;
  const _ContNamed(this.name, this.next);
}

/// Awaiting the inner parser of an `Expect`. On failure, replaces the errors
/// with a single `CustomError(message)` at the furthest position.
final class _ContExpect extends _Cont {
  final String message;
  final _Cont next;
  const _ContExpect(this.message, this.next);
}

/// Awaiting the inner parser of an `Attempt`. Reifies the inner result into a
/// `Success<Never, Result>` and restores on failure (full backtrack).
final class _ContAttempt extends _Cont {
  final int snapshot;
  final _Cont next;
  const _ContAttempt(this.snapshot, this.next);
}

/// Awaiting the inner parser of a `LookAhead`. Always restores the offset; on
/// success/partial yields the value with zero consumed.
final class _ContLookAhead extends _Cont {
  final int snapshot;
  final _Cont next;
  const _ContLookAhead(this.snapshot, this.next);
}

/// Awaiting the inner parser of a `NotFollowedBy`. Always restores; inverts
/// success/failure.
final class _ContNotFollowedBy extends _Cont {
  final int snapshot;
  final _Cont next;
  const _ContNotFollowedBy(this.snapshot, this.next);
}

/// Awaiting the primary parser of a `RecoverWith`. On failure, restore and run
/// the recovery parser under a [_ContRecoverCombine].
final class _ContRecoverTry extends _Cont {
  final Parser<dynamic, dynamic> recovery;
  final int snapshot;
  final _Cont next;
  const _ContRecoverTry(this.recovery, this.snapshot, this.next);
}

/// Awaiting the recovery parser of a `RecoverWith`. Combines the original
/// (eagerly-evaluated) errors with the recovery outcome.
final class _ContRecoverCombine extends _Cont {
  final List<Object?> originalErrors;
  final Location originalFurthest;
  final _Cont next;
  const _ContRecoverCombine(
    this.originalErrors,
    this.originalFurthest,
    this.next,
  );
}

/// A chain step at the erased-driver boundary: applies the parsed combiner
/// (held erased as `Object?`) to two erased operands, returning the combined
/// value. The chain node hands this out at push time ([Chainl1.combineStep] /
/// [Chainr1.combineStep]); it confines the `as A` casts inside the typed node,
/// so the driver invokes a combiner with no cast and no dynamic call.
typedef _ChainCombineStep =
    Object? Function(Object? combiner, Object? l, Object? r);

/// Awaiting the first element of a `Chainl1`/`Chainr1`. On failure, propagate;
/// on success, begin the operator loop.
final class _ContChainFirst extends _Cont {
  final Parser<dynamic, dynamic> p;
  final Parser<dynamic, dynamic> op;
  final _ChainCombineStep combineStep;
  final bool rightAssoc;
  final _Cont next;
  const _ContChainFirst(
    this.p,
    this.op,
    this.combineStep,
    this.rightAssoc,
    this.next,
  );
}

/// Awaiting an operator in a chain. On failure, restore and finalize; on
/// success, parse the next element under a [_ContChainRhs].
final class _ContChainOp extends _Cont {
  final Parser<dynamic, dynamic> p;
  final Parser<dynamic, dynamic> op;
  final _ChainCombineStep combineStep;
  final bool rightAssoc;
  // chainl1: accumulated lhs. chainr1: collected values/combiners for the final
  // fold.
  final Object? lhs;
  final List<Object?>? values;
  final List<Object?>? combiners;
  final int consumed;
  final int snapshot;
  final _Cont next;
  const _ContChainOp(
    this.p,
    this.op,
    this.combineStep,
    this.rightAssoc,
    this.lhs,
    this.values,
    this.combiners,
    this.consumed,
    this.snapshot,
    this.next,
  );
}

/// Awaiting the right-hand element after an operator in a chain.
final class _ContChainRhs extends _Cont {
  final Parser<dynamic, dynamic> p;
  final Parser<dynamic, dynamic> op;
  final _ChainCombineStep combineStep;
  final bool rightAssoc;
  final Object? lhs;
  final List<Object?>? values;
  final List<Object?>? combiners;
  final Object? combiner; // the operator's parsed combiner (erased)
  final int consumedBeforeOp;
  final int opConsumed;
  final int snapshot;
  final _Cont next;
  const _ContChainRhs(
    this.p,
    this.op,
    this.combineStep,
    this.rightAssoc,
    this.lhs,
    this.values,
    this.combiners,
    this.combiner,
    this.consumedBeforeOp,
    this.opConsumed,
    this.snapshot,
    this.next,
  );
}

/// Awaiting an `atom` (nud) subparse on behalf of a suspended Pratt loop.
///
/// The Pratt operator loop ([_PrattRun]) is iterative within one level, but
/// its atom subparse can itself be a nested Pratt (`'(' expr ')'`). Rather
/// than calling `interpretI(atom)` on the host stack, the loop suspends into
/// this frame and the main trampoline drives the atom; the apply handler feeds
/// the atom result back via [_PrattRun.resumeWithAtom] and re-steps.
final class _ContPratt extends _Cont {
  final _PrattRun run;
  final _Cont next;
  const _ContPratt(this.run, this.next);
}

/// Whether a parser is a `Capture(Many(Satisfy))` / `Capture(Many1(Satisfy))`
/// shape that the char-scan fast path handles directly. Such captures must be
/// recognized in [_leafInterpret] rather than framed as a generic `Capture`,
/// to preserve the zero-list-allocation scan.
bool _isScanFusableCapture(Parser<dynamic, dynamic> inner) =>
    (inner is Many<dynamic, dynamic> && inner.parser is Satisfy) ||
    (inner is Many1<dynamic, dynamic> && inner.parser is Satisfy);

// ===========================================================================
// Trampolined interpreter (eval/apply state machine)
// ===========================================================================

/// Interpret [parser] to a [Result], stack-safe for arbitrary combinator
/// nesting.
///
/// A single eval/apply trampoline drives all combinator composition AND
/// nesting through a heap-allocated continuation chain ([_Cont]), so a parser
/// that re-enters itself via a sub-parse (`'(' expr ')'`, `value.sepBy(...)`,
/// a Pratt parenthesized atom, …) does not consume Dart call frames per
/// nesting level. The previous design only trampolined the FlatMap/Map/Zip
/// *spine* (flat composition); every other sub-parse re-entered `interpretI`
/// recursively, so structural nesting was bounded by the native stack
/// (~600–2000 levels). This driver pushes a continuation frame for each
/// sub-parse-taking combinator instead.
///
/// Two exceptions stay on the host stack, by design:
/// - LR-enabled [Memo] (`rule()`, Warth seed-growth): its seed-regrowth loop
///   re-enters the interpreter with live LR state; trampolining it is deferred.
///   It nests by left-recursion depth, not structural depth.
/// - [Pratt]: its own operator loop is already iterative; its atom/operand
///   sub-parses currently re-enter via [_runSub]. (Lifting the atom onto the
///   continuation chain is the remaining nesting-safety work for Pratt.)
///
/// Char-scan fast paths (`Many(Satisfy)`, `Capture(Many(Satisfy))`, etc.) and
/// the StringMatch repetition paths are dispatched in [_leafInterpret] without
/// per-element frames, preserving their flat-repetition throughput (the axis
/// verified to 1B operands).
Result<E, A> interpretI<E, A>(Parser<E, A> parser, ParserState state) {
  Parser<dynamic, dynamic> currentParser = parser;
  _Cont cont = const _ContEnd();
  // Working result is fully type-erased; E/A are recovered once at _ContEnd.
  // This keeps the continuation frames non-generic.
  late Result<Object?, Object?> result;

  eval:
  while (true) {
    // Flatten the FlatMap/Map/Zip spine first (hot path, no per-node helper
    // call). A single combined loop, because peeling a `Mapped` can expose a
    // `FlatMap` underneath (and vice versa) — separate one-shot loops would
    // leave such an interleaved node unflattened, dropping it onto the
    // `_leafInterpret` default.
    spine:
    while (true) {
      if (currentParser is FlatMap<dynamic, dynamic, dynamic>) {
        cont = _ContFlatMap(currentParser, cont);
        currentParser = currentParser.source;
        continue spine;
      }
      if (currentParser is Mapped<dynamic, dynamic, dynamic>) {
        cont = _ContMap(currentParser, cont);
        currentParser = currentParser.source;
        continue spine;
      }
      if (currentParser is Zip<dynamic, dynamic, dynamic>) {
        cont = _ContZipRight(currentParser.right, cont);
        currentParser = currentParser.left;
        continue spine;
      }
      break spine;
    }

    // Sub-parse-taking combinators: push a continuation frame and descend,
    // rather than recursing into `interpretI`. This is what makes nesting
    // stack-safe. Cases that don't match fall through to `_leafInterpret`.
    final cp = currentParser;
    switch (cp) {
      case Defer<dynamic, dynamic>(:final thunk):
        currentParser = thunk();
        continue eval;

      // Fused skipThen/thenSkip: run left, then right, keep one value — no
      // (a,b) record, no discarding Mapped. The highest-frequency token shape.
      case SkipLeft<dynamic, dynamic, dynamic>(:final left, :final right):
        cont = _ContSkipLeftSide(right, false, cont);
        currentParser = left;
        continue eval;

      case SkipRight<dynamic, dynamic, dynamic>(:final left, :final right):
        cont = _ContSkipLeftSide(right, true, cont);
        currentParser = left;
        continue eval;

      case FirstCharChoice<dynamic, dynamic>(
        :final dispatch,
        :final fallback,
        :final expectedChars,
      ):
        if (state.hasChar) {
          final picked = dispatch[state.input.codeUnitAt(state.offset)];
          if (picked != null) {
            currentParser = picked;
            continue eval;
          }
        }
        if (fallback != null) {
          currentParser = fallback;
          continue eval;
        }
        final loc = state.location;
        if (state.hasChar) {
          final c = state.currentChar;
          result = Failure<Object?, Object?>(
            () => [
              Unexpected(c, {'one of "$expectedChars"'}, loc),
            ],
            loc,
          );
        } else {
          result = Failure<Object?, Object?>(
            () => [EndOfInput('one of "$expectedChars"', loc)],
            loc,
          );
        }

      case Or<dynamic, dynamic>(:final left, :final right):
        // FIRST-set fast path: if `left` is statically doomed at this char,
        // skip it and run `right` directly, merging on right-failure.
        final synthesized = _firstFail<Object?, Object?>(
          left as Parser<Object?, Object?>,
          state,
        );
        if (synthesized != null) {
          cont = _ContOrRight(synthesized, cont);
          currentParser = right;
          continue eval;
        }
        final simple = left.isSimple;
        cont = _ContOrLeft(right, simple ? 0 : state.save(), simple, cont);
        currentParser = left;
        continue eval;

      case Choice<dynamic, dynamic>(:final alternatives):
        if (alternatives.isEmpty) {
          result = Failure<Object?, Object?>(() => const [], state.location);
        } else {
          final snapshot = state.save();
          cont = _ContChoice(
            alternatives,
            0,
            snapshot,
            () => const [],
            state.location,
            cont,
          );
          currentParser = alternatives[0];
          continue eval;
        }

      case Many<dynamic, dynamic>(:final parser) when !_isLeafMany(parser):
        final node = cp;
        cont = _ContMany(
          parser,
          <Object?>[],
          node.buildList,
          [],
          parser.isSimple,
          0,
          parser.isSimple ? 0 : state.save(),
          0,
          cont,
        );
        currentParser = parser;
        continue eval;

      case Many1<dynamic, dynamic>(:final parser) when !_isLeafMany(parser):
        final node = cp;
        cont = _ContMany1First(parser, node.buildList, parser.isSimple, cont);
        currentParser = parser;
        continue eval;

      case SkipMany<dynamic, dynamic>(:final parser) when !_isLeafMany(parser):
        cont = _ContMany(
          parser,
          null,
          null,
          [],
          parser.isSimple,
          0,
          parser.isSimple ? 0 : state.save(),
          1,
          cont,
        );
        currentParser = parser;
        continue eval;

      case Capture<dynamic, dynamic>(:final parser)
          when !_isScanFusableCapture(parser):
        cont = _ContCapture(state.offset, cont);
        currentParser = parser;
        continue eval;

      case Optional<dynamic, dynamic>(:final parser):
        final simple = parser.isSimple;
        cont = _ContOptional(simple ? 0 : state.save(), simple, cont);
        currentParser = parser;
        continue eval;

      case Attempt<dynamic, dynamic>(:final parser):
        cont = _ContAttempt(state.save(), cont);
        currentParser = parser;
        continue eval;

      case LookAhead<dynamic, dynamic>(:final parser):
        cont = _ContLookAhead(state.save(), cont);
        currentParser = parser;
        continue eval;

      case NotFollowedBy(:final parser):
        cont = _ContNotFollowedBy(state.save(), cont);
        currentParser = parser;
        continue eval;

      case RecoverWith<dynamic, dynamic>(:final parser, :final recovery):
        cont = _ContRecoverTry(recovery, state.save(), cont);
        currentParser = parser;
        continue eval;

      case Expect<dynamic>(:final parser, :final message):
        cont = _ContExpect(message, cont);
        currentParser = parser;
        continue eval;

      case Named<dynamic>(:final parser, :final name):
        cont = _ContNamed(name, cont);
        currentParser = parser;
        continue eval;

      // Descend via the erased `elementParser`/`opParser` views (cast-free
      // covariant value-type upcasts) and capture the node's `combineStep`
      // reifier at push time. Destructuring `:final op` (or an `as
      // Chainl1<dynamic, dynamic>` cast) would instead impose a contravariant
      // function-type cast that a typed combiner like `int Function(int, int)`
      // fails. The combiner is a *parsed value*, so the node hands out a bound
      // `combineStep` closure that confines the `as A` casts inside the typed
      // class — the driver never casts or dynamic-calls a function itself.
      case Chainl1<dynamic, dynamic>(:final elementParser, :final opParser):
        cont = _ContChainFirst(
          elementParser,
          opParser,
          cp.combineStep,
          false,
          cont,
        );
        currentParser = elementParser;
        continue eval;

      case Chainr1<dynamic, dynamic>(:final elementParser, :final opParser):
        cont = _ContChainFirst(
          elementParser,
          opParser,
          cp.combineStep,
          true,
          cont,
        );
        currentParser = elementParser;
        continue eval;

      case Pratt<dynamic, dynamic>(
        :final atom,
        :final prefixes,
        :final getOpErased,
        :final minBp,
        :final opTable,
      ):
        final run = _PrattRun(
          atom,
          prefixes,
          getOpErased,
          minBp,
          opTable,
          state,
        );
        final r = run.step();
        if (r != null) {
          result = r;
        } else {
          // Suspended awaiting an atom subparse: descend, resume via _ContPratt.
          cont = _ContPratt(run, cont);
          currentParser = run.pendingAtom!;
          continue eval;
        }

      default:
        // Terminals, char-scan fast paths, Memo, Trace/Debug, InternedGreen:
        // produced directly (some recurse on the host stack — see
        // [_leafInterpret]).
        result = _leafInterpret(cp, state);
    }

    // APPLY: thread `result` back through the continuation chain. Frames that
    // need another sub-parse set `currentParser`/`cont` and `continue eval`;
    // frames that only transform a result update `result` and `continue apply`.
    apply:
    while (true) {
      switch (cont) {
        case _ContEnd():
          return switch (result) {
            Success<Object?, Object?>(:final value, :final consumed) =>
              Success<E, A>(value as A, consumed),
            Partial<Object?, Object?>(
              :final value,
              :final errorThunk,
              :final consumed,
            ) =>
              Partial<E, A>(value as A, () => errorThunk().cast<E>(), consumed),
            Failure<Object?, Object?>(:final errorThunk, :final furthest) =>
              Failure<E, A>(() => errorThunk().cast<E>(), furthest),
          };

        case _ContFlatMap(:final node, :final next):
          if (result case Success<Object?, Object?>(
            :final value,
            :final consumed,
          )) {
            currentParser = node.applyF(value);
            cont = consumed > 0 ? _ContPartialConsumed(consumed, next) : next;
            continue eval;
          }
          if (result case Partial<Object?, Object?>(
            :final value,
            :final errorThunk,
            :final consumed,
          )) {
            currentParser = node.applyF(value);
            cont = _ContPartial(
              errorThunk,
              consumed > 0 ? _ContPartialConsumed(consumed, next) : next,
            );
            continue eval;
          }
          cont = next;
          continue apply;

        case _ContMap(:final node, :final next):
          if (result case Success<Object?, Object?>(
            :final value,
            :final consumed,
          )) {
            result = Success<Object?, Object?>(node.applyF(value), consumed);
          } else if (result case Partial<Object?, Object?>(
            :final value,
            :final errorThunk,
            :final consumed,
          )) {
            result = Partial<Object?, Object?>(
              node.applyF(value),
              errorThunk,
              consumed,
            );
          }
          cont = next;
          continue apply;

        case _ContZipRight(:final right, :final next):
          if (result case Success<Object?, Object?>(
            :final value,
            :final consumed,
          )) {
            cont = _ContZipCombine(value, consumed, next);
            currentParser = right;
            continue eval;
          }
          if (result case Partial<Object?, Object?>(
            :final value,
            :final errorThunk,
            :final consumed,
          )) {
            cont = _ContPartial(
              errorThunk,
              _ContZipCombine(value, consumed, next),
            );
            currentParser = right;
            continue eval;
          }
          cont = next;
          continue apply;

        case _ContZipCombine(
          :final leftValue,
          :final leftConsumed,
          :final next,
        ):
          if (result case Success<Object?, Object?>(
            :final value,
            :final consumed,
          )) {
            result = Success<Object?, Object?>((
              leftValue,
              value,
            ), leftConsumed + consumed);
          } else if (result case Partial<Object?, Object?>(
            :final value,
            :final errorThunk,
            :final consumed,
          )) {
            result = Partial<Object?, Object?>(
              (leftValue, value),
              errorThunk,
              leftConsumed + consumed,
            );
          }
          cont = next;
          continue apply;

        case _ContSkipLeftSide(:final right, :final keepLeft, :final next):
          // Left side done. On success/partial, descend into right, carrying
          // the left value + consumed forward (mirrors Zip, but no record).
          if (result case Success<Object?, Object?>(
            :final value,
            :final consumed,
          )) {
            cont = _ContSkipRightSide(value, consumed, keepLeft, next);
            currentParser = right;
            continue eval;
          }
          if (result case Partial<Object?, Object?>(
            :final value,
            :final errorThunk,
            :final consumed,
          )) {
            cont = _ContPartial(
              errorThunk,
              _ContSkipRightSide(value, consumed, keepLeft, next),
            );
            currentParser = right;
            continue eval;
          }
          // Left failed: propagate the failure unchanged.
          cont = next;
          continue apply;

        case _ContSkipRightSide(
          :final leftValue,
          :final leftConsumed,
          :final keepLeft,
          :final next,
        ):
          // Right side done. Keep one value, sum consumed; build no record.
          if (result case Success<Object?, Object?>(
            :final value,
            :final consumed,
          )) {
            result = Success<Object?, Object?>(
              keepLeft ? leftValue : value,
              leftConsumed + consumed,
            );
          } else if (result case Partial<Object?, Object?>(
            :final value,
            :final errorThunk,
            :final consumed,
          )) {
            result = Partial<Object?, Object?>(
              keepLeft ? leftValue : value,
              errorThunk,
              leftConsumed + consumed,
            );
          }
          cont = next;
          continue apply;

        case _ContPartial(:final mkErrors, :final next):
          if (result case Success<Object?, Object?>(
            :final value,
            :final consumed,
          )) {
            result = Partial<Object?, Object?>(value, mkErrors, consumed);
          } else if (result case Partial<Object?, Object?>(
            :final value,
            :final errorThunk,
            :final consumed,
          )) {
            result = Partial<Object?, Object?>(
              value,
              () => [...mkErrors(), ...errorThunk()],
              consumed,
            );
          } else if (result case Failure<Object?, Object?>(
            :final errorThunk,
            :final furthest,
          )) {
            result = Failure<Object?, Object?>(
              () => [...mkErrors(), ...errorThunk()],
              furthest,
            );
          }
          cont = next;
          continue apply;

        case _ContPartialConsumed(:final extraConsumed, :final next):
          if (result case Success<Object?, Object?>(
            :final value,
            :final consumed,
          )) {
            result = Success<Object?, Object?>(value, extraConsumed + consumed);
          } else if (result case Partial<Object?, Object?>(
            :final value,
            :final errorThunk,
            :final consumed,
          )) {
            result = Partial<Object?, Object?>(
              value,
              errorThunk,
              extraConsumed + consumed,
            );
          }
          cont = next;
          continue apply;

        case _ContOrLeft(
          :final right,
          :final snapshot,
          :final simple,
          :final next,
        ):
          if (result is! Failure<Object?, Object?>) {
            cont = next;
            continue apply;
          }
          if (!simple) state.restore(snapshot);
          cont = _ContOrRight(result, next);
          currentParser = right;
          continue eval;

        case _ContOrRight(:final leftFailure, :final next):
          if (result is Failure<Object?, Object?>) {
            result = _mergeFailures<Object?, Object?>(leftFailure, result);
          }
          cont = next;
          continue apply;

        case _ContChoice(
          :final alternatives,
          :final index,
          :final snapshot,
          :final accMkErrors,
          :final furthest,
          :final next,
        ):
          if (result is! Failure<Object?, Object?>) {
            cont = next;
            continue apply;
          }
          state.restore(snapshot);
          final failure = result;
          List<Object?> Function() nextAcc;
          Location nextFurthest;
          if (failure.furthest.offset > furthest.offset) {
            nextAcc = failure.errorThunk;
            nextFurthest = failure.furthest;
          } else if (failure.furthest.offset == furthest.offset) {
            final prev = accMkErrors;
            final curr = failure.errorThunk;
            nextAcc = () => [...prev(), ...curr()];
            nextFurthest = furthest;
          } else {
            nextAcc = accMkErrors;
            nextFurthest = furthest;
          }
          if (index + 1 < alternatives.length) {
            cont = _ContChoice(
              alternatives,
              index + 1,
              snapshot,
              nextAcc,
              nextFurthest,
              next,
            );
            currentParser = alternatives[index + 1];
            continue eval;
          }
          result = Failure<Object?, Object?>(nextAcc, nextFurthest);
          cont = next;
          continue apply;

        case _ContMany(
          :final element,
          :final acc,
          :final rebuild,
          :final errThunks,
          :final simple,
          :final totalConsumed,
          :final iterSnapshot,
          :final kind,
          :final next,
        ):
          if (result case Success<Object?, Object?>(
            :final value,
            :final consumed,
          )) {
            if (acc != null) acc.add(value);
            cont = _ContMany(
              element,
              acc,
              rebuild,
              errThunks,
              simple,
              totalConsumed + consumed,
              simple ? 0 : state.save(),
              kind,
              next,
            );
            currentParser = element;
            continue eval;
          }
          if (result case Partial<Object?, Object?>(
            :final value,
            :final errorThunk,
            :final consumed,
          )) {
            if (acc != null) acc.add(value);
            errThunks.add(errorThunk);
            cont = _ContMany(
              element,
              acc,
              rebuild,
              errThunks,
              simple,
              totalConsumed + consumed,
              simple ? 0 : state.save(),
              kind,
              next,
            );
            currentParser = element;
            continue eval;
          }
          // Failure: end of repetition. Reify the accumulator to its real
          // element type (null for SkipMany, whose value is `void`).
          if (!simple) state.restore(iterSnapshot);
          final value = (acc == null || rebuild == null) ? null : rebuild(acc);
          if (errThunks.isEmpty) {
            result = Success<Object?, Object?>(value, totalConsumed);
          } else {
            final thunks = errThunks;
            result = Partial<Object?, Object?>(
              value,
              () => thunks.expand((t) => t()).toList(),
              totalConsumed,
            );
          }
          cont = next;
          continue apply;

        case _ContMany1First(
          :final element,
          :final rebuild,
          :final simple,
          :final next,
        ):
          if (result case Success<Object?, Object?>(
            :final value,
            :final consumed,
          )) {
            cont = _ContMany(
              element,
              <Object?>[value],
              rebuild,
              [],
              simple,
              consumed,
              simple ? 0 : state.save(),
              0,
              next,
            );
            currentParser = element;
            continue eval;
          }
          if (result case Partial<Object?, Object?>(
            :final value,
            :final errorThunk,
            :final consumed,
          )) {
            cont = _ContMany(
              element,
              <Object?>[value],
              rebuild,
              [errorThunk],
              simple,
              consumed,
              simple ? 0 : state.save(),
              0,
              next,
            );
            currentParser = element;
            continue eval;
          }
          // Failure on the mandatory first element: propagate.
          cont = next;
          continue apply;

        case _ContOptional(:final snapshot, :final simple, :final next):
          if (result is Failure<Object?, Object?>) {
            if (!simple) state.restore(snapshot);
            result = const Success<Object?, Object?>(null, 0);
          }
          cont = next;
          continue apply;

        case _ContCapture(:final startOffset, :final next):
          if (result case Success<Object?, Object?>(:final consumed)) {
            result = Success<Object?, Object?>(
              state.slice(startOffset, startOffset + consumed),
              consumed,
            );
          } else if (result case Partial<Object?, Object?>(
            :final errorThunk,
            :final consumed,
          )) {
            result = Partial<Object?, Object?>(
              state.slice(startOffset, startOffset + consumed),
              errorThunk,
              consumed,
            );
          }
          cont = next;
          continue apply;

        case _ContNamed(:final name, :final next):
          if (result case Failure<Object?, Object?>(
            :final errorThunk,
            :final furthest,
          )) {
            result = Failure<Object?, Object?>(
              () =>
                  errorThunk().map((e) {
                    if (e is Unexpected) {
                      return Unexpected(e.found, {
                        ...e.expected,
                        name,
                      }, e.location);
                    }
                    return e;
                  }).toList(),
              furthest,
            );
          }
          cont = next;
          continue apply;

        case _ContExpect(:final message, :final next):
          if (result case Failure<Object?, Object?>(:final furthest)) {
            result = Failure<Object?, Object?>(
              () => [CustomError(message, furthest)],
              furthest,
            );
          }
          cont = next;
          continue apply;

        case _ContAttempt(:final snapshot, :final next):
          switch (result) {
            case Success<Object?, Object?>(:final value, :final consumed):
              result = Success<Object?, Object?>(
                Success<Object?, Object?>(value, consumed),
                0,
              );
            case Partial<Object?, Object?>(
              :final value,
              :final errorThunk,
              :final consumed,
            ):
              result = Success<Object?, Object?>(
                Partial<Object?, Object?>.eager(value, errorThunk(), consumed),
                0,
              );
            case Failure<Object?, Object?>(:final errorThunk, :final furthest):
              state.restore(snapshot);
              result = Success<Object?, Object?>(
                Failure<Object?, Object?>.eager(errorThunk(), furthest),
                0,
              );
          }
          cont = next;
          continue apply;

        case _ContLookAhead(:final snapshot, :final next):
          state.restore(snapshot);
          if (result case Success<Object?, Object?>(:final value)) {
            result = Success<Object?, Object?>(value, 0);
          } else if (result case Partial<Object?, Object?>(
            :final value,
            :final errorThunk,
          )) {
            result = Partial<Object?, Object?>(value, errorThunk, 0);
          }
          cont = next;
          continue apply;

        case _ContNotFollowedBy(:final snapshot, :final next):
          state.restore(snapshot);
          if (result is! Failure<Object?, Object?>) {
            final loc = state.location;
            result = Failure<Object?, Object?>(
              () => [CustomError('Unexpected success', loc)],
              loc,
            );
          } else {
            result = const Success<Object?, Object?>(null, 0);
          }
          cont = next;
          continue apply;

        case _ContRecoverTry(:final recovery, :final snapshot, :final next):
          if (result is! Failure<Object?, Object?>) {
            cont = next;
            continue apply;
          }
          state.restore(snapshot);
          final failure = result;
          // Eagerly evaluate the original errors before recovery mutates state.
          final originalErrors = failure.errorThunk();
          cont = _ContRecoverCombine(originalErrors, failure.furthest, next);
          currentParser = recovery;
          continue eval;

        case _ContRecoverCombine(
          :final originalErrors,
          :final originalFurthest,
          :final next,
        ):
          if (result case Success<Object?, Object?>(
            :final value,
            :final consumed,
          )) {
            result = Partial<Object?, Object?>.eager(
              value,
              originalErrors,
              consumed,
            );
          } else if (result case Partial<Object?, Object?>(
            :final value,
            :final errorThunk,
            :final consumed,
          )) {
            result = Partial<Object?, Object?>(
              value,
              () => [...originalErrors, ...errorThunk()],
              consumed,
            );
          } else if (result case Failure<Object?, Object?>(
            :final errorThunk,
            :final furthest,
          )) {
            result = Failure<Object?, Object?>(
              () => [...originalErrors, ...errorThunk()],
              originalFurthest.offset > furthest.offset
                  ? originalFurthest
                  : furthest,
            );
          }
          cont = next;
          continue apply;

        case _ContChainFirst(
          :final p,
          :final op,
          :final combineStep,
          :final rightAssoc,
          :final next,
        ):
          // chainl1/chainr1 require a Success first element; anything else
          // short-circuits (matching the recursive implementations).
          if (result case Success<Object?, Object?>(
            :final value,
            :final consumed,
          )) {
            cont = _ContChainOp(
              p,
              op,
              combineStep,
              rightAssoc,
              rightAssoc ? null : value,
              rightAssoc ? <Object?>[value] : null,
              rightAssoc ? <Object?>[] : null,
              consumed,
              state.save(),
              next,
            );
            currentParser = op;
            continue eval;
          }
          cont = next;
          continue apply;

        case _ContChainOp(
          :final p,
          :final op,
          :final combineStep,
          :final rightAssoc,
          :final lhs,
          :final values,
          :final combiners,
          :final consumed,
          :final snapshot,
          :final next,
        ):
          if (result case Success<Object?, Object?>(
            value: final combiner,
            consumed: final opConsumed,
          )) {
            cont = _ContChainRhs(
              p,
              op,
              combineStep,
              rightAssoc,
              lhs,
              values,
              combiners,
              combiner,
              consumed,
              opConsumed,
              snapshot,
              next,
            );
            currentParser = p;
            continue eval;
          }
          // No more operators: finalize.
          state.restore(snapshot);
          result = _finalizeChain(
            combineStep,
            rightAssoc,
            lhs,
            values,
            combiners,
            consumed,
          );
          cont = next;
          continue apply;

        case _ContChainRhs(
          :final p,
          :final op,
          :final combineStep,
          :final rightAssoc,
          :final lhs,
          :final values,
          :final combiners,
          :final combiner,
          :final consumedBeforeOp,
          :final opConsumed,
          :final snapshot,
          :final next,
        ):
          if (result case Success<Object?, Object?>(
            :final value,
            :final consumed,
          )) {
            final newConsumed = consumedBeforeOp + opConsumed + consumed;
            if (rightAssoc) {
              // Defer the fold: collect values and parsed combiners, fold right
              // in `_finalizeChain` once the chain ends.
              values!.add(value);
              combiners!.add(combiner);
              cont = _ContChainOp(
                p,
                op,
                combineStep,
                true,
                null,
                values,
                combiners,
                newConsumed,
                state.save(),
                next,
              );
            } else {
              // Left-fold eagerly through the node's typed boundary method.
              cont = _ContChainOp(
                p,
                op,
                combineStep,
                false,
                combineStep(combiner, lhs, value),
                null,
                null,
                newConsumed,
                state.save(),
                next,
              );
            }
            currentParser = op;
            continue eval;
          }
          // rhs failed: finalize with what we have (consumed before the op).
          state.restore(snapshot);
          result = _finalizeChain(
            combineStep,
            rightAssoc,
            lhs,
            values,
            combiners,
            consumedBeforeOp,
          );
          cont = next;
          continue apply;

        case _ContPratt(:final run, :final next):
          // The atom subparse just completed (in `result`). Feed it back and
          // re-step the Pratt loop. If it suspends again (a further nested
          // atom), descend once more; otherwise its final Result flows on.
          run.resumeWithAtom(result);
          final r = run.step();
          if (r != null) {
            result = r;
            cont = next;
            continue apply;
          }
          cont = _ContPratt(run, next);
          currentParser = run.pendingAtom!;
          continue eval;
      }
    }
  }
}

/// Finalize a chain accumulation into a [Success]. For chainl1 the [lhs] is
/// already the left-folded value; for chainr1 the collected [values]/[combiners]
/// are right-folded here, each step routed through the node's typed
/// [combineStep] boundary so the parsed combiners are invoked with no cast and
/// no dynamic call.
Result<Object?, Object?> _finalizeChain(
  _ChainCombineStep combineStep,
  bool rightAssoc,
  Object? lhs,
  List<Object?>? values,
  List<Object?>? combiners,
  int consumed,
) {
  if (!rightAssoc) return Success<Object?, Object?>(lhs, consumed);
  final vals = values!;
  final combs = combiners!;
  var acc = vals.last;
  for (var i = vals.length - 2; i >= 0; i--) {
    acc = combineStep(combs[i], vals[i], acc);
  }
  return Success<Object?, Object?>(acc, consumed);
}

/// Whether a `Many`/`Many1`/`SkipMany` element is a terminal handled by the
/// allocation-free char-scan fast paths in [_leafInterpret]. Such elements
/// cannot recurse, so they need no continuation frame.
bool _isLeafMany(Parser<dynamic, dynamic> element) =>
    element is Satisfy || element is StringMatch;

/// Interpret the cases that are not driven by continuation frames: terminals,
/// the allocation-free char-scan fast paths, and the cases that (for now) stay
/// host-recursive — Pratt, LR/simple Memo, Trace/Debug, and InternedGreen.
///
/// The host-recursive cases re-enter [interpretI] (a fresh trampoline) for
/// their sub-parses. None of them is nested recursively by current grammars,
/// so this does not reintroduce the structural-nesting overflow for any real
/// parser; lifting Pratt's atom and InternedGreen onto the continuation chain
/// is follow-up work.
Result<Object?, Object?> _leafInterpret(
  Parser<dynamic, dynamic> p,
  ParserState state,
) {
  switch (p) {
    case Succeed<dynamic, dynamic>(:final value):
      return Success<Object?, Object?>(value, 0);

    case Fail<dynamic, dynamic>(:final error):
      final loc = state.location;
      return Failure<Object?, Object?>(() => [error], loc);

    case Satisfy(:final pred, :final expected):
      if (state.hasChar) {
        final c = state.currentChar;
        if (pred(c)) {
          state.advance();
          return Success<Object?, Object?>(c, 1);
        }
        final loc = state.location;
        return Failure<Object?, Object?>(
          () => [
            Unexpected(c, {expected}, loc),
          ],
          loc,
        );
      }
      final loc = state.location;
      return Failure<Object?, Object?>(() => [EndOfInput(expected, loc)], loc);

    case StringMatch(:final target):
      final len = target.length;
      if (state.offset + len > state.input.length) {
        final loc = state.location;
        return Failure<Object?, Object?>(
          () => [EndOfInput('"$target"', loc)],
          loc,
        );
      }
      if (_regionMatches(state.input, state.offset, target)) {
        state.advanceByString(target);
        return Success<Object?, Object?>(target, len);
      }
      final loc = state.location;
      final endOff = math.min(state.offset + len, state.input.length);
      final found = state.input.substring(state.offset, endOff);
      return Failure<Object?, Object?>(
        () => [
          Unexpected(found, {'"$target"'}, loc),
        ],
        loc,
      );

    case StringChoice(:final radix, :final targets):
      return _interpretStringChoice<Object?, Object?>(radix, targets, state);

    case Eof():
      if (state.atEnd) return const Success<Object?, Object?>(null, 0);
      final loc = state.location;
      return Failure<Object?, Object?>(
        () => [CustomError('Expected end of input', loc)],
        loc,
      );

    case GetPosition():
      return Success<Object?, Object?>(state.offset, 0);

    case Capture<dynamic, dynamic>(
      parser: Many<dynamic, dynamic>(parser: final Satisfy s),
    ):
      return _scanMany<Object?, Object?>(
        s.pred,
        s.expected,
        state,
        required: false,
      );

    case Capture<dynamic, dynamic>(
      parser: Many1<dynamic, dynamic>(parser: final Satisfy s),
    ):
      return _scanMany<Object?, Object?>(
        s.pred,
        s.expected,
        state,
        required: true,
      );

    case Many<dynamic, dynamic>(parser: final Satisfy s):
      return _collectMany<Object?, Object?>(s.pred, state);

    case Many1<dynamic, dynamic>(parser: final Satisfy s):
      return _collectMany1<Object?, Object?>(s.pred, s.expected, state);

    case Many<dynamic, dynamic>(parser: final StringMatch sm):
      return _collectManyString<Object?, Object?>(sm.target, state);

    case Many1<dynamic, dynamic>(parser: final StringMatch sm):
      return _collectMany1String<Object?, Object?>(sm.target, state);

    case SkipMany<dynamic, dynamic>(parser: final Satisfy s):
      return _skipManySatisfy<Object?>(s.pred, state);

    case SkipMany<dynamic, dynamic>(parser: final StringMatch sm):
      return _skipManyString<Object?>(sm.target, state);

    case Trace<dynamic, dynamic>(:final parser, :final label):
      final r = interpretI<Object?, Object?>(parser, state);
      switch (r) {
        case Success(:final consumed):
          print('[TRACE] $label: success, consumed $consumed chars');
        case Partial(:final consumed):
          print('[TRACE] $label: partial, consumed $consumed chars');
        case Failure():
          print('[TRACE] $label: failed');
      }
      return r;

    case Debug<dynamic, dynamic>(:final parser, :final label):
      print('[DEBUG] $label: trying at offset ${state.offset}');
      final r = interpretI<Object?, Object?>(parser, state);
      switch (r) {
        case Success(:final value):
          print('[DEBUG] $label: success, parsed $value');
        case Partial(:final value, :final errors):
          print('[DEBUG] $label: partial, $value with ${errors.length} errors');
        case Failure(:final errors):
          print(
            '[DEBUG] $label: failed with ${errors.firstOrNull ?? "unknown"}',
          );
      }
      return r;

    case Memo<dynamic, dynamic>(:final inner, :final key, :final enableLR):
      if (enableLR) return _interpretMemo<Object?, Object?>(inner, key, state);
      return _interpretSimpleMemo<Object?, Object?>(inner, key, state);

    // Pratt is driven in the eval phase of `interpretI` (its atom subparse
    // rides the continuation chain via _ContPratt), so it never reaches here.

    case final InternedGreen<dynamic, dynamic, dynamic> ig:
      return (ig as InternedGreen<ParseError, dynamic, dynamic>).interpretWith(
            <T0, S0>(InternedGreen<ParseError, T0, S0> typed) =>
                _interpretInternedGreen<ParseError, T0, S0>(typed, state),
          )
          as Result<Object?, Object?>;

    default:
      throw StateError('Unreachable: unhandled ${p.runtimeType}');
  }
}

/// Handler for [InternedGreen]. Runs `inner`, then on success/partial
/// replaces the produced green with the parse-scoped cache's canonical
/// instance. Failures pass through untouched — interning only ever rewrites
/// a successful green.
///
/// [Tok]/[Syn] are reified by [InternedGreen.interpretWith] at the dispatch
/// site, so this handler produces a precisely-typed result. The cache is
/// non-generic ([GreenCache.intern] is a generic method), so no cache-level
/// cast is needed here.
Result<E, GreenNode<Tok, Syn>> _interpretInternedGreen<E, Tok, Syn>(
  InternedGreen<E, Tok, Syn> ig,
  ParserState state,
) {
  final cache = state.greenCache;
  final r = interpretI<E, GreenNode<Tok, Syn>>(ig.inner, state);
  return switch (r) {
    Success<E, GreenNode<Tok, Syn>>(:final value, :final consumed) =>
      Success<E, GreenNode<Tok, Syn>>(cache.intern(value), consumed),
    Partial<E, GreenNode<Tok, Syn>>(
      :final value,
      :final errorThunk,
      :final consumed,
    ) =>
      Partial<E, GreenNode<Tok, Syn>>(
        cache.intern(value),
        errorThunk,
        consumed,
      ),
    Failure<E, GreenNode<Tok, Syn>>() => r,
  };
}

// ===========================================================================
// Left-recursion (Warth seed-growth)
// ===========================================================================

Result<E, A> _interpretMemo<E, A>(
  Parser<E, A> inner,
  MemoKey<E, A> key,
  ParserState state,
) {
  final pos = state.offset;
  final startSnapshot = state.save();

  final head = state.heads[pos];
  if (head != null) {
    if (head.evalSet.contains(key.id)) {
      head.evalSet.remove(key.id);
      final result = interpretI<E, A>(inner, state);
      state.memo.put(key, pos, result, state.offset);
      return result;
    }
    if (identical(head.rule, key.id)) {
      final slot = state.memo.getRaw(key, pos);
      if (slot case MemoSlotLR(:final lr)) return lr.seed as Result<E, A>;
      if (slot case MemoSlotEntry(:final entry)) {
        state.restoreTo(entry.endPos);
        return state.memo.getResult(key, pos)!;
      }
    }
    if (head.involvedSet.contains(key.id)) {
      final slot = state.memo.getRaw(key, pos);
      if (slot case MemoSlotLR(:final lr)) return lr.seed as Result<E, A>;
      if (slot case MemoSlotEntry(:final entry)) {
        state.restoreTo(entry.endPos);
        return state.memo.getResult(key, pos)!;
      }
    }
  }

  return _evaluateMemo<E, A>(inner, key, pos, startSnapshot, state);
}

Result<E, A> _evaluateMemo<E, A>(
  Parser<E, A> inner,
  MemoKey<E, A> key,
  int pos,
  int startSnapshot,
  ParserState state,
) {
  final slot = state.memo.getRaw(key, pos);

  if (slot case MemoSlotLR(:final lr)) {
    _setupLR(key.id, lr, state);
    return lr.seed as Result<E, A>;
  }

  if (slot case MemoSlotEntry(:final entry)) {
    state.restoreTo(entry.endPos);
    return entry.result as Result<E, A>;
  }

  final lr = LR(seed: Failure<E, A>.eager([], state.location), rule: key.id);
  state.lrStack.add(lr);
  state.memo.putLR(key, pos, lr);

  final result = interpretI<E, A>(inner, state);
  final endPos = state.offset;
  state.lrStack.removeLast();

  if (lr.head == null || !identical(lr.head!.rule, key.id)) {
    state.memo.put(key, pos, result, endPos);
    return result;
  }

  if (result is Failure<E, A>) {
    state.memo.put(key, pos, result, endPos);
    return result;
  }

  lr.seed = result;
  return _growLR<E, A>(inner, key, startSnapshot, lr, endPos, state);
}

void _setupLR(Object key, LR lr, ParserState state) {
  final existingHead =
      state.lrStack
          .where((slr) => slr.head != null)
          .map((slr) => slr.head!)
          .firstOrNull;

  final LRHead actualHead;
  if (existingHead != null) {
    lr.head = existingHead;
    if (!identical(key, existingHead.rule)) {
      existingHead.involvedSet.add(key);
    }
    actualHead = existingHead;
  } else {
    lr.head ??= LRHead(key, {}, {});
    actualHead = lr.head!;
  }

  for (final stackLr in state.lrStack.reversed) {
    if (identical(stackLr.rule, key) ||
        identical(stackLr.rule, actualHead.rule)) {
      continue;
    }
    stackLr.head = actualHead;
    actualHead.involvedSet.add(stackLr.rule);
  }
}

Result<E, A> _growLR<E, A>(
  Parser<E, A> inner,
  MemoKey<E, A> key,
  int startSnapshot,
  LR lr,
  int seedEndPos,
  ParserState state,
) {
  final pos = startSnapshot;
  state.heads[pos] = lr.head!;

  var lastResult = lr.seed as Result<E, A>;
  var lastPos = seedEndPos;

  while (true) {
    state.restore(startSnapshot);
    state.memo.put(key, pos, lastResult, lastPos);
    lr.head!.evalSet = {...lr.head!.involvedSet};

    final result = interpretI<E, A>(inner, state);
    final resultPos = state.offset;

    if (result is Failure || resultPos <= lastPos) break;

    lastResult = result;
    lastPos = resultPos;
    lr.seed = result;
  }

  state.heads.remove(pos);
  state.restoreTo(lastPos);
  state.memo.put(key, pos, lastResult, lastPos);
  return lastResult;
}

// ===========================================================================
// Simple memoization
// ===========================================================================

Result<E, A> _interpretSimpleMemo<E, A>(
  Parser<E, A> inner,
  MemoKey<E, A> key,
  ParserState state,
) {
  final pos = state.offset;
  final entry = state.simpleCache.getEntry(key, pos);

  if (entry != null) {
    state.restoreTo(entry.endPos);
    return entry.result as Result<E, A>;
  }

  final result = interpretI<E, A>(inner, state);
  state.simpleCache.put(key, pos, result, state.offset);
  return result;
}

// ===========================================================================
// Specialized helpers
// ===========================================================================

Result<E, A> _interpretStringChoice<E, A>(
  RadixNode radix,
  List<String> targets,
  ParserState state,
) {
  final input = state.input;
  final offset = state.offset;
  final matched = radix.matchAtOrNull(input, offset);

  if (matched != null) {
    state.advanceByString(matched);
    return Success<E, A>(matched as A, matched.length);
  }

  final loc = state.location;
  final maxLen = targets.fold(0, (m, t) => math.max(m, t.length));
  final found = input.substring(
    offset,
    math.min(offset + maxLen, input.length),
  );
  final expected = targets.map((s) => '"$s"').toSet();
  return Failure<E, A>(() => [Unexpected(found, expected, loc) as E], loc);
}

// ===========================================================================
// Fused Satisfy scan fast paths
// ===========================================================================

/// Capture(Many(Satisfy)) / Capture(Many1(Satisfy)) → direct string scan.
Result<E, A> _scanMany<E, A>(
  bool Function(String) pred,
  String expected,
  ParserState state, {
  required bool required,
}) {
  final start = state.offset;
  while (state.hasChar && pred(state.currentChar)) {
    state.advance();
  }
  final consumed = state.offset - start;
  if (required && consumed == 0) {
    final loc = state.location;
    if (state.hasChar) {
      final actual = state.currentChar;
      return Failure<E, A>(
        () => [
          Unexpected(actual, {expected}, loc) as E,
        ],
        loc,
      );
    }
    return Failure<E, A>(() => [EndOfInput(expected, loc) as E], loc);
  }
  return Success<E, A>(state.slice(start, state.offset) as A, consumed);
}

/// Many(Satisfy) → collect chars without per-character interpretI dispatch.
Result<E, A> _collectMany<E, A>(bool Function(String) pred, ParserState state) {
  final acc = <String>[];
  var totalConsumed = 0;
  while (state.hasChar && pred(state.currentChar)) {
    acc.add(state.currentChar);
    state.advance();
    totalConsumed++;
  }
  return Success<E, A>(acc as A, totalConsumed);
}

/// Many1(Satisfy) → collect chars, require at least one.
Result<E, A> _collectMany1<E, A>(
  bool Function(String) pred,
  String expected,
  ParserState state,
) {
  if (!state.hasChar || !pred(state.currentChar)) {
    final loc = state.location;
    if (state.hasChar) {
      final actual = state.currentChar;
      return Failure<E, A>(
        () => [
          Unexpected(actual, {expected}, loc) as E,
        ],
        loc,
      );
    }
    return Failure<E, A>(() => [EndOfInput(expected, loc) as E], loc);
  }
  final acc = <String>[state.currentChar];
  state.advance();
  var totalConsumed = 1;
  while (state.hasChar && pred(state.currentChar)) {
    acc.add(state.currentChar);
    state.advance();
    totalConsumed++;
  }
  return Success<E, A>(acc as A, totalConsumed);
}

/// Many(StringMatch) → collect target repetitions without per-iteration Failure.
Result<E, A> _collectManyString<E, A>(String target, ParserState state) {
  final acc = <String>[];
  var totalConsumed = 0;
  final input = state.input;
  final len = target.length;
  while (state.offset + len <= input.length &&
      _regionMatches(input, state.offset, target)) {
    acc.add(target);
    state.advanceByString(target);
    totalConsumed += len;
  }
  return Success<E, A>(acc as A, totalConsumed);
}

/// Many1(StringMatch) → collect target repetitions, require at least one.
Result<E, A> _collectMany1String<E, A>(String target, ParserState state) {
  final input = state.input;
  final len = target.length;
  if (state.offset + len > input.length ||
      !_regionMatches(input, state.offset, target)) {
    final loc = state.location;
    if (state.hasChar) {
      final endOff =
          state.offset + len <= input.length
              ? state.offset + len
              : input.length;
      final found = input.substring(state.offset, endOff);
      return Failure<E, A>(
        () => [
          Unexpected(found, {'"$target"'}, loc) as E,
        ],
        loc,
      );
    }
    return Failure<E, A>(() => [EndOfInput('"$target"', loc) as E], loc);
  }
  return _collectManyString<E, A>(target, state);
}

/// SkipMany(Satisfy) → advance while predicate matches, no allocation.
Result<E, void> _skipManySatisfy<E>(
  bool Function(String) pred,
  ParserState state,
) {
  var totalConsumed = 0;
  while (state.hasChar && pred(state.currentChar)) {
    state.advance();
    totalConsumed++;
  }
  return Success<E, void>(null, totalConsumed);
}

/// SkipMany(StringMatch) → advance while target matches, no allocation.
Result<E, void> _skipManyString<E>(String target, ParserState state) {
  final input = state.input;
  final len = target.length;
  var totalConsumed = 0;
  while (state.offset + len <= input.length &&
      _regionMatches(input, state.offset, target)) {
    state.advanceByString(target);
    totalConsumed += len;
  }
  return Success<E, void>(null, totalConsumed);
}

/// Frame on the Pratt operator stack: a pending operation waiting for the
/// in-flight nud subparse to produce a value. On completion the frame is
/// popped and either combined with [_PrattInfixFrame.savedLhs] (infix) or
/// applied to lhs alone (prefix). [outerMinBp] is the minBp threshold of the
/// surrounding scope, restored when the frame pops.
///
/// Each frame stores the *operator node itself* ([PrattOpInfix] /
/// [PrattPrefix]), which applies itself to erased operands through its typed
/// boundary method ([PrattOpInfix.combineWith] / [PrattPrefix.applyTo]). The
/// interpreter drives Pratt at `A = dynamic`, so it holds operands as
/// `Object?`; the `as A` casts live inside the operator node where [A] is in
/// scope, never on a widened `Function` at the use site. See [_applyFrame].
sealed class _PrattFrame {
  const _PrattFrame();
  int get outerMinBp;
}

final class _PrattInfixFrame extends _PrattFrame {
  final Object? savedLhs;
  final PrattOpInfix<dynamic> op;
  @override
  final int outerMinBp;
  const _PrattInfixFrame(this.savedLhs, this.op, this.outerMinBp);
}

final class _PrattPrefixFrame extends _PrattFrame {
  final PrattPrefix<dynamic, dynamic> prefix;
  @override
  final int outerMinBp;
  const _PrattPrefixFrame(this.prefix, this.outerMinBp);
}

/// Resumable Pratt (Top-Down Operator Precedence) loop.
///
/// The operator loop is iterative within one level (an explicit
/// [_PrattFrame] stack, so unbounded right-associative chains `a^b^c^…` and
/// prefix chains `---5` do not consume Dart call frames). The one subparse
/// that nests by *structural depth* is the **atom** (`'(' expr ')'`), which
/// can itself be a nested Pratt. Rather than calling `interpretI(atom)` on the
/// host stack, [step] runs until it needs an atom, stashes [pendingAtom], and
/// returns null; the main trampoline drives the atom under a [_ContPratt]
/// frame and feeds the result back via [resumeWithAtom], then re-steps. Atom
/// nesting therefore lives on the heap continuation chain, like every other
/// combinator.
///
/// Prefix symbols and the general `getOp` parser are operator *terminals* —
/// bounded, not depth-nesting — so they remain host-recursive `interpretI`
/// calls inside [step].
///
/// Two phases keyed by `lhsValid`:
/// - PARSE_NUD: try each prefix; on a hit, push a [_PrattPrefixFrame] and
///   re-enter with the prefix's bp as the new minBp. On a miss-of-all, request
///   the [atom] (suspend) to obtain the lhs, then transition to LOOP_OPS.
/// - LOOP_OPS: peek the next operator (via [_opTable] when available, else the
///   general [_getOp] parser). On infix at lbp > minBp, push a
///   [_PrattInfixFrame] and transition to PARSE_NUD with rbp as the new minBp.
///   On postfix at bp > minBp, apply in place. On no match or low-bp, pop a
///   single frame and stay in LOOP_OPS.
class _PrattRun {
  final Parser<dynamic, dynamic> atom;
  final List<PrattPrefix<dynamic, dynamic>> prefixes;
  final Parser<dynamic, dynamic> getOp;
  final PrattOpTable<dynamic>? opTable;
  final ParserState state;

  final stack = <_PrattFrame>[];
  int minBp;
  int totalConsumed = 0;
  Object? lhs;
  bool lhsValid = false;

  /// When [step] suspends to request a nud subparse, the parser to descend
  /// into (always [atom]). The trampoline reads it, runs it, and resumes.
  Parser<dynamic, dynamic>? pendingAtom;

  _PrattRun(
    this.atom,
    this.prefixes,
    this.getOp,
    int initialMinBp,
    this.opTable,
    this.state,
  ) : minBp = initialMinBp;

  /// Feed a completed atom subparse result back into the loop. On failure the
  /// whole Pratt parse fails (returned by the next [step]); on success the
  /// value becomes the current lhs.
  Result<Object?, Object?>? _atomFailure;
  void resumeWithAtom(Result<Object?, Object?> atomR) {
    if (atomR is Success<Object?, Object?>) {
      lhs = atomR.value;
      totalConsumed += atomR.consumed;
      lhsValid = true;
    } else {
      _atomFailure = atomR;
    }
  }

  /// Advance the loop. Returns a final [Result] when the Pratt parse is
  /// complete, or null when it has suspended awaiting [pendingAtom].
  Result<Object?, Object?>? step() {
    if (_atomFailure != null) return _atomFailure;
    final state = this.state;
    final input = state.input;
    final table = opTable;
    final consumesWs = table?.consumesTrailingWs ?? false;

    while (true) {
      if (!lhsValid) {
        // PARSE_NUD: try prefixes (each pushes a frame and re-loops), then
        // request the atom.
        var matchedPrefix = false;
        for (final pre in prefixes) {
          final snapshot = state.save();
          final r = interpretI<dynamic, Object?>(pre.symbol, state);
          if (r is Success<dynamic, Object?>) {
            stack.add(_PrattPrefixFrame(pre, minBp));
            minBp = pre.bp;
            totalConsumed += r.consumed;
            matchedPrefix = true;
            break;
          }
          state.restore(snapshot);
        }
        if (matchedPrefix) continue;

        // Suspend: the trampoline runs `atom` and calls resumeWithAtom.
        pendingAtom = atom;
        return null;
      }

      // LOOP_OPS: try to extend lhs with the next operator.
      if (table != null) {
        if (!state.hasChar) {
          if (stack.isNotEmpty) {
            _popFrame();
            continue;
          }
          return Success<Object?, Object?>(lhs, totalConsumed);
        }
        final bucket = table.entriesAt(input.codeUnitAt(state.offset));
        if (bucket == null) {
          if (stack.isNotEmpty) {
            _popFrame();
            continue;
          }
          return Success<Object?, Object?>(lhs, totalConsumed);
        }

        final matchOffset = state.offset;
        PrattOpEntry<dynamic>? matched;
        for (final entry in bucket) {
          if (_matchEntry(entry, input, matchOffset)) {
            matched = entry;
            break;
          }
        }
        if (matched == null) {
          if (stack.isNotEmpty) {
            _popFrame();
            continue;
          }
          return Success<Object?, Object?>(lhs, totalConsumed);
        }

        final op = matched.op;
        final prefixLen = matched.prefix.length;
        // The operator applies itself through its typed boundary method
        // ([PrattOpInfix.combineWith] / [PrattOpPostfix.applyTo]); the infix
        // frame stores the operator node, not a widened `Function`.
        switch (op) {
          case PrattOpInfix<dynamic>(:final lbp, :final rbp):
            if (lbp <= minBp) {
              if (stack.isNotEmpty) {
                _popFrame();
                continue;
              }
              return Success<Object?, Object?>(lhs, totalConsumed);
            }
            state.advanceN(prefixLen);
            totalConsumed += prefixLen + (consumesWs ? _skipAsciiWs(state) : 0);
            stack.add(_PrattInfixFrame(lhs, op, minBp));
            minBp = rbp;
            lhsValid = false;
            continue;
          case PrattOpPostfix<dynamic>(:final bp):
            if (bp <= minBp) {
              if (stack.isNotEmpty) {
                _popFrame();
                continue;
              }
              return Success<Object?, Object?>(lhs, totalConsumed);
            }
            state.advanceN(prefixLen);
            totalConsumed += prefixLen + (consumesWs ? _skipAsciiWs(state) : 0);
            lhs = op.applyTo(lhs);
        }
      } else {
        final snapshot = state.save();
        final opResult = interpretI<dynamic, Object?>(getOp, state);
        if (opResult is! Success<dynamic, Object?>) {
          state.restore(snapshot);
          if (stack.isNotEmpty) {
            _popFrame();
            continue;
          }
          return Success<Object?, Object?>(lhs, totalConsumed);
        }
        final op = opResult.value as PrattOp<dynamic>;
        switch (op) {
          case PrattOpInfix<dynamic>(:final lbp, :final rbp):
            if (lbp <= minBp) {
              state.restore(snapshot);
              if (stack.isNotEmpty) {
                _popFrame();
                continue;
              }
              return Success<Object?, Object?>(lhs, totalConsumed);
            }
            totalConsumed += opResult.consumed;
            stack.add(_PrattInfixFrame(lhs, op, minBp));
            minBp = rbp;
            lhsValid = false;
            continue;
          case PrattOpPostfix<dynamic>(:final bp):
            if (bp <= minBp) {
              state.restore(snapshot);
              if (stack.isNotEmpty) {
                _popFrame();
                continue;
              }
              return Success<Object?, Object?>(lhs, totalConsumed);
            }
            totalConsumed += opResult.consumed;
            lhs = op.applyTo(lhs);
        }
      }
    }
  }

  /// Pop one operator-stack frame, combining/applying it into [lhs] and
  /// restoring the surrounding minBp.
  void _popFrame() {
    final popped = _applyFrame(stack.removeLast(), lhs);
    lhs = popped.lhs;
    minBp = popped.outerMinBp;
  }
}

/// Result of applying a single popped frame to the current `lhs`. Returned
/// as a record so callers can update both the lhs accumulator and the minBp
/// threshold in one assignment.
typedef _PoppedFrame = ({Object? lhs, int outerMinBp});

/// Combines (infix) or applies (prefix) [frame] to the erased [lhs] and returns
/// the updated lhs together with the frame's outerMinBp. Each operator applies
/// itself through its typed boundary method ([PrattOpInfix.combineWith] /
/// [PrattPrefix.applyTo]), so the `as A` casts stay inside the operator node —
/// no widened `Function`, no dynamic call here.
_PoppedFrame _applyFrame(_PrattFrame frame, Object? lhs) => switch (frame) {
  _PrattInfixFrame(:final savedLhs, :final op, :final outerMinBp) => (
    lhs: op.combineWith(savedLhs, lhs),
    outerMinBp: outerMinBp,
  ),
  _PrattPrefixFrame(:final prefix, :final outerMinBp) => (
    lhs: prefix.applyTo(lhs),
    outerMinBp: outerMinBp,
  ),
};

/// Returns true if [entry]'s prefix matches [input] starting at [offset] and
/// its guard (word boundary or not-followed-by) is satisfied.
bool _matchEntry<A>(PrattOpEntry<A> entry, String input, int offset) {
  final prefix = entry.prefix;
  final prefixLen = prefix.length;
  if (offset + prefixLen > input.length) return false;
  for (var i = 0; i < prefixLen; i++) {
    if (input.codeUnitAt(offset + i) != prefix.codeUnitAt(i)) return false;
  }
  final guard = entry.guard;
  switch (guard) {
    case TokenGuardNone():
      return true;
    case TokenGuardWordBoundary():
      final after = offset + prefixLen;
      if (after >= input.length) return true;
      return !isIdentChar(input.codeUnitAt(after));
    case TokenGuardNotFollowedByChar(:final codeUnit):
      final after = offset + prefixLen;
      if (after >= input.length) return true;
      return input.codeUnitAt(after) != codeUnit;
  }
}

/// Advances past ASCII whitespace (space, tab, CR, LF). Returns bytes skipped.
int _skipAsciiWs(ParserState state) {
  final input = state.input;
  final len = input.length;
  final start = state.offset;
  var i = start;
  while (i < len) {
    final c = input.codeUnitAt(i);
    if (c == 0x20 || c == 0x09 || c == 0x0D || c == 0x0A) {
      i++;
    } else {
      break;
    }
  }
  state.restoreTo(i);
  return i - start;
}

/// In-place string comparison without substring allocation.
bool _regionMatches(String input, int offset, String target) {
  for (var i = 0; i < target.length; i++) {
    if (input.codeUnitAt(offset + i) != target.codeUnitAt(i)) return false;
  }
  return true;
}

/// FIRST-set check for Or: if [p]'s leading token is decidable from the
/// current char alone, peek and return a synthesized Failure when it cannot
/// match; otherwise return null so the caller falls back to running [p].
///
/// This avoids the save/interpretI/restore round-trip on the left branch of
/// a choice when a one-char lookahead already proves it will fail. The
/// synthesized Failure carries the same errors the left branch would have
/// produced, so error merging on both-fail is unchanged.
///
/// Handles terminals whose acceptance is a single-char predicate (Satisfy,
/// StringMatch, StringChoice, Eof) and peels wrappers that don't change the
/// leading char (Mapped/Zip-left/Named/Expect/LookAhead). Opaque cases
/// (FlatMap, Defer thunks, Memo, etc.) return null.
Failure<E, A>? _firstFail<E, A>(Parser<E, A> p, ParserState state) {
  var node = p as Parser<dynamic, dynamic>;
  while (true) {
    switch (node) {
      case Satisfy(:final pred, :final expected):
        if (!state.hasChar) {
          final loc = state.location;
          return Failure<E, A>(() => [EndOfInput(expected, loc) as E], loc);
        }
        final c = state.currentChar;
        if (pred(c)) return null;
        final loc = state.location;
        return Failure<E, A>(
          () => [
            Unexpected(c, {expected}, loc) as E,
          ],
          loc,
        );

      case StringMatch(:final target):
        final len = target.length;
        if (state.offset + len > state.input.length) {
          final loc = state.location;
          return Failure<E, A>(() => [EndOfInput('"$target"', loc) as E], loc);
        }
        if (state.input.codeUnitAt(state.offset) != target.codeUnitAt(0)) {
          final loc = state.location;
          final endOff = state.offset + len;
          final found = state.input.substring(state.offset, endOff);
          return Failure<E, A>(
            () => [
              Unexpected(found, {'"$target"'}, loc) as E,
            ],
            loc,
          );
        }
        return null;

      case Eof():
        if (state.atEnd) return null;
        final loc = state.location;
        return Failure<E, A>(
          () => [CustomError('Expected end of input', loc) as E],
          loc,
        );

      case Mapped(:final source):
        node = source;

      case Zip(:final left):
        node = left;

      // skipThen/thenSkip both run `left` first, so the leading char is
      // decidable from it (same as Zip-left). Peel it for the FIRST-set check.
      case SkipLeft(:final left):
        node = left;

      case SkipRight(:final left):
        node = left;

      case LookAhead(:final parser):
        node = parser;

      case InternedGreen(:final inner):
        // Interning only rewrites a successful green; a failing inner
        // propagates unchanged, so the leading-char test peels the wrapper.
        node = inner;

      default:
        return null;
    }
  }
}

/// Merge two Failures, keeping the furthest location and combining error
/// thunks. Preserves the invariant tested by `or merges errors from both
/// branches when both fail at same offset`.
Failure<E, A> _mergeFailures<E, A>(Failure<E, A> r1, Failure<E, A> r2) {
  if (r1.furthest.offset > r2.furthest.offset) return r1;
  if (r2.furthest.offset > r1.furthest.offset) return r2;
  return Failure<E, A>(
    () => [...r1.errorThunk(), ...r2.errorThunk()],
    r1.furthest,
  );
}
