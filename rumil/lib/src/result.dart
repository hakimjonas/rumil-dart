/// Three-way parse result: [Success], [Partial], or [Failure].
///
/// This is the core result type for both parsing (Rumil) and decoding (Sarati).
/// It is sealed — switch expressions are exhaustive.
///
/// [Partial] and [Failure] use lazy error construction: errors are stored
/// as a `List<E> Function()` thunk and only materialized on first access
/// via `late final`. During backtracking, failed branches' error thunks
/// are captured but never invoked if another branch succeeds — preserving
/// the 2.6x speedup measured in the Scala implementation.
library;

import 'location.dart';

/// The result of a parse or decode operation.
///
/// Sealed over three cases:
/// - [Success]: produced a value, no errors
/// - [Partial]: produced a value, but with accumulated warnings/errors
/// - [Failure]: no value produced, parsing failed
///
/// Type parameters:
/// - [E]: error type (covariant in spirit; use `Never` for infallible)
/// - [A]: value type
sealed class Result<E, A> {
  const Result._();
}

/// Parse succeeded with no errors.
final class Success<E, A> extends Result<E, A> {
  /// The parsed value.
  final A value;

  /// Number of characters consumed from the input.
  final int consumed;

  /// Creates a successful result.
  const Success(this.value, this.consumed) : super._();

  @override
  String toString() => 'Success($value, consumed: $consumed)';
}

/// Parse succeeded but accumulated errors (resilient parsing).
///
/// Used for IDE tooling: the parser produces a result (often a syntax tree
/// with error markers) while collecting errors. This allows tooling to work
/// with partially-valid code.
///
/// Errors are lazily constructed — the thunk is only evaluated when
/// [errors] is first accessed.
final class Partial<E, A> extends Result<E, A> {
  /// The parsed value (possibly containing error markers).
  final A value;

  /// Number of characters consumed from the input.
  final int consumed;

  /// The lazy error thunk. Access [errors] instead for the materialized list.
  ///
  /// Exposed for the interpreter/trampoline to recompose results without
  /// forcing materialization during backtracking.
  final List<E> Function() errorThunk;

  /// Accumulated errors, lazily materialized on first access.
  late final List<E> errors = errorThunk();

  /// Creates a partial result with a lazy error thunk.
  Partial(this.value, this.errorThunk, this.consumed) : super._();

  /// Creates a partial result with eager errors.
  Partial.eager(this.value, List<E> errors, this.consumed)
      : errorThunk = (() => errors),
        super._();

  @override
  String toString() => 'Partial($value, errors: $errors, consumed: $consumed)';
}

/// Parse failed entirely — no value produced.
///
/// [furthest] tracks the deepest position reached before failure,
/// used for "expected X at position Y" diagnostics.
///
/// Errors are lazily constructed — the thunk is only evaluated when
/// [errors] is first accessed. During backtracking in [Or]/[Choice],
/// if another branch succeeds, this thunk is never called.
final class Failure<E, A> extends Result<E, A> {
  /// The deepest position reached before failure.
  final Location furthest;

  /// The lazy error thunk. Access [errors] instead for the materialized list.
  ///
  /// Exposed for the interpreter/trampoline to recompose results without
  /// forcing materialization during backtracking.
  final List<E> Function() errorThunk;

  /// Error details, lazily materialized on first access.
  late final List<E> errors = errorThunk();

  /// Creates a failure with a lazy error thunk.
  Failure(this.errorThunk, this.furthest) : super._();

  /// Creates a failure with eager errors.
  Failure.eager(List<E> errors, this.furthest)
      : errorThunk = (() => errors),
        super._();

  @override
  String toString() => 'Failure(errors: $errors, furthest: $furthest)';
}

/// Convenience extensions on [Result].
extension ResultOps<E, A> on Result<E, A> {
  /// Whether this is a [Success].
  bool get isSuccess => this is Success<E, A>;

  /// Whether this is a [Partial].
  bool get isPartial => this is Partial<E, A>;

  /// Whether this is a [Failure].
  bool get isFailure => this is Failure<E, A>;

  /// The value if [Success] or [Partial], `null` if [Failure].
  A? get valueOrNull => switch (this) {
        Success(:final value) => value,
        Partial(:final value) => value,
        Failure() => null,
      };

  /// Errors from any case. Empty for [Success].
  List<E> get errors => switch (this) {
        Success() => const [],
        Partial(:final errors) => errors,
        Failure(:final errors) => errors,
      };

  /// Transforms the value if [Success] or [Partial], preserving errors.
  Result<E, B> map<B>(B Function(A) f) => switch (this) {
        Success(:final value, :final consumed) => Success(f(value), consumed),
        Partial(:final value, :final consumed, :final errorThunk) =>
          Partial(f(value), errorThunk, consumed),
        Failure(:final furthest, :final errorThunk) =>
          Failure(errorThunk, furthest),
      };
}
