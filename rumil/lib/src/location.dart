/// Source position and span types.
library;

/// A position in source text.
///
/// Line and column are computed lazily from offset and input string.
/// `.line` walks forward over `[0, offset)`; `.column` walks backward
/// from `offset` to the previous newline (so it terminates early in
/// the common case). [format] uses a single forward walk that
/// produces both at once. Callers that resolve many positions against
/// the same source should use [LineIndex] for O(log n) lookups
/// instead of O(offset) walks.
///
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
  ///
  /// Forward walk over `[0, offset)` counting `\n`. O(offset).
  int get line {
    var n = 1;
    for (var i = 0; i < offset; i++) {
      if (_input.codeUnitAt(i) == 0x0A) n++;
    }
    return n;
  }

  /// 1-indexed column number.
  ///
  /// Backward walk from `offset - 1` until a `\n` is found or the
  /// start of input is reached. O(column) — stops at the previous
  /// newline rather than walking the whole input.
  int get column {
    var col = 1;
    for (var i = offset - 1; i >= 0; i--) {
      if (_input.codeUnitAt(i) == 0x0A) break;
      col++;
    }
    return col;
  }

  /// Formats as `line:column (offset N)`.
  ///
  /// Single forward walk that produces both line and column,
  /// avoiding the two-walk cost of reading the getters separately.
  String format() {
    var lineNum = 1;
    var lastNewline = -1;
    for (var i = 0; i < offset; i++) {
      if (_input.codeUnitAt(i) == 0x0A) {
        lineNum++;
        lastNewline = i;
      }
    }
    final col = offset - lastNewline;
    return '$lineNum:$col (offset $offset)';
  }

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

/// A [Location] with precomputed line and column.
///
/// Constructed via [LineIndex.locationAt] when an index is in scope.
/// Identical externally to a plain [Location], but `.line` and
/// `.column` are O(1) instead of O(n) and O(column) respectively.
final class PrecomputedLocation implements Location {
  @override
  final String _input;

  @override
  final int offset;

  @override
  final int line;

  @override
  final int column;

  /// Creates a location with all fields known up front.
  ///
  /// Internal API. End users should call [LineIndex.locationAt]
  /// instead of constructing this directly.
  const PrecomputedLocation(this._input, this.offset, this.line, this.column);

  @override
  String format() => '$line:$column (offset $offset)';

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
