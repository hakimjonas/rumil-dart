/// Parse error types.
library;

import 'location.dart';

/// A parse error with source location.
sealed class ParseError {
  Location get location;
}

/// Found unexpected input where something else was expected.
final class Unexpected extends ParseError {
  final String found;
  final Set<String> expected;
  @override
  final Location location;

  Unexpected(this.found, this.expected, this.location);

  @override
  String toString() =>
      'Unexpected "$found" at ${location.format()}, expected: ${expected.join(', ')}';
}

/// Reached end of input when more was expected.
final class EndOfInput extends ParseError {
  final String expected;
  @override
  final Location location;

  EndOfInput(this.expected, this.location);

  @override
  String toString() =>
      'Unexpected end of input at ${location.format()}, expected $expected';
}

/// A custom error message.
final class CustomError extends ParseError {
  final String message;
  @override
  final Location location;

  CustomError(this.message, this.location);

  @override
  String toString() => '$message at ${location.format()}';
}
