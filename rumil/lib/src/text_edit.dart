/// A text edit: replace the half-open range `[startOffset, endOffset)` of a
/// source string with [newText].
///
/// The unit of incremental reparse. An LSP `didChange` becomes a [TextEdit];
/// the incremental parser uses it to find and reparse only the affected
/// region. Examples:
///
/// ```dart
/// TextEdit.insert(5, 'x');        // insert "x" at offset 5
/// TextEdit.delete(10, 15);        // delete offsets 10..15
/// TextEdit.replace(0, 3, 'bar');  // replace offsets 0..3 with "bar"
/// ```
library;

/// An edit replacing `[startOffset, endOffset)` with [newText].
final class TextEdit {
  /// Start of the replaced range (inclusive, 0-indexed).
  final int startOffset;

  /// End of the replaced range (exclusive, 0-indexed).
  final int endOffset;

  /// The text inserted in place of the replaced range.
  final String newText;

  /// Creates an edit replacing `[startOffset, endOffset)` with [newText].
  ///
  /// Asserts `0 <= startOffset <= endOffset`. An insertion is the degenerate
  /// case `startOffset == endOffset`.
  TextEdit(this.startOffset, this.endOffset, this.newText)
    : assert(startOffset >= 0, 'startOffset must be non-negative'),
      assert(endOffset >= startOffset, 'endOffset must be >= startOffset');

  /// An insertion of [text] at [offset] (deletes nothing).
  factory TextEdit.insert(int offset, String text) =>
      TextEdit(offset, offset, text);

  /// A deletion of `[startOffset, endOffset)` (inserts nothing).
  factory TextEdit.delete(int startOffset, int endOffset) =>
      TextEdit(startOffset, endOffset, '');

  /// A replacement of `[startOffset, endOffset)` with [newText]. Alias for
  /// the default constructor, for symmetry with [insert] / [delete].
  factory TextEdit.replace(int startOffset, int endOffset, String newText) =>
      TextEdit(startOffset, endOffset, newText);

  /// Number of characters deleted by this edit.
  int get deleteLength => endOffset - startOffset;

  /// Number of characters inserted by this edit.
  int get insertLength => newText.length;

  /// Net change in document length: positive grows, negative shrinks.
  int get lengthDelta => insertLength - deleteLength;

  /// True if this edit only inserts (deletes nothing).
  bool get isInsertion => startOffset == endOffset;

  /// True if this edit only deletes (inserts nothing).
  bool get isDeletion => newText.isEmpty;

  /// True if this edit both deletes and inserts.
  bool get isReplacement => deleteLength > 0 && insertLength > 0;

  /// Apply this edit to [source], returning the new source.
  ///
  /// Asserts `endOffset <= source.length`.
  String apply(String source) {
    assert(
      endOffset <= source.length,
      'endOffset ($endOffset) exceeds source length (${source.length})',
    );
    return source.substring(0, startOffset) +
        newText +
        source.substring(endOffset);
  }

  /// Whether this edit overlaps or abuts the range `[rangeStart, rangeEnd)`.
  bool affects(int rangeStart, int rangeEnd) =>
      startOffset < rangeEnd && endOffset > rangeStart;

  /// Map a pre-edit [offset] to its position in the post-edit document.
  ///
  /// Offsets before the edit are unchanged; offsets inside the deleted range
  /// collapse to [startOffset]; offsets after shift by [lengthDelta].
  int adjustOffset(int offset) {
    if (offset <= startOffset) return offset;
    if (offset < endOffset) return startOffset;
    return offset + lengthDelta;
  }

  @override
  String toString() {
    if (isInsertion) {
      return 'TextEdit.insert($startOffset, ${_preview(newText)})';
    }
    if (isDeletion) {
      return 'TextEdit.delete($startOffset, $endOffset)';
    }
    return 'TextEdit.replace($startOffset, $endOffset, ${_preview(newText)})';
  }

  /// Compose [edits] into a sequence applicable left-to-right.
  ///
  /// [edits] must be sorted by [startOffset] and non-overlapping. Each edit's
  /// offsets are shifted by the net [lengthDelta] of all earlier edits, so
  /// the returned edits can be applied in order to a single evolving source.
  /// Asserts the non-overlap precondition.
  static List<TextEdit> compose(List<TextEdit> edits) {
    var delta = 0;
    final out = <TextEdit>[];
    for (var i = 0; i < edits.length; i++) {
      if (i > 0) {
        assert(
          edits[i - 1].endOffset <= edits[i].startOffset,
          'compose: edits must be sorted and non-overlapping',
        );
      }
      final e = edits[i];
      out.add(TextEdit(e.startOffset + delta, e.endOffset + delta, e.newText));
      delta += e.lengthDelta;
    }
    return out;
  }

  static String _preview(String s) {
    final escaped = s.replaceAll('\n', r'\n');
    return escaped.length > 20
        ? '"${escaped.substring(0, 20)}…"'
        : '"$escaped"';
  }
}
