/// Deep equality helpers for ADT collection fields.
///
/// Exported as part of `rumil` core because both green-tree machinery and
/// the format ASTs in `rumil_parsers` need them. Keeping one canonical
/// source avoids drift between the two layers.
library;

/// Deep equality for lists.
bool listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Deep equality for maps.
bool mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key) || a[key] != b[key]) return false;
  }
  return true;
}

/// Deep equality for sets.
bool setEquals<T>(Set<T> a, Set<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final element in a) {
    if (!b.contains(element)) return false;
  }
  return true;
}

/// Combined hash for a list of values.
int listHash<T>(List<T> items) => Object.hashAll(items);

/// Combined hash for a map's entries.
int mapHash<K, V>(Map<K, V> m) =>
    Object.hashAll(m.entries.map((e) => Object.hash(e.key, e.value)));

/// Combined hash for a set's elements (order-insensitive).
int setHash<T>(Set<T> s) => Object.hashAllUnordered(s);
