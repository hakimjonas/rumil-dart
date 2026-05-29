/// Position-independent lossless syntax tree nodes.
///
/// Green nodes are pure lexical payload: a token carries its kind and text;
/// a tree carries its kind and children. Absolute offsets, line numbers, and
/// spans are computed at the [RedTree] layer (see `red_tree.dart`) from the
/// offset at which a green is viewed plus the textual lengths of its
/// preceding siblings.
///
/// Keeping position data off the green has three consequences:
/// 1. Green subtrees are shareable across edits — the same `1+2` subtree
///    can appear at any offset in any file without allocation or rewriting.
/// 2. Splicing a subtree into a tree is a pure vector update — no
///    `adjustSpans` pass.
/// 3. Parsers do not thread absolute offsets through combinators; Pratt,
///    chainl1, etc. produce correct trees without lexer-level offset
///    plumbing.
///
/// The [GreenMissing] / [GreenUnexpected] pair is the SwiftSyntax-style
/// resilient-tree model: the tree itself records what went wrong at the
/// structural position it went wrong, instead of emitting a flat list of
/// errors alongside a tree that looks as if it had parsed.
library;

import 'equality.dart';

/// A position-independent green-tree node, parameterized by a language's
/// token alphabet [Tok] and syntax-tree-node alphabet [Syn].
///
/// Four cases:
/// - [GreenToken]: leaf carrying kind + raw text.
/// - [GreenTree]: interior node carrying kind + children.
/// - [GreenMissing]: zero-width placeholder synthesized when the parser
///   expected a token that wasn't there; carries the kind that was
///   expected so quick-fixes and diagnostics can name it exactly
///   ("expected `)`"). `textLength(GreenMissing(...)) == 0`, so
///   [GreenNodeOps.toSource] is lossless.
/// - [GreenUnexpected]: wraps tokens skipped during recovery; carries the
///   skipped tokens as children so [GreenNodeOps.toSource] reconstructs
///   the original input verbatim.
sealed class GreenNode<Tok, Syn> {
  /// Base constructor.
  const GreenNode();

  /// Total source-character length of this subtree, in O(1).
  ///
  /// Leaves ([GreenToken], [GreenMissing]) compute it directly; interior
  /// nodes ([GreenTree], [GreenUnexpected]) store it, summed once from
  /// their children's lengths at construction. This keeps offset
  /// computation in [RedTree] linear in tree depth rather than quadratic —
  /// descending N levels reads N cached lengths instead of re-walking N
  /// subtrees. Matches Rowan's stored-width design.
  int get textLength;
}

/// Leaf token: kind + raw text.
final class GreenToken<Tok, Syn> extends GreenNode<Tok, Syn> {
  /// The token's classification.
  final Tok kind;

  /// The token's source text. Concatenated across a tree, this reconstructs
  /// the original input.
  final String text;

  /// Creates a token green.
  const GreenToken(this.kind, this.text);

  @override
  int get textLength => text.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GreenToken<Tok, Syn> &&
          other.kind == kind &&
          other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => 'GreenToken($kind, ${_quote(text)})';
}

/// Interior node: kind + ordered children.
final class GreenTree<Tok, Syn> extends GreenNode<Tok, Syn> {
  /// The tree's classification.
  final Syn kind;

  /// The children, in source order.
  final List<GreenNode<Tok, Syn>> children;

  @override
  final int textLength;

  /// Creates a tree green. [textLength] is summed once from [children].
  GreenTree(this.kind, this.children) : textLength = _sumLengths(children);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GreenTree<Tok, Syn> &&
          other.kind == kind &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hash(kind, listHash(children));

  @override
  String toString() {
    final n = children.length;
    return 'GreenTree($kind, $n ${n == 1 ? "child" : "children"})';
  }
}

/// Zero-width placeholder for a token the parser expected but didn't find.
///
/// Carries the [expected] kind so consumers can name the missing element
/// exactly ("expected `)`"). Contributes zero characters to the lossless
/// source reconstruction, so trees containing [GreenMissing] still satisfy
/// `GreenNodeOps.toSource(tree) == originalSource` for the input that was
/// actually present.
final class GreenMissing<Tok, Syn> extends GreenNode<Tok, Syn> {
  /// The token kind the parser expected.
  final Tok expected;

  /// Creates a missing-token placeholder.
  const GreenMissing(this.expected);

