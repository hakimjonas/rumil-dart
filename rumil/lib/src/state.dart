/// Mutable parser state: input, position, line/column tracking, memo tables.
library;

import 'green_cache.dart';
import 'location.dart';
import 'memo.dart';

/// Mutable state carried through a parse.
///
/// Design rule: this is the one mutable object in the parsing pipeline.
/// Its lifetime is exactly one `parser.run(input)` call — it is allocated
/// in `run()`, threaded through the interpreter, and discarded on return.
/// It never escapes to user code, never crosses isolate boundaries, and
/// is never shared between concurrent parses. Parsers themselves
/// (`Parser<E, A>` ADT) and results (`Result<E, A>` ADT) are immutable.
///
/// New mutable state added here must respect that lifetime: it lives
/// for one parse, observed only by the interpreter, and is discarded
/// when `run()` returns.
final class ParserState {
  /// The full input string.
  final String input;

  int _offset;

  /// Memo table for left-recursion-enabled parsers.
  late final MemoTable memo = MemoTable();

  /// Memo table for simple (non-LR) memoized parsers.
  late final SimpleMemoTable simpleCache = SimpleMemoTable();

  /// Stack for tracking left-recursive cycles.
  late final List<LR> lrStack = [];

  /// Active LR heads by position.
  late final Map<int, LRHead> heads = {};

  /// Parse-scoped hash-cons cache for `InternedGreen`. The cache is
  /// non-generic (greens stored at `GreenNode<Object?, Object?>`, [intern]
  /// a generic method), so [ParserState] holds it without being
  /// parameterised on a language's `(Tok, Syn)` — which would cascade
  /// through every interpreter signature. Created lazily; parses with no
  /// interning pay nothing.
  late final GreenCache greenCache = GreenCache();

  /// Creates state for parsing [input].
  ParserState(this.input) : _offset = 0;

  /// Current byte offset (0-indexed).
  int get offset => _offset;

  /// Current position as a [Location].
  Location get location => Location(input, _offset);

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

  /// Advance by one character.
  void advance() {
    _offset++;
  }

  /// Advance by [n] characters.
  void advanceN(int n) {
    _offset += n;
  }

  /// Advance by a known string.
  void advanceByString(String s) {
    _offset += s.length;
  }

  /// Save current position for later backtracking via [restore].
  int save() => _offset;

  /// Restore position from a previously saved offset.
  void restore(int snapshot) {
    _offset = snapshot;
  }

  /// Restore to an explicit position.
  void restoreTo(int offset) {
    _offset = offset;
  }
}
