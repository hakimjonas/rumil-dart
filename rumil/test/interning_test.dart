import 'package:rumil/rumil.dart';
import 'package:test/test.dart';

enum Tok { digit, plus }

enum Syn { expr }

typedef G = GreenNode<Tok, Syn>;

Parser<ParseError, G> digitTok() =>
    digit().map((c) => GreenToken<Tok, Syn>(Tok.digit, c));

void main() {
  group('GreenCache (unit)', () {
    test('interning structurally-equal greens returns one canonical', () {
      final cache = GreenCache();
      // Non-const so they are genuinely distinct instances — otherwise the
      // Dart compiler would canonicalize two identical const literals into
      // one object and the test would prove nothing. The '5' text is built
      // at runtime to defeat const-folding of the argument too.
      final five1 = String.fromCharCode(0x35);
      final five2 = String.fromCharCode(0x35);
      final a = GreenToken<Tok, Syn>(Tok.digit, five1);
      final b = GreenToken<Tok, Syn>(Tok.digit, five2);
      expect(identical(a, b), isFalse); // distinct instances to start
      final ca = cache.intern(a);
      final cb = cache.intern(b);
      expect(identical(ca, cb), isTrue); // collapsed to one
      expect(identical(ca, a), isTrue); // first wins as canonical
      expect(cache.size, 1);
    });

    test('distinct greens stay distinct', () {
      final cache = GreenCache();
      final five = cache.intern(const GreenToken<Tok, Syn>(Tok.digit, '5'));
      final six = cache.intern(const GreenToken<Tok, Syn>(Tok.digit, '6'));
      expect(identical(five, six), isFalse);
      expect(cache.size, 2);
    });

    test('interns tree subtrees structurally', () {
      final cache = GreenCache();
      G tree() => GreenTree<Tok, Syn>(Syn.expr, [
        const GreenToken<Tok, Syn>(Tok.digit, '1'),
        const GreenToken<Tok, Syn>(Tok.plus, '+'),
        const GreenToken<Tok, Syn>(Tok.digit, '2'),
      ]);
      final a = cache.intern(tree());
      final b = cache.intern(tree());
      expect(identical(a, b), isTrue);
      expect(cache.size, 1);
    });
  });

  group('internToken combinator', () {
    test('repeated identical tokens collapse within one parse', () {
      // Parse three digits, each interned. The two '5's must be identical;
      // the '7' distinct.
      final tok = internToken(digitTok());
      final three = tok.zip(tok).zip(tok).map((nested) {
        final ((a, b), c) = nested;
        return [a, b, c];
      });
      final r = three.run('575');
      final values = (r as Success<ParseError, List<G>>).value;
      expect(identical(values[0], values[2]), isTrue); // both '5'
      expect(identical(values[0], values[1]), isFalse); // '5' vs '7'
    });

    test('parse-scoped: no canonical leaks across separate runs', () {
      final tok = internToken(digitTok());
      final r1 = tok.run('5');
      final r2 = tok.run('5');
      final g1 = (r1 as Success<ParseError, G>).value;
      final g2 = (r2 as Success<ParseError, G>).value;
      // Equal in value, but each parse has its own cache, so not identical.
      expect(g1, equals(g2));
      expect(identical(g1, g2), isFalse);
    });

    test('interning preserves parse semantics (value unchanged)', () {
      final plain = digitTok();
      final interned = internToken(digitTok());
      final rp = plain.run('9') as Success<ParseError, G>;
      final ri = interned.run('9') as Success<ParseError, G>;
      expect(ri.value, equals(rp.value));
      expect(ri.consumed, rp.consumed);
    });

    test('failure passes through interning untouched', () {
      final tok = internToken(digitTok());
      expect(tok.run('x'), isA<Failure<ParseError, G>>());
    });
  });

  group('internTree combinator', () {
    test('identical subtrees across a parse collapse', () {
      // Two parenthesised digits; intern the inner trees. Same structure →
      // identical.
      final inner = internTree(
        treeOf<Tok, Syn>(Syn.expr, [digitTok()]),
      );
      final pair = inner.zip(inner).map((p) => [p.$1, p.$2]);
      final r = pair.run('55');
      final trees = (r as Success<ParseError, List<G>>).value;
      expect(identical(trees[0], trees[1]), isTrue);
    });
  });

  group('RedTree survives interning (sibling identity contract)', () {
    // The reason RedTree disambiguates siblings by childIndex rather than
    // green reference identity is precisely so it survives interning, which
    // makes structurally-equal siblings `identical`. Build such a tree
    // directly and confirm navigation still distinguishes the siblings.
    test('identical sibling greens navigate by position, not identity', () {
      final cache = GreenCache();
      // Two structurally-equal digit tokens, interned to one canonical, used
      // as two siblings of one parent. After interning they are `identical`.
      // Non-const on purpose: the point is two genuinely distinct instances
      // that interning then collapses, not compiler-canonicalized literals.
      // ignore: prefer_const_constructors
      final dig = cache.intern(GreenToken<Tok, Syn>(Tok.digit, '5'));
      final dig2 = cache.intern(
        GreenToken<Tok, Syn>(Tok.digit, String.fromCharCode(0x35)),
      );
      expect(identical(dig, dig2), isTrue); // interning collapsed them

      // Parent with the same canonical green appearing at index 0 and 2,
      // a distinct '+' between them.
      final parent = GreenTree<Tok, Syn>(Syn.expr, [
        dig,
        const GreenToken<Tok, Syn>(Tok.plus, '+'),
        dig2,
      ]);
      final root = RedTree<Tok, Syn>(parent, '5+5');

      final kids = root.children;
      expect(kids.length, 3);
      // The two digit reds wrap the same canonical green but are distinct
      // red views at distinct offsets / indices.
      expect(identical(kids[0].green, kids[2].green), isTrue);
      expect(kids[0].offset, 0);
      expect(kids[2].offset, 2);
      expect(kids[0].childIndex, 0);
      expect(kids[2].childIndex, 2);

      // Navigation distinguishes them despite identical greens.
      expect(kids[0].nextSibling?.text, '+');
      expect(kids[2].prevSibling?.text, '+');
      expect(kids[0].nextSibling?.nextSibling, isNotNull);
      expect(identical(kids[0].nextSibling?.nextSibling, kids[2]), isTrue);

      // pathFromRoot keys on childIndex, so the two collapse-equal greens
      // still get distinct paths.
      expect(kids[0].pathFromRoot, [0]);
      expect(kids[2].pathFromRoot, [2]);
    });
  });
}
