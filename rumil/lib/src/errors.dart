/// Parse error types — a sealed hierarchy for exhaustive handling.
///
/// Every error carries a [Location] so diagnostics always include position.
/// The sealed class ensures the compiler verifies all cases are handled
/// in switch expressions.
library;

import 'location.dart';

/// A parse error with source location.
///
/// Sealed — all subtypes are known at compile time. Switch expressions
/// over [ParseError] are exhaustive.
sealed class ParseError {
  /// The source location where this error occurred.
  Location get location;
}

/// Found unexpected input where something else was expected.
///
/// [found] is what was actually encountered (e.g. `"x"`, `"end of input"`).
/// [expected] is the set of things that would have been valid.
final class Unexpected extends ParseError {
  /// What was actually found at this position.
  final String found;

  /// The set of expected alternatives.
  final Set<String> expected;

  @override
  final Location location;

  /// Creates an [Unexpected] error.
  Unexpected(this.found, this.expected, this.location);

  @override
  String toString() =>
      'Unexpected "$found" at ${location.format()}, expected: ${expected.join(', ')}';
}

/// Reached end of input when more was expected.
final class EndOfInput extends ParseError {
  /// What was expected at the point where input ended.
  final String expected;

  @override
  final Location location;

  /// Creates an [EndOfInput] error.
  EndOfInput(this.expected, this.location);

  @override
  String toString() => 'Unexpected end of input at ${location.format()}, expected $expected';
}

/// A custom error message from user-defined parsing logic.
final class CustomError extends ParseError {
  /// The error message.
  final String message;

  @override
  final Location location;

  /// Creates a [CustomError].
  CustomError(this.message, this.location);

  @override
  String toString() => '$message at ${location.format()}';
}
