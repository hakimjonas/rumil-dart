/// Parse error types.
library;

import 'location.dart';

/// A parse error with source location.
sealed class ParseError {
  /// Where in the input this error occurred.
  Location get location;
}

/// Found unexpected input where something else was expected.
final class Unexpected extends ParseError {
  /// The actual input found.
  final String found;

  /// What was expected instead.
  final Set<String> expected;

  @override
  final Location location;

  /// Creates an unexpected-input error.
  Unexpected(this.found, this.expected, this.location);

  @override
  String toString() =>
      'Unexpected "$found" at ${location.format()}, expected: ${expected.join(', ')}';
}

/// Reached end of input when more was expected.
final class EndOfInput extends ParseError {
  /// What was expected at end of input.
  final String expected;

  @override
  final Location location;

  /// Creates an end-of-input error.
  EndOfInput(this.expected, this.location);

  @override
  String toString() =>
      'Unexpected end of input at ${location.format()}, expected $expected';
}

/// A custom error message.
final class CustomError extends ParseError {
  /// The error message.
  final String message;

  @override
  final Location location;

  /// Creates a custom error.
  CustomError(this.message, this.location);

  @override
  String toString() => '$message at ${location.format()}';
}
