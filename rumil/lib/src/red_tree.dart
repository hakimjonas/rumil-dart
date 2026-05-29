/// Position-aware view over a [GreenNode].
///
/// Inspired by rust-analyzer's Rowan library, [RedTree] is an ephemeral,
/// position-aware interface over the immutable, position-independent
/// [GreenNode] structure.
///
/// Design:
/// - Green trees are position-independent (immutable, shareable, cacheable).
/// - Red trees compute positions on demand from the offset at which a green
///   is viewed plus the textual lengths of its preceding siblings.
/// - Parent/sibling navigation without storing back-pointers on greens.
///
/// A red node is lightweight: a reference to its green, its absolute offset,
/// an optional parent, its index among its parent's children, and a shared
/// reference to the source string (for line/column resolution). Children are
/// computed lazily on first access.
///
/// Sibling identity is carried in [childIndex], assigned once at
/// construction. It is the disambiguation key used by [pathFromRoot] —
/// offset-based keys collapse zero-width siblings onto the same index, and
/// green reference identity collapses structurally-equal siblings (which
/// happens once green-node interning lands), so neither survives as a
/// reliable sibling key; [childIndex] survives both.
library;

import 'errors.dart';
import 'green_node.dart';
import 'line_index.dart';
import 'location.dart';

/// A position-aware view over a [GreenNode], parameterized by a language's
/// token alphabet [Tok] and syntax-tree-node alphabet [Syn].
final class RedTree<Tok, Syn> {
  /// The underlying green node.
  final GreenNode<Tok, Syn> green;

  /// Absolute offset of this node in the source (0-indexed).
  final int offset;

  /// The parent red node, or null for the root.
  final RedTree<Tok, Syn>? parent;

  /// This node's index in `parent.children`. `0` for the root (by
  /// convention — the root has no parent and therefore no meaningful
  /// sibling index).
  final int childIndex;

  /// The full source string, shared by reference across all nodes of the
  /// tree. Used only for line/column resolution in [location] and [span].
  final String _source;

  RedTree._(
    this.green,
    this.offset,
    this.parent,
    this.childIndex,
    this._source,
  );

  /// Create a root red tree at offset 0 over [green], with [source] as the
  /// original input string used for line/column resolution.
  factory RedTree(GreenNode<Tok, Syn> green, String source) =>
      RedTree._(green, 0, null, 0, source);

  /// Source-character length of this node's green subtree.
  ///
  /// A pure forward to the green's own cached [GreenNode.textLength] (O(1)).
  /// Not stored on the red node — reds are ephemeral and numerous, and the
  /// length already lives on the immutable green, so a second per-red cache
  /// would only add a field to the hot allocation for no benefit.
  int get length => green.textLength;

  /// One-past-the-last source offset covered by this node.
  int get endOffset => offset + length;

  /// Absolute location (line, column, offset) of this node's start.
  ///
  /// Resolved on demand against the source via [Location]. O(offset) for the
  /// first line/column read on a fresh [Location] (walks from start of
  /// input). Callers resolving many positions should build a [LineIndex]
  /// over the source once and call `lineIndex.locationAt(node.offset)`
  /// directly for O(log n) lookups.
  Location get location => Location(_source, offset);

  /// Absolute span of this node, from [offset] to [endOffset].
  Span get span => Span(
    start: Location(_source, offset),
    end: Location(_source, endOffset),
  );

  /// The source text covered by this node, reconstructed from the green
  /// subtree. Self-contained — works on synthetic or spliced trees that
  /// don't correspond to a contiguous region of [_source].
  ///
  /// Not cached: each access re-walks the subtree via
  /// [GreenNodeOps.toSource] (O(subtree size)). Cheap for tokens; for an
  /// interior node accessed repeatedly, hoist the result into a local.
  /// Reds are ephemeral, so caching here would bloat the hot allocation for
  /// a value most call sites read at most once.
  String get text => GreenNodeOps.toSource(green);

  /// Children as red trees, each carrying its correct absolute offset.
  ///
  /// [GreenTree] and [GreenUnexpected] carry children; [GreenToken] and
  /// [GreenMissing] are leaves and return an empty list. Places each child
  /// by accumulating the prior children's [GreenNode.textLength] — each an
  /// O(1) field read — so building one node's children is O(its child
  /// count). [GreenMissing] contributes zero, so a Missing child's red view
  /// sits at the same offset as the token that would follow it.
  late final List<RedTree<Tok, Syn>> children = _computeChildren();

