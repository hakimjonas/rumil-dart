/// Source position and span types.
library;

/// A position in source text.
///
/// Line and column are 1-indexed. Offset is 0-indexed from start of input.
/// Zero-cost extension type over a named record.
extension type const Location._(({int line, int column, int offset}) _) {
  const Location({required int line, required int column, required int offset})
    : _ = (line: line, column: column, offset: offset);

  static const zero = Location(line: 1, column: 1, offset: 0);

  int get line => _.line;
  int get column => _.column;
  int get offset => _.offset;

  String format() => '$line:$column (offset $offset)';
}

/// A contiguous range in source text from [start] to [end].
///
/// Zero-cost extension type over a pair of [Location]s.
extension type const Span._(({Location start, Location end}) _) {
  const Span({required Location start, required Location end})
    : _ = (start: start, end: end);

  Location get start => _.start;
  Location get end => _.end;

  String format() => '${start.format()}..${end.format()}';
}
