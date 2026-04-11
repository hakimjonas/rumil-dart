/// Memoization infrastructure for the Warth seed-growth algorithm.
library;

import 'result.dart';

/// Identity-based memoization key with phantom type parameters.
///
/// Each [rule] call creates a unique instance. Identity is by reference.
extension type const MemoKey<E, A>._(
  /// The identity object used for reference-based memo table lookups.
  Object
  id
) {
  /// Creates a new unique key.
  factory MemoKey() => const MemoKey._(Object());
}

/// Entry in the full memo table.
final class MemoEntry {
  /// The cached parse result.
  final Object? result;

  /// The input position after this parse.
  final int endPos;

  /// Creates a memo entry.
  const MemoEntry(this.result, this.endPos);
}

/// Entry in the simple memo table.
final class SimpleCacheEntry {
  /// The cached parse result.
  final Object result;

  /// The input position after this parse.
  final int endPos;

  /// Creates a cache entry.
  const SimpleCacheEntry(this.result, this.endPos);
}

/// Head of a left-recursive cycle.
final class LRHead {
  /// The rule that started the cycle.
  final Object rule;

  /// Rules involved in this cycle.
  final Set<Object> involvedSet;

  /// Rules still to evaluate in the current growth iteration.
  Set<Object> evalSet;

  /// Creates an LR head.
  LRHead(this.rule, this.involvedSet, this.evalSet);
}

/// Left-recursion marker in the memo table.
final class LR {
  /// The current seed result for the left-recursive rule.
  Object seed;

  /// The rule being evaluated.
  final Object rule;

  /// The head of the cycle, if detected.
  LRHead? head;

  /// Creates an LR marker.
  LR({required this.seed, required this.rule, this.head});
}

/// Memo table slot: either an [LR] marker or a cached [MemoEntry].
sealed class MemoSlot {}

/// Slot containing an LR marker.
final class MemoSlotLR extends MemoSlot {
  /// The left-recursion marker.
  final LR lr;

  /// Creates an LR slot.
  MemoSlotLR(this.lr);
}

/// Slot containing a cached result.
final class MemoSlotEntry extends MemoSlot {
  /// The cached entry.
  final MemoEntry entry;

  /// Creates an entry slot.
  MemoSlotEntry(this.entry);
}

/// Memoization table with left-recursion support.
final class MemoTable {
  final Map<(Object, int), MemoSlot> _table = {};

  /// Store a result for [key] at [pos].
  void put<E, A>(MemoKey<E, A> key, int pos, Result<E, A> result, int endPos) {
    _table[(key.id, pos)] = MemoSlotEntry(MemoEntry(result, endPos));
  }

  /// Store an LR marker for [key] at [pos].
  void putLR<E, A>(MemoKey<E, A> key, int pos, LR lr) {
    _table[(key.id, pos)] = MemoSlotLR(lr);
  }

  /// Get the raw slot (LR or Entry) for [key] at [pos].
  MemoSlot? getRaw<E, A>(MemoKey<E, A> key, int pos) => _table[(key.id, pos)];

  /// Get the cached result for [key] at [pos], or null.
  Result<E, A>? getResult<E, A>(MemoKey<E, A> key, int pos) {
    final slot = _table[(key.id, pos)];
    if (slot case MemoSlotEntry(:final entry)) {
      return entry.result as Result<E, A>?;
    }
    return null;
  }

  /// Get the end position for [key] at [pos], or null.
  int? getEndPos<E, A>(MemoKey<E, A> key, int pos) {
    final slot = _table[(key.id, pos)];
    if (slot case MemoSlotEntry(:final entry)) return entry.endPos;
    return null;
  }

  /// True if a result is cached for [key] at [pos].
  bool contains<E, A>(MemoKey<E, A> key, int pos) =>
      _table.containsKey((key.id, pos));
}

/// Simple memoization table (no LR support, faster cache hits).
final class SimpleMemoTable {
  final Map<(Object, int), SimpleCacheEntry> _table = {};

  /// Store a result for [key] at [pos].
  void put<E, A>(MemoKey<E, A> key, int pos, Result<E, A> result, int endPos) {
    _table[(key.id, pos)] = SimpleCacheEntry(result, endPos);
  }

  /// Get the cached result for [key] at [pos], or null.
  Result<E, A>? getResult<E, A>(MemoKey<E, A> key, int pos) {
    final entry = _table[(key.id, pos)];
    return entry?.result as Result<E, A>?;
  }

  /// Get the raw cache entry for [key] at [pos], or null.
  SimpleCacheEntry? getEntry<E, A>(MemoKey<E, A> key, int pos) =>
      _table[(key.id, pos)];
}