  List<RedTree<Tok, Syn>> _computeChildren() {
    final List<GreenNode<Tok, Syn>> kids = switch (green) {
      GreenTree<Tok, Syn>(:final children) => children,
      GreenUnexpected<Tok, Syn>(:final children) => children,
      GreenToken<Tok, Syn>() || GreenMissing<Tok, Syn>() => const [],
    };
    if (kids.isEmpty) return const [];
    final result = <RedTree<Tok, Syn>>[];
    var childOffset = offset;
    for (var i = 0; i < kids.length; i++) {
      final kid = kids[i];
      result.add(RedTree._(kid, childOffset, this, i, _source));
      childOffset += kid.textLength;
    }
    return result;
  }

  /// The parent node, or null for the root.
  RedTree<Tok, Syn>? get parentNode => parent;

  /// The next sibling, or null if this is the last child (or the root).
  RedTree<Tok, Syn>? get nextSibling {
    final p = parent;
    if (p == null) return null;
    final siblings = p.children;
    return childIndex < siblings.length - 1 ? siblings[childIndex + 1] : null;
  }

  /// The previous sibling, or null if this is the first child (or the root).
  RedTree<Tok, Syn>? get prevSibling {
    final p = parent;
    if (p == null) return null;
    return childIndex > 0 ? p.children[childIndex - 1] : null;
  }

