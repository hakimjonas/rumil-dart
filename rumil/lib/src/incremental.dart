/// Incremental reparse: update a green tree after a [TextEdit] by reparsing
/// only the smallest affected region and splicing it back.
///
/// Three-tier strategy, in order of preference:
///
/// 1. **Token-level micro-update.** If the edit falls entirely inside one
///    "simple" token (identifier, number, string, whitespace, comment — as
///    declared by [ReparseableParsers.isSimpleToken]) and doesn't empty it,
///    splice a new token with the edited text. No parsing at all —
///    constant-time regardless of file size. The keystroke-latency path.
/// 2. **Block-level reparse.** Find the smallest ancestor whose syntax kind
///    has a registered sub-parser ([ReparseableParsers.byKind]), reparse
///    just that region's text, splice the result via [TreeSplicing.replaceAt].
///    Reparses a function/statement/block, not the whole file.
/// 3. **Full reparse fallback.** When neither fires — no reparsable ancestor,
///    the sub-parse fails, the region would be most of the document, or the
///    splice doesn't resolve — reparse the whole new source.
///
/// Because greens are position-independent, splicing needs no span fixup;
/// offsets are recomputed lazily when the result is next viewed through a
/// [RedTree].
///
/// ## Isolate safety
///
/// All operations here are pure functions of their inputs producing a fresh
/// tree; the only mutable state is the parse-scoped [GreenCache] inside each
/// `run`, which never escapes. An LSP can drive [incrementalParse] on a
/// worker isolate without synchronization — the previous tree is immutable
/// and the result is a new immutable tree.
library;

import 'errors.dart';
import 'extensions.dart';
import 'green_node.dart';
import 'parser.dart';
import 'red_tree.dart';
import 'result.dart';
import 'text_edit.dart';
import 'tree_splicing.dart';

/// The grammar-supplied policy an incremental reparse needs.
///
/// All four pieces are language-specific, which is why they're injected
/// rather than defaulted:
///
/// - [full] — the whole-file parser, for the initial parse and the
///   full-reparse fallback.
/// - [byKind] — sub-parsers indexed by syntax kind. A kind is reparsable iff
///   it appears here; the value parses a bare subtree of that kind from its
///   region text.
/// - [isSimpleToken] — which token kinds may be edited in place. Identifiers,
///   numbers, strings, whitespace, comments are the usual yes; structural
///   kinds (operators, braces) must go through block-level reparse because a
///   text edit can change their kind (`==` → `=`).
/// - [onParseFailure] — builds a fallback tree from source when [full]
///   fails on the whole document, so the lossless invariant
///   `GreenNodeOps.toSource(tree) == source` holds even on total failure.
///   No default: the shape of an "unparseable" tree is grammar policy.
final class ReparseableParsers<Tok, Syn> {
  /// Whole-file parser, used for the initial parse and the fallback.
  final Parser<ParseError, GreenNode<Tok, Syn>> full;

  /// Sub-parsers per reparsable syntax kind.
  final Map<Syn, Parser<ParseError, GreenNode<Tok, Syn>>> byKind;

  /// Whether a token kind may be edited in place (token-level fast path).
  final bool Function(Tok) isSimpleToken;

  /// Builds the fallback tree when [full] fails on the whole document.
  final GreenNode<Tok, Syn> Function(String source) onParseFailure;

  /// Creates a reparser bundle.
  const ReparseableParsers({
    required this.full,
    required this.byKind,
    required this.isSimpleToken,
    required this.onParseFailure,
  });

  /// A degenerate bundle with no reparsable kinds and no in-place tokens —
  /// every edit falls back to full reparse. For grammars without reparsable
  /// substructure, or for tests.
  factory ReparseableParsers.onlyFull({
    required Parser<ParseError, GreenNode<Tok, Syn>> full,
    required GreenNode<Tok, Syn> Function(String source) onParseFailure,
  }) => ReparseableParsers(
    full: full,
    byKind: const {},
    isSimpleToken: _never,
    onParseFailure: onParseFailure,
  );

  /// Syntax kinds with a registered sub-parser.
  Set<Syn> get reparsableKinds => byKind.keys.toSet();

  static bool _never(Object? _) => false;
}

/// Incremental-parse tuning.
final class IncrementalConfig {
  /// If the would-be reparse region is within [minReparseSize] characters of
  /// the whole document, do a full reparse instead — the incremental
  /// bookkeeping isn't worth it for near-whole-document edits.
  final int minReparseSize;

