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

  /// Creates a tree green.
  const GreenTree(this.kind, this.children);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GreenTree<Tok, Syn> &&
          other.kind == kind &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hash(kind, listHash(children));

  @override
  String toString() => 'GreenTree($kind, ${children.length} children)';
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

  /// Creates an unexpected-region wrapper.
  const GreenUnexpected(this.children);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GreenUnexpected<Tok, Syn> &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hash('unexpected', listHash(children));

  @override
  String toString() => 'GreenUnexpected(${children.length} children)';
}

/// Operations on green trees. Lifted into a namespace rather than methods
/// on [GreenNode] so the ADT stays minimal data and the operations are
/// easy to extend without modifying the sealed hierarchy.
abstract final class GreenNodeOps {
  /// Total source-character length of the subtree rooted at [node].
  ///
  /// Sums across children for [GreenTree] and [GreenUnexpected].
  /// [GreenMissing] contributes zero (it is a zero-width placeholder).
  /// [GreenToken] contributes its [GreenToken.text] length.
  static int textLength<Tok, Syn>(GreenNode<Tok, Syn> node) => switch (node) {
    GreenToken<Tok, Syn>(:final text) => text.length,
    GreenTree<Tok, Syn>(:final children) => _sumLengths(children),
    GreenMissing<Tok, Syn>() => 0,
    GreenUnexpected<Tok, Syn>(:final children) => _sumLengths(children),
  };

  /// Reconstruct the original source covered by the subtree rooted at
  /// [node]. Concatenates [GreenToken.text] across the in-order traversal,
  /// skips [GreenMissing] (zero-width), descends into [GreenUnexpected]
  /// children verbatim.
  ///
  /// Lossless invariant: for any tree produced by a parser run on
  /// `originalSource`, `toSource(tree) == originalSource`.
  static String toSource<Tok, Syn>(GreenNode<Tok, Syn> node) {
    final buffer = StringBuffer();
    _writeSource(node, buffer);
    return buffer.toString();
  }

  static int _sumLengths<Tok, Syn>(List<GreenNode<Tok, Syn>> children) {
    var total = 0;
    for (final child in children) {
      total += textLength(child);
    }
    return total;
  }

  static void _writeSource<Tok, Syn>(
    GreenNode<Tok, Syn> node,
    StringBuffer buffer,
  ) {
    switch (node) {
      case GreenToken<Tok, Syn>(:final text):
        buffer.write(text);
      case GreenTree<Tok, Syn>(:final children):
        for (final child in children) {
          _writeSource(child, buffer);
        }
      case GreenMissing<Tok, Syn>():
        break;
      case GreenUnexpected<Tok, Syn>(:final children):
        for (final child in children) {
          _writeSource(child, buffer);
        }
    }
  }
}

String _quote(String text) {
  if (text.length > 16) {
    return '"${text.substring(0, 16).replaceAll('\n', r'\n')}…"';
  }
  return '"${text.replaceAll('\n', r'\n')}"';
}
