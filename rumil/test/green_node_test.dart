import 'package:rumil/rumil.dart';
import 'package:test/test.dart';

/// A small token alphabet used across these tests. Concrete enums are
/// the canonical way for grammar authors to declare a language's tokens;
/// `JsonTok` here stands in for any real grammar's choice.
enum JsonTok { lbrace, rbrace, lbracket, rbracket, comma, colon, str, num, bool_, null_, ws }

/// A small syntax-tree-node alphabet.
enum JsonSyn { document, object, array, member, value }

/// Convenience aliases for the test's language shape. Matches the
/// per-language typedef pattern recommended for downstream consumers.
typedef JsonGreen = GreenNode<JsonTok, JsonSyn>;
typedef JsonToken = GreenToken<JsonTok, JsonSyn>;
typedef JsonTree = GreenTree<JsonTok, JsonSyn>;
typedef JsonMissing = GreenMissing<JsonTok, JsonSyn>;
typedef JsonUnexpected = GreenUnexpected<JsonTok, JsonSyn>;

void main() {
  group('GreenToken', () {
    test('textLength is text.length', () {
      const t = JsonToken(JsonTok.str, '"hello"');
      expect(t.textLength, 7);
    });

    test('toSource returns text verbatim', () {
      const t = JsonToken(JsonTok.num, '3.14');
      expect(t.toSource(), '3.14');
    });

    test('equality is structural', () {
      const a = JsonToken(JsonTok.lbrace, '{');
      const b = JsonToken(JsonTok.lbrace, '{');
      const c = JsonToken(JsonTok.lbrace, '} ');
      const d = JsonToken(JsonTok.rbrace, '{');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });

    test('different generic instantiations are unequal', () {
      const a = JsonToken(JsonTok.lbrace, '{');
      const b = GreenToken<int, String>(0, '{');
      // ignore: unrelated_type_equality_checks
      expect(a == b, isFalse);
    });
  });

  group('GreenTree', () {
    test('empty children give zero textLength', () {
      const t = JsonTree(JsonSyn.document, []);
      expect(t.textLength, 0);
    });

    test('textLength sums children', () {
      const tree = JsonTree(JsonSyn.array, [
        JsonToken(JsonTok.lbracket, '['),
        JsonToken(JsonTok.num, '42'),
        JsonToken(JsonTok.rbracket, ']'),
      ]);
      expect(tree.textLength, 4);
    });

    test('toSource concatenates children in order', () {
      const tree = JsonTree(JsonSyn.array, [
        JsonToken(JsonTok.lbracket, '['),
        JsonToken(JsonTok.num, '1'),
        JsonToken(JsonTok.comma, ','),
        JsonToken(JsonTok.num, '2'),
        JsonToken(JsonTok.rbracket, ']'),
      ]);
      expect(tree.toSource(), '[1,2]');
    });

    test('toSource is recursive', () {
      const inner = JsonTree(JsonSyn.array, [
        JsonToken(JsonTok.lbracket, '['),
        JsonToken(JsonTok.num, '7'),
        JsonToken(JsonTok.rbracket, ']'),
      ]);
      const outer = JsonTree(JsonSyn.array, [
        JsonToken(JsonTok.lbracket, '['),
        inner,
        JsonToken(JsonTok.rbracket, ']'),
      ]);
      expect(outer.toSource(), '[[7]]');
      expect(outer.textLength, 5);
    });

    test('equality is structural and recursive', () {
      const a = JsonTree(JsonSyn.array, [
        JsonToken(JsonTok.lbracket, '['),
        JsonToken(JsonTok.num, '1'),
        JsonToken(JsonTok.rbracket, ']'),
      ]);
      const b = JsonTree(JsonSyn.array, [
        JsonToken(JsonTok.lbracket, '['),
        JsonToken(JsonTok.num, '1'),
        JsonToken(JsonTok.rbracket, ']'),
      ]);
      const differentKind = JsonTree(JsonSyn.object, [
        JsonToken(JsonTok.lbracket, '['),
        JsonToken(JsonTok.num, '1'),
        JsonToken(JsonTok.rbracket, ']'),
      ]);
      const differentChild = JsonTree(JsonSyn.array, [
        JsonToken(JsonTok.lbracket, '['),
        JsonToken(JsonTok.num, '2'),
        JsonToken(JsonTok.rbracket, ']'),
      ]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(differentKind)));
      expect(a, isNot(equals(differentChild)));
    });
  });

  group('GreenMissing', () {
    test('textLength is zero', () {
      const m = JsonMissing(JsonTok.rbrace);
      expect(m.textLength, 0);
    });

    test('toSource is empty', () {
      const m = JsonMissing(JsonTok.rbrace);
      expect(m.toSource(), isEmpty);
    });

    test('equality is by expected kind', () {
      const a = JsonMissing(JsonTok.rbrace);
      const b = JsonMissing(JsonTok.rbrace);
      const c = JsonMissing(JsonTok.rbracket);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('does not equal a token of the same kind', () {
      const m = JsonMissing(JsonTok.rbrace);
      const t = JsonToken(JsonTok.rbrace, '}');
      // ignore: unrelated_type_equality_checks
      expect(m == t, isFalse);
    });
  });

  group('GreenUnexpected', () {
    test('textLength sums children', () {
      const u = JsonUnexpected([
        JsonToken(JsonTok.str, 'garbage'),
        JsonToken(JsonTok.ws, '  '),
      ]);
      expect(u.textLength, 9);
    });

    test('toSource concatenates children verbatim', () {
      const u = JsonUnexpected([
        JsonToken(JsonTok.str, 'garbage'),
        JsonToken(JsonTok.ws, '  '),
      ]);
      expect(u.toSource(), 'garbage  ');
    });

    test('equality is structural and recursive', () {
      const a = JsonUnexpected([
        JsonToken(JsonTok.str, 'x'),
      ]);
      const b = JsonUnexpected([
        JsonToken(JsonTok.str, 'x'),
      ]);
      const c = JsonUnexpected([
        JsonToken(JsonTok.str, 'y'),
      ]);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('empty unexpected (zero-width recovery placeholder)', () {
      const u = JsonUnexpected([]);
      expect(u.textLength, 0);
      expect(u.toSource(), isEmpty);
    });
  });

  group('Lossless invariant', () {
    test('mixed tree with Missing and Unexpected reconstructs source', () {
      // Models a `{key: value` (missing closing brace) where the parser
      // produced `}` as Missing. The Missing contributes zero characters
      // so toSource matches what was actually present in the input.
      const tree = JsonTree(JsonSyn.object, [
        JsonToken(JsonTok.lbrace, '{'),
        JsonTree(JsonSyn.member, [
          JsonToken(JsonTok.str, '"key"'),
          JsonToken(JsonTok.colon, ':'),
          JsonToken(JsonTok.str, '"value"'),
        ]),
        JsonMissing(JsonTok.rbrace),
      ]);
      expect(tree.toSource(), '{"key":"value"');
    });

    test('skipped region wrapped in Unexpected reconstructs verbatim', () {
      // Models a recovered statement: valid prefix then garbage skipped
      // and wrapped, total source matches the original input text.
      const tree = JsonTree(JsonSyn.value, [
        JsonToken(JsonTok.num, '5'),
        JsonUnexpected([
          JsonToken(JsonTok.str, '+garbage'),
        ]),
      ]);
      expect(tree.toSource(), '5+garbage');
    });
  });

  group('Stack safety', () {
    /// Build `((((...))))`-style nesting at the requested depth.
    /// Each level wraps the previous tree as the middle child of an
    /// outer `value`-kinded tree with `(` and `)` token children.
    JsonGreen buildDeepTree(int depth) {
      JsonGreen current = const JsonToken(JsonTok.num, '0');
      for (var i = 0; i < depth; i++) {
        current = JsonTree(JsonSyn.value, [
          const JsonToken(JsonTok.lbracket, '('),
          current,
          const JsonToken(JsonTok.rbracket, ')'),
        ]);
      }
      return current;
    }

    test('textLength on 100k-deep nested tree does not overflow', () {
      final deep = buildDeepTree(100000);
      // 100k pairs of parentheses + the inner '0'.
      expect(deep.textLength, 100000 * 2 + 1);
    });

    test('toSource on 100k-deep nested tree does not overflow', () {
      final deep = buildDeepTree(100000);
      final source = deep.toSource();
      expect(source.length, 100000 * 2 + 1);
      expect(source.startsWith('('), isTrue);
      expect(source.endsWith(')'), isTrue);
      expect(source.contains('0'), isTrue);
    });
  });

  group('toString', () {
    test('GreenToken includes kind and text preview', () {
      const t = JsonToken(JsonTok.num, '42');
      expect(t.toString(), contains('JsonTok.num'));
      expect(t.toString(), contains('42'));
    });

    test('GreenTree includes kind and child count', () {
      const t = JsonTree(JsonSyn.array, [
        JsonToken(JsonTok.lbracket, '['),
        JsonToken(JsonTok.rbracket, ']'),
      ]);
      expect(t.toString(), contains('JsonSyn.array'));
      expect(t.toString(), contains('2 children'));
    });

    test('GreenMissing includes expected kind', () {
      const m = JsonMissing(JsonTok.rbrace);
      expect(m.toString(), contains('JsonTok.rbrace'));
    });

    test('GreenUnexpected uses singular for one child', () {
      const u = JsonUnexpected([
        JsonToken(JsonTok.str, 'x'),
      ]);
      expect(u.toString(), contains('1 child'));
      expect(u.toString(), isNot(contains('1 children')));
    });

    test('GreenUnexpected uses plural for two children', () {
      const u = JsonUnexpected([
        JsonToken(JsonTok.str, 'x'),
        JsonToken(JsonTok.str, 'y'),
      ]);
      expect(u.toString(), contains('2 children'));
    });

    test('GreenTree uses singular for one child', () {
      const t = JsonTree(JsonSyn.array, [
        JsonToken(JsonTok.lbracket, '['),
      ]);
      expect(t.toString(), contains('1 child'));
      expect(t.toString(), isNot(contains('1 children')));
    });
  });
}
