/// Resilient-parse combinators that build [GreenNode] trees.
///
/// Three combinators bridge the parser ADT to the green-tree layer:
///
/// - [treeOf] composes child green-producing parsers into a [GreenTree],
///   the Rowan-style `start_node` / `finish_node` shape as a combinator.
/// - [expectToken] turns a token failure into a zero-width [GreenMissing]
///   placeholder and a [Result.Partial], so a missing `)` doesn't abort the
///   parse — the tree records the gap at the structural position it occurred.
/// - [syncUntil] is panic-mode recovery: on inner failure it skips to the
///   next synchronization character, wraps the skipped text in a
///   [GreenUnexpected], and resumes — so one derailed construct doesn't lose
///   the rest of the document's structure.
///
/// [expectToken] and [syncUntil] are the [GreenMissing] / [GreenUnexpected]
/// producers; the SwiftSyntax resilient-tree model lives here. All three
/// preserve the lossless invariant: `GreenNodeOps.toSource(result)` over the
/// consumed input reproduces that input verbatim (Missing is zero-width;
/// Unexpected keeps the skipped text).
library;

import 'errors.dart';
import 'extensions.dart';
import 'green_node.dart';
import 'parser.dart';
import 'primitives.dart';

/// Intern [inner]'s produced green through the parse-scoped cache, so every
/// structurally-equal token green (e.g. each `GreenToken(num, "5")` in the
/// parse) collapses to one canonical heap instance.
///
/// For token-producing parsers (leaves). Equality cost is `kind == &&
/// text ==` — cheap. Use [internTree] for tree-producing parsers, where
/// equality recurses into children. Both produce the same [InternedGreen]
/// ADT case; the split is a cost signal to the reader, not two mechanisms.
///
/// Interning makes structurally-equal siblings `identical`. RedTree sibling
/// disambiguation uses `childIndex`, not green reference identity, so it is
/// unaffected — see `green_cache.dart`'s sibling-identity contract.
Parser<E, GreenNode<Tok, Syn>> internToken<E, Tok, Syn>(
  Parser<E, GreenNode<Tok, Syn>> inner,
) =>
    InternedGreen(inner);

/// Intern [inner]'s produced green through the parse-scoped cache. For
/// tree-producing parsers: every structurally-equal subtree — same kind,
/// same children in order, children themselves structurally equal —
/// collapses to one canonical instance.
///
/// Cost differs from [internToken]: the cache's structural equality recurses
/// into the tree's children, so a lookup is O(subtree size). Worth it only
/// when structurally-equal subtrees actually recur in the workload — then
/// one cache hit replaces allocating every descendant; if they don't, the
/// recursive equality buys nothing. Same [InternedGreen] ADT case as
/// [internToken].
Parser<E, GreenNode<Tok, Syn>> internTree<E, Tok, Syn>(
  Parser<E, GreenNode<Tok, Syn>> inner,
) =>
    InternedGreen(inner);

/// Compose child green-producing parsers into a [GreenTree] of kind [kind].
///
/// The child parsers run in sequence; all must succeed (or recover to a
/// [Result.Partial]) for the composed parser to produce a tree. Their green
/// results become the tree's children, in the order given.
///
/// This is the combinator form of Rowan's `GreenNodeBuilder.start_node` /
/// `finish_node` pair — a grammar author writes
///
/// ```dart
/// final array = treeOf(JsonSyn.array, [
///   lbracket,                  // Parser<ParseError, JsonGreen>
///   element.sepBy(comma),      // ... flattened into the children
///   rbracket,
/// ]);
/// ```
///
/// rather than threading `~`/`.map` tuple plumbing. Each part yields exactly
/// one green; to splice a variable number of children (e.g. a separated
/// list) into the same parent, have that part yield a wrapper green, or
/// compose the list at the green level before calling [treeOf].
///
/// Implementation: a left fold over [parts] via [flatMap], accumulating each
/// child green into a fresh list per run (the [defer] gives every parse its
/// own accumulator), terminated by a [map] that wraps the collected children.
/// No new Parser ADT case — composes the existing combinators. The fold
/// chain length is the static child count at one tree level, not input
/// depth, so the existing trampoline handles runtime nesting.
Parser<ParseError, GreenNode<Tok, Syn>> treeOf<Tok, Syn>(
  Syn kind,
  List<Parser<ParseError, GreenNode<Tok, Syn>>> parts,
) =>
    defer(() {
      final collected = <GreenNode<Tok, Syn>>[];
      Parser<ParseError, void> chain = succeed<ParseError, void>(null);
      for (final part in parts) {
        // Each part runs for its side effect of appending to `collected`;
        // its value is discarded by the void cast and thenSkip.
        chain = chain.thenSkip(part.map<void>(collected.add));
      }
      return chain.map(
        (_) =>
            GreenTree<Tok, Syn>(kind, List<GreenNode<Tok, Syn>>.of(collected)),
      );
    });

