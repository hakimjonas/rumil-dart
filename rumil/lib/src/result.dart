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
  final A value;
  final int consumed;
  const Success(this.value, this.consumed) : super._();

  @override
  String toString() => 'Success($value, consumed: $consumed)';
}

/// Parse succeeded but accumulated errors (resilient parsing).
final class Partial<E, A> extends Result<E, A> {
  final A value;
  final int consumed;
  final List<E> Function() errorThunk;
  late final List<E> errors = errorThunk();

  Partial(this.value, this.errorThunk, this.consumed) : super._();

  Partial.eager(this.value, List<E> errors, this.consumed)
    : errorThunk = (() => errors),
      super._();

  @override
  String toString() => 'Partial($value, errors: $errors, consumed: $consumed)';
}

/// Parse failed — no value produced.
///
/// [furthest] tracks the deepest position reached, used for diagnostics.
final class Failure<E, A> extends Result<E, A> {
  final Location furthest;
  final List<E> Function() errorThunk;
  late final List<E> errors = errorThunk();

  Failure(this.errorThunk, this.furthest) : super._();

  Failure.eager(List<E> errors, this.furthest)
    : errorThunk = (() => errors),
      super._();

  @override
  String toString() => 'Failure(errors: $errors, furthest: $furthest)';
}

/// Convenience extensions on [Result].
extension ResultOps<E, A> on Result<E, A> {
  bool get isSuccess => this is Success<E, A>;
  bool get isPartial => this is Partial<E, A>;
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
