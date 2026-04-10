/// Source position and span types.
library;

/// A position in source text.
///
/// Line and column are 1-indexed. Offset is 0-indexed from start of input.
extension type const Location._(({int line, int column, int offset}) _) {
  /// Creates a location at [line], [column], and byte [offset].
  const Location({required int line, required int column, required int offset})
    : _ = (line: line, column: column, offset: offset);

  /// The start of input: line 1, column 1, offset 0.
  static const zero = Location(line: 1, column: 1, offset: 0);

  /// 1-indexed line number.
  int get line => _.line;

  /// 1-indexed column number.
  int get column => _.column;

  /// 0-indexed byte offset from start of input.
  int get offset => _.offset;

  /// Formats as `line:column (offset N)`.
  String format() => '$line:$column (offset $offset)';
}

/// A contiguous range in source text from [start] to [end].
extension type const Span._(({Location start, Location end}) _) {
  /// Creates a span from [start] to [end].
  const Span({required Location start, required Location end})
    : _ = (start: start, end: end);

  /// The beginning of the span.
  Location get start => _.start;

  /// The end of the span.
  Location get end => _.end;

  /// Formats as `start..end`.
  String format() => '${start.format()}..${end.format()}';
}
