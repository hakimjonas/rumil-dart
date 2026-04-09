/// Benchmark 4: Lazy error construction — measure the cost saved by
/// late final error thunks on failing branches.
library;

import 'package:rumil/rumil.dart';

import 'package:rumil_bench/harness.dart';

void main() {
  // Grammar with many failing alternatives before the matching one.
  // JSON's value parser tries: null | bool | number | string | array | object
  // When parsing objects, 4 alternatives fail before "object" matches.
  // With lazy errors, those 4 failure error messages are never constructed.

  // Build inputs: arrays of objects (forces many failing branches per element)
  final input100 = _buildObjectArray(100);
  final input1000 = _buildObjectArray(1000);

  // Measure with lazy errors (current implementation)
  print('=== Lazy error construction ===');
  print('');
  print('Parse array of 100 objects (${input100.length} bytes):');
  benchWithSize(
    'lazy (current)',
    () => _parseJsonValue(input100),
    input100.length,
    iterations: 1000,
  );

  print('');
  print('Parse array of 1000 objects (${input1000.length} bytes):');
  benchWithSize(
    'lazy (current)',
    () => _parseJsonValue(input1000),
    input1000.length,
    iterations: 100,
  );

  // Measure accessing errors (forces thunk evaluation)
  print('');
  print('Parse invalid input + access errors:');
  final invalid = '!!!invalid!!!';
  bench('parse + errors', () {
    final r = _parseJsonValue(invalid);
    if (r case Failure(:final errors)) {
      errors.length; // Force error thunk evaluation
    }
  }, iterations: 50000);

  // Measure deeply branching grammar
  print('');
  print('Deeply branching alternation (20 alternatives):');
  final deepAlt = _buildDeepAlternation();
  final deepInput = 'match_19';
  bench(
    '20-way Or (last matches)',
    () => deepAlt.run(deepInput),
    iterations: 50000,
  );
}

String _buildObjectArray(int count) {
  final sb = StringBuffer('[');
  for (var i = 0; i < count; i++) {
    if (i > 0) sb.write(',');
    sb.write('{"id":$i,"name":"item_$i"}');
  }
  sb.write(']');
  return sb.toString();
}

// Inline JSON value parser to avoid import issues with private _jsonParser
final Parser<ParseError, Object?> _jsonValue = _buildJsonParser();

Parser<ParseError, Object?> _buildJsonParser() {
  final ws = satisfy(
    (c) => c == ' ' || c == '\t' || c == '\n' || c == '\r',
    'whitespace',
  ).many.as<void>(null);

  Parser<ParseError, A> lex<A>(Parser<ParseError, A> p) =>
      ws.skipThen(p).thenSkip(ws);

  final jsonNull = lex(string('null')).as<Object?>(null);
  final jsonBool = lex(
    string('true').as<Object?>(true) | string('false').as<Object?>(false),
  );
  final jsonNumber = lex(
    (char(
      '-',
    ).optional.zip(digit().many1)).capture.map<Object?>((s) => double.parse(s)),
  );
  final jsonString = lex(
    char('"')
        .skipThen(satisfy((c) => c != '"' && c != '\\', 'char').many)
        .map<Object?>((cs) => cs.join())
        .thenSkip(char('"')),
  );

  final jsonArray = lex(char('['))
      .skipThen(defer(() => _jsonValue).sepBy(lex(char(','))))
      .map<Object?>((List<Object?> l) => l)
      .thenSkip(lex(char(']')));

  final jsonObject = lex(char('{'))
      .skipThen(
        lex(
              char('"')
                  .skipThen(
                    satisfy((c) => c != '"', 'c').many.map((cs) => cs.join()),
                  )
                  .thenSkip(char('"')),
            )
            .zip(lex(char(':')).skipThen(defer(() => _jsonValue)))
            .sepBy(lex(char(','))),
      )
      .map<Object?>(
        (pairs) => Map.fromEntries(pairs.map((p) => MapEntry(p.$1, p.$2))),
      )
      .thenSkip(lex(char('}')));

  return (jsonNull |
          jsonBool |
          jsonNumber |
          jsonString |
          jsonArray |
          jsonObject)
      .named('value');
}

Result<ParseError, Object?> _parseJsonValue(String input) => (satisfy(
  (c) => c == ' ' || c == '\t' || c == '\n' || c == '\r',
  'whitespace',
).many.as<void>(null).skipThen(_jsonValue).thenSkip(eof()).run(input));

Parser<ParseError, String> _buildDeepAlternation() {
  Parser<ParseError, String> p = string('match_0');
  for (var i = 1; i < 20; i++) {
    p = p | string('match_$i');
  }
  return p;
}
