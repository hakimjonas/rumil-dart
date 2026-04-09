/// Memoization infrastructure for the Warth seed-growth algorithm.
library;

import 'result.dart';

/// Identity-based memoization key with phantom type parameters.
///
/// Each [rule] call creates a unique instance. Identity is by reference.
extension type const MemoKey<E, A>._(Object id) {
  factory MemoKey() => const MemoKey._(Object());
}

/// Entry in the full memo table.
final class MemoEntry {
  final Object? result;
  final int endPos;
  const MemoEntry(this.result, this.endPos);
}

/// Entry in the simple memo table.
final class SimpleCacheEntry {
  final Object result;
  final int endPos;
  const SimpleCacheEntry(this.result, this.endPos);
}

/// Head of a left-recursive cycle.
final class LRHead {
  final Object rule;
  final Set<Object> involvedSet;
  Set<Object> evalSet;
  LRHead(this.rule, this.involvedSet, this.evalSet);
}

/// Left-recursion marker in the memo table.
final class LR {
  Object seed;
  final Object rule;
  LRHead? head;
  LR({required this.seed, required this.rule, this.head});
}

/// Memo table slot: either an [LR] marker or a cached [MemoEntry].
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
final class MemoTable {
  final Map<(Object, int), MemoSlot> _table = {};

  void put<E, A>(MemoKey<E, A> key, int pos, Result<E, A> result, int endPos) {
    _table[(key.id, pos)] = MemoSlotEntry(MemoEntry(result, endPos));
  }

  void putLR<E, A>(MemoKey<E, A> key, int pos, LR lr) {
    _table[(key.id, pos)] = MemoSlotLR(lr);
  }

  MemoSlot? getRaw<E, A>(MemoKey<E, A> key, int pos) => _table[(key.id, pos)];

  Result<E, A>? getResult<E, A>(MemoKey<E, A> key, int pos) {
    final slot = _table[(key.id, pos)];
    if (slot case MemoSlotEntry(:final entry)) {
      return entry.result as Result<E, A>?;
    }
    return null;
  }

  int? getEndPos<E, A>(MemoKey<E, A> key, int pos) {
    final slot = _table[(key.id, pos)];
    if (slot case MemoSlotEntry(:final entry)) return entry.endPos;
    return null;
  }

  bool contains<E, A>(MemoKey<E, A> key, int pos) =>
      _table.containsKey((key.id, pos));
}

/// Simple memoization table (no LR, ~50% faster cache hits).
final class SimpleMemoTable {
  final Map<(Object, int), SimpleCacheEntry> _table = {};

  void put<E, A>(MemoKey<E, A> key, int pos, Result<E, A> result, int endPos) {
    _table[(key.id, pos)] = SimpleCacheEntry(result, endPos);
  }

  Result<E, A>? getResult<E, A>(MemoKey<E, A> key, int pos) {
    final entry = _table[(key.id, pos)];
    return entry?.result as Result<E, A>?;
  }

  SimpleCacheEntry? getEntry<E, A>(MemoKey<E, A> key, int pos) =>
      _table[(key.id, pos)];
}
