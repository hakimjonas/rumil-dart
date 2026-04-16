/// Three-way parse result: [Success], [Partial], or [Failure].
///
/// Errors in [Partial] and [Failure] are lazily constructed. During
/// backtracking, error thunks for failing branches are never evaluated
/// if another branch succeeds.
library;

import 'location.dart';

/// The result of a parse or decode operation.
sealed class Result<E, A> {
  const Result._();
}

/// Parse succeeded with no errors.
final class Success<E, A> extends Result<E, A> {
  /// The parsed value.
  final A value;

  /// Number of input characters consumed.
  final int consumed;

  /// Creates a successful result.
  const Success(this.value, this.consumed) : super._();

  @override
  String toString() => 'Success($value, consumed: $consumed)';
}

/// Parse succeeded but accumulated errors (resilient parsing).
final class Partial<E, A> extends Result<E, A> {
  /// The parsed value.
  final A value;

  /// Number of input characters consumed.
  final int consumed;

  /// Lazy error thunk, evaluated on first access of [errors].
  final List<E> Function() errorThunk;

  List<E>? _errors;

  /// Materialized errors (evaluated once from [errorThunk]).
  List<E> get errors => _errors ??= errorThunk();

  /// Creates a partial result with lazy errors.
  Partial(this.value, this.errorThunk, this.consumed) : super._();

  /// Creates a partial result with pre-computed errors.
  Partial.eager(this.value, List<E> errors, this.consumed)
    : errorThunk = (() => errors),
      _errors = errors,
      super._();

  @override
  String toString() => 'Partial($value, errors: $errors, consumed: $consumed)';
}

/// Parse failed, no value produced.
///
/// [furthest] tracks the deepest position reached, for diagnostics.
final class Failure<E, A> extends Result<E, A> {
  /// The deepest input position reached before failure.
  final Location furthest;

  /// Lazy error thunk, evaluated on first access of [errors].
  final List<E> Function() errorThunk;

  List<E>? _errors;

  /// Materialized errors (evaluated once from [errorThunk]).
  List<E> get errors => _errors ??= errorThunk();

  /// Creates a failure with lazy errors.
  Failure(this.errorThunk, this.furthest) : super._();

  /// Creates a failure with pre-computed errors.
  Failure.eager(List<E> errors, this.furthest)
    : errorThunk = (() => errors),
      _errors = errors,
      super._();

  @override
  String toString() => 'Failure(errors: $errors, furthest: $furthest)';
}

/// Convenience extensions on [Result].
extension ResultOps<E, A> on Result<E, A> {
  /// True if this is a [Success].
  bool get isSuccess => this is Success<E, A>;

  /// True if this is a [Partial].
  bool get isPartial => this is Partial<E, A>;

  /// True if this is a [Failure].
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

  /// Transforms the value, preserving errors and consumed count.
  Result<E, B> map<B>(B Function(A) f) => switch (this) {
    Success(:final value, :final consumed) => Success(f(value), consumed),
    Partial(:final value, :final consumed, :final errorThunk) => Partial(
      f(value),
      errorThunk,
      consumed,
    ),
    Failure(:final furthest, :final errorThunk) => Failure(
      errorThunk,
      furthest,
    ),
  };
}
