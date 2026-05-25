/// On-demand 1-indexed line/column resolution for byte offsets.
///
/// Builds a sorted array of every `\n` offset in the source in one
/// O(n) pass; subsequent [LineIndex.locationAt] queries run in
/// O(log n) via binary search.
///
/// Line-terminator policy. `\n` (U+000A) is the sole line terminator
/// for indexing purposes; `\r` (U+000D) is a regular character and
/// contributes to its line's column count. On CRLF input
/// (`"abc\r\ndef"`) the `\r` at offset 3 is column 4 of line 1, the
/// `\n` at offset 4 is column 5 of line 1, and the `d` at offset 5 is
/// column 1 of line 2. On CR-only input (legacy Mac Classic) every
/// character stays on line 1. Callers that want `\r\n` treated as a
/// single terminator, or that target lone-`\r` line endings, must
/// normalize at the editor or LSP boundary before building the index
/// — rumil does not normalize line endings internally.
///
/// Column encoding. Offsets are Dart `String` indexes, which are
/// UTF-16 code units. Columns are computed as
/// `offset - prevNewlineOffset`, so a supplementary-plane codepoint
/// encoded as a surrogate pair contributes two columns. This matches
/// the LSP default encoding (UTF-16) and the behavior clients get
/// when they use `document.offsetAt` in vscode-style APIs. Callers
/// that need Unicode-codepoint columns (or UTF-8 byte columns for
/// LSP clients that negotiated those encodings) must post-process
/// the returned [Location] against the source string; rumil does not
/// convert between encodings.
library;

import 'dart:typed_data';

import 'location.dart';

/// A precomputed index of newline offsets in a source document.
final class LineIndex {
  final String _source;
  final Uint32List _newlines;

  /// Builds an index over [source].
  ///
  /// Two passes: count newlines, then fill a right-sized
  /// [Uint32List] with their offsets.
  factory LineIndex(String source) {
    final len = source.length;
    var count = 0;
    for (var i = 0; i < len; i++) {
      if (source.codeUnitAt(i) == 0x0a) count++;
    }
    final newlines = Uint32List(count);
    var j = 0;
    for (var i = 0; i < len; i++) {
      if (source.codeUnitAt(i) == 0x0a) {
        newlines[j++] = i;
      }
    }
    return LineIndex._(source, newlines);
  }

  const LineIndex._(this._source, this._newlines);

  /// 1-indexed `(line, column, offset)` for [offset], returned as a
  /// [Location] with all fields precomputed.
  ///
  /// - `offset = 0` → `line: 1, column: 1, offset: 0`.
  /// - Negative offsets clamp to 0.
  /// - Offsets at or past the last newline resolve to their column on
  ///   the last line, computed as `offset - lastNewlineOffset`.
  ///
  /// Callers that need end-of-source clamping should clamp their
  /// input first.
  Location locationAt(int offset) {
    final clamped = offset < 0 ? 0 : offset;
    final prevNewlineIdx = _largestStrictlyLessThan(clamped);
    if (prevNewlineIdx < 0) {
      return PrecomputedLocation(_source, clamped, 1, clamped + 1);
    }
    final prevNewline = _newlines[prevNewlineIdx];
    return PrecomputedLocation(
      _source,
      clamped,
      prevNewlineIdx + 2,
      clamped - prevNewline,
    );
  }

  /// Returns a [Span] from [startOffset] to [endOffset] with both
  /// endpoints carrying real line/column.
  Span spanAt(int startOffset, int endOffset) =>
      Span(start: locationAt(startOffset), end: locationAt(endOffset));

  /// Binary search for the index of the largest entry strictly less
  /// than [value]. Returns -1 if no such entry exists.
  ///
  /// Equivalent to Scala's `Arrays.binarySearch` semantics:
  ///   - if [value] equals an entry at index `k`, the strictly-less
  ///     index is `k - 1`;
  ///   - if [value] would be inserted before index `k`, the
  ///     strictly-less index is `k - 1`.
  int _largestStrictlyLessThan(int value) {
    var lo = 0;
    var hi = _newlines.length;
    while (lo < hi) {
      final mid = (lo + hi) >>> 1;
      if (_newlines[mid] < value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    // lo is now the insertion point: smallest index with newlines[lo] >= value.
    return lo - 1;
  }
}