/// Expect a token via [inner]; on failure synthesize a zero-width
/// [GreenMissing] placeholder of kind [kind] and continue as a
/// [Result.Partial].
///
/// On success [expectToken] returns whatever green [inner] produced. On
/// failure it consumes no input, yields `GreenMissing(kind)` as the value,
/// and surfaces [inner]'s errors via the partial result — so the caller's
/// tree gets a zero-width placeholder at the point the token was expected
/// and parsing continues. The lossless invariant holds because Missing
/// contributes no characters.
///
/// ```dart
/// // `( expr )` where a missing `)` is recoverable:
/// final closeParen = char(')').map(
///   (c) => GreenToken<Tok, Syn>(Tok.rparen, c),
/// );
/// final group = treeOf(Syn.group, [
///   openParen,
///   expr,
///   expectToken(Tok.rparen, closeParen),
/// ]);
/// ```
Parser<ParseError, GreenNode<Tok, Syn>> expectToken<Tok, Syn>(
  Tok kind,
  Parser<ParseError, GreenNode<Tok, Syn>> inner,
) =>
    RecoverWith(inner, succeed(GreenMissing<Tok, Syn>(kind)));

/// Panic-mode recovery: if [inner] fails, skip input up to (but not
/// including) the next character in [syncChars], wrap the skipped text in a
/// [GreenUnexpected], and surface [inner]'s errors via [Result.Partial]. The
/// sync character is left unconsumed so the caller can match it next.
///
/// Behaviour by case:
/// 1. [inner] succeeds → its green is returned unchanged; no Unexpected
///    node is allocated.
/// 2. [inner] fails and a sync char is at the failure offset → returns
///    `Partial(GreenUnexpected([]), innerErrors, 0)`. Zero-width; nothing is
///    consumed so the caller matches the sync char next.
/// 3. [inner] fails and a sync char appears after M skipped characters →
///    returns `Partial(GreenUnexpected([GreenToken(errorTokenKind,
///    skipped)]), innerErrors, M)`.
/// 4. [inner] fails and no sync char is ever found → the skip runs to
///    end-of-input; the remaining text is wrapped and returned as a Partial.
///
/// Lossless invariant: the returned tree covers exactly the characters from
/// the failure offset up to the sync char (or end-of-input); the caller's
/// remaining input resumes at the sync char, so concatenation reproduces the
/// original text.
///
/// Recovery is all-or-nothing at the boundary: if [inner] consumes input
/// before failing, that consumed prefix is part of the Unexpected region —
/// there is no partial commit of a valid prefix into structure. Committing a
/// mid-parse prefix needs a commit-point discipline [RecoverWith] does not
/// offer; a future `syncUntilCommitted` could add it.
///
/// The skip is a single linear scan (`notFollowedBy(sync).skipThen(anyChar)`
/// repeated), capturing the skipped slice in one pass — no per-character
/// allocation, no position resolution here (positions are recovered later
/// from the [GreenUnexpected]'s offset in a [RedTree]).
///
/// Progress guard: when [inner] fails at end-of-input with nothing to skip,
/// the result is a zero-consumption `Partial(GreenUnexpected([]), …, 0)`,
/// which will livelock a `.many` loop. Callers placing [syncUntil] inside
/// `.many` should guard the element (e.g. `eof().notFollowedBy.skipThen(...)`)
/// so the loop terminates at end-of-input.
Parser<ParseError, GreenNode<Tok, Syn>> syncUntil<Tok, Syn>(
  Parser<ParseError, GreenNode<Tok, Syn>> inner,
  Set<String> syncChars,
  Tok errorTokenKind,
) {
  final syncP = satisfy(syncChars.contains, 'sync character');
  final skipStep = syncP.notFollowedBy.skipThen(anyChar());
  final skipUntilSync = skipStep.skipMany.capture;
  final recovery = skipUntilSync.map<GreenNode<Tok, Syn>>((skipped) {
    if (skipped.isEmpty) {
      return GreenUnexpected<Tok, Syn>(const []);
    }
    return GreenUnexpected<Tok, Syn>([
      GreenToken<Tok, Syn>(errorTokenKind, skipped),
    ]);
  });
  return RecoverWith(inner, recovery);
}
