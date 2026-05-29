import 'package:rumil/rumil.dart';
import 'package:test/test.dart';

enum Tok { lparen, rparen, plus, num, ws, error }

enum Syn { doc, group }

typedef G = GreenNode<Tok, Syn>;

// --- A tiny grammar producing green trees. ---
//
// doc   := group*
// group := '(' (num | '+' | ws)* ')'
// A "simple" (in-place-editable) token is `num` or `ws`.

Parser<ParseError, G> _numTok() =>
    digit().many1.capture.map((s) => GreenToken<Tok, Syn>(Tok.num, s));

Parser<ParseError, G> _wsTok() => char(
  ' ',
).many1.capture.map((s) => GreenToken<Tok, Syn>(Tok.ws, s));

Parser<ParseError, G> _plusTok() =>
    char('+').map((c) => GreenToken<Tok, Syn>(Tok.plus, c));

Parser<ParseError, G> _lparen() =>
    char('(').map((c) => GreenToken<Tok, Syn>(Tok.lparen, c));

Parser<ParseError, G> _rparen() =>
    char(')').map((c) => GreenToken<Tok, Syn>(Tok.rparen, c));

/// A group `( ... )` as a `Syn.group` tree.
Parser<ParseError, G> _group() {
  final inner = (_numTok() | _wsTok() | _plusTok()).many;
  return _lparen().flatMap(
    (lp) => inner.flatMap(
      (mid) => _rparen().map(
        (rp) => GreenTree<Tok, Syn>(Syn.group, [lp, ...mid, rp]),
      ),
    ),
  );
}

/// The whole document: groups wrapped in a `Syn.doc` tree. Requires EOF, so
/// trailing junk (e.g. an unmatched paren) is a genuine parse failure —
/// which is what drives the `onParseFailure` fallback path.
Parser<ParseError, G> _doc() => _group().many
    .thenSkip(eof())
    .map((groups) => GreenTree<Tok, Syn>(Syn.doc, groups));

ReparseableParsers<Tok, Syn> _parsers() => ReparseableParsers(
  full: _doc(),
  byKind: {Syn.group: _group()},
  isSimpleToken: (t) => t == Tok.num || t == Tok.ws,
  onParseFailure: (src) =>
      GreenUnexpected<Tok, Syn>([GreenToken<Tok, Syn>(Tok.error, src)]),
);

/// Tiny minReparseSize so the small test documents actually exercise the
/// incremental paths — the default (50) would full-reparse any document
/// shorter than ~50 chars, which all these fixtures are.
const _smallConfig = IncrementalConfig(minReparseSize: 2);

/// Parse [src] with the full doc parser; expects success.
G _parse(String src) {
  final r = _doc().run(src);
  return (r as Success<ParseError, G>).value;
}

