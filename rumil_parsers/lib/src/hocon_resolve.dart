/// Iterative HOCON resolution engine.
///
/// Turns the source-shaped AST from `ast/hocon.dart` into a resolved
/// configuration: includes loaded and merged, substitutions looked up,
/// value concatenations combined, and duplicate keys merged.
///
/// ## Semantics (per the lightbend/config HOCON spec)
///
/// - **Look forward:** substitutions resolve against the final merged
///   tree, so forward references work.
/// - **Look back on self-reference:** when a substitution inside the
///   value assigned to path `P` targets `P` (or a path below it), it
///   resolves to the value `P` had *before* this assignment — possibly
///   nothing, which makes the substitution undefined. This is what
///   makes `path = ${path} [ /usr/bin ]` and `a += b` work.
/// - **Cycles fail fast:** mutual substitution cycles that lookback
///   cannot break throw [HoconResolveException], as do circular
///   includes.
/// - **Concatenation:** strings join (whitespace between parts is
///   preserved by the parser), objects merge, arrays concatenate;
///   mixing kinds is an error.
/// - **Optional substitutions (`${?p}`)** that stay undefined omit the
///   object field, drop the array element, or contribute nothing to a
///   concatenation.
/// - **Environment fallback:** a path missing from the tree is looked
///   up in [HoconConfig.environment] before being declared undefined.
///
/// ## Stack safety
///
/// Every stage — include loading, tree materialization, substitution
/// resolution, and the final AST round-trip — runs on an explicit
/// worklist of work items. No resolution step ever calls itself through
/// Dart's call stack, so resolution depth is bounded by heap, not by
/// stack. The only direct recursion is dotted-path navigation, whose
/// depth is the (small) length of a single path.
library;

import 'package:rumil/rumil.dart';

import 'ast/hocon.dart';
import 'hocon.dart' show parseHocon;

/// Configuration for [resolveHocon].
final class HoconConfig {
  /// Loads the raw text of an `include` resource, or returns null when
  /// the resource does not exist. Loaders are responsible for resolving
  /// relative paths; the resolver only tracks resource names for cycle
  /// detection.
  final String? Function(String resource)? includeLoader;

  /// Environment variables consulted when a substitution path is
  /// missing from the configuration tree, keyed by the dotted path as
  /// written (e.g. `HOME`).
  final Map<String, String>? environment;

  /// Creates a resolver configuration.
  const HoconConfig({this.includeLoader, this.environment});
}

/// Thrown when a HOCON document cannot be resolved: circular includes,
/// unresolvable substitutions, cyclic references, or invalid
/// concatenation kinds.
final class HoconResolveException implements Exception {
  /// The failure description.
  final String message;

  /// Creates the exception.
  HoconResolveException(this.message);

  @override
  String toString() => 'HoconResolveException: $message';
}

/// Sentinel delivered to sinks when an optional substitution fails to
/// resolve: object fields are removed, array elements skipped, and
/// concatenation parts dropped.
final class _Omitted {
  const _Omitted();
}

const _omitted = _Omitted();

/// Marker delivered by tree lookups that found no value.
const _notFound = _NotFound();

final class _NotFound {
  const _NotFound();
}

/// A value slot whose AST source contains a substitution or a
/// concatenation and therefore needs resolution.
final class _Pending {
  /// The unresolved AST value.
  final HoconValue source;

  /// Candidate lookup prefixes for substitution paths, tried in order.
  /// Normally just the empty prefix (paths are root-absolute). Content
  /// loaded through an include gets the include site's path as an extra
  /// prefix, tried first (the spec's "fixup" rule), with the path as
  /// written second.
  final List<List<String>> lookupPrefixes;

  /// Path of the slot this pending fills, when the pending came
  /// directly from an assignment (self-reference lookback applies).
  /// Null for pendings nested inside objects or arrays, which the spec
  /// treats as unbreakable cycles.
  List<String>? selfPath;

