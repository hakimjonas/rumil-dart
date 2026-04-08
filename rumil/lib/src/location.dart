/// Zero-cost position and span types for source tracking.
///
/// [Location] wraps a `(int, int, int)` record representing a position in
/// source text. [Span] wraps two [Location]s representing a contiguous range.
///
/// Both are extension types — they ARE the underlying records at runtime,
/// with no allocation overhead. The compiler prevents accidentally passing
/// a raw `(int, int, int)` where a [Location] is expected.
library;

/// A position in source text: line (1-indexed), column (1-indexed),
/// byte offset (0-indexed).
///
/// This is an extension type over a positional record — zero runtime cost.
/// The type system prevents mixing up `Location` with arbitrary `(int, int, int)`.
extension type const Location._(({int line, int column, int offset}) _) {
  /// Creates a [Location] with named parameters.
  const Location({required int line, required int column, required int offset})
      : _ = (line: line, column: column, offset: offset);

  /// Creates a [Location] at the start of input: line 1, column 1, offset 0.
  static const zero = Location(line: 1, column: 1, offset: 0);

  /// 1-indexed line number.
  int get line => _.line;

  /// 1-indexed column number.
  int get column => _.column;

  /// 0-indexed byte offset from start of input.
  int get offset => _.offset;

  /// Formatted as `line:column (offset N)`.
  String format() => '$line:$column (offset $offset)';
}

/// A contiguous range in source text, from [start] (inclusive) to [end]
/// (exclusive).
///
/// Extension type over a pair of [Location]s — zero runtime cost.
extension type const Span._(({Location start, Location end}) _) {
  /// Creates a [Span] with named parameters.
  const Span({required Location start, required Location end})
      : _ = (start: start, end: end);

  /// The start of this span (inclusive).
  Location get start => _.start;

  /// The end of this span (exclusive).
  Location get end => _.end;

  /// Formatted as `start..end`.
  String format() => '${start.format()}..${end.format()}';
}
