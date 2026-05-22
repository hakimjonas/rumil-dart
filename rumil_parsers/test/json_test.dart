import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

JsonValue val_(Result<ParseError, JsonValue> r) => switch (r) {
  Success<ParseError, JsonValue>(:final value) => value,
  Partial<ParseError, JsonValue>(:final value) => value,
  Failure() => throw StateError('Expected success, got ${r.errors}'),
};

void main() {
  group('JSON literals', () {
    test('null', () {
      expect(val_(parseJson('null')), isA<JsonNull>());
    });

    test('true', () {
      final v = val_(parseJson('true'));
      expect(v, isA<JsonBool>());
      expect((v as JsonBool).value, true);
    });

    test('false', () {
      final v = val_(parseJson('false'));
      expect((v as JsonBool).value, false);
    });
  });

  group('JSON numbers', () {
    test('integer parses as JsonInt', () {
      final v = val_(parseJson('42')) as JsonInt;
      expect(v.value, 42);
    });

    test('negative integer parses as JsonInt', () {
      final v = val_(parseJson('-17')) as JsonInt;
      expect(v.value, -17);
    });

    test('float parses as JsonDouble', () {
      final v = val_(parseJson('3.14')) as JsonDouble;
      expect(v.value, closeTo(3.14, 0.001));
    });

    test('exponent parses as JsonDouble', () {
      final v = val_(parseJson('1e10')) as JsonDouble;
      expect(v.value, 1e10);
    });

    test('negative exponent parses as JsonDouble', () {
      final v = val_(parseJson('2.5e-3')) as JsonDouble;
      expect(v.value, closeTo(0.0025, 1e-10));
    });

    test('zero parses as JsonInt', () {
      final v = val_(parseJson('0')) as JsonInt;
      expect(v.value, 0);
    });

    test('integer-valued float preserves source token shape', () {
      // `1.0` keeps a decimal point, so it's JsonDouble — NOT JsonInt.
      // The source-token-shape preservation pins round-trip fidelity:
      // see serialize_test.dart for the back half of the round-trip.
      final v = val_(parseJson('1.0'));
      expect(v, isA<JsonDouble>());
      expect((v as JsonDouble).value, 1.0);
    });

    test('big integer fits in int → JsonInt (preserved exactly)', () {
      // 2^53 + 1 cannot be represented exactly in `double`. The split
      // AST keeps it in `int`, so consumers like jsonToNative get the
      // exact value rather than the rounded double.
      final v = val_(parseJson('9007199254740993'));
      expect(v, isA<JsonInt>());
      expect((v as JsonInt).value, 9007199254740993);
    });

    test('integer overflow falls back to JsonDouble', () {
      // Beyond Dart's `int` range, falls back to double per
      // `dart:convert`'s rule. Big-int storage is reserved for a
      // future release.
      final v = val_(parseJson('99999999999999999999'));
      expect(v, isA<JsonDouble>());
    });

    test('JsonInt(1) != JsonDouble(1.0)', () {
      // Discrimination across the variants matches serde_json, Jackson,
      // circe — numeric equality is intentionally NOT identity here.
      // Hash codes for `int.hashCode` and `double.hashCode` collide on
      // numerically-equal values per Dart's standard contract; that's
      // fine for hash-table correctness because `==` still returns
      // `false` so collisions resolve correctly.
      expect(const JsonInt(1) == const JsonDouble(1.0), isFalse);
      expect(const JsonDouble(1.0) == const JsonInt(1), isFalse);
    });
  });

  group('JSON strings', () {
    test('simple', () {
      final v = val_(parseJson('"hello"')) as JsonString;
      expect(v.value, 'hello');
    });

    test('empty', () {
      final v = val_(parseJson('""')) as JsonString;
      expect(v.value, '');
    });

    test('escape sequences', () {
      final v = val_(parseJson(r'"a\nb\tc"')) as JsonString;
      expect(v.value, 'a\nb\tc');
    });

    test('escaped quotes', () {
      final v = val_(parseJson(r'"say \"hello\""')) as JsonString;
      expect(v.value, 'say "hello"');
    });

    test('escaped backslash', () {
      final v = val_(parseJson(r'"a\\b"')) as JsonString;
      expect(v.value, r'a\b');
    });

    test('unicode escape', () {
      final v = val_(parseJson(r'"\u0041"')) as JsonString;
      expect(v.value, 'A');
    });
  });

  group('JSON arrays', () {
    test('empty', () {
      final v = val_(parseJson('[]')) as JsonArray;
      expect(v.elements, isEmpty);
    });

    test('single element', () {
      final v = val_(parseJson('[1]')) as JsonArray;
      expect(v.elements.length, 1);
      expect((v.elements[0] as JsonInt).value, 1);
    });

    test('multiple elements', () {
      final v = val_(parseJson('[1, "two", true, null]')) as JsonArray;
      expect(v.elements.length, 4);
      expect(v.elements[0], isA<JsonInt>());
      expect(v.elements[1], isA<JsonString>());
      expect(v.elements[2], isA<JsonBool>());
      expect(v.elements[3], isA<JsonNull>());
    });

    test('nested', () {
      final v = val_(parseJson('[[1, 2], [3, 4]]')) as JsonArray;
      expect(v.elements.length, 2);
      expect((v.elements[0] as JsonArray).elements.length, 2);
    });
  });

  group('JSON objects', () {
    test('empty', () {
      final v = val_(parseJson('{}')) as JsonObject;
      expect(v.fields, isEmpty);
    });

    test('single field', () {
      final v = val_(parseJson('{"name": "Rumil"}')) as JsonObject;
      expect((v.fields['name'] as JsonString).value, 'Rumil');
    });

    test('multiple fields', () {
      final v = val_(parseJson('{"a": 1, "b": true, "c": null}')) as JsonObject;
      expect(v.fields.length, 3);
      expect((v.fields['a'] as JsonInt).value, 1);
      expect((v.fields['b'] as JsonBool).value, true);
      expect(v.fields['c'], isA<JsonNull>());
    });

    test('nested objects', () {
      final v = val_(parseJson('{"x": {"y": 42}}')) as JsonObject;
      final inner = v.fields['x'] as JsonObject;
      expect((inner.fields['y'] as JsonInt).value, 42);
    });
  });

  group('JSON whitespace', () {
    test('leading and trailing', () {
      final v = val_(parseJson('  42  '));
      expect(v, isA<JsonInt>());
    });

    test('around structural characters', () {
      final v = val_(parseJson('{ "a" : [ 1 , 2 ] }')) as JsonObject;
      expect((v.fields['a'] as JsonArray).elements.length, 2);
    });

    test('newlines and tabs', () {
      final v = val_(parseJson('{\n\t"x": 1\n}')) as JsonObject;
      expect(v.fields.containsKey('x'), true);
    });
  });

  group('JSON complex', () {
    test('realistic document', () {
      const input = '''
      {
        "name": "Rumil",
        "version": "0.1.0",
        "features": ["parsing", "left-recursion", "memoization"],
        "config": {
          "strict": true,
          "maxDepth": null
        }
      }
      ''';
      final v = val_(parseJson(input)) as JsonObject;
      expect((v.fields['name'] as JsonString).value, 'Rumil');
      expect((v.fields['features'] as JsonArray).elements.length, 3);
      final config = v.fields['config'] as JsonObject;
      expect((config.fields['strict'] as JsonBool).value, true);
      expect(config.fields['maxDepth'], isA<JsonNull>());
    });
  });

  group('JSON errors', () {
    test('invalid input', () {
      final r = parseJson('xyz');
      expect(r, isA<Failure<ParseError, JsonValue>>());
    });

    test('trailing garbage', () {
      final r = parseJson('42 xyz');
      expect(r, isA<Failure<ParseError, JsonValue>>());
    });
  });
}