  /// Creates a config. [minReparseSize] defaults to 50, matching rumil-scala.
  const IncrementalConfig({this.minReparseSize = 50});
}

/// The result of an incremental parse.
final class IncrementalResult<Tok, Syn> {
  /// The updated green tree.
  final GreenNode<Tok, Syn> tree;

  /// Which strategy fired, for diagnostics and tests.
  final IncrementalStrategy strategy;

  /// Creates a result.
  const IncrementalResult(this.tree, this.strategy);
}

/// Which tier of [incrementalParse] produced the result.
enum IncrementalStrategy {
  /// Tier 1 — a single token's text was edited in place.
  tokenLevel,

  /// Tier 2 — a reparsable region was reparsed and spliced.
  blockLevel,

  /// Tier 3 — the whole document was reparsed.
  fullReparse,
}

/// Incrementally update [previousTree] (parsed from [previousSource]) after
/// [edit], using [parsers]. See the library doc for the three-tier strategy.
IncrementalResult<Tok, Syn> incrementalParse<Tok, Syn>(
  GreenNode<Tok, Syn> previousTree,
  String previousSource,
  TextEdit edit,
  ReparseableParsers<Tok, Syn> parsers, {
  IncrementalConfig config = const IncrementalConfig(),
}) {
  final newSource = edit.apply(previousSource);

  final tokenLevel = _tryTokenLevelUpdate(
    previousTree,
    previousSource,
    edit,
    parsers.isSimpleToken,
  );
  if (tokenLevel != null) return tokenLevel;

  return _blockLevelReparse(
    previousTree,
    previousSource,
    edit,
    newSource,
    parsers,
    config,
  );
}

/// Tier 1. Returns null when the edit straddles a token boundary, lands on a
/// non-token (Tree / Missing / Unexpected), targets a non-simple kind, or
/// would empty the token — all of which must go through block-level reparse.
IncrementalResult<Tok, Syn>? _tryTokenLevelUpdate<Tok, Syn>(
  GreenNode<Tok, Syn> tree,
  String previousSource,
  TextEdit edit,
  bool Function(Tok) isSimpleToken,
) {
  final node = RedTree<Tok, Syn>(tree, previousSource).nodeAt(edit.startOffset);
  if (node == null) return null;

  final green = node.green;
  if (green is! GreenToken<Tok, Syn>) return null;

  final tokenStart = node.offset;
  final tokenEnd = node.endOffset;
  // The edit must lie entirely within this one token.
  if (edit.startOffset < tokenStart || edit.endOffset > tokenEnd) return null;
  if (!isSimpleToken(green.kind)) return null;

  final inStart = edit.startOffset - tokenStart;
  final inEnd = edit.endOffset - tokenStart;
  final newText =
      green.text.substring(0, inStart) +
      edit.newText +
      green.text.substring(inEnd);
  // An emptied token changes structure — defer to block-level.
  if (newText.isEmpty) return null;

  final spliced = TreeSplicing.replaceAt<Tok, Syn>(
    tree,
    node.pathFromRoot,
    GreenToken<Tok, Syn>(green.kind, newText),
  );
  if (spliced == null) return null;
  return IncrementalResult(spliced, IncrementalStrategy.tokenLevel);
}

