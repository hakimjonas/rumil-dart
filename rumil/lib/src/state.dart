/// Mutable parser state: input, position, line/column tracking, memo tables.
library;

import 'location.dart';
import 'memo.dart';

/// Snapshot of parser position for backtracking.
typedef Snapshot = ({int offset, int line, int column});

/// Mutable state carried through a parse.
final class ParserState {
  final String input;

  int _offset;
  int _line;
  int _column;

  late final MemoTable memo = MemoTable();
  late final SimpleMemoTable simpleCache = SimpleMemoTable();
  late final List<LR> lrStack = [];
  late final Map<int, LRHead> heads = {};

  ParserState(this.input) : _offset = 0, _line = 1, _column = 1;

  int get offset => _offset;
  int get line => _line;
  int get column => _column;
  Location get location =>
      Location(line: _line, column: _column, offset: _offset);

  bool get atEnd => _offset >= input.length;
  bool get hasChar => _offset < input.length;
  String get currentChar => input[_offset];
  String get remaining => input.substring(_offset);

  String slice(int start, int end) => input.substring(start, end);

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

  Snapshot save() => (offset: _offset, line: _line, column: _column);

  void restore(Snapshot snapshot) {
    _offset = snapshot.offset;
    _line = snapshot.line;
    _column = snapshot.column;
  }

  void restoreTo(int offset, int line, int column) {
    _offset = offset;
    _line = line;
    _column = column;
  }
}
