/// Simplified YAML 1.2 parser.
library;

import 'package:rumil/rumil.dart';

import 'ast/yaml.dart';
import 'common.dart' as common;

/// Parse a YAML document from [input].
Result<ParseError, YamlDocument> parseYaml(String input) =>
    _yamlDocument.run(input);

// ---- Whitespace & comments ----

final Parser<ParseError, void> _ws = satisfy(
  (c) => c == ' ' || c == '\t' || c == '\r' || c == '\n',
  'whitespace',
).many.as<void>(null);

final Parser<ParseError, void> _yamlComment = char('#')
    .skipThen(satisfy((c) => c != '\n', 'comment char').many)
    .skipThen(common.newline().as<void>(null) | eof())
    .as<void>(null);

final Parser<ParseError, void> _blankLine = common.hspaces().skipThen(
  _yamlComment | common.newline().as<void>(null),
);

// ---- Scalars ----

final Parser<ParseError, YamlValue> _yamlNull = stringIn([
  'null',
  '~',
]).as<YamlValue>(const YamlNull());

final Parser<ParseError, YamlValue> _yamlBoolean = keywords<YamlValue>({
  'true': const YamlBool(true),
  'yes': const YamlBool(true),
  'on': const YamlBool(true),
  'false': const YamlBool(false),
  'no': const YamlBool(false),
  'off': const YamlBool(false),
});

final Parser<ParseError, YamlValue> _yamlInteger = (common
    .signedInt()
    .thenSkip(oneOf('.eE').notFollowedBy)
    .map<YamlValue>(YamlInteger.new));

final Parser<ParseError, YamlValue> _yamlFloat = common
    .floatingPoint()
    .map<YamlValue>(YamlFloat.new);

final Parser<ParseError, YamlValue> _yamlNumber = _yamlInteger | _yamlFloat;

final Parser<ParseError, YamlValue> _plainString = satisfy(
  (c) =>
      c != ':' &&
      c != '#' &&
      c != '\n' &&
      c != '[' &&
      c != ']' &&
      c != '{' &&
      c != '}',
  'plain char',
).many1.map<YamlValue>((cs) => YamlString(cs.join().trim()));

final Parser<ParseError, YamlValue> _quotedString =
    (common.doubleQuotedString() | common.singleQuotedString()).map<YamlValue>(
      YamlString.new,
    );

final Parser<ParseError, YamlValue> _yamlScalar =
    _yamlNull | _yamlBoolean | _yamlNumber | _quotedString | _plainString;

// ---- Flow collections ----

final Parser<ParseError, YamlValue> _flowPlainString = satisfy(
  (c) =>
      c != ':' &&
      c != '#' &&
      c != '\n' &&
      c != ',' &&
      c != '[' &&
      c != ']' &&
      c != '{' &&
      c != '}',
  'plain char',
).many1.map<YamlValue>((cs) => YamlString(cs.join().trim()));

final Parser<ParseError, YamlValue> _flowScalar =
    _yamlNull | _yamlBoolean | _yamlNumber | _quotedString | _flowPlainString;

final Parser<ParseError, YamlValue> _flowValue =
    defer(() => _flowSequence) | defer(() => _flowMapping) | _flowScalar;

final Parser<ParseError, YamlValue> _flowSequence = char('[')
    .skipThen(_ws)
    .skipThen(_flowValue.sepBy(_ws.skipThen(char(',')).skipThen(_ws)))
    .flatMap(
      (elements) => _ws
          .skipThen(char(']'))
          .map((_) => YamlSequence(elements) as YamlValue),
    );

final Parser<ParseError, YamlValue> _flowMapping = () {
  final key = (_flowPlainString | _quotedString).map(
    (v) => switch (v) {
      YamlString(:final value) => value,
      _ => '',
    },
  );

  final pair = key.flatMap(
    (k) => _ws
        .skipThen(char(':'))
        .skipThen(_ws)
        .skipThen(_flowValue)
        .map((v) => (k, v)),
  );

  return char('{')
      .skipThen(_ws)
      .skipThen(pair.sepBy(_ws.skipThen(char(',')).skipThen(_ws)))
      .flatMap(
        (pairs) => _ws
            .skipThen(char('}'))
            .map(
              (_) =>
                  YamlMapping(
                        Map.fromEntries(pairs.map((p) => MapEntry(p.$1, p.$2))),
                      )
                      as YamlValue,
            ),
      );
}();

// ---- Block collections ----

final Parser<ParseError, YamlValue> _blockSequence = () {
  final item = char('-')
      .skipThen(common.hspaces1())
      .skipThen(_yamlScalar)
      .thenSkip(common.newline().optional);

  return item.many1.map<YamlValue>(YamlSequence.new);
}();

final Parser<ParseError, YamlValue> _blockMapping = () {
  final key = satisfy(
    (c) => c != ':' && c != '\n' && c != '#',
    'key char',
  ).many1.map((cs) => cs.join().trim());

  final pair = key.flatMap(
    (k) => char(':')
        .skipThen(common.hspaces1() | common.newline().map((_) => <String>[]))
        .skipThen(_yamlScalar)
        .flatMap((v) => common.newline().optional.map((_) => (k, v))),
  );

  return pair.many1.map<YamlValue>(
    (pairs) =>
        YamlMapping(Map.fromEntries(pairs.map((p) => MapEntry(p.$1, p.$2)))),
  );
}();

// ---- Value ----

final Parser<ParseError, YamlValue> _yamlValue =
    _flowSequence | _flowMapping | _blockSequence | _blockMapping | _yamlScalar;

// ---- Document ----

final Parser<ParseError, YamlDocument> _yamlDocument = _blankLine.many.skipThen(
  (string('---').thenSkip(common.newline().optional).optional)
      .skipThen(_blankLine.many)
      .skipThen(_yamlValue)
      .flatMap(
        (root) => _blankLine.many.skipThen(
          (string('...').thenSkip(common.newline().optional).optional)
              .skipThen(_ws)
              .skipThen(eof())
              .map((_) => root),
        ),
      ),
);