void main() {
  group('tier 1 — token-level micro-update', () {
    test('editing inside a num token splices in place', () {
      const src = '(12+3)';
      final tree = _parse(src);
      // Insert '9' inside '12' (offset 2, between '1' and '2').
      final edit = TextEdit.insert(2, '9');
      final res = tree.applyEdit(src, edit, _parsers());
      expect(res.strategy, IncrementalStrategy.tokenLevel);
      expect(GreenNodeOps.toSource<Tok, Syn>(res.tree), '(192+3)');
    });

    test('editing whitespace splices in place', () {
      const src = '(1 +2)';
      final tree = _parse(src);
      final edit = TextEdit.insert(2, '  '); // widen the space run
      final res = tree.applyEdit(src, edit, _parsers());
      expect(res.strategy, IncrementalStrategy.tokenLevel);
      expect(GreenNodeOps.toSource<Tok, Syn>(res.tree), '(1   +2)');
    });

    test('token-level preserves structural sharing off the edited spine', () {
      const src = '(12)(34)';
      final tree = _parse(src) as GreenTree<Tok, Syn>;
      final secondGroupBefore = tree.children[1];
      final edit = TextEdit.insert(2, '9'); // edit first group's '12'
      final res = tree.applyEdit(src, edit, _parsers());
      final newDoc = res.tree as GreenTree<Tok, Syn>;
      // Second group untouched → same instance.
      expect(identical(newDoc.children[1], secondGroupBefore), isTrue);
    });
  });

  group('tier 2 — block-level reparse', () {
    test('a structural edit reparses just the affected group', () {
      const src = '(12)(34)';
      final tree = _parse(src) as GreenTree<Tok, Syn>;
      final secondGroupBefore = tree.children[1];
      // Insert a '+' into the first group — '+' is not a simple token, so
      // tier 1 is skipped and the group is reparsed.
      final edit = TextEdit.insert(3, '+'); // '(12+)(34)'
      final res = tree.applyEdit(src, edit, _parsers(), config: _smallConfig);
      expect(res.strategy, IncrementalStrategy.blockLevel);
      expect(GreenNodeOps.toSource<Tok, Syn>(res.tree), '(12+)(34)');
      // The untouched second group is shared by reference.
      final newDoc = res.tree as GreenTree<Tok, Syn>;
      expect(identical(newDoc.children[1], secondGroupBefore), isTrue);
    });
  });

  group('tier 3 — full reparse fallback', () {
    test('no reparsable ancestor → full reparse', () {
      const src = '(12)';
      final tree = _parse(src);
      // Edit at offset 0 hits the doc root level; with a structural change
      // ('(' is not simple) and the group boundary involved, the region
      // logic may fall back. Use a bundle with no byKind to force tier 3.
      final noKinds = ReparseableParsers.onlyFull(
        full: _doc(),
        onParseFailure: (s) =>
            GreenUnexpected<Tok, Syn>([GreenToken<Tok, Syn>(Tok.error, s)]),
      );
      final edit = TextEdit.insert(3, '+');
      final res = tree.applyEdit(src, edit, noKinds);
      expect(res.strategy, IncrementalStrategy.fullReparse);
      expect(GreenNodeOps.toSource<Tok, Syn>(res.tree), '(12+)');
    });

    test('unparseable result uses onParseFailure, staying lossless', () {
      const src = '(12)';
      final tree = _parse(src);
      final noKinds = ReparseableParsers.onlyFull(
        full: _doc(),
        onParseFailure: (s) =>
            GreenUnexpected<Tok, Syn>([GreenToken<Tok, Syn>(Tok.error, s)]),
      );
      // Make the document unparseable: an unmatched '('.
      final edit = TextEdit.insert(4, '(');
      final res = tree.applyEdit(src, edit, noKinds);
      expect(res.strategy, IncrementalStrategy.fullReparse);
      // Lossless even on total failure.
      expect(GreenNodeOps.toSource<Tok, Syn>(res.tree), '(12)(');
    });
  });

  group('correctness — incremental matches a fresh full parse', () {
    test('token-level result equals from-scratch parse', () {
      const src = '(12+3)';
      final tree = _parse(src);
      final edit = TextEdit.insert(2, '9');
      final incremental = tree.applyEdit(src, edit, _parsers()).tree;
      final fresh = _parse(edit.apply(src));
      expect(incremental, equals(fresh));
    });

    test('block-level result equals from-scratch parse', () {
      const src = '(12)(34)';
      final tree = _parse(src);
      final edit = TextEdit.insert(3, '+');
      final incremental =
          tree.applyEdit(src, edit, _parsers(), config: _smallConfig).tree;
      final fresh = _parse(edit.apply(src));
      expect(incremental, equals(fresh));
    });
  });

  group('batchIncrementalParse', () {
    test('empty edits returns the tree unchanged', () {
      const src = '(12)';
      final tree = _parse(src);
      final res = batchIncrementalParse(tree, src, const [], _parsers());
      expect(identical(res.tree, tree), isTrue);
    });

    test('single edit delegates to incrementalParse', () {
      const src = '(12+3)';
      final tree = _parse(src);
      final res = batchIncrementalParse(tree, src, [
        TextEdit.insert(2, '9'),
      ], _parsers());
      expect(GreenNodeOps.toSource<Tok, Syn>(res.tree), '(192+3)');
    });

    test('multiple edits combine and match a fresh parse', () {
      const src = '(12)(34)';
      final tree = _parse(src);
      // Two non-overlapping edits, sorted by offset. batchIncrementalParse
      // applies them to the evolving source in sequence (each edit's offsets
      // are in terms of the source as it stands when that edit applies), so
      // we compute the expected source the same way.
      final edits = [
        TextEdit.insert(2, '9'), // '(192)(34)'
        TextEdit.insert(7, '8'), // now offset 7 == before '4' in '(192)(34)'
      ];
      var expected = src;
      for (final e in edits) {
        expected = e.apply(expected);
      }
      expect(expected, '(192)(384)');
      final res = batchIncrementalParse(tree, src, edits, _parsers());
      expect(GreenNodeOps.toSource<Tok, Syn>(res.tree), expected);
      expect(res.tree, equals(_parse(expected)));
    });
  });
}
