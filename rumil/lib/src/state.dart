/// Mutable parser state — the one controlled imperative shell.
///
/// [ParserState] tracks position (offset, line, column), provides
/// save/restore for backtracking, and holds the memoization tables
/// and left-recursion tracking structures.
///
/// All mutation is encapsulated here. Parser descriptions ([Parser])
/// are pure and immutable; only the interpreter mutates state.
library;

import 'location.dart';
import 'memo.dart';

/// Snapshot of parser position for backtracking.
///
/// A plain record — immutable, structural, no class overhead.
typedef Snapshot = ({int offset, int line, int column});

/// Mutable state carried through a parse.
///
/// Tracks input position and hosts the memoization tables.
/// Created via [ParserState.new] or the top-level [parserState] function.
final class ParserState {
  /// The input string being parsed.
  final String input;

  int _offset;
  int _line;
  int _column;

  /// Full memo table with LR support. Lazily created.
  late final MemoTable memo = MemoTable();

  /// Simple cache for non-LR parsers. Lazily created.
  late final SimpleMemoTable simpleCache = SimpleMemoTable();

  /// Stack tracking left-recursive rule invocations.
  late final List<LR> lrStack = [];

  /// Map from input position to the head of a left-recursive cycle.
  late final Map<int, LRHead> heads = {};

  /// Creates parser state for [input], starting at line 1, column 1.
  ParserState(this.input)
      : _offset = 0,
        _line = 1,
        _column = 1;

  // ---- Position accessors ----

  /// Current 0-indexed character offset.
  int get offset => _offset;

  /// Current 1-indexed line number.
  int get line => _line;

  /// Current 1-indexed column number.
  int get column => _column;

  /// Current [Location] (line, column, offset).
  Location get location => Location(line: _line, column: _column, offset: _offset);

  /// Whether the input is fully consumed.
  bool get atEnd => _offset >= input.length;

  /// Whether there is a character available at the current position.
  bool get hasChar => _offset < input.length;

  /// The character at the current position.
  ///
  /// Only call when [hasChar] is `true`.
  String get currentChar => input[_offset];

  /// The remaining unconsumed input.
  String get remaining => input.substring(_offset);

  /// Extract a substring from the input.
  String slice(int start, int end) => input.substring(start, end);

  // ---- Position manipulation ----

  /// Advance one character, updating line/column tracking.
  void advance() {
    if (!atEnd) {
      if (input[_offset] == '\n') {
        _line += 1;
        _column = 1;
      } else {
        _column += 1;
      }
      _offset += 1;
    }
  }

  /// Advance [n] characters.
  void advanceN(int n) {
    for (var i = 0; i < n; i++) {
      advance();
    }
  }

  /// Advance by a known string in O(1) for newline-free strings.
  ///
  /// [s] must match the input at the current position. This is an
  /// optimization for [StringMatch] where we know the exact content.
  void advanceByString(String s) {
    final len = s.length;
    _offset += len;
    final nlIdx = s.indexOf('\n');
    if (nlIdx < 0) {
      _column += len;
    } else {
      var newlines = 0;
      for (var i = 0; i < len; i++) {
        if (s[i] == '\n') newlines++;
      }
      _line += newlines;
      _column = len - s.lastIndexOf('\n');
    }
  }

  // ---- Save / Restore (backtracking) ----

  /// Save the current position as a [Snapshot].
  Snapshot save() => (offset: _offset, line: _line, column: _column);

  /// Restore position from a [Snapshot].
  void restore(Snapshot snapshot) {
    _offset = snapshot.offset;
    _line = snapshot.line;
    _column = snapshot.column;
  }

  /// Restore just the offset (for memo table cached end positions).
  void restoreTo(int offset, int line, int column) {
    _offset = offset;
    _line = line;
    _column = column;
  }
}