  /// All descendants in pre-order (parents before children), excluding this
  /// node.
  ///
  /// Lazy: yields on demand over an explicit worklist, so chain depth lives
  /// in the worklist (not the call stack) and a caller using `.firstWhere`
  /// / `.any` / `.take` stops the walk early without materializing the rest.
  /// Use `.toList()` when an eager snapshot is wanted.
  Iterable<RedTree<Tok, Syn>> get descendants sync* {
    // Seed with this node's children in order; process depth-first while
    // preserving pre-order by pushing each node's children reversed.
    final stack = <RedTree<Tok, Syn>>[];
    final kids = children;
    for (var i = kids.length - 1; i >= 0; i--) {
      stack.add(kids[i]);
    }
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      yield node;
      final nodeKids = node.children;
      for (var i = nodeKids.length - 1; i >= 0; i--) {
        stack.add(nodeKids[i]);
      }
    }
  }

  /// All ancestors from immediate parent up to the root, in that order.
  /// Iterative walk up the parent chain — depth-bounded, no recursion.
  List<RedTree<Tok, Syn>> get ancestors {
    final result = <RedTree<Tok, Syn>>[];
    var node = parent;
    while (node != null) {
      result.add(node);
      node = node.parent;
    }
    return result;
  }

  /// Find the deepest node whose span strictly contains [targetOffset]
  /// (half-open: start inclusive, end exclusive).
  ///
  /// "Which node does the cursor sit inside?" Returns null at end-of-input
  /// since no node's half-open span includes `source.length`. For an
  /// edit-range query that must be satisfied by insertions at end-of-input,
  /// use [nodeEnclosingRange], which treats the right edge as inclusive on
  /// the root's span. Iterative descent.
  RedTree<Tok, Syn>? nodeAt(int targetOffset) {
    if (targetOffset < offset || targetOffset >= endOffset) return null;
    var node = this;
    while (true) {
      final child = _childContaining(node, targetOffset);
      if (child == null) return node;
      node = child;
    }
  }

  static RedTree<T, S>? _childContaining<T, S>(
    RedTree<T, S> node,
    int targetOffset,
  ) =>
      node._childStartContaining(targetOffset);

  /// The single child whose half-open range `[offset, endOffset)` contains
  /// [point], or null if none does — constructed on the spot without
  /// materializing this node's full [children] list.
  ///
  /// Walks this node's green children once, accumulating each child's
  /// (O(1) cached) [GreenNode.textLength] to track offsets, and stops at the
  /// first child whose range contains [point]. Builds exactly one red node
  /// (the match) rather than one per sibling — so a descent that touches K
  /// levels allocates K reds, not the sum of the levels' fan-outs.
  ///
  /// The scan is left-to-right, so it costs O(index-of-match) arithmetic per
  /// level. For a node with very many children this is linear in the worst
  /// case (the match near the end); the win here is dropping N allocations
  /// to 1, not the arithmetic. A cumulative-width index on the green would
  /// make it O(log N), but that bloats every interior node for a pattern
  /// only very-wide flat trees hit — deferred until a consumer needs it.
  ///
  /// Zero-width children ([GreenMissing]) contain no point (`offset ==
  /// endOffset`), so the `point < childEnd` test skips them.
  RedTree<Tok, Syn>? _childStartContaining(int point) {
    final kids = _greenChildren(green);
    var childOffset = offset;
    for (var i = 0; i < kids.length; i++) {
      final kid = kids[i];
      final childEnd = childOffset + kid.textLength;
      if (point >= childOffset && point < childEnd) {
        return RedTree._(kid, childOffset, this, i, _source);
      }
      if (childOffset > point) break; // children are offset-sorted; overshot
      childOffset = childEnd;
    }
    return null;
  }

  /// The green children of [node], or an empty list for leaves.
  static List<GreenNode<T, S>> _greenChildren<T, S>(GreenNode<T, S> node) =>
      switch (node) {
        GreenTree<T, S>(:final children) => children,
        GreenUnexpected<T, S>(:final children) => children,
        GreenToken<T, S>() || GreenMissing<T, S>() => const [],
      };

  /// Find the deepest node enclosing the edit range `[editStart, editEnd]`.
  ///
  /// The right primitive for an edit range, as opposed to [nodeAt] (a cursor
  /// point). Descends to a child only when the range fits inside the child's
  /// span *and* the range start falls strictly within the child's half-open
  /// interior — `child.offset <= editStart < child.endOffset` and
  /// `editEnd <= child.endOffset`. Three consequences:
  ///
  /// - **Consistency with [nodeAt]:** start-containment uses the same
  ///   half-open rule, so the two never disagree about which node owns an
  ///   offset.
  /// - **No boundary tie-break:** at a boundary `A=[a, N)` / `B=[N, b)`, a
  ///   range starting at `N` does not descend into `A` (its interior ends
  ///   before `N`) and only descends into `B` if the range fits. A range
  ///   that straddles the boundary descends into neither and resolves to
  ///   their common parent — there is no arbitrary first-match winner.
  /// - **Zero-width nodes never enclose:** a [GreenMissing] (or any node
  ///   with `offset == endOffset`) has no interior, so `editStart <
  ///   endOffset` is always false. An edit at a Missing's position resolves
  ///   to the enclosing parent, not the placeholder.
  ///
  /// A pure insertion at the very end of the source
  /// (`editStart == editEnd == endOffset`) resolves to the enclosing node,
  /// not its last child: the last child's half-open interior ends before
  /// `endOffset`, so no child's start-containment holds and the descent
  /// stops. On the root this means the root itself — consistent with
  /// `nodeAt(endOffset) == null` (no node *starts*-contains end-of-input).
  /// An insertion strictly between two children resolves to their deepest
  /// common ancestor. Iterative descent.
  RedTree<Tok, Syn>? nodeEnclosingRange(int editStart, int editEnd) {
    if (editStart < offset || editEnd > endOffset) return null;
    var node = this;
    while (true) {
      final child = _childEnclosing(node, editStart, editEnd);
      if (child == null) return node;
      node = child;
    }
  }

  static RedTree<T, S>? _childEnclosing<T, S>(
    RedTree<T, S> node,
    int editStart,
    int editEnd,
  ) {
    // Same half-open start-containment as nodeAt (one red node built, not
    // the whole children list), then require the range to fit
    // (editEnd <= endOffset). Zero-width children can't start-contain, so
    // they're never returned, matching the doc's "never enclose" rule.
    final child = node._childStartContaining(editStart);
    if (child != null && editEnd <= child.endOffset) {
      return child;
    }
    return null;
  }

  /// The syntax kind if this is a [GreenTree], otherwise null. [GreenMissing]
  /// and [GreenUnexpected] are never reparsable boundaries — returning null
  /// keeps [findReparseRegion] from landing on an error marker as a reparse
  /// boundary.
  Syn? get syntaxKind => switch (green) {
    GreenTree<Tok, Syn>(:final kind) => kind,
    _ => null,
  };

  /// The token kind if this is a [GreenToken], otherwise null.
  Tok? get tokenKind => switch (green) {
    GreenToken<Tok, Syn>(:final kind) => kind,
    _ => null,
  };

  /// The expected kind if this is a [GreenMissing] placeholder, otherwise
  /// null.
  Tok? get missingKind => switch (green) {
    GreenMissing<Tok, Syn>(:final expected) => expected,
    _ => null,
  };

  /// True if this node's green is a [GreenToken].
  bool get isToken => green is GreenToken<Tok, Syn>;

  /// True if this node's green is a [GreenTree].
  bool get isTree => green is GreenTree<Tok, Syn>;

  /// True if this node's green is a [GreenMissing] placeholder.
  bool get isMissing => green is GreenMissing<Tok, Syn>;

  /// True if this node's green is a [GreenUnexpected] recovery wrapper.
  bool get isUnexpected => green is GreenUnexpected<Tok, Syn>;

  /// Find the nearest ancestor (including this node) whose syntax kind is in
  /// [reparsableKinds]. Returns null if none is found. Iterative walk up the
  /// parent chain.
  RedTree<Tok, Syn>? findReparseAncestor(Set<Syn> reparsableKinds) {
    RedTree<Tok, Syn>? node = this;
    while (node != null) {
      final kind = node.syntaxKind;
      if (kind != null && reparsableKinds.contains(kind)) return node;
      node = node.parent;
    }
    return null;
  }

  /// Find the smallest reparsable ancestor containing the offset range
  /// `[editStart, editEnd]`. The key operation for incremental parsing: it
  /// finds the minimal subtree that needs to be reparsed after an edit.
  ///
  /// Descends to the deepest node enclosing the edit range via
  /// [nodeEnclosingRange], then walks up to the nearest ancestor whose kind
  /// is in [reparsableKinds]. Returns null if no reparsable ancestor exists.
  RedTree<Tok, Syn>? findReparseRegion(
    int editStart,
    int editEnd,
    Set<Syn> reparsableKinds,
  ) {
    final deepest = nodeEnclosingRange(editStart, editEnd);
    return deepest?.findReparseAncestor(reparsableKinds);
  }

  /// The path from the root to this node as a list of child indices,
  /// suitable for tree splicing (`replaceAt`, lands in 0.9). An empty path
  /// refers to the root. Iterative walk up the parent chain, reversed.
  List<int> get pathFromRoot {
    final reversed = <int>[];
    var node = this;
    var p = node.parent;
    while (p != null) {
      reversed.add(node.childIndex);
      node = p;
      p = node.parent;
    }
    return reversed.reversed.toList();
  }

  /// Collect [ParseError]s from structural error markers in this subtree:
  ///
  /// - [GreenMissing] → [EndOfInput] naming the expected kind ("expected K").
  /// - [GreenUnexpected] → [CustomError] describing the skipped text.
  /// - any [GreenToken] whose kind satisfies [isErrorToken] → [CustomError].
  ///
  /// [GreenMissing] uses [EndOfInput] rather than [Unexpected] because the
  /// semantic is "parser expected K but found nothing" — [EndOfInput] best
  /// matches the "expected K, not available" message shape.
  ///
  /// `isErrorToken` is supplied by the caller so the notion of an "error
  /// token kind" stays language-specific. Errors carry a real [Location]
  /// resolved against the source.
  ///
  /// Builds one [LineIndex] over the source up front and resolves every
  /// error position through it in O(log n), so a resilient parse with many
  /// error markers stays O(errors × log n) rather than O(errors × offset).
  /// Iterative pre-order walk — depth lives in the worklist, not the call
  /// stack.
  List<ParseError> validateWith(bool Function(Tok) isErrorToken) {
    final errors = <ParseError>[];
    final index = LineIndex(_source);
    final stack = <RedTree<Tok, Syn>>[this];
    // Pre-order: push children reversed so they pop left-to-right. Because
    // we emit the current node's error before pushing children, errors come
    // out in source order.
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      switch (node.green) {
        case GreenToken<Tok, Syn>(:final kind, :final text)
            when isErrorToken(kind):
          errors.add(
            CustomError('Error token: $text', index.locationAt(node.offset)),
          );
        case GreenMissing<Tok, Syn>(:final expected):
          errors.add(
            EndOfInput(expected.toString(), index.locationAt(node.offset)),
          );
        case GreenUnexpected<Tok, Syn>():
          errors.add(
            CustomError(
              'Unexpected: ${node.text}',
              index.locationAt(node.offset),
            ),
          );
        case _:
          break;
      }
      final kids = node.children;
      for (var i = kids.length - 1; i >= 0; i--) {
        stack.add(kids[i]);
      }
    }
    return errors;
  }

  @override
  String toString() {
    final kindStr = switch (green) {
      GreenToken<Tok, Syn>(:final kind) => 'Token($kind)',
      GreenTree<Tok, Syn>(:final kind) => 'Tree($kind)',
      GreenMissing<Tok, Syn>(:final expected) => 'Missing($expected)',
      GreenUnexpected<Tok, Syn>() => 'Unexpected',
    };
    return 'RedTree($kindStr, offset=$offset, length=$length)';
  }
}
