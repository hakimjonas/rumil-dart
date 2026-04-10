/// YAML 1.2 parser with indentation-based nesting.
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

final Parser<ParseError, void> _lineEnd = common.hspaces().skipThen(
  _yamlComment | common.newline().as<void>(null) | eof(),
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

final Parser<ParseError, YamlValue> _yamlInteger = common
    .signedInt()
    .thenSkip(oneOf('.eE').notFollowedBy)
    .map<YamlValue>(YamlInteger.new);

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

// ---- Inline value (flow or scalar, same line) ----

final Parser<ParseError, YamlValue> _inlineValue =
    _flowSequence | _flowMapping | _yamlScalar;

// ---- Indentation helpers ----

Parser<ParseError, void> _indent(int n) =>
    n == 0
        ? succeed<ParseError, void>(null)
        : char(' ').times(n).as<void>(null);

final Parser<ParseError, int> _peekIndent = char(
  ' ',
).many.capture.lookAhead.map((s) => s.length);

// ---- Block mapping key ----

final Parser<ParseError, String> _blockKey = satisfy(
  (c) => c != ':' && c != '\n' && c != '#',
  'key char',
).many1.map((cs) => cs.join().trim());

// ---- Indentation-aware block parsing ----

Parser<ParseError, YamlValue> _blockValueAt(int minIndent) =>
    _peekIndent.flatMap((actual) {
      if (actual < minIndent) {
        return failure<ParseError, YamlValue>(
          CustomError(
            'expected indent >= $minIndent, got $actual',
            Location.zero,
          ),
        );
      }
      // Sequence before mapping: '- ' at line start would match as a
      // mapping key otherwise (since '-' passes the key predicate).
      return _blockSequenceAt(actual) |
          _blockMappingAt(actual) |
          _indent(actual).skipThen(_inlineValue).thenSkip(_lineEnd);
    });

Parser<ParseError, YamlValue> _blockMappingAt(int indent) {
  final entry = _indent(indent).skipThen(
    _blockKey.flatMap(
      (key) => char(':')
          .skipThen(
            // Inline value on same line
            common.hspaces1().skipThen(_inlineValue).thenSkip(_lineEnd) |
                // Nested value on next line(s)
                _lineEnd.skipThen(defer(() => _blockValueAt(indent + 1))),
          )
          .map((value) => (key, value)),
    ),
  );

  return entry.many1.map<YamlValue>(
    (pairs) =>
        YamlMapping(Map.fromEntries(pairs.map((p) => MapEntry(p.$1, p.$2)))),
  );
}

Parser<ParseError, YamlValue> _blockSequenceAt(int indent) {
  // Parse one key: value pair inline (right after "- ")
  final inlineEntry = _blockKey.flatMap(
    (key) => char(':')
        .skipThen(
          common.hspaces1().skipThen(_inlineValue).thenSkip(_lineEnd) |
              _lineEnd.skipThen(defer(() => _blockValueAt(indent + 2))),
        )
        .map((value) => (key, value)),
  );

  // Compact mapping: first entry inline, then more at indent + 2
  final compactMapping = inlineEntry.flatMap(
    (first) => defer(() => _blockMappingAt(indent + 2)).optional.map((rest) {
      final entries = <(String, YamlValue)>[first];
      if (rest case YamlMapping(:final pairs)) {
        entries.addAll(
          pairs.entries.map(
            (MapEntry<String, YamlValue> e) => (e.key, e.value),
          ),
        );
      }
      return YamlMapping(
            Map.fromEntries(entries.map((p) => MapEntry(p.$1, p.$2))),
          )
          as YamlValue;
    }),
  );

  final item = _indent(indent).skipThen(
    char('-')
        .skipThen(common.hspaces1())
        .skipThen(
          // Compact nested mapping: "- key: value\n    key2: value2"
          compactMapping |
              // Inline value on same line after "- "
              _inlineValue.thenSkip(_lineEnd) |
              // Nested value on next line
              _lineEnd.skipThen(defer(() => _blockValueAt(indent + 2))),
        ),
  );

  return item.many1.map<YamlValue>(YamlSequence.new);
}

// ---- Top-level value ----

final Parser<ParseError, YamlValue> _yamlValue =
    _flowSequence | _flowMapping | _blockValueAt(0);

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
