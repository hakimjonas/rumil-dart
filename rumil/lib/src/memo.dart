/// Memoization infrastructure for the Warth seed-growth algorithm.
///
/// [MemoKey] is a zero-cost extension type for identity-based memo keys.
/// [MemoTable] stores results keyed by (MemoKey, position) with LR support.
/// [SimpleMemoTable] is a faster cache for non-left-recursive parsers.
/// [LR] and [LRHead] track left-recursive cycles during parsing.
library;

import 'result.dart';

// ---------------------------------------------------------------------------
// MemoKey — identity-based, phantom-typed
// ---------------------------------------------------------------------------

/// A type-safe, identity-based memoization key.
///
/// Each call to [rule] creates a unique [MemoKey] instance. Identity is
/// determined by the underlying [Object] — two separately created keys
/// are always distinct, even if they have the same type parameters.
///
/// Type parameters [E] and [A] are phantom: erased at runtime, enforced
/// at compile time. This ensures that a key used to store a
/// `Result<ParseError, int>` can only retrieve a `Result<ParseError, int>`.
///
/// This is an extension type — zero allocation overhead for the wrapper.
extension type const MemoKey<E, A>._(Object id) {
  /// Creates a fresh unique memo key.
  factory MemoKey() => MemoKey._(Object());
}

// ---------------------------------------------------------------------------
// MemoEntry / SimpleCacheEntry — internal storage records
// ---------------------------------------------------------------------------

/// Entry in the full (LR-capable) memo table.
///
/// [result] is `null` when the entry is an LR marker being evaluated.
/// Type-erased to `Object?` for heterogeneous storage; type safety is
/// maintained by the [MemoKey] identity contract.
final class MemoEntry {
  final Object? result; // Result<Object, Object>? — type-erased
  final int endPos;
  const MemoEntry(this.result, this.endPos);
}

/// Entry in the simple (non-LR) memo table.
final class SimpleCacheEntry {
  final Object result; // Result<Object, Object> — type-erased
  final int endPos;
  const SimpleCacheEntry(this.result, this.endPos);
}

// ---------------------------------------------------------------------------
// LR / LRHead — left recursion tracking
// ---------------------------------------------------------------------------

/// Tracks the "head" of a left-recursive rule cycle.
///
/// Created when the interpreter detects that a memoized parser is being
/// called at the same position as an ongoing evaluation (cycle detected).
///
/// [rule] is the [MemoKey] identity that started the left recursion.
/// [involvedSet] tracks all rules participating in the cycle.
/// [evalSet] tracks rules that need re-evaluation during seed growth.
///
/// These sets are mutable because the seed-growth algorithm modifies them
/// as it discovers the full extent of the left-recursive cycle.
final class LRHead {
  final Object rule; // MemoKey identity
  final Set<Object> involvedSet;
  Set<Object> evalSet;
  LRHead(this.rule, this.involvedSet, this.evalSet);
}

/// Left recursion marker placed in the memo table during seed detection.
///
/// When the interpreter first enters a [Memo] parser at a position,
/// it plants an [LR] marker. If the same parser is reached again at the
/// same position, the marker signals a left-recursive cycle.
///
/// [seed] is the current seed result (initially a failure). During seed
/// growth, it is iteratively updated until no more progress is made.
///
/// Mutable fields are required by the Warth algorithm — the seed and head
/// are updated in place during the growth phase.
final class LR {
  Object seed; // Result<Object, Object> — type-erased
  final Object rule; // MemoKey identity
  LRHead? head;
  LR({required this.seed, required this.rule, this.head});
}

// ---------------------------------------------------------------------------
// MemoTable — full LR support
// ---------------------------------------------------------------------------

/// Sealed entry type: either an [LR] marker or a [MemoEntry] result.
sealed class MemoSlot {}

final class MemoSlotLR extends MemoSlot {
  final LR lr;
  MemoSlotLR(this.lr);
}

final class MemoSlotEntry extends MemoSlot {
  final MemoEntry entry;
  MemoSlotEntry(this.entry);
}

/// Memoization table with left-recursion support.
///
/// Stores parse results keyed by `(MemoKey identity, input position)`.
/// Internally type-erased — the [MemoKey] identity contract guarantees
/// that retrieval casts are safe.
///
/// The table stores [MemoSlot] values: either an [LR] marker (cycle
/// in progress) or a [MemoEntry] (cached result).
final class MemoTable {
  final Map<(Object, int), MemoSlot> _table = {};

  /// Store a cached result.
  void put<E, A>(
    MemoKey<E, A> key,
    int pos,
    Result<E, A> result,
    int endPos,
  ) {
    _table[(key.id, pos)] = MemoSlotEntry(MemoEntry(result, endPos));
  }

  /// Store an LR marker.
  void putLR<E, A>(MemoKey<E, A> key, int pos, LR lr) {
    _table[(key.id, pos)] = MemoSlotLR(lr);
  }

  /// Get the raw slot: [LR] marker or [MemoEntry].
  MemoSlot? getRaw<E, A>(MemoKey<E, A> key, int pos) =>
      _table[(key.id, pos)];

  /// Get a cached result, or `null` if not found or is an LR marker.
  ///
  /// SAFETY: The cast from `Object?` to `Result<E, A>` is safe because
  /// the same [MemoKey] instance is used for both [put] and [getResult].
  Result<E, A>? getResult<E, A>(MemoKey<E, A> key, int pos) {
    final slot = _table[(key.id, pos)];
    if (slot case MemoSlotEntry(:final entry)) {
      return entry.result as Result<E, A>?;
    }
    return null;
  }

  /// Get the end position for a cached entry.
  int? getEndPos<E, A>(MemoKey<E, A> key, int pos) {
    final slot = _table[(key.id, pos)];
    if (slot case MemoSlotEntry(:final entry)) {
      return entry.endPos;
    }
    return null;
  }

  /// Check if any entry (LR or result) exists at this key+position.
  bool contains<E, A>(MemoKey<E, A> key, int pos) =>
      _table.containsKey((key.id, pos));
}

// ---------------------------------------------------------------------------
// SimpleMemoTable — fast path for non-LR parsers
// ---------------------------------------------------------------------------

/// Simple memoization table for non-left-recursive parsers.
///
/// No LR overhead: direct result storage without [LR]/[MemoSlot] wrapping.
/// ~50% faster cache hits than the full LR path.
final class SimpleMemoTable {
  final Map<(Object, int), SimpleCacheEntry> _table = {};

  /// Store a cached result.
  void put<E, A>(
    MemoKey<E, A> key,
    int pos,
    Result<E, A> result,
    int endPos,
  ) {
    _table[(key.id, pos)] = SimpleCacheEntry(result, endPos);
  }

  /// Get a cached result.
  ///
  /// SAFETY: Cast is safe by MemoKey identity contract.
  Result<E, A>? getResult<E, A>(MemoKey<E, A> key, int pos) {
    final entry = _table[(key.id, pos)];
    return entry?.result as Result<E, A>?;
  }

  /// Get a cached entry (result + end position).
  SimpleCacheEntry? getEntry<E, A>(MemoKey<E, A> key, int pos) =>
      _table[(key.id, pos)];
}
