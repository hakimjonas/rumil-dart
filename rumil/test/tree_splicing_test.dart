import 'package:rumil/rumil.dart';
import 'package:test/test.dart';

enum Tok { lparen, rparen, plus, num }

enum Syn { expr, root }

typedef G = GreenNode<Tok, Syn>;
typedef Tk = GreenToken<Tok, Syn>;
typedef Tr = GreenTree<Tok, Syn>;
typedef Unexp = GreenUnexpected<Tok, Syn>;

/// `(1+2)` as root[ '(', expr[ '1','+','2' ], ')' ].
G sample() => Tr(Syn.root, [
  const Tk(Tok.lparen, '('),
  Tr(Syn.expr, [
    const Tk(Tok.num, '1'),
    const Tk(Tok.plus, '+'),
    const Tk(Tok.num, '2'),
  ]),
  const Tk(Tok.rparen, ')'),
]);

void main() {
  group('replaceAt — basic', () {
    test('empty path replaces the whole root', () {
      final root = sample();
      const replacement = Tk(Tok.num, '9');
      final out = TreeSplicing.replaceAt<Tok, Syn>(root, const [], replacement);
      expect(identical(out, replacement), isTrue);
    });

    test('replace a top-level child', () {
      final root = sample();
      const replacement = Tk(Tok.num, '0');
      // Index 0 is the '(' token.
      final out =
          TreeSplicing.replaceAt<Tok, Syn>(root, const [0], replacement)!;
      expect(GreenNodeOps.toSource<Tok, Syn>(out), '01+2)');
    });

    test('replace a deeply-nested child', () {
      final root = sample();
      const replacement = Tk(Tok.num, '7');
      // root -> child 1 (expr) -> child 0 ('1').
      final out =
          TreeSplicing.replaceAt<Tok, Syn>(root, const [1, 0], replacement)!;
      expect(GreenNodeOps.toSource<Tok, Syn>(out), '(7+2)');
    });

    test('replace with a larger subtree updates textLength up the spine', () {
      final root = sample();
      // Replace the '1' with a parenthesised group '(8)' (length 3).
      final replacement = Tr(Syn.expr, [
        const Tk(Tok.lparen, '('),
        const Tk(Tok.num, '8'),
        const Tk(Tok.rparen, ')'),
      ]);
      final out =
          TreeSplicing.replaceAt<Tok, Syn>(root, const [1, 0], replacement)!;
      expect(GreenNodeOps.toSource<Tok, Syn>(out), '((8)+2)');
      // textLength recomputed: '((8)+2)' is 7 chars.
      expect(out.textLength, 7);
      // The expr subtree's length also updated: '(8)+2' is 5.
      final expr = (out as Tr).children[1];
      expect(expr.textLength, 5);
    });
  });

  group('replaceAt — structural sharing', () {
    test('off-path siblings are reused by reference', () {
      final root = sample() as Tr;
      final originalLparen = root.children[0];
      final originalRparen = root.children[2];
      final originalExpr = root.children[1] as Tr;
      final originalPlus = originalExpr.children[1];
      final originalTwo = originalExpr.children[2];

      // Replace the '1' (path [1,0]).
      final out =
          TreeSplicing.replaceAt<Tok, Syn>(root, const [
                1,
                0,
              ], const Tk(Tok.num, '7'))!
              as Tr;

      // Root's off-path children ('(' and ')') are the SAME instances.
      expect(identical(out.children[0], originalLparen), isTrue);
      expect(identical(out.children[2], originalRparen), isTrue);

      // Within the rebuilt expr, the off-path siblings ('+' and '2') are
      // the same instances; only '1' changed.
      final newExpr = out.children[1] as Tr;
      expect(identical(newExpr.children[1], originalPlus), isTrue);
      expect(identical(newExpr.children[2], originalTwo), isTrue);
      expect(newExpr.children[0].textLength, 1);
      expect((newExpr.children[0] as Tk).text, '7');

      // On-path nodes are NEW instances (root and expr were rebuilt).
      expect(identical(out, root), isFalse);
      expect(identical(out.children[1], originalExpr), isFalse);
    });

    test('original tree is unmodified (persistence)', () {
      final root = sample();
      TreeSplicing.replaceAt<Tok, Syn>(root, const [
        1,
        0,
      ], const Tk(Tok.num, '7'));
      // Original still reads as before.
      expect(GreenNodeOps.toSource<Tok, Syn>(root), '(1+2)');
    });
  });

  group('replaceAt — unresolvable paths return null', () {
    test('index out of range at the top level', () {
      final root = sample();
      expect(
        TreeSplicing.replaceAt<Tok, Syn>(root, const [
          9,
        ], const Tk(Tok.num, '0')),
        isNull,
      );
    });

    test('index out of range deeper', () {
      final root = sample();
      expect(
        TreeSplicing.replaceAt<Tok, Syn>(root, const [
          1,
          9,
        ], const Tk(Tok.num, '0')),
        isNull,
      );
    });

    test('descending into a leaf', () {
      final root = sample();
      // Index 0 is the '(' token (a leaf); can't descend further.
      expect(
        TreeSplicing.replaceAt<Tok, Syn>(root, const [
          0,
          0,
        ], const Tk(Tok.num, '0')),
        isNull,
      );
    });

    test('negative index', () {
      final root = sample();
      expect(
        TreeSplicing.replaceAt<Tok, Syn>(root, const [
          -1,
        ], const Tk(Tok.num, '0')),
        isNull,
      );
    });
  });

  group('replaceAt — GreenUnexpected is descendable', () {
    test('replace a child inside an Unexpected wrapper', () {
      final root = Tr(Syn.root, [
        Unexp([const Tk(Tok.num, 'x'), const Tk(Tok.num, 'y')]),
      ]);
      // root -> child 0 (Unexpected) -> child 1 ('y').
      final out =
          TreeSplicing.replaceAt<Tok, Syn>(root, const [
            0,
            1,
          ], const Tk(Tok.num, 'z'))!;
      expect(GreenNodeOps.toSource<Tok, Syn>(out), 'xz');
      expect((out as Tr).children[0], isA<Unexp>());
    });
  });

  group('replaceAt — round-trips with RedTree.pathFromRoot', () {
    test('a path read from a RedTree splices back at that node', () {
      final root = sample();
      final red = RedTree<Tok, Syn>(root, '(1+2)');
      // Find the '+' via nodeAt, read its path, splice a '-' there.
      final plus = red.nodeAt(2)!; // '+' at offset 2
      expect(plus.text, '+');
      final path = plus.pathFromRoot;
      final out =
          TreeSplicing.replaceAt<Tok, Syn>(
            root,
            path,
            const Tk(Tok.plus, '-'),
          )!;
      expect(GreenNodeOps.toSource<Tok, Syn>(out), '(1-2)');
    });
  });

  group('replaceAt — stack safety', () {
    test('replace the leaf of a 100k-deep spine', () {
      // Build root[ child[ child[ ... [ '0' ] ] ] ] 100k deep, path all 0s.
      G current = const Tk(Tok.num, '0');
      for (var i = 0; i < 100000; i++) {
        current = Tr(Syn.expr, [current]);
      }
      final path = List<int>.filled(100000, 0);
      final out = TreeSplicing.replaceAt<Tok, Syn>(
        current,
        path,
        const Tk(Tok.num, '1'),
      );
      expect(out, isNotNull);
      expect(GreenNodeOps.toSource<Tok, Syn>(out!), '1');
    });
  });
}
