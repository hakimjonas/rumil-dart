/// Anchor and alias resolution for YAML ASTs.
///
/// Resolution is an iterative depth-first walk driven by an explicit worklist
/// of thunks, not a recursive descent, so a deeply-nested document resolves
/// without overflowing the Dart call stack. The worklist preserves the exact
/// traversal order of the original recursive implementation, which matters
/// because anchor resolution is *stateful*:
///
/// - `&anchor value` registers its name **post-order** — after its subtree
///   resolves — so a deferred continuation runs the registration once the
///   child has fully drained.
/// - Mapping key-anchors register **pre-order**, before any value resolves.
/// - Mapping pairs are processed **strictly left-to-right**, each fully
///   resolved and applied to the result before the next begins, so merge-key
///   (`<<`) `putIfAbsent` precedence and alias-key lookups see exactly the
///   `anchors`/`result` state they would under recursion.
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
  final stack = <void Function()>[];

  // Mutually recursive in *scheduling* only: every task body runs in the
  // drain loop at the bottom, so there is no native-stack recursion here.
  late final void Function(YamlValue, void Function(YamlValue)) schedule;

  void resolveMapping(YamlMapping node, void Function(YamlValue) sink) {
    // Register key anchors before resolving any value, so aliases within the
    // same mapping can reference keys defined earlier (pre-order, as in the
    // recursive version).
    for (final MapEntry(:key, :value) in node.keyAnchors.entries) {
      anchors[key] = YamlString(value);
    }

    final result = <String, YamlValue>{};
    sink(YamlMapping(result));

    final entries = node.pairs.entries.toList();

    // Process pairs strictly sequentially: each pair resolves its value, then
    // applies to `result`, then schedules the next pair. This keeps the
    // `anchors`/`result` state at each step identical to the recursive
    // left-to-right fold, which `<<` putIfAbsent precedence depends on.
    late final void Function(int) scheduleFrom;
    scheduleFrom = (int i) {
      if (i >= entries.length) return;
      final MapEntry(:key, :value) = entries[i];

      // Resolve alias keys: the key string is the alias name, replaced with
      // the resolved anchor's string value. Computed here — after prior pairs
      // have resolved — exactly as in the recursive loop.
      final resolvedKey =
          node.aliasKeys.contains(key)
              ? switch (anchors[key]) {
                YamlString(:final value) => value,
                _ => key,
              }
              : key;

      final holder = <YamlValue>[const YamlNull()];

      // Push in reverse of desired run order (LIFO): next pair, then apply,
      // then resolve-value on top so it drains first.
      stack.add(() => scheduleFrom(i + 1));
      stack.add(() {
        final resolved = holder[0];
        if (resolvedKey == '<<') {
          // Merge key: merge aliased mapping entries. Existing keys take
          // precedence over merged keys (putIfAbsent).
          switch (resolved) {
            case YamlMapping(:final pairs):
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
          result[resolvedKey] = resolved;
        }
      });
      schedule(value, (r) => holder[0] = r);
    };
    scheduleFrom(0);
  }

  schedule = (YamlValue node, void Function(YamlValue) sink) {
    stack.add(() {
      switch (node) {
        case YamlAnchor(:final name, :final value):
          // Resolve the child, then register the anchor post-order and pass
          // the resolved value on.
          final holder = <YamlValue>[const YamlNull()];
          stack.add(() {
            final resolved = holder[0];
            anchors[name] = resolved;
            sink(resolved);
          });
          schedule(value, (r) => holder[0] = r);
        case YamlAlias(:final name):
          final resolved = anchors[name];
          if (resolved == null) {
            throw StateError('Undefined YAML alias: *$name');
          }
          sink(resolved);
        case YamlSequence(:final elements):
          final list = List<YamlValue>.filled(
            elements.length,
            const YamlNull(),
          );
          sink(YamlSequence(list));
          // Reverse-push so elements resolve left-to-right (each subtree
          // fully drains before the next), preserving anchor-registration
          // order.
          for (var i = elements.length - 1; i >= 0; i--) {
            final idx = i;
            schedule(elements[idx], (r) => list[idx] = r);
          }
        case YamlMapping():
          resolveMapping(node, sink);
        case YamlNull() ||
            YamlBool() ||
            YamlInteger() ||
            YamlFloat() ||
            YamlString():
          sink(node);
      }
    });
  };

  final rootHolder = <YamlValue>[const YamlNull()];
  schedule(value, (r) => rootHolder[0] = r);
  while (stack.isNotEmpty) {
    stack.removeLast()();
  }
  return rootHolder[0];
}
