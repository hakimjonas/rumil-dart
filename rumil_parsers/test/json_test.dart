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
    test('integer', () {
      final v = val_(parseJson('42')) as JsonNumber;
      expect(v.value, 42.0);
    });

    test('negative', () {
      final v = val_(parseJson('-17')) as JsonNumber;
      expect(v.value, -17.0);
    });

    test('float', () {
      final v = val_(parseJson('3.14')) as JsonNumber;
      expect(v.value, closeTo(3.14, 0.001));
    });

    test('exponent', () {
      final v = val_(parseJson('1e10')) as JsonNumber;
      expect(v.value, 1e10);
    });

    test('negative exponent', () {
      final v = val_(parseJson('2.5e-3')) as JsonNumber;
      expect(v.value, closeTo(0.0025, 1e-10));
    });

    test('zero', () {
      final v = val_(parseJson('0')) as JsonNumber;
      expect(v.value, 0.0);
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
      expect((v.elements[0] as JsonNumber).value, 1.0);
    });

    test('multiple elements', () {
      final v = val_(parseJson('[1, "two", true, null]')) as JsonArray;
      expect(v.elements.length, 4);
      expect(v.elements[0], isA<JsonNumber>());
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
      expect((v.fields['a'] as JsonNumber).value, 1.0);
      expect((v.fields['b'] as JsonBool).value, true);
      expect(v.fields['c'], isA<JsonNull>());
    });

    test('nested objects', () {
      final v = val_(parseJson('{"x": {"y": 42}}')) as JsonObject;
      final inner = v.fields['x'] as JsonObject;
      expect((inner.fields['y'] as JsonNumber).value, 42.0);
    });
  });

  group('JSON whitespace', () {
    test('leading and trailing', () {
      final v = val_(parseJson('  42  '));
      expect(v, isA<JsonNumber>());
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
