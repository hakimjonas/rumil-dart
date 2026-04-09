/// RFC 8259 compliant JSON parser.
library;

import 'package:rumil/rumil.dart';

import 'ast/json.dart';
import 'common.dart' as common;

/// Parse a JSON string into a [JsonValue].
Result<ParseError, JsonValue> parseJson(String input) => _jsonParser.run(input);

/// The full JSON parser (exposed for benchmarking).
final Parser<ParseError, JsonValue> _jsonParser = _ws
    .skipThen(_jsonValue)
    .thenSkip(_ws)
    .thenSkip(eof());

// ---- Whitespace ----

final Parser<ParseError, void> _ws = satisfy(
  (c) => c == ' ' || c == '\t' || c == '\n' || c == '\r',
  'whitespace',
).many.as<void>(null);

Parser<ParseError, A> _lex<A>(Parser<ParseError, A> p) =>
    _ws.skipThen(p).thenSkip(_ws);

// ---- Literals ----

final Parser<ParseError, JsonValue> _jsonNull = _lex(
  string('null'),
).as<JsonValue>(const JsonNull()).named('null');

final Parser<ParseError, JsonValue> _jsonBool = _lex(
  string('true').as<JsonValue>(const JsonBool(true)) |
      string('false').as<JsonValue>(const JsonBool(false)),
).named('boolean');

// ---- Numbers ----

final Parser<ParseError, JsonValue> _jsonNumber = _lex(
  char('-').optional.flatMap(
    (neg) => (char('0').as('0') |
            satisfy(
                  (c) => c.compareTo('1') >= 0 && c.compareTo('9') <= 0,
                  '1-9',
                )
                .zip(digit().many)
                .map(((String, List<String>) pair) => pair.$1 + pair.$2.join()))
        .flatMap(
          (intPart) => char('.')
              .skipThen(digit().many1)
              .optional
              .flatMap(
                (frac) => oneOf('eE')
                    .skipThen(
                      (char('+') | char('-')).optional.zip(digit().many1),
                    )
                    .optional
                    .map((exp) {
                      final sign = neg != null ? '-' : '';
                      final fracStr = frac != null ? '.${frac.join()}' : '';
                      final expStr =
                          exp != null ? 'e${exp.$1 ?? ''}${exp.$2.join()}' : '';
                      return JsonNumber(
                        double.parse('$sign$intPart$fracStr$expStr'),
                      );
                    }),
              ),
        ),
  ),
).named('number');

// ---- Strings ----

final Parser<ParseError, String> _escapeSequence = char('\\').skipThen(
  char('"').as('"') |
      char('\\').as('\\') |
      char('/').as('/') |
      char('b').as('\b') |
      char('f').as('\f') |
      char('n').as('\n') |
      char('r').as('\r') |
      char('t').as('\t') |
      _unicodeEscape,
);

final Parser<ParseError, String> _unicodeEscape = char('u')
    .skipThen(common.hexDigit().times(4))
    .map((digits) => String.fromCharCode(int.parse(digits.join(), radix: 16)));

final Parser<ParseError, String> _stringChar =
    _escapeSequence |
    satisfy(
      (c) => c != '"' && c != '\\' && c.codeUnitAt(0) >= 0x20,
      'string char',
    );

final Parser<ParseError, String> _rawString = char(
  '"',
).skipThen(_stringChar.many).map((chars) => chars.join()).thenSkip(char('"'));

final Parser<ParseError, JsonValue> _jsonString = _lex(
  _rawString,
).map<JsonValue>(JsonString.new).named('string');

// ---- Arrays and Objects (recursive via defer) ----

final Parser<ParseError, JsonValue> _jsonArray = (_lex(char('['))
    .skipThen(_jsonValue.sepBy(_lex(char(','))))
    .thenSkip(_lex(char(']')))
    .map<JsonValue>(JsonArray.new)
    .named('array'));

final Parser<ParseError, JsonValue> _jsonObject = () {
  final member = _lex(
    _rawString,
  ).zip(_lex(char(':')).skipThen(defer(() => _jsonValue)));

  return (_lex(char('{'))
      .skipThen(member.sepBy(_lex(char(','))))
      .thenSkip(_lex(char('}')))
      .map<JsonValue>(
        (pairs) => JsonObject(
          Map.fromEntries(pairs.map((pair) => MapEntry(pair.$1, pair.$2))),
        ),
      )
      .named('object'));
}();

final Parser<ParseError, JsonValue> _jsonValue = (_jsonNull |
        _jsonBool |
        _jsonNumber |
        _jsonString |
        defer(() => _jsonArray) |
        defer(() => _jsonObject))
    .named('value');