  /// The value previously in the slot, captured when the pending was
  /// placed. Only meaningful when [selfPath] is set.
  Object? previous;
  bool hasPrevious = false;

  /// Where to deliver the resolved value (installed on first resolve).
  void Function(Object?)? sink;

  /// Memoized resolution result.
  bool done = false;
  Object? resolved;

  /// The map or rebuilt list this pending will be delivered into, set
  /// by the resolution walk. Used to detect structurally
  /// self-containing values (`a : [${a}]`), where the substitution
  /// target is the very container the pending feeds.
  Object? container;

  /// Object-valued assignments committed onto this pending while it sat
  /// unresolved in the slot (later `key { ... }` after `key = ${...}`).
  /// They merge into the resolved value in source order; if the pending
  /// resolves to a non-object, the overlay replaces it (the later value
  /// wins).
  Map<String, Object?>? overlay;

  _Pending(this.source, this.lookupPrefixes);
}

/// Shared resolution context: the materialized tree root plus the work
/// bookkeeping. One instance per [resolveHocon] call.
final class _ResolveCtx {
  final HoconConfig config;

  /// The materialized tree; the lookup root.
  Object? tree;

  /// LIFO worklist of pending work items.
  final List<void Function()> work = [];

  /// Pendings currently being resolved, for cycle detection.
  final Set<_Pending> active = {};

  /// Stack of resource names currently being materialized, for include
  /// cycle detection.
  final List<String> activeIncludes = [];

  _ResolveCtx(this.config);

  /// Schedule [task] to run after everything already scheduled.
  void push(void Function() task) => work.add(task);
}

/// Resolve [root] into a fully-resolved [HoconValue]: no substitutions,
/// concatenations, or includes remain.
///
/// A root object resolves field-by-field; a root array resolves its
/// elements (substitutions inside a root array cannot navigate the
/// tree, since lookups walk objects only).
HoconValue resolveHocon(
  HoconValue root, {
  HoconConfig config = const HoconConfig(),
}) {
  final ctx = _ResolveCtx(config);
  ctx.tree = _materialize(root, ctx);
  _resolveTree(ctx);
  return _toHocon(ctx.tree);
}

// ---------------------------------------------------------------------------
// Stage 1: materialization (AST → mutable tree, includes loaded)
// ---------------------------------------------------------------------------

/// One materialization work item: convert [node] and deliver to [sink].
///
/// [objPath] is the path of the enclosing object — the base for dotted
/// key navigation and for nested objects. [includePrefix] is non-empty
/// when the node came from an included file, in which case
/// substitutions are additionally looked up under that prefix.
/// [include]/[targetMap] carry an include statement to load and merge.
final class _MatWork {
  final HoconValue node;
  final void Function(Object?) sink;
  final List<String> objPath;
  final List<String>? includePrefix;
  final List<String>? selfPath;
  final HoconInclude? include;
  final Map<String, Object?>? targetMap;

  _MatWork(
    this.node,
    this.sink, {
    required this.objPath,
    required this.includePrefix,
    this.selfPath,
    this.include,
    this.targetMap,
  });
}

Object? _materialize(HoconValue root, _ResolveCtx ctx) {
  Object? out;
  final stack = <_MatWork>[
    _MatWork(root, (v) => out = v, objPath: const [], includePrefix: null),
  ];
  while (stack.isNotEmpty) {
    _matStep(stack.removeLast(), stack, ctx);
  }
  return out;
}