  @override
  int get textLength => 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GreenMissing<Tok, Syn> && other.expected == expected;

  @override
  int get hashCode => Object.hash('missing', expected);

  @override
  String toString() => 'GreenMissing($expected)';
}

/// Wraps tokens skipped during error recovery.
///
/// The [children] are the greens that were skipped past. Concatenating their
/// text reconstructs the skipped region. Diagnostics walk over an
/// [GreenUnexpected] surface the original errors; the tree itself preserves
/// the skipped text so the lossless invariant
/// `GreenNodeOps.toSource(tree) == originalSource` round-trips.
final class GreenUnexpected<Tok, Syn> extends GreenNode<Tok, Syn> {
  /// The skipped greens, in source order.
  final List<GreenNode<Tok, Syn>> children;

  @override
  final int textLength;

  /// Creates an unexpected-region wrapper. [textLength] is summed once from
  /// [children].
  GreenUnexpected(this.children) : textLength = _sumLengths(children);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GreenUnexpected<Tok, Syn> &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hash('unexpected', listHash(children));

  @override
  String toString() {
    final n = children.length;
    return 'GreenUnexpected($n ${n == 1 ? "child" : "children"})';
  }
}

/// Operations on green trees. Lifted into a namespace rather than methods
/// on [GreenNode] so the ADT stays minimal data and the operations are
/// easy to extend without modifying the sealed hierarchy. The
/// [GreenNodeExt] extension below forwards to these for ergonomic
/// `node.textLength` / `node.toSource()` call sites.
abstract final class GreenNodeOps {
  /// Total source-character length of the subtree rooted at [node], O(1).
  ///
  /// Reads the cached [GreenNode.textLength] — interior nodes store it,
  /// summed once at construction; leaves compute it directly. This is the
  /// load-bearing property that keeps [RedTree] offset computation linear
  /// in tree depth: descending N levels reads N cached lengths rather than
  /// re-walking N subtrees (which would be O(depth²)).
  static int textLength<Tok, Syn>(GreenNode<Tok, Syn> node) => node.textLength;

  /// Reconstruct the original source covered by the subtree rooted at
  /// [node]. Concatenates [GreenToken.text] in source-order traversal,
  /// skips [GreenMissing] (zero-width), descends into [GreenUnexpected]
  /// children verbatim.
  ///
  /// Iterative depth-first walk: children are pushed to the worklist in
  /// reverse so they pop in source order. Same stack-safety property as
  /// [textLength].
  ///
  /// Lossless invariant: for any tree produced by a parser run on
  /// `originalSource`, `toSource(tree) == originalSource`.
  static String toSource<Tok, Syn>(GreenNode<Tok, Syn> node) {
    final buffer = StringBuffer();
    final stack = <GreenNode<Tok, Syn>>[node];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      switch (current) {
        case GreenToken<Tok, Syn>(:final text):
          buffer.write(text);
        case GreenMissing<Tok, Syn>():
          break;
        case GreenTree<Tok, Syn>(:final children):
        case GreenUnexpected<Tok, Syn>(:final children):
          for (var i = children.length - 1; i >= 0; i--) {
            stack.add(children[i]);
          }
      }
    }
    return buffer.toString();
  }
}

/// Ergonomic source accessor on [GreenNode]. [GreenNode.textLength] is
/// already an instance getter; this adds the matching `node.toSource()`
/// so callers don't have to reach through [GreenNodeOps].
extension GreenNodeExt<Tok, Syn> on GreenNode<Tok, Syn> {
  /// Reconstructed source covered by this subtree. See
  /// [GreenNodeOps.toSource].
  String toSource() => GreenNodeOps.toSource(this);
}

/// Sum of children's cached text lengths. O(immediate children) because
/// each child's [GreenNode.textLength] is itself O(1). Used by the
/// [GreenTree] / [GreenUnexpected] constructors to compute their stored
/// length once, bottom-up.
int _sumLengths<Tok, Syn>(List<GreenNode<Tok, Syn>> children) {
  var total = 0;
  for (final child in children) {
    total += child.textLength;
  }
  return total;
}

String _quote(String text) {
  if (text.length > 16) {
    return '"${text.substring(0, 16).replaceAll('\n', r'\n')}…"';
  }
  return '"${text.replaceAll('\n', r'\n')}"';
}
