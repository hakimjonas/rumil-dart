/// Deep equality helpers for AST collection fields.
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

/// Combined hash for a list of values.
int listHash<T>(List<T> items) => Object.hashAll(items);

/// Combined hash for a map's entries.
int mapHash<K, V>(Map<K, V> m) =>
    Object.hashAll(m.entries.map((e) => Object.hash(e.key, e.value)));
