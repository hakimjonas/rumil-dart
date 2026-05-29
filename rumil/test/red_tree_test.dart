import 'package:rumil/rumil.dart';
import 'package:test/test.dart';

enum Tok { lparen, rparen, plus, num, ws, error }

enum Syn { expr, term, root }

typedef G = GreenNode<Tok, Syn>;
typedef Tk = GreenToken<Tok, Syn>;
typedef Tr = GreenTree<Tok, Syn>;
typedef Miss = GreenMissing<Tok, Syn>;
typedef Unexp = GreenUnexpected<Tok, Syn>;

/// `1+2` as a flat expr tree: three token children.
G onePlusTwo() => Tr(Syn.expr, [
  const Tk(Tok.num, '1'),
  const Tk(Tok.plus, '+'),
  const Tk(Tok.num, '2'),
]);

void main() {
  group('offset and length', () {
    test('root starts at offset 0', () {
      final r = RedTree(onePlusTwo(), '1+2');
      expect(r.offset, 0);
      expect(r.length, 3);
      expect(r.endOffset, 3);
    });

    test('children carry incrementing offsets', () {
      final r = RedTree(onePlusTwo(), '1+2');
      final kids = r.children;
      expect(kids.length, 3);
      expect(kids[0].offset, 0); // '1'
      expect(kids[1].offset, 1); // '+'
      expect(kids[2].offset, 2); // '2'
      expect(kids[0].length, 1);
      expect(kids[1].length, 1);
      expect(kids[2].length, 1);
    });

    test('nested tree offsets accumulate', () {
      // (1+2) — paren wrapper around the expr.
      final g = Tr(Syn.root, [
        const Tk(Tok.lparen, '('),
        Tr(Syn.expr, [
          const Tk(Tok.num, '1'),
          const Tk(Tok.plus, '+'),
          const Tk(Tok.num, '2'),
        ]),
        const Tk(Tok.rparen, ')'),
      ]);
      final r = RedTree(g, '(1+2)');
      expect(r.length, 5);
      final inner = r.children[1]; // the expr
      expect(inner.offset, 1);
      expect(inner.length, 3);
      expect(inner.children[0].offset, 1); // '1'
      expect(inner.children[2].offset, 3); // '2'
      expect(r.children[2].offset, 4); // ')'
    });

    test('Missing child has zero length and shares the following offset', () {
      // `(1+2` with a synthesized Missing ')'.
      final g = Tr(Syn.root, [
        const Tk(Tok.lparen, '('),
        Tr(Syn.expr, [
          const Tk(Tok.num, '1'),
          const Tk(Tok.plus, '+'),
          const Tk(Tok.num, '2'),
        ]),
        const Miss(Tok.rparen),
      ]);
      final r = RedTree(g, '(1+2');
      final missing = r.children[2];
      expect(missing.isMissing, isTrue);
      expect(missing.length, 0);
      expect(missing.offset, 4); // sits at end-of-input
      expect(missing.endOffset, 4);
    });
  });

  group('location and span (real line/column)', () {
    test('single-line resolution', () {
      final r = RedTree(onePlusTwo(), '1+2');
      final plus = r.children[1];
      expect(plus.location.line, 1);
      expect(plus.location.column, 2);
      expect(plus.location.offset, 1);
    });

    test('multi-line resolution', () {
      // A green over a source with newlines. Token offsets are what matter;
      // line/column is resolved against the source string.
      const source = 'a\nbb\nccc';
      // One token covering 'ccc' at offset 5.
      final g = Tr(Syn.root, [
        const Tk(Tok.num, 'a\nbb\nccc'),
      ]);
      final r = RedTree(g, source);
      final tok = r.children[0];
      expect(tok.offset, 0);
      // The span end is at offset 8 = line 3, column 4.
      expect(tok.span.end.line, 3);
      expect(tok.span.end.column, 4);
    });

    test('span covers offset to endOffset', () {
      final r = RedTree(onePlusTwo(), '1+2');
      expect(r.span.start.offset, 0);
      expect(r.span.end.offset, 3);
    });
  });

  group('text', () {
    test('reconstructs from green subtree', () {
      final r = RedTree(onePlusTwo(), '1+2');
      expect(r.text, '1+2');
      expect(r.children[1].text, '+');
    });

    test('Missing contributes empty text', () {
      final g = Tr(Syn.root, [
        const Tk(Tok.num, '1'),
        const Miss(Tok.rparen),
      ]);
      final r = RedTree(g, '1');
      expect(r.text, '1');
    });
  });

  group('navigation', () {
    test('parentNode', () {
      final r = RedTree(onePlusTwo(), '1+2');
      expect(r.parentNode, isNull);
      expect(r.children[0].parentNode, same(r));
    });

    test('nextSibling / prevSibling', () {
      final r = RedTree(onePlusTwo(), '1+2');
      final kids = r.children;
      expect(kids[0].prevSibling, isNull);
      expect(kids[0].nextSibling?.text, '+');
      expect(kids[1].prevSibling?.text, '1');
      expect(kids[1].nextSibling?.text, '2');
      expect(kids[2].nextSibling, isNull);
    });

    test('childIndex', () {
      final r = RedTree(onePlusTwo(), '1+2');
      expect(r.childIndex, 0); // root convention
      expect(r.children[0].childIndex, 0);
      expect(r.children[1].childIndex, 1);
      expect(r.children[2].childIndex, 2);
    });

    test('descendants in pre-order', () {
      final g = Tr(Syn.root, [
        const Tk(Tok.lparen, '('),
        Tr(Syn.expr, [
          const Tk(Tok.num, '1'),
          const Tk(Tok.plus, '+'),
          const Tk(Tok.num, '2'),
        ]),
        const Tk(Tok.rparen, ')'),
      ]);
      final r = RedTree(g, '(1+2)');
      final texts = r.descendants.map((n) => n.text).toList();
      // '(' , expr('1+2'), '1', '+', '2', ')'
      expect(texts, ['(', '1+2', '1', '+', '2', ')']);
    });

    test('ancestors from node to root', () {
      final g = Tr(Syn.root, [
        Tr(Syn.expr, [
          const Tk(Tok.num, '1'),
        ]),
      ]);
      final r = RedTree(g, '1');
      final leaf = r.children[0].children[0]; // the '1' token
      final ancestorKinds = leaf.ancestors.map((n) => n.syntaxKind).toList();
      expect(ancestorKinds, [Syn.expr, Syn.root]);
    });
  });

  group('nodeAt (half-open: start inclusive, end exclusive)', () {
    test('finds the deepest token at an offset', () {
      final r = RedTree(onePlusTwo(), '1+2');
      expect(r.nodeAt(0)?.text, '1');
      expect(r.nodeAt(1)?.text, '+');
      expect(r.nodeAt(2)?.text, '2');
    });

    test('returns null at end-of-input', () {
      final r = RedTree(onePlusTwo(), '1+2');
      expect(r.nodeAt(3), isNull);
    });

    test('returns null before start', () {
      final r = RedTree(onePlusTwo(), '1+2');
      expect(r.nodeAt(-1), isNull);
    });

    test('descends through nested trees', () {
      final g = Tr(Syn.root, [
        const Tk(Tok.lparen, '('),
        Tr(Syn.expr, [
          const Tk(Tok.num, '1'),
          const Tk(Tok.plus, '+'),
          const Tk(Tok.num, '2'),
        ]),
        const Tk(Tok.rparen, ')'),
      ]);
      final r = RedTree(g, '(1+2)');
      // Offsets: '(' at 0, '1' at 1, '+' at 2, '2' at 3, ')' at 4.
      expect(r.nodeAt(1)?.text, '1'); // inside the inner expr
      expect(r.nodeAt(1)?.tokenKind, Tok.num);
      expect(r.nodeAt(2)?.text, '+');
    });
  });

  group('nodeEnclosingRange (right edge inclusive)', () {
    test('insertion at end-of-input resolves to the enclosing root', () {
      // offset 3 == root.endOffset. The last token '2' is [2,3); its
      // half-open interior does not contain 3 (3 < 3 is false), so the
      // descent stops at the root. Consistent with nodeAt(3) == null:
      // no node *starts*-contains end-of-input, so the range resolves up.
      final r = RedTree(onePlusTwo(), '1+2');
      expect(r.nodeEnclosingRange(3, 3), same(r));
    });

    test('edit at a zero-width Missing resolves to the parent, not the '
        'placeholder', () {
      // source '1' with a trailing Missing ')'. Token '1' is [0,1),
      // Missing is [1,1). An edit at offset 1: the token's interior ends
      // at 1 (excluded), the Missing has no interior (1 < 1 is false), so
      // neither child encloses and the result is the parent. A zero-width
      // placeholder never wins an enclosing query — there is no tie-break.
      final g = Tr(Syn.root, [
        const Tk(Tok.num, '1'),
        const Miss(Tok.rparen),
      ]);
      final r = RedTree(g, '1');
      expect(r.nodeEnclosingRange(1, 1), same(r));
    });

    test('insertion between tokens returns common ancestor', () {
      final g = Tr(Syn.root, [
        Tr(Syn.expr, [
          const Tk(Tok.num, '1'),
          const Tk(Tok.plus, '+'),
          const Tk(Tok.num, '2'),
        ]),
      ]);
      final r = RedTree(g, '1+2');
      // Range [1,2] spans '+' fully — deepest enclosing is '+'.
      expect(r.nodeEnclosingRange(1, 2)?.text, '+');
      // Range [0,3] spans the whole expr.
      expect(r.nodeEnclosingRange(0, 3)?.syntaxKind, Syn.expr);
    });

    test('out-of-range returns null', () {
      final r = RedTree(onePlusTwo(), '1+2');
      expect(r.nodeEnclosingRange(0, 4), isNull);
      expect(r.nodeEnclosingRange(-1, 1), isNull);
    });
  });

  group('kind predicates', () {
    test('isToken / isTree / isMissing / isUnexpected', () {
      final g = Tr(Syn.root, [
        const Tk(Tok.num, '1'),
        const Miss(Tok.rparen),
        Unexp([const Tk(Tok.error, 'x')]),
      ]);
      final r = RedTree(g, '1x');
      expect(r.isTree, isTrue);
      expect(r.children[0].isToken, isTrue);
      expect(r.children[1].isMissing, isTrue);
      expect(r.children[2].isUnexpected, isTrue);
    });

    test('syntaxKind / tokenKind / missingKind', () {
      final g = Tr(Syn.expr, [
        const Tk(Tok.num, '1'),
        const Miss(Tok.rparen),
      ]);
      final r = RedTree(g, '1');
      expect(r.syntaxKind, Syn.expr);
      expect(r.tokenKind, isNull);
      expect(r.children[0].tokenKind, Tok.num);
      expect(r.children[0].syntaxKind, isNull);
      expect(r.children[1].missingKind, Tok.rparen);
    });
  });

  group('findReparseAncestor / findReparseRegion', () {
    test('finds nearest reparsable ancestor including self', () {
      final g = Tr(Syn.root, [
        Tr(Syn.expr, [
          const Tk(Tok.num, '1'),
        ]),
      ]);
      final r = RedTree(g, '1');
      final leaf = r.children[0].children[0];
      expect(leaf.findReparseAncestor({Syn.expr})?.syntaxKind, Syn.expr);
      expect(leaf.findReparseAncestor({Syn.root})?.syntaxKind, Syn.root);
      expect(leaf.findReparseAncestor({Syn.term}), isNull);
    });

    test('findReparseRegion descends then walks up', () {
      final g = Tr(Syn.root, [
        Tr(Syn.expr, [
          const Tk(Tok.num, '1'),
          const Tk(Tok.plus, '+'),
          const Tk(Tok.num, '2'),
        ]),
      ]);
      final r = RedTree(g, '1+2');
      // Edit at the '+' (offset 1): smallest reparsable expr ancestor.
      final region = r.findReparseRegion(1, 2, {Syn.expr});
      expect(region?.syntaxKind, Syn.expr);
      expect(region?.text, '1+2');
    });

    test('findReparseRegion returns null when no reparsable kind', () {
      final r = RedTree(onePlusTwo(), '1+2');
      expect(r.findReparseRegion(1, 2, {Syn.term}), isNull);
    });
  });

  group('pathFromRoot', () {
    test('root has empty path', () {
      final r = RedTree(onePlusTwo(), '1+2');
      expect(r.pathFromRoot, isEmpty);
    });

    test('child indices accumulate root-to-node', () {
      final g = Tr(Syn.root, [
        const Tk(Tok.lparen, '('),
        Tr(Syn.expr, [
          const Tk(Tok.num, '1'),
          const Tk(Tok.plus, '+'),
          const Tk(Tok.num, '2'),
        ]),
      ]);
      final r = RedTree(g, '(1+2');
      // root -> child 1 (expr) -> child 2 ('2')
      final two = r.children[1].children[2];
      expect(two.text, '2');
      expect(two.pathFromRoot, [1, 2]);
    });
  });

  group('validateWith', () {
    test('collects Missing as EndOfInput', () {
      final g = Tr(Syn.root, [
        const Tk(Tok.num, '1'),
        const Miss(Tok.rparen),
      ]);
      final r = RedTree(g, '1');
      final errors = r.validateWith((t) => t == Tok.error);
      expect(errors.length, 1);
      expect(errors[0], isA<EndOfInput>());
    });

    test('collects Unexpected as CustomError', () {
      final g = Tr(Syn.root, [
        const Tk(Tok.num, '5'),
        Unexp([const Tk(Tok.error, '+garbage')]),
      ]);
      final r = RedTree(g, '5+garbage');
      final errors = r.validateWith((t) => t == Tok.error);
      // One for the Unexpected wrapper, one for the error token inside it.
      expect(errors.whereType<CustomError>().length, greaterThanOrEqualTo(1));
      expect(errors.any((e) => e.toString().contains('Unexpected')), isTrue);
    });

    test('collects error tokens via the predicate', () {
      final g = Tr(Syn.root, [
        const Tk(Tok.error, '?'),
      ]);
      final r = RedTree(g, '?');
      final errors = r.validateWith((t) => t == Tok.error);
      expect(errors.length, 1);
      expect(errors[0], isA<CustomError>());
      expect(errors[0].toString(), contains('Error token'));
    });

    test('clean tree yields no errors', () {
      final r = RedTree(onePlusTwo(), '1+2');
      expect(r.validateWith((t) => t == Tok.error), isEmpty);
    });

    test('errors come out in source order', () {
      final g = Tr(Syn.root, [
        const Tk(Tok.error, 'a'),
        Tr(Syn.expr, [
          const Tk(Tok.error, 'b'),
        ]),
        const Tk(Tok.error, 'c'),
      ]);
      final r = RedTree(g, 'abc');
      final errors = r.validateWith((t) => t == Tok.error);
      final offsets = errors.map((e) => e.location.offset).toList();
      expect(offsets, [0, 1, 2]);
    });
  });

  group('stack safety', () {
    RedTree<Tok, Syn> buildDeep(int depth) {
      G current = const Tk(Tok.num, '0');
      for (var i = 0; i < depth; i++) {
        current = Tr(Syn.expr, [
          const Tk(Tok.lparen, '('),
          current,
          const Tk(Tok.rparen, ')'),
        ]);
      }
      return RedTree(current, '${'(' * depth}0${')' * depth}');
    }

    test('descendants on 50k-deep tree does not overflow', () {
      final r = buildDeep(50000);
      // Each level adds 3 descendants (lparen, inner subtree, rparen) but
      // the inner subtree node is itself counted once; total descendants =
      // 50000 levels * 3 nodes - but simplest assertion is "completes and
      // is large".
      expect(r.descendants.length, greaterThan(50000));
    });

    test('nodeAt on 50k-deep tree does not overflow', () {
      final r = buildDeep(50000);
      // Offset 50000 is the inner '0'.
      expect(r.nodeAt(50000)?.text, '0');
    });

    test('validateWith on 50k-deep tree does not overflow', () {
      final r = buildDeep(50000);
      expect(r.validateWith((t) => t == Tok.error), isEmpty);
    });
  });

  group('toString', () {
    test('includes kind, offset, length', () {
      final r = RedTree(onePlusTwo(), '1+2');
      expect(r.toString(), contains('Tree(Syn.expr)'));
      expect(r.toString(), contains('offset=0'));
      expect(r.toString(), contains('length=3'));
    });
  });
}