/// Tier 2 + Tier 3. Finds the smallest reparsable ancestor of the edit,
/// reparses its (edit-adjusted) region text with the matching sub-parser,
/// and splices. Falls back to full reparse when any step doesn't hold.
IncrementalResult<Tok, Syn> _blockLevelReparse<Tok, Syn>(
  GreenNode<Tok, Syn> previousTree,
  String previousSource,
  TextEdit edit,
  String newSource,
  ReparseableParsers<Tok, Syn> parsers,
  IncrementalConfig config,
) {
  final reparsableKinds = parsers.reparsableKinds;
  if (reparsableKinds.isEmpty) return _fullReparse(newSource, parsers);

  final region = RedTree<Tok, Syn>(
    previousTree,
    previousSource,
  ).findReparseRegion(edit.startOffset, edit.endOffset, reparsableKinds);
  if (region == null) return _fullReparse(newSource, parsers);

  final kind = region.syntaxKind;
  final subParser = kind == null ? null : parsers.byKind[kind];
  if (subParser == null) return _fullReparse(newSource, parsers);

  final regionStart = region.offset;
  final regionEnd = region.endOffset;
  // The region's end shifts by the edit's lengthDelta when the edit is
  // within it; an edit straddling the end is not a single-region edit.
  final adjustedEnd =
      edit.endOffset <= regionEnd ? regionEnd + edit.lengthDelta : regionEnd;

  // Near-whole-document edits aren't worth the incremental bookkeeping.
  if (adjustedEnd - regionStart >= newSource.length - config.minReparseSize) {
    return _fullReparse(newSource, parsers);
  }
  // Defensive: a corrupt range can't index the new source.
  if (regionStart < 0 ||
      adjustedEnd > newSource.length ||
      adjustedEnd < regionStart) {
    return _fullReparse(newSource, parsers);
  }

  final regionText = newSource.substring(regionStart, adjustedEnd);
  final result = subParser.run(regionText);
  final newSubtree = switch (result) {
    Success<ParseError, GreenNode<Tok, Syn>>(:final value) => value,
    Partial<ParseError, GreenNode<Tok, Syn>>(:final value) => value,
    Failure<ParseError, GreenNode<Tok, Syn>>() => null,
  };
  if (newSubtree == null) return _fullReparse(newSource, parsers);

  final spliced = TreeSplicing.replaceAt<Tok, Syn>(
    previousTree,
    region.pathFromRoot,
    newSubtree,
  );
  if (spliced == null) return _fullReparse(newSource, parsers);
  return IncrementalResult(spliced, IncrementalStrategy.blockLevel);
}

/// Tier 3. Parse the whole new source; on failure build the grammar's
/// fallback tree so the lossless invariant survives total parse failure.
IncrementalResult<Tok, Syn> _fullReparse<Tok, Syn>(
  String source,
  ReparseableParsers<Tok, Syn> parsers,
) {
  final result = parsers.full.run(source);
  final tree = switch (result) {
    Success<ParseError, GreenNode<Tok, Syn>>(:final value) => value,
    Partial<ParseError, GreenNode<Tok, Syn>>(:final value) => value,
    Failure<ParseError, GreenNode<Tok, Syn>>() => parsers.onParseFailure(
      source,
    ),
  };
  return IncrementalResult(tree, IncrementalStrategy.fullReparse);
}

/// Batch several edits into one incremental update.
///
/// [edits] must be sorted by start offset and non-overlapping. They are
/// combined into a single super-edit over the union of their ranges (via the
/// new source they jointly produce), then run through [incrementalParse]. If
/// the combined range exceeds half the new document, falls straight to full
/// reparse.
IncrementalResult<Tok, Syn> batchIncrementalParse<Tok, Syn>(
  GreenNode<Tok, Syn> previousTree,
  String previousSource,
  List<TextEdit> edits,
  ReparseableParsers<Tok, Syn> parsers, {
  IncrementalConfig config = const IncrementalConfig(),
}) {
  if (edits.isEmpty) {
    return IncrementalResult(previousTree, IncrementalStrategy.tokenLevel);
  }
  if (edits.length == 1) {
    return incrementalParse(
      previousTree,
      previousSource,
      edits.first,
      parsers,
      config: config,
    );
  }

  var newSource = previousSource;
  for (final edit in edits) {
    newSource = edit.apply(newSource);
  }
  var minStart = edits.first.startOffset;
  var maxEnd = edits.first.endOffset + edits.first.lengthDelta;
  for (final e in edits) {
    if (e.startOffset < minStart) minStart = e.startOffset;
    final end = e.endOffset + e.lengthDelta;
    if (end > maxEnd) maxEnd = end;
  }

  if (maxEnd - minStart > newSource.length ~/ 2) {
    return _fullReparse(newSource, parsers);
  }

  final combined = TextEdit(
    minStart,
    edits.last.endOffset,
    newSource.substring(minStart, minStart + (maxEnd - minStart)),
  );
  return incrementalParse(
    previousTree,
    previousSource,
    combined,
    parsers,
    config: config,
  );
}

/// Fluent incremental update on a green tree.
extension IncrementalGreenExt<Tok, Syn> on GreenNode<Tok, Syn> {
  /// Apply [edit] incrementally, returning the updated tree and the strategy
  /// that fired. Convenience for `incrementalParse(this, source, edit, …)`.
  IncrementalResult<Tok, Syn> applyEdit(
    String source,
    TextEdit edit,
    ReparseableParsers<Tok, Syn> parsers, {
    IncrementalConfig config = const IncrementalConfig(),
  }) => incrementalParse(this, source, edit, parsers, config: config);
}
