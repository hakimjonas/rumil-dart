/// Pure-functional subtree replacement on green trees.
///
/// Splicing parses a subtree and grafts it back into an existing tree: given
/// a path (from [RedTree.pathFromRoot]) and a replacement green, [replaceAt]
/// returns a new root identical to the old one except at that path.
/// Structural sharing makes it cheap — only the nodes from the root down to
/// the replacement are newly allocated; every sibling off the path is reused
/// by reference. This is the operation incremental reparse splices a freshly
/// parsed region back through.
///
/// Greens are position-independent, so splicing needs no span fixup (the
/// `adjustSpans` pass an offset-bearing tree would require). Offsets are
/// recomputed lazily when the result is next viewed through a [RedTree].
library;

import 'green_node.dart';

/// Subtree replacement operations on green trees.
abstract final class TreeSplicing {
  /// Replace the node at [path] in [root] with [replacement], returning a new
  /// root. Returns null if [path] does not resolve — an index out of range,
  /// or descending into a leaf ([GreenToken] / [GreenMissing]) that has no
  /// children.
  ///
  /// An empty [path] refers to the root itself, so `replaceAt(root, const [],
  /// r)` returns `r`. Otherwise `path[0]` selects a child of the root,
  /// `path[1]` a child of that, and so on — the same encoding
  /// [RedTree.pathFromRoot] produces.
  ///
  /// Structural sharing: only the nodes along [path] are rebuilt; off-path
  /// siblings are carried over by reference. The rebuilt interior nodes
  /// recompute their cached `textLength` from their (mostly shared) children
  /// — O(branching) per rebuilt level, O(path length × branching) total. No
  /// recursion: the descent collects the path frames into a list, then the
  /// rebuild folds replacement-upward over that list, so depth lives in the
  /// list, not the call stack.
  static GreenNode<Tok, Syn>? replaceAt<Tok, Syn>(
    GreenNode<Tok, Syn> root,
    List<int> path,
    GreenNode<Tok, Syn> replacement,
  ) {
    if (path.isEmpty) return replacement;

    // Descend, recording (node, chosen child index) at each step. Bail to
    // null the moment the path can't be followed.
    final frames = <(GreenNode<Tok, Syn>, int)>[];
    var current = root;
    for (final index in path) {
      final children = _childrenOf(current);
      if (children == null || index < 0 || index >= children.length) {
        return null;
      }
      frames.add((current, index));
      current = children[index];
    }

    // Rebuild bottom-up: start from the replacement, and at each recorded
    // frame produce a new node with the chosen child swapped for the
    // accumulator, sharing all other children by reference.
    var rebuilt = replacement;
    for (var i = frames.length - 1; i >= 0; i--) {
      final (node, index) = frames[i];
      rebuilt = _withChildReplaced(node, index, rebuilt);
    }
    return rebuilt;
  }

  /// The children of [node] if it is an interior node ([GreenTree] /
  /// [GreenUnexpected]), otherwise null. Leaves ([GreenToken] /
  /// [GreenMissing]) have no children and a path cannot descend through them.
  static List<GreenNode<Tok, Syn>>? _childrenOf<Tok, Syn>(
    GreenNode<Tok, Syn> node,
  ) => switch (node) {
    GreenTree<Tok, Syn>(:final children) => children,
    GreenUnexpected<Tok, Syn>(:final children) => children,
    GreenToken<Tok, Syn>() || GreenMissing<Tok, Syn>() => null,
  };

  /// A copy of interior [node] with child [index] replaced by [child], other
  /// children shared by reference. [node] is known to be a [GreenTree] or
  /// [GreenUnexpected] (it was descended through), so the leaf cases throw —
  /// reaching them is an internal invariant violation, not a user error.
  static GreenNode<Tok, Syn> _withChildReplaced<Tok, Syn>(
    GreenNode<Tok, Syn> node,
    int index,
    GreenNode<Tok, Syn> child,
  ) {
    switch (node) {
      case GreenTree<Tok, Syn>(:final kind, :final children):
        final next = List<GreenNode<Tok, Syn>>.of(children);
        next[index] = child;
        return GreenTree<Tok, Syn>(kind, next);
      case GreenUnexpected<Tok, Syn>(:final children):
        final next = List<GreenNode<Tok, Syn>>.of(children);
        next[index] = child;
        return GreenUnexpected<Tok, Syn>(next);
      case GreenToken<Tok, Syn>() || GreenMissing<Tok, Syn>():
        throw StateError(
          'replaceAt: descended into a leaf node — path resolution bug',
        );
    }
  }
}