void _matStep(_MatWork w, List<_MatWork> stack, _ResolveCtx ctx) {
  // Include statements are materialized as loads, not values.
  if (w.include != null) {
    _loadInclude(w, stack, ctx);
    return;
  }

  final node = w.node;
  switch (node) {
    case HoconNull():
      w.sink(null);
    case HoconBool(:final value):
      w.sink(value);
    case HoconInt(:final value):
      w.sink(value);
    case HoconDouble(:final value):
      w.sink(value);
    case HoconString(:final value):
      w.sink(value);

    case HoconSubstitution():
      w.sink(
        _Pending(node, _lookupPrefixes(w.includePrefix))..selfPath = w.selfPath,
      );

    case HoconConcat():
      w.sink(
        _Pending(node, _lookupPrefixes(w.includePrefix))..selfPath = w.selfPath,
      );

    case HoconArray(:final elements):
      final list = <Object?>[];
      w.sink(list);
      // Push in reverse so elements materialize in source order.
      for (var i = elements.length - 1; i >= 0; i--) {
        stack.add(
          _MatWork(
            elements[i],
            list.add,
            objPath: w.objPath,
            includePrefix: w.includePrefix,
          ),
        );
      }

    case HoconObject(:final entries):
      final map = <String, Object?>{};
      w.sink(map);
      _pushEntries(entries, map, w, stack);

    case HoconInclude():
      throw HoconResolveException(
        'Internal error: include statement outside object entries',
      );
  }
}

/// Schedule materialization of object [entries] into [parent] — either
/// a freshly allocated map (normal objects) or the including object's
/// map (included documents merge in place).
///
/// Each assignment is split into a value-materialization item and a
/// *commit* item pushed beneath it: the commit runs only after the
/// value's entire subtree has drained (LIFO), so it observes fully
/// populated containers when deciding merge/override. The commit order
/// across siblings follows source order.
void _pushEntries(
  List<HoconEntry> entries,
  Map<String, Object?> parent,
  _MatWork w,
  List<_MatWork> stack,
) {
  for (var i = entries.length - 1; i >= 0; i--) {
    final entry = entries[i];
    switch (entry) {
      case HoconAssignment(:final path, :final value):
        final fullPath = [...w.objPath, ...path];
        final (assignmentParent, key) = _navigate(parent, path);
        final cell = <Object?>[null];
        // Pushed commit-first so it sits beneath the value work (and
        // beneath everything the value work itself schedules).
        stack.add(
          _MatWork(
            const HoconObject([]),
            (_) => _commitAssignment(assignmentParent, key, cell),
            objPath: const [],
            includePrefix: null,
          ),
        );
        stack.add(
          _MatWork(
            value,
            (v) => cell[0] = v,
            objPath: fullPath,
            includePrefix: w.includePrefix,
            selfPath: fullPath,
          ),
        );
      case HoconIncludeEntry(:final include):
        stack.add(
          _MatWork(
            const HoconObject([]),
            (_) {},
            objPath: w.objPath,
            includePrefix: w.includePrefix,
            include: include,
            targetMap: parent,
          ),
        );
    }
  }
}

/// Place a materialized assignment value into its slot, deciding
/// merge/override semantics now that the value is fully materialized.
void _commitAssignment(
  Map<String, Object?> parent,
  String key,
  List<Object?> cell,
) {
  final v = cell[0];
  final existed = parent.containsKey(key);
  final existing = existed ? parent[key] : null;
  if (v is _Pending) {
    v.hasPrevious = existed;
    v.previous = existing;
    parent[key] = v;
    return;
  }
  if (v is Map<String, Object?>) {
    if (existing is _Pending) {
      // The pending stays in the slot; the object merges with its
      // resolved value later (spec: `foo : ${foo.a}` example).
      final overlay = existing.overlay;
      if (overlay == null) {
        existing.overlay = v;
      } else {
        _mergeInto(overlay, v);
      }
      return;
    }
    if (existing is Map<String, Object?>) {
      _mergeInto(existing, v);
      return;
    }
  }
  parent[key] = v;
}

/// Lookup prefix candidates for a substitution. Without an include
/// prefix, substitutions are root-absolute. Included content tries the
/// include site's path first (fixup), then the path as written.
List<List<String>> _lookupPrefixes(List<String>? includePrefix) {
  if (includePrefix == null || includePrefix.isEmpty) return const [[]];
  return [includePrefix, const []];
}

