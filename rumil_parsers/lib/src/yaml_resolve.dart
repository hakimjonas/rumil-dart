/// Anchor and alias resolution for YAML ASTs.
library;

import 'ast/yaml.dart';

/// Resolve all anchors and aliases in a YAML value.
///
/// Replaces [YamlAlias] nodes with the value defined by the corresponding
/// [YamlAnchor]. Handles merge keys (`<<: *name`) by merging aliased
/// mapping entries into the current mapping.
///
/// Throws [StateError] if an alias references an undefined anchor.
YamlValue resolveAnchors(YamlValue value) {
  final anchors = <String, YamlValue>{};
  return _resolve(value, anchors);
}

YamlValue _resolve(YamlValue value, Map<String, YamlValue> anchors) =>
    switch (value) {
      YamlAnchor(:final name, :final value) => () {
        final resolved = _resolve(value, anchors);
        anchors[name] = resolved;
        return resolved;
      }(),
      YamlAlias(:final name) =>
        anchors[name] ?? (throw StateError('Undefined YAML alias: *$name')),
      YamlSequence(:final elements) => YamlSequence([
        for (final e in elements) _resolve(e, anchors),
      ]),
      YamlMapping(:final pairs, :final keyAnchors, :final aliasKeys) =>
        _resolveMapping(pairs, anchors, keyAnchors, aliasKeys),
      _ => value,
    };

YamlValue _resolveMapping(
  Map<String, YamlValue> pairs,
  Map<String, YamlValue> anchors,
  Map<String, String> keyAnchors,
  Set<String> aliasKeys,
) {
  // Register key anchors before resolving values so aliases within the
  // same mapping can reference keys defined earlier in the mapping.
  for (final MapEntry(:key, :value) in keyAnchors.entries) {
    anchors[key] = YamlString(value);
  }

  final result = <String, YamlValue>{};

  for (final MapEntry(:key, :value) in pairs.entries) {
    // Resolve alias keys: the key string is the alias name, replace with
    // the resolved anchor's string value.
    final resolvedKey =
        aliasKeys.contains(key)
            ? switch (anchors[key]) {
              YamlString(:final value) => value,
              _ => key,
            }
            : key;
    if (resolvedKey == '<<') {
      // Merge key: merge aliased mapping entries.
      final resolved = _resolve(value, anchors);
      switch (resolved) {
        case YamlMapping(:final pairs):
          // Existing keys take precedence over merged keys.
          for (final MapEntry(:key, :value) in pairs.entries) {
            result.putIfAbsent(key, () => value);
          }
        case YamlSequence(:final elements):
          // Multiple merges: <<: [*a, *b] — merge in order.
          for (final element in elements) {
            if (element case YamlMapping(:final pairs)) {
              for (final MapEntry(:key, :value) in pairs.entries) {
                result.putIfAbsent(key, () => value);
              }
            }
          }
        default:
          result[resolvedKey] = resolved;
      }
    } else {
      result[resolvedKey] = _resolve(value, anchors);
    }
  }

  return YamlMapping(result);
}
