import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

List<JsonValue> _ok(Result<ParseError, List<JsonValue>> r) => switch (r) {
  Success(:final value) => value,
  Partial(:final value) => value,
  Failure() => throw StateError('Expected success, got ${r.errors}'),
};

void main() {
  group('parseNdJson', () {
    test('three single-value lines', () {
      const input = '{"a":1}\n{"a":2}\n{"a":3}\n';
      final r = parseNdJson(input);
      expect(r, isA<Success<ParseError, List<JsonValue>>>());
      final values = _ok(r);
      expect(values.length, 3);
      expect(values.every((v) => v is JsonObject), isTrue);
      expect(((values[0] as JsonObject).fields['a']! as JsonInt).value, 1);
      expect(((values[1] as JsonObject).fields['a']! as JsonInt).value, 2);
      expect(((values[2] as JsonObject).fields['a']! as JsonInt).value, 3);
    });

    test('no trailing newline', () {
      const input = '{"a":1}\n{"a":2}\n{"a":3}';
      final values = _ok(parseNdJson(input));
      expect(values.length, 3);
    });

    test('empty input is empty list', () {
      final values = _ok(parseNdJson(''));
      expect(values, isEmpty);
    });

    test(
      'blank-line-only input is Partial with one error per blank (strict)',
      () {
        // Strict mode: every blank line is a parse error.
        const input = '\n\n\n';
        final r = parseNdJson(input);
        expect(r, isA<Partial<ParseError, List<JsonValue>>>());
        final partial = r as Partial<ParseError, List<JsonValue>>;
        expect(partial.value, isEmpty);
        expect(partial.errors.length, 3);
        expect(partial.errors.every((e) => e is CustomError), isTrue);
      },
    );

    test('blank-line-only input is Success([]) under lenient', () {
      const input = '\n\n\n';
      final r = parseNdJson(input, config: const NdJsonConfig(lenient: true));
      expect(r, isA<Success<ParseError, List<JsonValue>>>());
      expect(_ok(r), isEmpty);
    });

    test('blank lines between values are errors in strict mode', () {
      // Strict mode rejects the blank lines between records.
      const input = '1\n\n2\n\n3\n';
      final r = parseNdJson(input);
      expect(r, isA<Partial<ParseError, List<JsonValue>>>());
      final partial = r as Partial<ParseError, List<JsonValue>>;
      expect(partial.value.map((v) => (v as JsonInt).value).toList(), [
        1,
        2,
        3,
      ]);
      // Two blank-line errors (lines 2 and 4); the trailing \n on line 5 is the
      // record-3 terminator, not a blank line.
      expect(partial.errors.length, 2);
      expect(partial.errors[0].location.line, 2);
      expect(partial.errors[1].location.line, 4);
    });

    test('blank lines between values are skipped in lenient mode', () {
      const input = '1\n\n2\n\n3\n';
      final values = _ok(
        parseNdJson(input, config: const NdJsonConfig(lenient: true)),
      );
      expect(values.map((v) => (v as JsonInt).value).toList(), [1, 2, 3]);
    });

    test('CRLF-delimited input parses identically to LF', () {
      const lfInput = '{"a":1}\n{"a":2}\n';
      const crlfInput = '{"a":1}\r\n{"a":2}\r\n';
      expect(_ok(parseNdJson(lfInput)).length, 2);
      expect(_ok(parseNdJson(crlfInput)).length, 2);
    });

    test('mixed scalar and object lines', () {
      const input = 'true\n42\n"hello"\nnull\n[1,2]\n{"k":"v"}\n';
      final values = _ok(parseNdJson(input));
      expect(values[0], isA<JsonBool>());
      expect(values[1], isA<JsonInt>());
      expect(values[2], isA<JsonString>());
      expect(values[3], isA<JsonNull>());
      expect(values[4], isA<JsonArray>());
      expect(values[5], isA<JsonObject>());
    });

    test('bad line returns Partial with parsed values + errors', () {
      // Line 2 is unparseable; lines 1, 3 are fine.
      const input = '{"a":1}\nNOT JSON\n{"a":3}\n';
      final r = parseNdJson(input);
      expect(r, isA<Partial<ParseError, List<JsonValue>>>());
      final partial = r as Partial<ParseError, List<JsonValue>>;
      expect(partial.value.length, 2);
      expect(partial.errors, isNotEmpty);
      // Error location should reference line 2 of the original input.
      final firstError = partial.errors.first;
      expect(firstError.location.line, 2);
    });

    test('all-bad input is Partial with empty values', () {
      const input = 'NOT\nALSO NOT\n';
      final r = parseNdJson(input);
      expect(r, isA<Partial<ParseError, List<JsonValue>>>());
      final partial = r as Partial<ParseError, List<JsonValue>>;
      expect(partial.value, isEmpty);
      expect(partial.errors.length, greaterThanOrEqualTo(2));
    });

    test('single line with no newline parses', () {
      const input = '{"only":"line"}';
      final values = _ok(parseNdJson(input));
      expect(values.length, 1);
      expect(values.first, isA<JsonObject>());
    });

    test('whitespace-only line is a parse error in both modes', () {
      // The line "   " is non-empty (it has space characters) and so
      // does not hit the blank-line path; parseJson fails on it. The
      // contract: a whitespace-only line is malformed JSON, not a
      // skippable blank. Holds in lenient mode too — lenient is about
      // *blank* lines, not whitespace tolerance.
      const input = '1\n   \n2\n';
      final strict = parseNdJson(input);
      expect(strict, isA<Partial<ParseError, List<JsonValue>>>());
      final partial = strict as Partial<ParseError, List<JsonValue>>;
      expect(partial.value.map((v) => (v as JsonInt).value).toList(), [1, 2]);
      expect(partial.errors.length, 1);
      expect(partial.errors.first.location.line, 2);

      final lenient = parseNdJson(
        input,
        config: const NdJsonConfig(lenient: true),
      );
      expect(lenient, isA<Partial<ParseError, List<JsonValue>>>());
      expect(
        (lenient as Partial<ParseError, List<JsonValue>>).errors.length,
        1,
      );
    });

    test('consumed count covers full input on success', () {
      const input = '1\n2\n3\n';
      final r = parseNdJson(input);
      switch (r) {
        case Success(:final consumed):
          expect(consumed, input.length);
        case _:
          fail('Expected Success');
      }
    });

    test('consumed count covers full input on Partial', () {
      const input = '1\nbad\n3\n';
      final r = parseNdJson(input);
      switch (r) {
        case Partial(:final consumed):
          expect(consumed, input.length);
        case _:
          fail('Expected Partial');
      }
    });
  });
}
