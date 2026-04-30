/// Source position and span types.
library;

/// A position in source text.
///
/// Line and column are computed lazily from offset and input string.
/// Offset is 0-indexed from start of input.
final class Location {
  final String _input;

  /// 0-indexed byte offset from start of input.
  final int offset;

  /// Creates a location at [offset] within the given input string.
  const Location(this._input, this.offset);

  /// The start of input: line 1, column 1, offset 0.
  static const zero = _ZeroLocation();

  /// 1-indexed line number.
  int get line {
    var n = 1;
    for (var i = 0; i < offset; i++) {
      if (_input.codeUnitAt(i) == 0x0A) n++;
    }
    return n;
  }

  /// 1-indexed column number.
  int get column {
    var col = 1;
    for (var i = offset - 1; i >= 0; i--) {
      if (_input.codeUnitAt(i) == 0x0A) break;
      col++;
    }
    return col;
  }

  /// Formats as `line:column (offset N)`.
  String format() => '$line:$column (offset $offset)';

  @override
  String toString() => format();
}

/// Sentinel for offset 0 — avoids requiring an input string.
final class _ZeroLocation implements Location {
  const _ZeroLocation();

  @override
  String get _input => '';

  @override
  int get offset => 0;

  @override
  int get line => 1;

  @override
  int get column => 1;

  @override
  String format() => '1:1 (offset 0)';

  @override
  String toString() => format();
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
