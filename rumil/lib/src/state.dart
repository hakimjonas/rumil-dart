/// Mutable parser state: input, position, line/column tracking, memo tables.
library;

import 'location.dart';
import 'memo.dart';

/// Snapshot of parser position for backtracking.
typedef Snapshot = ({int offset, int line, int column});

/// Mutable state carried through a parse.
final class ParserState {
  /// The full input string.
  final String input;

  int _offset;
  int _line;
  int _column;

  /// Memo table for left-recursion-enabled parsers.
  late final MemoTable memo = MemoTable();

  /// Memo table for simple (non-LR) memoized parsers.
  late final SimpleMemoTable simpleCache = SimpleMemoTable();

  /// Stack for tracking left-recursive cycles.
  late final List<LR> lrStack = [];

  /// Active LR heads by position.
  late final Map<int, LRHead> heads = {};

  /// Creates state for parsing [input].
  ParserState(this.input) : _offset = 0, _line = 1, _column = 1;

  /// Current byte offset (0-indexed).
  int get offset => _offset;

  /// Current line number (1-indexed).
  int get line => _line;

  /// Current column number (1-indexed).
  int get column => _column;

  /// Current position as a [Location].
  Location get location =>
      Location(line: _line, column: _column, offset: _offset);

  /// True if all input has been consumed.
  bool get atEnd => _offset >= input.length;

  /// True if there is at least one character remaining.
  bool get hasChar => _offset < input.length;

  /// The character at the current position.
  String get currentChar => input[_offset];

  /// The unconsumed portion of input.
  String get remaining => input.substring(_offset);

  /// Extract a substring from [start] to [end].
  String slice(int start, int end) => input.substring(start, end);

  /// Advance by one character, updating line/column.
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

  /// Advance by [n] characters.
  void advanceN(int n) {
    for (var i = 0; i < n; i++) {
      advance();
    }
  }

  /// Advance by a known string (O(1) for newline-free strings).
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

  /// Save current position for later backtracking via [restore].
  Snapshot save() => (offset: _offset, line: _line, column: _column);

  /// Restore position from a previously saved [snapshot].
  void restore(Snapshot snapshot) {
    _offset = snapshot.offset;
    _line = snapshot.line;
    _column = snapshot.column;
  }

  /// Restore to an explicit position.
  void restoreTo(int offset, int line, int column) {
    _offset = offset;
    _line = line;
    _column = column;
  }
}
