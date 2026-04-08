/// Stack-safe interpreter using a type-preserving continuation stack
/// and a `while(true)` state machine.
///
/// The trampoline converts recursive [FlatMap]/[Map]/[Zip] chains into
/// an explicit continuation-passing loop, achieving O(1) call stack
/// usage for arbitrarily deep parser compositions. Tested to 7M+
/// sequential operations in the Scala implementation.
///
/// Two sealed hierarchies define the state machine:
/// - [ParserCont]: immutable continuation stack (linked list of frames)
/// - [EvalState]: two-phase loop state (Eval parser or Apply result)
library;

import 'parser.dart';
import 'result.dart';

// ---------------------------------------------------------------------------
// ParserCont — continuation stack
// ---------------------------------------------------------------------------

/// A frame in the continuation stack. Each frame knows how to transform
/// a value of type [In] into progress toward a final value of type [Out].
///
/// Sealed with 5 cases, exhaustively matched in the Apply phase.
sealed class ParserCont<E, In, Out> {
  const ParserCont();
}

/// Bottom of the stack — identity continuation. The value IS the final result.
final class EndCont<E, A> extends ParserCont<E, A, A> {
  const EndCont();
}

/// FlatMap continuation: apply [f] to the input value to get a new parser.
final class StepCont<E, In, Mid, Out> extends ParserCont<E, In, Out> {
  final Parser<E, Mid> Function(In) f;
  final ParserCont<E, Mid, Out> next;
  const StepCont(this.f, this.next);
}

/// Map continuation: apply pure function [f] to the input value.
final class MapCont<E, In, Mid, Out> extends ParserCont<E, In, Out> {
  final Mid Function(In) f;
  final ParserCont<E, Mid, Out> next;
  const MapCont(this.f, this.next);
}

/// Partial continuation: carries a lazy error thunk through flatMap chains.
///
/// When a [Partial] result flows through a FlatMap, we capture the
/// error thunk here so it can be combined with downstream errors.
final class PartialCont<E, A, Out> extends ParserCont<E, A, Out> {
  final List<E> Function() mkErrors;
  final ParserCont<E, A, Out> next;
  const PartialCont(this.mkErrors, this.next);
}

/// Composed continuation: right-associating two continuations.
///
/// Prevents O(n^2) left-leaning chains when nesting FlatMaps.
final class ComposeCont<E, In, Mid, Out> extends ParserCont<E, In, Out> {
  final ParserCont<E, In, Mid> first;
  final ParserCont<E, Mid, Out> second;
  const ComposeCont(this.first, this.second);
}

// ---------------------------------------------------------------------------
// EvalState — two-phase state machine
// ---------------------------------------------------------------------------

/// The current state of the trampoline loop.
///
/// - [Eval]: we have a parser to evaluate; decompose FlatMap/Map/Zip
///   and push continuations
/// - [Apply]: we have a result; pop a continuation and process it
sealed class EvalState<E, Out> {
  const EvalState();
}

/// Eval phase: decompose the parser, pushing continuations for
/// FlatMap/Map/Zip, or interpret terminal parsers directly.
final class Eval<E, Mid, Out> extends EvalState<E, Out> {
  final Parser<E, Mid> parser;
  final ParserCont<E, Mid, Out> cont;
  final int consumed;
  const Eval(this.parser, this.cont, this.consumed);
}

/// Apply phase: process [result] against the top continuation.
final class Apply<E, Mid, Out> extends EvalState<E, Out> {
  final Result<E, Mid> result;
  final ParserCont<E, Mid, Out> cont;
  final int consumed;
  const Apply(this.result, this.cont, this.consumed);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Smart constructor for [ComposeCont] that avoids wrapping [EndCont].
ParserCont<E, A, C> composeK<E, A, B, C>(
  ParserCont<E, A, B> first,
  ParserCont<E, B, C> second,
) {
  if (first is EndCont<E, A>) {
    // EndCont is identity — skip the composition.
    // Safe cast: EndCont<E, A> extends ParserCont<E, A, A>,
    // and if first is End then B == A, so second : ParserCont<E, A, C>.
    return second as ParserCont<E, A, C>;
  }
  return ComposeCont(first, second);
}

/// Add consumed characters to a result.
Result<E, A> addConsumed<E, A>(Result<E, A> result, int extra) {
  if (extra == 0) return result;
  return switch (result) {
    Success(:final value, :final consumed) => Success(value, consumed + extra),
    Partial(:final value, :final errorThunk, :final consumed) =>
      Partial(value, errorThunk, consumed + extra),
    Failure() => result, // Failure has no consumed count to adjust
  };
}
