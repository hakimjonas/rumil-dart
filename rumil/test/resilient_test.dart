import 'package:rumil/rumil.dart';
import 'package:test/test.dart';

enum Tok { lparen, rparen, digit, error }

enum Syn { group, list }

typedef G = GreenNode<Tok, Syn>;

/// A single digit as a green token.
Parser<ParseError, G> digitTok() =>
    digit().map((c) => GreenToken<Tok, Syn>(Tok.digit, c));

Parser<ParseError, G> lparenTok() =>
    char('(').map((c) => GreenToken<Tok, Syn>(Tok.lparen, c));

Parser<ParseError, G> rparenTok() =>
    char(')').map((c) => GreenToken<Tok, Syn>(Tok.rparen, c));

void main() {
  group('treeOf', () {
    test('composes children into a GreenTree in order', () {
      final p = treeOf<Tok, Syn>(Syn.group, [
        lparenTok(),
        digitTok(),
        rparenTok(),
      ]);
      final r = p.run('(5)');
      expect(r, isA<Success<ParseError, G>>());
      final tree = (r as Success<ParseError, G>).value;
      expect(tree, isA<GreenTree<Tok, Syn>>());
      expect(GreenNodeOps.toSource<Tok, Syn>(tree), '(5)');
      final asTree = tree as GreenTree<Tok, Syn>;
      expect(asTree.kind, Syn.group);
      expect(asTree.children.length, 3);
      expect(asTree.children[1], isA<GreenToken<Tok, Syn>>());
    });

    test('fails if a required child fails', () {
      final p = treeOf<Tok, Syn>(Syn.group, [
        lparenTok(),
        digitTok(),
        rparenTok(),
      ]);
      // 'x' is not a digit.
      expect(p.run('(x)'), isA<Failure<ParseError, G>>());
    });

    test('each run gets a fresh accumulator (no leak across runs)', () {
      final p = treeOf<Tok, Syn>(Syn.group, [
        lparenTok(),
        digitTok(),
        rparenTok(),
      ]);
      final a = (p.run('(1)') as Success<ParseError, G>).value
          as GreenTree<Tok, Syn>;
      final b = (p.run('(2)') as Success<ParseError, G>).value
          as GreenTree<Tok, Syn>;
      // If the accumulator leaked, b would carry a's children too.
      expect(a.children.length, 3);
      expect(b.children.length, 3);
      expect(GreenNodeOps.toSource<Tok, Syn>(a), '(1)');
      expect(GreenNodeOps.toSource<Tok, Syn>(b), '(2)');
    });

    test('empty parts yields an empty tree, consuming nothing', () {
      final p = treeOf<Tok, Syn>(Syn.group, []);
      final r = p.run('abc');
      expect(r, isA<Success<ParseError, G>>());
      final tree = (r as Success<ParseError, G>).value as GreenTree<Tok, Syn>;
      expect(tree.children, isEmpty);
      expect(tree.kind, Syn.group);
      expect(GreenNodeOps.toSource<Tok, Syn>(tree), isEmpty);
    });

    test('nested treeOf', () {
      final inner = treeOf<Tok, Syn>(Syn.group, [
        lparenTok(),
        digitTok(),
        rparenTok(),
      ]);
      final outer = treeOf<Tok, Syn>(Syn.list, [
        lparenTok(),
        inner,
        rparenTok(),
      ]);
      final r = outer.run('((5))');
      final tree = (r as Success<ParseError, G>).value;
      expect(GreenNodeOps.toSource<Tok, Syn>(tree), '((5))');
      expect((tree as GreenTree<Tok, Syn>).kind, Syn.list);
    });
  });

  group('expectToken', () {
    test('returns the inner green on success', () {
      final p = expectToken<Tok, Syn>(Tok.rparen, rparenTok());
      final r = p.run(')');
      expect(r, isA<Success<ParseError, G>>());
      final g = (r as Success<ParseError, G>).value;
      expect(g, isA<GreenToken<Tok, Syn>>());
      expect((g as GreenToken<Tok, Syn>).kind, Tok.rparen);
    });

    test('synthesizes a zero-width Missing on failure as Partial', () {
      final p = expectToken<Tok, Syn>(Tok.rparen, rparenTok());
      // Input does not contain ')'.
      final r = p.run('x');
      expect(r, isA<Partial<ParseError, G>>());
      final partial = r as Partial<ParseError, G>;
      expect(partial.value, isA<GreenMissing<Tok, Syn>>());
      expect((partial.value as GreenMissing<Tok, Syn>).expected, Tok.rparen);
      expect(partial.consumed, 0); // zero-width, nothing consumed
      expect(partial.errors, isNotEmpty); // inner errors surfaced
    });

    test('composes inside treeOf to recover a missing closer', () {
      // `( digit )` where the ')' may be missing.
      final group = treeOf<Tok, Syn>(Syn.group, [
        lparenTok(),
        digitTok(),
        expectToken<Tok, Syn>(Tok.rparen, rparenTok()),
      ]);
      // Missing ')': '(5' — parser recovers, tree has a Missing child.
      final r = group.run('(5');
      expect(r, isA<Partial<ParseError, G>>());
      final tree = (r as Partial<ParseError, G>).value as GreenTree<Tok, Syn>;
      expect(tree.children.length, 3);
      expect(tree.children[2], isA<GreenMissing<Tok, Syn>>());
      // Lossless: Missing is zero-width, so source is what was present.
      expect(GreenNodeOps.toSource<Tok, Syn>(tree), '(5');
    });
  });

  group('syncUntil', () {
    test('returns the inner green on success, no Unexpected', () {
      final p = syncUntil<Tok, Syn>(digitTok(), {';'}, Tok.error);
      final r = p.run('7');
      expect(r, isA<Success<ParseError, G>>());
      expect((r as Success<ParseError, G>).value, isA<GreenToken<Tok, Syn>>());
    });

    test('skips to the sync char and wraps skipped text in Unexpected', () {
      final p = syncUntil<Tok, Syn>(digitTok(), {';'}, Tok.error);
      // 'xyz;' — inner (digit) fails at 'x', skip to ';'.
      final r = p.run('xyz;');
      expect(r, isA<Partial<ParseError, G>>());
      final partial = r as Partial<ParseError, G>;
      final g = partial.value;
      expect(g, isA<GreenUnexpected<Tok, Syn>>());
      final unexp = g as GreenUnexpected<Tok, Syn>;
      expect(unexp.children.length, 1);
      expect(GreenNodeOps.toSource<Tok, Syn>(unexp), 'xyz');
      // The sync char ';' is left unconsumed.
      expect(partial.consumed, 3);
    });

    test('sync char at failure offset → zero-width Unexpected', () {
      final p = syncUntil<Tok, Syn>(digitTok(), {';'}, Tok.error);
      // ';' immediately — inner fails, nothing to skip.
      final r = p.run(';');
      expect(r, isA<Partial<ParseError, G>>());
      final partial = r as Partial<ParseError, G>;
      final unexp = partial.value as GreenUnexpected<Tok, Syn>;
      expect(unexp.children, isEmpty);
      expect(partial.consumed, 0);
    });

    test('no sync char → skips to end-of-input', () {
      final p = syncUntil<Tok, Syn>(digitTok(), {';'}, Tok.error);
      final r = p.run('xyz');
      expect(r, isA<Partial<ParseError, G>>());
      final partial = r as Partial<ParseError, G>;
      final unexp = partial.value as GreenUnexpected<Tok, Syn>;
      expect(GreenNodeOps.toSource<Tok, Syn>(unexp), 'xyz');
      expect(partial.consumed, 3);
    });

    test('lossless: source reconstructs across the recovery boundary', () {
      // A list of digits separated by ';', with one garbage element
      // recovered. Build: digit-or-sync, repeated.
      final element = syncUntil<Tok, Syn>(digitTok(), {';'}, Tok.error);
      final r = element.run('xy;');
      final partial = r as Partial<ParseError, G>;
      // The element captured 'xy'; ';' remains for a following parser.
      expect(GreenNodeOps.toSource<Tok, Syn>(partial.value), 'xy');
    });
  });
}