/// Navigate/create nested maps along [path] inside [map]; returns the
/// parent map of the final segment and that segment.
(Map<String, Object?>, String) _navigate(
  Map<String, Object?> map,
  List<String> path,
) {
  var current = map;
  for (var i = 0; i < path.length - 1; i++) {
    final seg = path[i];
    final next = current[seg];
    if (next is Map<String, Object?>) {
      current = next;
    } else {
      final fresh = <String, Object?>{};
      current[seg] = fresh;
      current = fresh;
    }
  }
  return (current, path.last);
}

/// Merge [overlay] into [base] in place: overlay wins on scalar
/// conflicts, object-valued fields merge recursively. Iterative.
void _mergeInto(Map<String, Object?> base, Map<String, Object?> overlay) {
  final stack = <(Map<String, Object?>, Map<String, Object?>)>[];
  void one(Map<String, Object?> b, Map<String, Object?> o) {
    for (final MapEntry(:key, :value) in o.entries) {
      final existing = b[key];
      if (existing is Map<String, Object?> && value is Map<String, Object?>) {
        stack.add((existing, value));
      } else {
        b[key] = value;
      }
    }
  }

  one(base, overlay);
  while (stack.isNotEmpty) {
    final (b, o) = stack.removeLast();
    one(b, o);
  }
}

/// Load an include and merge the included document's entries into the
/// containing object's map.
void _loadInclude(_MatWork w, List<_MatWork> stack, _ResolveCtx ctx) {
  final include = w.include!;
  final targetMap = w.targetMap!;
  if (ctx.activeIncludes.contains(include.resource)) {
    throw HoconResolveException('Circular include: ${include.resource}');
  }
  final content = ctx.config.includeLoader?.call(include.resource);
  if (content == null) {
    if (include.required) {
      throw HoconResolveException(
        'Required include not found: ${include.resource}',
      );
    }
    return; // a missing optional include is silently ignored
  }
  final result = parseHocon(content);
  final HoconValue doc = switch (result) {
    Success<ParseError, HoconValue>(:final value) => value,
    Partial<ParseError, HoconValue>(:final value) => value,
    Failure<ParseError, HoconValue>() =>
      throw HoconResolveException(
        'Invalid HOCON in include ${include.resource}: ${result.errors}',
      ),
  };
  if (doc is HoconArray) {
    throw HoconResolveException(
      'Included document ${include.resource} must be an object, not an array',
    );
  }
  ctx.activeIncludes.add(include.resource);
  // The pop sentinel is pushed before the document work so it sits
  // beneath it on the LIFO stack: it runs only after every descendant
  // work item of the included document has drained.
  stack.add(
    _MatWork(
      const HoconObject([]),
      (_) => ctx.activeIncludes.removeLast(),
      objPath: const [],
      includePrefix: null,
    ),
  );
  // The included document's entries merge into the including object's
  // map; the include site's path becomes the substitution fixup prefix.
  switch (doc) {
    case final HoconObject included:
      _pushEntries(
        included.entries,
        targetMap,
        _MatWork(
          included,
          (_) {},
          objPath: w.objPath,
          includePrefix: w.objPath,
        ),
        stack,
      );
    default:
      throw HoconResolveException(
        'Internal error: included document is not an object',
      );
  }
}

