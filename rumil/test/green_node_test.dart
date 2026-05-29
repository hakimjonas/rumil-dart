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
      expect(GreenNodeOps.textLength<JsonTok, JsonSyn>(t), 7);
    });

    test('toSource returns text verbatim', () {
      const t = JsonToken(JsonTok.num, '3.14');
      expect(GreenNodeOps.toSource<JsonTok, JsonSyn>(t), '3.14');
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
      expect(GreenNodeOps.textLength<JsonTok, JsonSyn>(t), 0);
    });

    test('textLength sums children', () {
      const tree = JsonTree(JsonSyn.array, [
        JsonToken(JsonTok.lbracket, '['),
        JsonToken(JsonTok.num, '42'),
        JsonToken(JsonTok.rbracket, ']'),
      ]);
      expect(GreenNodeOps.textLength<JsonTok, JsonSyn>(tree), 4);
    });

    test('toSource concatenates children in order', () {
      const tree = JsonTree(JsonSyn.array, [
        JsonToken(JsonTok.lbracket, '['),
        JsonToken(JsonTok.num, '1'),
        JsonToken(JsonTok.comma, ','),
        JsonToken(JsonTok.num, '2'),
        JsonToken(JsonTok.rbracket, ']'),
      ]);
      expect(GreenNodeOps.toSource<JsonTok, JsonSyn>(tree), '[1,2]');
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
      expect(GreenNodeOps.toSource<JsonTok, JsonSyn>(outer), '[[7]]');
      expect(GreenNodeOps.textLength<JsonTok, JsonSyn>(outer), 5);
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
      expect(GreenNodeOps.textLength<JsonTok, JsonSyn>(m), 0);
    });

    test('toSource is empty', () {
      const m = JsonMissing(JsonTok.rbrace);
      expect(GreenNodeOps.toSource<JsonTok, JsonSyn>(m), isEmpty);
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
      expect(GreenNodeOps.textLength<JsonTok, JsonSyn>(u), 9);
    });

    test('toSource concatenates children verbatim', () {
      const u = JsonUnexpected([
        JsonToken(JsonTok.str, 'garbage'),
        JsonToken(JsonTok.ws, '  '),
      ]);
      expect(GreenNodeOps.toSource<JsonTok, JsonSyn>(u), 'garbage  ');
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
      expect(GreenNodeOps.textLength<JsonTok, JsonSyn>(u), 0);
      expect(GreenNodeOps.toSource<JsonTok, JsonSyn>(u), isEmpty);
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
      expect(GreenNodeOps.toSource<JsonTok, JsonSyn>(tree), '{"key":"value"');
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
      expect(GreenNodeOps.toSource<JsonTok, JsonSyn>(tree), '5+garbage');
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

    test('GreenUnexpected includes child count', () {
      const u = JsonUnexpected([
        JsonToken(JsonTok.str, 'x'),
      ]);
      expect(u.toString(), contains('1 children'));
    });
  });
}