/// Merge [overlay] over a deep copy of [base]: overlay wins on scalar
/// conflicts, object-valued fields merge recursively. Iterative.
Map<String, Object?> _deepMerge(
  Map<String, Object?> base,
  Map<String, Object?> overlay,
) {
  final out = <String, Object?>{};
  final stack =
      <(Map<String, Object?>, Map<String, Object?>, Map<String, Object?>)>[];

  void mergeInto(
    Map<String, Object?> b,
    Map<String, Object?> o,
    Map<String, Object?> t,
  ) {
    for (final key in b.keys) {
      t[key] = b[key];
    }
    for (final MapEntry(:key, :value) in o.entries) {
      final existing = t[key];
      if (existing is Map<String, Object?> && value is Map<String, Object?>) {
        final nested = <String, Object?>{};
        t[key] = nested;
        stack.add((existing, value, nested));
      } else {
        t[key] = value;
      }
    }
  }

  mergeInto(base, overlay, out);
  while (stack.isNotEmpty) {
    final (b, o, t) = stack.removeLast();
    mergeInto(b, o, t);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Stage 2: resolution (substitutions, concatenations)
// ---------------------------------------------------------------------------

void _noopSink(Object? _) {}

void _resolveTree(_ResolveCtx ctx) {
  ctx.push(() => _resolveNode(ctx.tree, _noopSink, ctx));
  while (ctx.work.isNotEmpty) {
    ctx.work.removeLast()();
  }
}

/// Resolve [node] deeply and deliver the result to [sink].
///
/// Containers mutate in place (maps) or are rebuilt (lists); a
/// container's sink may fire before its descendants finish — the
/// worklist drains fully before [resolveHocon] reads anything, and
/// on-demand lookup resolves any pending encountered mid-flight.
void _resolveNode(Object? node, void Function(Object?) sink, _ResolveCtx ctx) {
  switch (node) {
    case final _Pending p:
      _resolvePending(p, sink, ctx);
    case final Map<String, Object?> m:
      sink(m);
      final entries = m.entries.toList();
      for (var i = entries.length - 1; i >= 0; i--) {
        final key = entries[i].key;
        final value = entries[i].value;
        if (_needsResolution(value)) {
          if (value is _Pending) {
            value.container = m;
          }
          ctx.push(() {
            _resolveNode(value, (rv) => _deliverField(m, key, rv, value), ctx);
          });
        }
      }
    case final List<Object?> l:
      final out = <Object?>[];
      sink(out);
      for (var i = l.length - 1; i >= 0; i--) {
        final element = l[i];
        if (element is _Pending) {
          element.container = out;
        }
        ctx.push(() {
          _resolveNode(element, (rv) {
            if (!identical(rv, _omitted)) out.add(rv);
          }, ctx);
        });
      }
    default:
      sink(node);
  }
}

/// True when [node] (or anything reachable through it) is identical to
/// [pending] — a structurally self-containing value, i.e. an unbreakable
/// cycle like `a : { b : ${a} }`.
bool _containsIdentical(Object? node, Object? target) {
  final seen = <Object?>{};
  final stack = <Object?>[node];
  while (stack.isNotEmpty) {
    final current = stack.removeLast();
    if (identical(current, target)) return true;
    if (current is Map<String, Object?>) {
      if (seen.add(current)) {
        stack.addAll(current.values);
      }
    } else if (current is List<Object?>) {
      if (seen.add(current)) {
        stack.addAll(current);
      }
    }
  }
  return false;
}

bool _needsResolution(Object? value) =>
    value is! String && value is! num && value is! bool && value != null;

/// Write a resolved value back into a map field, honoring the omitted
/// sentinel for pendings (restore the previous value, or remove the
/// field).
void _deliverField(
  Map<String, Object?> map,
  String key,
  Object? resolved,
  Object? originalSlot,
) {
  if (identical(resolved, _omitted)) {
    if (originalSlot is _Pending && originalSlot.hasPrevious) {
      map[key] = originalSlot.previous;
    } else {
      map.remove(key);
    }
    return;
  }
  map[key] = resolved;
}

void _resolvePending(_Pending p, void Function(Object?) sink, _ResolveCtx ctx) {
  if (p.done) {
    sink(p.resolved);
    return;
  }
  if (ctx.active.contains(p)) {
    throw HoconResolveException(
      'Circular reference resolving \${${_pathText(p)}}',
    );
  }
  ctx.active.add(p);
  p.sink = sink;
  ctx.push(() => _resolvePendingSource(p, ctx));
}

String _pathText(_Pending p) => switch (p.source) {
  HoconSubstitution(:final path) => path,
  _ => p.selfPath?.join('.') ?? '<concatenation>',
};

void _resolvePendingSource(_Pending p, _ResolveCtx ctx) {
  void finish(Object? raw) {
    if (p.hasPrevious &&
        raw is Map<String, Object?> &&
        p.previous is Map<String, Object?>) {
      raw = _deepMerge(p.previous as Map<String, Object?>, raw);
    }
    final overlay = p.overlay;
    if (overlay != null) {
      if (raw is Map<String, Object?>) {
        _mergeInto(raw, overlay);
      } else {
        raw = overlay;
      }
    }
    if (raw is Map<String, Object?> || raw is List<Object?>) {
      if (_containsIdentical(raw, p) ||
          (p.container != null && _containsIdentical(raw, p.container))) {
        throw HoconResolveException(
          'Circular reference resolving \${${_pathText(p)}}: '
          'the substituted value contains the field being defined',
        );
      }
    }
    p.done = true;
    p.resolved = raw;
    ctx.active.remove(p);
    p.sink!(raw);
  }

  switch (p.source) {
    case HoconSubstitution():
      ctx.push(
        () =>
            _resolveSubstitution(p, p.source as HoconSubstitution, finish, ctx),
      );
    case HoconConcat(:final parts):
      final results = List<Object?>.filled(parts.length, null);
      // Pushed before the parts, so it runs after all of them (LIFO).
      ctx.push(() => finish(_combineParts(parts, results)));
      for (var i = parts.length - 1; i >= 0; i--) {
        final idx = i;
        final part = parts[i];
        switch (part) {
          case HoconSubstitution():
            ctx.push(
              () => _resolveSubstitution(p, part, (v) => results[idx] = v, ctx),
            );
          case HoconString(:final value):
            results[idx] = value;
          case HoconInt(:final value):
            results[idx] = value;
          case HoconDouble(:final value):
            results[idx] = value;
          case HoconBool(:final value):
            results[idx] = value;
          case HoconNull():
            results[idx] = null;
          default:
            // Object/array/nested-concat part: materialize, then resolve.
            ctx.push(() {
              Object? slot;
              _matInto(part, (v) => slot = v, ctx.config);
              _resolveNode(slot, (v) => results[idx] = v, ctx);
            });
        }
      }
    default:
      throw HoconResolveException(
        'Internal error: unexpected pending source ${p.source.runtimeType}',
      );
  }
}

/// Materialize [node] into a tree synchronously (includes are
/// statement-level only and cannot appear here).
void _matInto(
  HoconValue node,
  void Function(Object?) sink,
  HoconConfig config,
) {
  final ctx = _ResolveCtx(config);
  sink(_materialize(node, ctx));
}

void _resolveSubstitution(
  _Pending p,
  HoconSubstitution sub,
  void Function(Object?) sink,
  _ResolveCtx ctx,
) {
  _tryLookup(p, sub, sub.path.split('.'), 0, sink, ctx);
}

/// Try each lookup prefix in order; on total miss fall back to the
/// environment, then to the optional/undefined handling.
void _tryLookup(
  _Pending p,
  HoconSubstitution sub,
  List<String> segs,
  int prefixIndex,
  void Function(Object?) sink,
  _ResolveCtx ctx,
) {
  if (prefixIndex >= p.lookupPrefixes.length) {
    final env = ctx.config.environment;
    if (env != null && env.containsKey(sub.path)) {
      sink(env[sub.path]);
      return;
    }
    if (sub.optional) {
      sink(_omitted);
      return;
    }
    throw HoconResolveException(
      'Could not resolve substitution: \${${sub.path}}',
    );
  }
  final candidate = [...p.lookupPrefixes[prefixIndex], ...segs];
  final selfPath = p.selfPath;

  // Self-reference: the candidate resolves against the previous value
  // in the slot being defined (or below it, for paths like ${foo.a}
  // inside an assignment to foo).
  if (selfPath != null && _extendsPath(candidate, selfPath)) {
    if (!p.hasPrevious || p.previous == _notFound) {
      _nextPrefix(p, sub, segs, prefixIndex, sink, ctx);
      return;
    }
    _walkLookup(p.previous, candidate.sublist(selfPath.length), 0, (found) {
      if (identical(found, _notFound)) {
        ctx.push(() {
          _nextPrefix(p, sub, segs, prefixIndex, sink, ctx);
        });
      } else {
        sink(found);
      }
    }, ctx);
    return;
  }

  _walkLookup(ctx.tree, candidate, 0, (found) {
    if (identical(found, _notFound)) {
      ctx.push(() {
        _nextPrefix(p, sub, segs, prefixIndex, sink, ctx);
      });
    } else {
      sink(found);
    }
  }, ctx);
}

void _nextPrefix(
  _Pending p,
  HoconSubstitution sub,
  List<String> segs,
  int prefixIndex,
  void Function(Object?) sink,
  _ResolveCtx ctx,
) {
  _tryLookup(p, sub, segs, prefixIndex + 1, sink, ctx);
}

bool _extendsPath(List<String> candidate, List<String> base) {
  if (candidate.length < base.length) return false;
  for (var i = 0; i < base.length; i++) {
    if (candidate[i] != base[i]) return false;
  }
  return true;
}

/// Walk [segs] from [start] through maps, resolving any pending
/// encountered along the way, and deliver the target — or the
/// [_notFound] marker — to [sink].
void _walkLookup(
  Object? start,
  List<String> segs,
  int index,
  void Function(Object?) sink,
  _ResolveCtx ctx,
) {
  var node = start;
  var i = index;
  while (true) {
    if (i == segs.length) {
      if (node is _Pending) {
        final pending = node;
        ctx.push(() {
          _resolveNode(pending, sink, ctx);
        });
      } else {
        sink(node);
      }
      return;
    }
    if (node is _Pending) {
      final rest = segs.sublist(i);
      ctx.push(() {
        _resolveNode(
          node,
          (resolved) => _walkLookup(resolved, rest, 0, sink, ctx),
          ctx,
        );
      });
      return;
    }
    if (node is Map<String, Object?>) {
      if (!node.containsKey(segs[i])) {
        sink(_notFound);
        return;
      }
      node = node[segs[i]];
      i++;
      continue;
    }
    sink(_notFound);
    return;
  }
}

/// Combine resolved concatenation parts: strings join, objects merge,
/// arrays concatenate, whitespace-only string parts are ignored in the
/// container cases, and anything mixed is an error. A concatenation
/// whose parts were all omitted resolves to the omitted sentinel.
Object? _combineParts(List<HoconValue> parts, List<Object?> results) {
  final real = <Object?>[];
  for (final r in results) {
    if (!identical(r, _omitted)) real.add(r);
  }
  if (real.isEmpty) return _omitted;
  bool isWsString(Object? v) => v is String && v.trim().isEmpty;

  final hasObject = real.any((v) => v is Map<String, Object?>);
  final hasList = real.any((v) => v is List<Object?>);
  if (hasObject) {
    var merged = <String, Object?>{};
    for (final v in real) {
      if (v is Map<String, Object?>) {
        merged = _deepMerge(merged, v);
      } else if (isWsString(v)) {
        continue; // inter-part whitespace is insignificant here
      } else {
        throw HoconResolveException(
          'Cannot concatenate ${_kindName(v)} with object',
        );
      }
    }
    return merged;
  }
  if (hasList) {
    final out = <Object?>[];
    for (final v in real) {
      if (v is List<Object?>) {
        out.addAll(v);
      } else if (isWsString(v)) {
        continue;
      } else {
        throw HoconResolveException(
          'Cannot concatenate ${_kindName(v)} with array',
        );
      }
    }
    return out;
  }
  final buf = StringBuffer();
  for (final v in real) {
    buf.write(_stringify(v));
  }
  return buf.toString();
}

String _kindName(Object? v) => switch (v) {
  String() => 'string',
  int() || double() => 'number',
  bool() => 'boolean',
  null => 'null',
  List() => 'array',
  Map() => 'object',
  _ => v.runtimeType.toString(),
};

String _stringify(Object? v) => switch (v) {
  final String s => s,
  final int i => '$i',
  final double d => '$d',
  final bool b => '$b',
  null => 'null',
  _ =>
    throw HoconResolveException(
      'Cannot concatenate ${_kindName(v)} in a string value',
    ),
};

// ---------------------------------------------------------------------------
// Stage 3: tree → HoconValue
// ---------------------------------------------------------------------------

HoconValue _toHocon(Object? node) {
  HoconValue? out;
  final stack = <(Object?, void Function(HoconValue))>[(node, (v) => out = v)];
  while (stack.isNotEmpty) {
    final (current, sink) = stack.removeLast();
    switch (current) {
      case null:
        sink(const HoconNull());
      case final bool b:
        sink(HoconBool(b));
      case final int i:
        sink(HoconInt(i));
      case final double d:
        sink(HoconDouble(d));
      case final String s:
        sink(HoconString(s));
      case final List<Object?> l:
        final values = List<HoconValue?>.filled(l.length, null);
        sink(HoconArray(values.cast<HoconValue>()));
        for (var i = l.length - 1; i >= 0; i--) {
          final idx = i;
          stack.add((l[i], (v) => values[idx] = v));
        }
      case final Map<String, Object?> m:
        final keys = m.keys.toList();
        final entries = List<HoconEntry?>.filled(keys.length, null);
        sink(HoconObject(entries.cast<HoconEntry>()));
        for (var i = keys.length - 1; i >= 0; i--) {
          final idx = i;
          stack.add((
            m[keys[idx]],
            (v) => entries[idx] = HoconAssignment([keys[idx]], v),
          ));
        }
      default:
        throw HoconResolveException(
          'Internal error: unexpected resolved node ${current.runtimeType}',
        );
    }
  }
  return out!;
}

// ---------------------------------------------------------------------------
// Public decoder: resolved HoconValue → native Dart
// ---------------------------------------------------------------------------

/// Convert a *resolved* [HoconValue] to native Dart types
/// (`Map<String, Object?>`, `List<Object?>`, `String`, `int`, `double`,
/// `bool`, `null`).
///
/// Throws [HoconResolveException] when the value still contains
/// substitutions, concatenations, or includes — run [resolveHocon]
/// first. Iterative over an explicit worklist, so arbitrarily deep
/// documents convert without call-stack growth.
Object? hoconToNative(HoconValue root) {
  Object? out;
  final stack = <(HoconValue, void Function(Object?))>[(root, (v) => out = v)];
  while (stack.isNotEmpty) {
    final (node, sink) = stack.removeLast();
    switch (node) {
      case HoconNull():
        sink(null);
      case HoconBool(:final value):
        sink(value);
      case HoconInt(:final value):
        sink(value);
      case HoconDouble(:final value):
        sink(value);
      case HoconString(:final value):
        sink(value);
      case HoconArray(:final elements):
        final list = List<Object?>.filled(elements.length, null);
        sink(list);
        for (var i = 0; i < elements.length; i++) {
          final idx = i;
          stack.add((elements[idx], (v) => list[idx] = v));
        }
      case HoconObject(:final entries):
        final map = <String, Object?>{};
        sink(map);
        for (final entry in entries) {
          switch (entry) {
            case HoconAssignment(:final path, :final value):
              final (parent, key) = _navigate(map, path);
              parent[key] = null; // reserve key order
              stack.add((value, (v) => parent[key] = v));
            case HoconIncludeEntry():
              throw HoconResolveException(
                'Unresolved include — call resolveHocon before hoconToNative',
              );
          }
        }
      case HoconSubstitution() || HoconConcat() || HoconInclude():
        throw HoconResolveException(
          'Unresolved HOCON value (${node.runtimeType}) — '
          'call resolveHocon before hoconToNative',
        );
    }
  }
  return out;
}
