/// YAML 1.2 parser with indentation-based nesting.
library;

import 'package:rumil/rumil.dart';

import 'ast/yaml.dart';
import 'common.dart' as common;

/// Configuration for YAML parsing.
class YamlParseConfig {
  /// Whether to use strict YAML 1.2 boolean semantics.
  ///
  /// When `true`, only `true` and `false` are booleans.
  /// When `false` (default), `yes`/`no`/`on`/`off` are also booleans.
  final bool strict12;

  /// Creates a parse configuration.
  const YamlParseConfig({this.strict12 = false});
}

/// Parse a YAML document from [input].
///
/// Returns [YamlNull] for empty/comment-only input.
Result<ParseError, YamlDocument> parseYaml(
  String input, {
  YamlParseConfig config = const YamlParseConfig(),
}) {
  _activeBoolean =
      config.strict12 ? _yamlBooleanStrict : _yamlBooleanPermissive;
  // Handle empty/comment-only/doc-end-only input.
  final lines = input
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty);
  if (lines.every((l) => l.startsWith('#') || l == '...')) {
    return const Success(YamlNull(), 0);
  }
  return _yamlDocument.run(input);
}

/// Parse multiple YAML documents from [input].
Result<ParseError, List<YamlDocument>> parseYamlMulti(
  String input, {
  YamlParseConfig config = const YamlParseConfig(),
}) {
  _activeBoolean =
      config.strict12 ? _yamlBooleanStrict : _yamlBooleanPermissive;
  return _yamlMultiDocument.run(input);
}

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

/// Word boundary: next character must not be alphanumeric, `_`, or `-`.
/// Prevents keyword prefixes from matching (e.g. `on` in `one`).
final Parser<ParseError, void> _wordBoundary =
    satisfy(
      (c) =>
          (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
          (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
          (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
          c == '_' ||
          c == '-' ||
          c == '.',
      'word char',
    ).notFollowedBy;

final Parser<ParseError, YamlValue> _yamlNull = stringIn([
  'null',
  '~',
]).thenSkip(_wordBoundary).as<YamlValue>(const YamlNull());

final Parser<ParseError, YamlValue> _yamlBooleanPermissive =
    keywords<YamlValue>({
      'true': const YamlBool(true),
      'yes': const YamlBool(true),
      'on': const YamlBool(true),
      'false': const YamlBool(false),
      'no': const YamlBool(false),
      'off': const YamlBool(false),
    }).thenSkip(_wordBoundary);

final Parser<ParseError, YamlValue> _yamlBooleanStrict = keywords<YamlValue>({
  'true': const YamlBool(true),
  'false': const YamlBool(false),
}).thenSkip(_wordBoundary);

/// Active boolean parser — set before parsing via config.
Parser<ParseError, YamlValue> _activeBoolean = _yamlBooleanPermissive;

final Parser<ParseError, YamlValue> _yamlHexInteger = string('0x')
    .skipThen(common.hexDigit().many1)
    .thenSkip(_wordBoundary)
    .map<YamlValue>(
      (digits) => YamlInteger(int.parse(digits.join(), radix: 16)),
    );

final Parser<ParseError, YamlValue> _yamlOctalInteger = string('0o')
    .skipThen(
      satisfy(
        (c) => c.compareTo('0') >= 0 && c.compareTo('7') <= 0,
        'octal digit',
      ).many1,
    )
    .thenSkip(_wordBoundary)
    .map<YamlValue>(
      (digits) => YamlInteger(int.parse(digits.join(), radix: 8)),
    );

final Parser<ParseError, YamlValue> _yamlInteger =
    _yamlHexInteger |
    _yamlOctalInteger |
    common
        .signedInt()
        .thenSkip(oneOf('.eE').notFollowedBy)
        .thenSkip(_wordBoundary)
        .map<YamlValue>(YamlInteger.new);

final Parser<ParseError, YamlValue> _yamlSpecialFloat = keywords<YamlValue>({
  '.inf': const YamlFloat(double.infinity),
  '-.inf': const YamlFloat(double.negativeInfinity),
  '.nan': const YamlFloat(double.nan),
}).thenSkip(_wordBoundary);

final Parser<ParseError, YamlValue> _yamlFloat = common
    .floatingPoint()
    .thenSkip(_wordBoundary)
    .map<YamlValue>(YamlFloat.new);

/// Number must not be followed by `:` to avoid matching prefix of `20:03:20`.
final Parser<ParseError, YamlValue> _yamlNumber = (_yamlSpecialFloat |
        _yamlInteger |
        _yamlFloat)
    .thenSkip(char(':').notFollowedBy);

/// Resolve a plain scalar's string value to its YAML type.
///
/// For multi-line plain scalars (e.g., `null\n  d` → "null d"), the
/// value won't match any keyword/number and stays as a string.
/// For single-line values that match keywords/numbers, resolves to
/// the typed value (YamlNull, YamlBool, YamlInteger, YamlFloat).
YamlValue _resolveScalarType(YamlValue value) {
  if (value is! YamlString) return value;
  final text = value.value;
  // Null
  if (text == 'null' || text == '~') return const YamlNull();
  // Booleans (respects active config)
  if (identical(_activeBoolean, _yamlBooleanStrict)) {
    if (text == 'true') return const YamlBool(true);
    if (text == 'false') return const YamlBool(false);
  } else {
    switch (text) {
      case 'true' || 'yes' || 'on':
        return const YamlBool(true);
      case 'false' || 'no' || 'off':
        return const YamlBool(false);
    }
  }
  // Special floats
  switch (text) {
    case '.inf':
      return const YamlFloat(double.infinity);
    case '-.inf':
      return const YamlFloat(double.negativeInfinity);
    case '.nan':
      return const YamlFloat(double.nan);
  }
  // Hex integer
  if (text.startsWith('0x')) {
    final hex = int.tryParse(text.substring(2), radix: 16);
    if (hex != null) return YamlInteger(hex);
  }
  // Octal integer
  if (text.startsWith('0o')) {
    final oct = int.tryParse(text.substring(2), radix: 8);
    if (oct != null) return YamlInteger(oct);
  }
  // Integer (must not contain `.` or `e`/`E`)
  if (!text.contains('.') && !text.contains('e') && !text.contains('E')) {
    final i = int.tryParse(text);
    if (i != null) return YamlInteger(i);
  }
  // Float
  final f = double.tryParse(text);
  if (f != null) return YamlFloat(f);
  return value;
}

// ---- Unified plain scalar (§7.3.3, §6.9) ----

/// Plain scalar parser parameterized by context.
///
/// [isFlow]: true excludes flow indicators `[]{},` from valid chars.
/// [blockIndent]: non-null enables multi-line continuation at that indent level.
///   null means single-line only (for keys). For flow, continuation uses flowWs.
///
/// Character rules per §7.3.3:
/// - First char: any non-ws except indicators, but `?`, `:`, `-` are allowed
///   when followed by a non-space "safe" character.
/// - Subsequent chars: most chars are valid. `:` valid when not followed by ws.
///   `#` valid when not preceded by ws. Space valid when not followed by `#`.
Parser<ParseError, YamlValue> _plainScalar({
  required bool isFlow,
  int? blockIndent,
}) {
  // -- Character predicates parameterized by context --

  // "Safe" char for non-first position (ns-plain-safe, §7.3.3).
  // `&` and `*` are valid in non-first position (they're only indicators
  // at the start of a node, and we're past the first char here).
  final safeChar = satisfy(
    (c) =>
        c != ':' &&
        c != '#' &&
        c != '\n' &&
        c != '\r' &&
        c != ' ' &&
        c != '\t' &&
        !(isFlow && (c == '[' || c == ']' || c == '{' || c == '}' || c == ',')),
    'plain char',
  );

  // `:` followed by ns-plain-safe (§7.3.3) — i.e., `:` NOT followed by
  // whitespace (space, tab, newline) or flow indicators in flow context.
  final colonSafe = char(':')
      .thenSkip(
        satisfy(
          (c) =>
              c == ' ' ||
              c == '\t' ||
              c == '\n' ||
              c == '\r' ||
              (isFlow && (c == ',' || c == ']' || c == '}')),
          'terminator',
        ).notFollowedBy,
      )
      .lookAhead
      .skipThen(char(':'));

  // `#` valid in non-first position.
  final hashInMiddle = char('#');

  // Space/tab not followed by `#`.
  final spaceSafe = satisfy((c) => c == ' ' || c == '\t', 'space')
      .thenSkip(char('#').notFollowedBy)
      .lookAhead
      .skipThen(satisfy((c) => c == ' ' || c == '\t', 'space'));

  // Content char (after the first character).
  final contentChar = safeChar | colonSafe | hashInMiddle | spaceSafe;

  // First character: `?`, `:`, `-` allowed when followed by a safe char.
  // `[`, `]`, `{`, `}` NOT allowed as first char even in block context
  // (they would be ambiguous with flow collections).
  final indicatorFirst = oneOf('?:-').thenSkip(
    satisfy(
      (c) =>
          c != ' ' &&
          c != '\t' &&
          c != '\n' &&
          c != '\r' &&
          !(isFlow &&
              (c == '[' || c == ']' || c == '{' || c == '}' || c == ',')),
      'non-ws',
    ).lookAhead,
  );

  final firstSafe = satisfy(
    (c) =>
        c != ':' &&
        c != '#' &&
        c != '\n' &&
        c != '\r' &&
        c != ' ' &&
        c != '\t' &&
        c != '!' &&
        c != '|' &&
        c != '>' &&
        c != '&' &&
        c != '*' &&
        c != '?' &&
        c != '-' &&
        c != '[' &&
        c != ']' &&
        c != '{' &&
        c != '}' &&
        !(isFlow && c == ','),
    'plain first',
  );

  final firstChar = firstSafe | indicatorFirst;

  // -- Single-line scalar --
  final singleLine = firstChar.flatMap(
    (first) => contentChar.many.map(
      (rest) => YamlString([first, ...rest].join().trimRight()) as YamlValue,
    ),
  );

  // -- Multi-line block continuation --
  if (!isFlow && blockIndent != null) {
    final bi = blockIndent;
    final lineChars = contentChar.many1.map((cs) => cs.join().trimRight());

    final contBlankLine = satisfy(
      (c) => c == ' ' || c == '\t',
      'space',
    ).many.skipThen(common.newline()).as<void>(null);

    final continuation = common.newline().flatMap(
      (_) => contBlankLine.many.flatMap(
        (blanks) => _peekIndent.flatMap((indent) {
          if (indent <= bi) {
            return failure<ParseError, (int, String)>(
              CustomError('continuation ended', Location.zero),
            );
          }
          final guard =
              indent == 0
                  ? (_docStart | _docEnd).notFollowedBy
                  : succeed<ParseError, void>(null);
          return guard
              .skipThen(_indent(indent))
              .skipThen(common.hspaces()) // Strip s-separate-in-line (§7.3.3)
              .skipThen(lineChars)
              .map((text) => (blanks.length, text));
        }),
      ),
    );

    return firstChar.flatMap(
      (first) => contentChar.many.flatMap((restFirst) {
        final firstLine = [first, ...restFirst].join().trimRight();
        return continuation.many.map((continuations) {
          if (continuations.isEmpty) return YamlString(firstLine);
          final buf = StringBuffer(firstLine);
          for (final (emptyCount, text) in continuations) {
            if (emptyCount > 0) {
              for (var i = 0; i < emptyCount; i++) {
                buf.write('\n');
              }
            } else {
              buf.write(' ');
            }
            buf.write(text);
          }
          return YamlString(buf.toString()) as YamlValue;
        });
      }),
    );
  }

  // -- Multi-line flow continuation --
  if (isFlow && blockIndent != null) {
    final lineChars = contentChar.many1.map((cs) => cs.join().trimRight());

    final continuation = common.newline().flatMap(
      (_) => _flowWs.skipThen(
        satisfy(
          (c) => c != ']' && c != '}' && c != ',' && c != '\n' && c != '#',
          'flow content',
        ).lookAhead.as<void>(null).skipThen(lineChars),
      ),
    );

    return firstChar.flatMap(
      (first) => contentChar.many.flatMap((restFirst) {
        final firstLine = [first, ...restFirst].join().trimRight();
        return continuation.many.map((continuations) {
          if (continuations.isEmpty) return YamlString(firstLine);
          return YamlString([firstLine, ...continuations].join(' '))
              as YamlValue;
        });
      }),
    );
  }

  return singleLine;
}

// ---- YAML-specific quoted strings (§7.3.1, §7.3.2) ----

/// Sentinel for source newlines in double-quoted strings (vs escaped `\n`).
const _sourceNewline = '\x00SRCNL\x00';

/// YAML 1.2 double-quoted string with full escape set (§5.7).
final Parser<ParseError, String> _yamlDoubleQuotedString = () {
  // Simple escape sequences.
  const escapes = <String, String>{
    '\\': '\\',
    '"': '"',
    '/': '/',
    '0': '\x00', // null
    'a': '\x07', // bell
    'b': '\b', // backspace
    't': '\t', // tab
    'n': '\n', // newline
    'v': '\x0B', // vertical tab
    'f': '\f', // form feed
    'r': '\r', // carriage return
    'e': '\x1B', // escape
    ' ': ' ', // space
    'N': '\u0085', // next line
    '_': '\u00A0', // non-breaking space
    'L': '\u2028', // line separator
    'P': '\u2029', // paragraph separator
  };

  final simpleEscape = char('\\')
      .skipThen(satisfy((c) => escapes.containsKey(c), 'escape char'))
      .map((c) => escapes[c]!);

  // Escaped newline: `\` at end of line — skip the line break and leading ws
  final escapedLineBreak = char('\\')
      .skipThen(common.newline())
      .skipThen(satisfy((c) => c == ' ' || c == '\t', 'ws').many)
      .as<String>('');

  // \xHH — 8-bit Unicode
  final hexEscape = char('\\')
      .skipThen(char('x'))
      .skipThen(common.hexDigit().times(2))
      .map((ds) => String.fromCharCode(int.parse(ds.join(), radix: 16)));

  // \uHHHH — 16-bit Unicode
  final unicodeEscape4 = char('\\')
      .skipThen(char('u'))
      .skipThen(common.hexDigit().times(4))
      .map((ds) => String.fromCharCode(int.parse(ds.join(), radix: 16)));

  // \UHHHHHHHH — 32-bit Unicode
  final unicodeEscape8 = char('\\')
      .skipThen(char('U'))
      .skipThen(common.hexDigit().times(8))
      .map((ds) => String.fromCharCode(int.parse(ds.join(), radix: 16)));

  final escape =
      escapedLineBreak |
      hexEscape |
      unicodeEscape8 |
      unicodeEscape4 |
      simpleEscape;

  // Source newline (not escaped) → sentinel for folding.
  final sourceNewline = common.newline().as<String>(_sourceNewline);
  final normalChar = satisfy(
    (c) => c != '"' && c != '\\' && c != '\n' && c != '\r',
    'string char',
  );

  return char('"')
      .skipThen((escape | sourceNewline | normalChar).many)
      .thenSkip(char('"'))
      .map((cs) => _foldQuotedString(cs.join()));
}();

/// YAML single-quoted string: `''` → `'` (§7.3.2).
final Parser<ParseError, String> _yamlSingleQuotedString = () {
  final escapedQuote = string("''").as<String>("'");
  final sourceNewline = common.newline().as<String>(_sourceNewline);
  final normalChar = satisfy(
    (c) => c != "'" && c != '\n' && c != '\r',
    'string char',
  );

  return char("'")
      .skipThen((escapedQuote | sourceNewline | normalChar).many)
      .thenSkip(char("'"))
      .map((cs) => _foldQuotedString(cs.join()));
}();

/// Fold source newlines in multi-line quoted strings per YAML §6.5.
///
/// Source newlines are marked with [_sourceNewline] sentinel.
/// Escaped newlines (`\n`) are real newline characters and are NOT folded.
///
/// Rules:
/// - Single source newline between content → space
/// - Consecutive source newlines (blank lines) → newline(s)
/// - First segment: trimRight; last segment: trimLeft; middle: trim both
/// - First and last segments participate in folding even when empty
String _foldQuotedString(String s) {
  if (!s.contains(_sourceNewline)) return s;
  final lines = s.split(_sourceNewline);
  // Trim: first line trailing ws, last line leading ws, middle lines both.
  final trimmed = <String>[
    for (var i = 0; i < lines.length; i++)
      if (i == 0)
        lines[i].trimRight()
      else if (i == lines.length - 1)
        lines[i].trimLeft()
      else
        lines[i].trim(),
  ];
  final result = StringBuffer(trimmed[0]);
  var blankCount = 0;
  for (var i = 1; i < trimmed.length; i++) {
    final isLast = i == trimmed.length - 1;
    if (trimmed[i].isEmpty && !isLast) {
      // Empty middle segment = blank line.
      blankCount++;
    } else {
      // Content segment (or last segment): emit accumulated fold.
      if (blankCount > 0) {
        for (var j = 0; j < blankCount; j++) {
          result.write('\n');
        }
        blankCount = 0;
      } else {
        result.write(' ');
      }
      result.write(trimmed[i]);
    }
  }
  return result.toString();
}

final Parser<ParseError, YamlValue> _quotedString = (_yamlDoubleQuotedString |
        _yamlSingleQuotedString)
    .map<YamlValue>(YamlString.new);

// ---- Flow collections ----

/// Flow whitespace: spaces, tabs, newlines, and comments.
final Parser<ParseError, void> _flowWs = (satisfy(
          (c) => c == ' ' || c == '\t' || c == '\n' || c == '\r',
          'flow whitespace',
        ) |
        _yamlComment.as<String>(''))
    .many
    .as<void>(null);

/// A flow value: scalars, nested collections, aliases.
/// Multi-line flow scalars are supported for quoted strings (folding)
/// and plain scalars (continuation lines).
final Parser<ParseError, YamlValue> _flowValue =
    defer(() => _yamlAlias) |
    defer(
      () => _withNodeProps(
        defer(() => _flowSequence) |
            defer(() => _flowMapping) |
            _yamlNull |
            defer(() => _activeBoolean) |
            _yamlNumber |
            _quotedString |
            _plainScalar(isFlow: true, blockIndent: 0),
      ),
    );

/// Flow mapping key: quoted string or flow plain string (multi-line).
final Parser<ParseError, String> _flowKey =
    (_yamlDoubleQuotedString |
        _yamlSingleQuotedString |
        _plainScalar(isFlow: true, blockIndent: 0).map(
          (v) => switch (v) {
            YamlString(:final value) => value,
            _ => '',
          },
        ));

/// Flow mapping pair: key followed by `:` and optional value.
/// Supports adjacent colon (`"key":value`), colon after ws, and key without value.
final Parser<ParseError, (String, YamlValue)> _flowPair = () {
  // Explicit key: ? key : value (? must be followed by space)
  final explicitPair = char('?')
      .thenSkip(
        satisfy((c) => c == ' ' || c == '\t' || c == '\n', 'ws').lookAhead,
      )
      .skipThen(_flowWs)
      .skipThen(_flowValue)
      .flatMap(
        (keyVal) => _flowWs
            .skipThen(char(':'))
            .skipThen(
              _flowWs.skipThen(_flowValue) |
                  succeed<ParseError, YamlValue>(const YamlNull()),
            )
            .map(
              (v) => (
                switch (keyVal) {
                  YamlString(:final value) => value,
                  _ => keyVal.toString(),
                },
                v,
              ),
            ),
      );

  // Key: value (with space or adjacent colon)
  final implicitPair = _flowKey.flatMap(
    (k) =>
        // Adjacent colon: "key":value (no space before colon, may have no space after)
        char(':')
            .skipThen(
              // After colon: value or empty (null)
              satisfy(
                    (c) =>
                        c != ',' &&
                        c != '}' &&
                        c != ']' &&
                        c != ' ' &&
                        c != '\t' &&
                        c != '\n' &&
                        c != '\r',
                    'value char',
                  ).lookAhead.as<void>(null).skipThen(_flowValue) |
                  _flowWs.skipThen(
                    // Check if next is a value or end of flow
                    satisfy(
                          (c) => c != ',' && c != '}' && c != ']',
                          'value',
                        ).lookAhead.as<void>(null).skipThen(_flowValue) |
                        succeed<ParseError, YamlValue>(const YamlNull()),
                  ),
            )
            .map((v) => (k, v)) |
        // Key with whitespace then colon
        _flowWs
            .skipThen(char(':'))
            .skipThen(_flowWs)
            .skipThen(
              satisfy(
                    (c) => c != ',' && c != '}' && c != ']',
                    'value',
                  ).lookAhead.as<void>(null).skipThen(_flowValue) |
                  succeed<ParseError, YamlValue>(const YamlNull()),
            )
            .map((v) => (k, v)),
  );

  // Tagged key: tag alone as key → empty string key (e.g., !!str : value)
  final taggedKeyPair = _tag
      .skipThen(_flowWs)
      .skipThen(char(':'))
      .skipThen(_flowWs)
      .skipThen(
        satisfy(
              (c) => c != ',' && c != '}' && c != ']',
              'value',
            ).lookAhead.as<void>(null).skipThen(_flowValue) |
            succeed<ParseError, YamlValue>(const YamlNull()),
      )
      .map((v) => ('', v));

  return explicitPair | taggedKeyPair | implicitPair;
}();

final Parser<ParseError, YamlValue> _flowSequence = char('[')
    .skipThen(_flowWs)
    .skipThen(
      // Flow sequence entries: anchored pair, plain pair, or standalone value.
      // Anchored pair: &name key: value (node props before a flow pair).
      (_nodeProps.flatMap<YamlValue>(
                (props) => _flowWs
                    .skipThen(defer(() => _flowPair))
                    .map<YamlValue>((p) {
                      YamlValue result = YamlMapping({p.$1: p.$2});
                      if (props.anchor case final name?) {
                        result = YamlAnchor(name, result);
                      }
                      return result;
                    }),
              ) |
              defer(
                () => _flowPair,
              ).map<YamlValue>((p) => YamlMapping({p.$1: p.$2})) |
              _flowValue)
          .sepBy(_flowWs.skipThen(char(',')).skipThen(_flowWs)),
    )
    .flatMap(
      (elements) =>
      // Trailing comma allowed.
      (_flowWs.skipThen(char(',')).skipThen(_flowWs)).optional.skipThen(
        _flowWs
            .skipThen(char(']'))
            .map((_) => YamlSequence(elements) as YamlValue),
      ),
    );

final Parser<ParseError, YamlValue> _flowMapping = () {
  // A flow mapping entry: anchored pair, plain pair, or lone key.
  final entry =
      // Props on key: &name key: value (anchor/tag consumed, key parsed normally)
      _nodeProps.flatMap(
        (props) =>
            _flowWs.skipThen(defer(() => _flowPair)).map((p) => (p.$1, p.$2)),
      ) |
      defer(() => _flowPair) |
      _flowKey.map((k) => (k, const YamlNull() as YamlValue));

  return char('{')
      .skipThen(_flowWs)
      .skipThen(entry.sepBy(_flowWs.skipThen(char(',')).skipThen(_flowWs)))
      .flatMap(
        (pairs) =>
        // Trailing comma allowed.
        (_flowWs.skipThen(char(',')).skipThen(_flowWs)).optional.skipThen(
          _flowWs
              .skipThen(char('}'))
              .map(
                (_) =>
                    YamlMapping(
                          Map.fromEntries(
                            pairs.map((p) => MapEntry(p.$1, p.$2)),
                          ),
                        )
                        as YamlValue,
              ),
        ),
      );
}();

// ---- Anchors and aliases (§7.1) ----

/// Anchor/alias name: any non-whitespace character that is not a flow
/// indicator (§6.9.2). YAML 1.2 allows much more than just word chars.
final Parser<ParseError, String> _anchorName = satisfy(
  (c) =>
      c != ' ' &&
      c != '\t' &&
      c != '\n' &&
      c != '\r' &&
      c != '[' &&
      c != ']' &&
      c != '{' &&
      c != '}' &&
      c != ',',
  'anchor name char',
).many1.capture;

/// Alias: `*name` as a value.
final Parser<ParseError, YamlValue> _yamlAlias = char(
  '*',
).skipThen(_anchorName).map<YamlValue>(YamlAlias.new);

// ---- Tags (§6.8) ----

/// Tag: `!!tag`, `!tag`, `!<uri>`, `!handle!tag`.
/// Returns `true` for non-specific `!` tag, `false` for specific tags.
final Parser<ParseError, bool> _tag =
    (
    // Verbatim: !<uri>
    string('!<')
            .skipThen(satisfy((c) => c != '>', 'tag uri char').many1)
            .skipThen(char('>'))
            .as<bool>(false) |
        // Named/secondary: !!tag or !handle!tag — at least one char after !
        char('!')
            .skipThen(
              satisfy(
                (c) =>
                    c != ' ' &&
                    c != '\t' &&
                    c != '\n' &&
                    c != ',' &&
                    c != '[' &&
                    c != ']' &&
                    c != '{' &&
                    c != '}',
                'tag char',
              ).many1,
            )
            .as<bool>(false) |
        // Primary: ! alone (non-specific tag)
        char('!').as<bool>(true));

// ---- Unified node properties (§6.9) ----

/// Result of parsing node properties.
typedef _NodeProps = ({bool hasTag, bool isNonSpecificTag, String? anchor});

/// Parse node properties: `tag anchor?`, `anchor tag?`, `tag`, or `anchor`.
/// ALWAYS consumes >= 1 character when successful (starts with `!` or `&`).
/// Returns which properties were found.
final Parser<ParseError, _NodeProps> _nodeProps = () {
  // Tag followed by optional (space + anchor)
  final tagFirst = _tag.flatMap(
    (isNonSpecific) => (common.hspaces1().skipThen(
      char('&').skipThen(_anchorName),
    )).optional.map<_NodeProps>(
      (anchor) => (
        hasTag: true,
        isNonSpecificTag: isNonSpecific,
        anchor: anchor,
      ),
    ),
  );

  // Anchor followed by optional (space + tag)
  final anchorFirst = char('&')
      .skipThen(_anchorName)
      .flatMap(
        (name) => (common.hspaces1().skipThen(_tag)).optional.map<_NodeProps>(
          (isNonSpecific) => (
            hasTag: isNonSpecific != null,
            isNonSpecificTag: isNonSpecific ?? false,
            anchor: name,
          ),
        ),
      );

  return tagFirst | anchorFirst;
}();

/// Wrap [valueParser] with optional node properties (§6.9).
///
/// Handles tag+anchor in either order, tag-alone → empty string,
/// and props on their own line → value on next line.
///
/// [minChildIndent]: for "props on own line" case, the minimum indent
///   for the value on the next line.
/// [allowSameIndentSeq]: whether a sequence at [indent] is valid after props.
/// [indent]: the current block indent level.
Parser<ParseError, YamlValue> _withNodeProps(
  Parser<ParseError, YamlValue> valueParser, {
  int minChildIndent = 1,
  bool allowSameIndentSeq = false,
  int indent = 0,
}) =>
    _nodeProps.flatMap((props) {
      // After properties: space + value on same line.
      final inlineAfterProps = common.hspaces1().skipThen(valueParser);

      // Props on their own line → block value on next line.
      final sameIndentSeq =
          allowSameIndentSeq
              ? defer(() => _blockSequenceAt(indent))
              : failure<ParseError, YamlValue>(
                CustomError('no same-indent seq', Location.zero),
              );

      // Per §8.2.3: props at indent n+1, collection at n = indent - 1.
      final parentSeq =
          indent > 0
              ? defer(() => _blockSequenceAt(indent - 1))
              : failure<ParseError, YamlValue>(
                CustomError('no parent seq', Location.zero),
              );

      final propsOnOwnLine = _lineEnd
          .skipThen(_blankLine.many)
          .skipThen(
            defer(
                  () => _blockValueAt(
                    minChildIndent,
                    blockScalarParent: minChildIndent - 1,
                  ),
                ) |
                sameIndentSeq |
                parentSeq,
          );

      // Props alone at end of line/flow → empty value.
      // Tag alone → empty string (§6.28). Anchor alone → null.
      final propsAloneEmpty = (satisfy(
                (c) =>
                    c == '\n' || c == '\r' || c == ',' || c == ']' || c == '}',
                'end',
              ).lookAhead.as<void>(null) |
              eof())
          .as<YamlValue>(
            props.hasTag ? const YamlString('') : const YamlNull(),
          );

      return (inlineAfterProps | propsOnOwnLine | propsAloneEmpty).map((value) {
        // Non-specific `!` tag forces scalar to string (§6.28).
        final result =
            props.isNonSpecificTag
                ? switch (value) {
                  YamlInteger(:final value) => YamlString(value.toString()),
                  YamlFloat(:final value) => YamlString(value.toString()),
                  YamlBool(:final value) => YamlString(value.toString()),
                  YamlNull() => const YamlString(''),
                  _ => value,
                }
                : value;
        if (props.anchor case final name?) {
          return YamlAnchor(name, result) as YamlValue;
        }
        return result;
      });
    }) |
    valueParser;

// ---- Block node value (§8.2) ----

/// Parse the value portion after a structural indicator (`:`, `-`, `---`).
/// This is the SINGLE entry point for "what comes after the indicator".
///
/// [parentIndent]: indent of the containing structure.
/// [minChildIndent]: minimum indent for block content on next line.
/// [blockIndent]: blockIndent for multi-line plain scalars (defaults to parentIndent).
/// [allowSameIndentSeq]: whether a sequence at [parentIndent] is valid.
/// [extraInline]: additional inline alternatives before plain scalar
///   (e.g., nested seq/compact mapping in sequence items).
Parser<ParseError, YamlValue> _blockNodeValue({
  required int parentIndent,
  required int minChildIndent,
  int? blockIndent,
  bool allowSameIndentSeq = false,
  Parser<ParseError, YamlValue>? extraInline,
}) {
  final bi = blockIndent ?? parentIndent;

  // Block scalar (consumes own newlines — no lineEnd needed).
  final blockScalar = common.hspaces1().skipThen(
    _withNodeProps(
      _blockScalarValue(parentIndent),
      indent: parentIndent,
      minChildIndent: minChildIndent,
      allowSameIndentSeq: allowSameIndentSeq,
    ),
  );

  // Single-line inline values (need lineEnd after).
  // Plain scalar is tried first with post-hoc type resolution so that
  // multi-line scalars like `null\n  d` → "null d" aren't shadowed by
  // keyword matchers that only match the first word.
  final singleLineAlts =
      _flowSequence |
      _flowMapping |
      _yamlAlias |
      _quotedString |
      _plainScalar(isFlow: false, blockIndent: bi).map(_resolveScalarType);

  final singleLine = common
      .hspaces1()
      .skipThen(
        _withNodeProps(
          singleLineAlts,
          indent: parentIndent,
          minChildIndent: minChildIndent,
          allowSameIndentSeq: allowSameIndentSeq,
        ),
      )
      .thenSkip(_lineEnd);

  // Multi-line inline values (consume own newlines, no lineEnd needed).
  // Compact mappings and nested sequences span multiple lines.
  final multiLine =
      extraInline != null
          ? common.hspaces1().skipThen(
            _withNodeProps(
              extraInline,
              indent: parentIndent,
              minChildIndent: minChildIndent,
            ),
          )
          : failure<ParseError, YamlValue>(
            CustomError('no multi-line inline', Location.zero),
          );

  // Same-line block sequence: `: - value` starts a sequence inline.
  // The `-` must be followed by whitespace to be a sequence indicator.
  final sameLineSeq = common.hspaces1().capture.flatMap((spaces) {
    final seqIndent = parentIndent + 1 + spaces.length;
    return char('-')
        .thenSkip(
          satisfy(
            (c) => c == ' ' || c == '\t' || c == '\n' || c == '\r',
            'ws',
          ).lookAhead,
        )
        .skipThen(
          _blockNodeValue(
            parentIndent: seqIndent,
            minChildIndent: seqIndent + 1,
          ),
        )
        .thenSkip(_blankLine.many)
        .flatMap(
          (first) =>
              defer(() => _blockSequenceAt(seqIndent)).optional.map((rest) {
                if (rest case YamlSequence(:final elements)) {
                  return YamlSequence([first, ...elements]) as YamlValue;
                }
                return YamlSequence([first]) as YamlValue;
              }),
        );
  });

  // Same-indent sequence (for mapping values).
  final sameIndentSeq =
      allowSameIndentSeq
          ? defer(() => _blockSequenceAt(parentIndent))
          : failure<ParseError, YamlValue>(
            CustomError('no same-indent seq', Location.zero),
          );

  // Value on next line.
  final nextLine = _lineEnd.skipThen(
    _blankLine.many.skipThen(
      defer(() => _blockValueAt(minChildIndent)) | sameIndentSeq,
    ),
  );

  // Comment → null value ("key: # comment\n").
  final commentNull = _yamlComment.as<YamlValue>(const YamlNull());

  // Empty → null value ("key:\n" or "-\n").
  final emptyNull = _lineEnd.as<YamlValue>(const YamlNull());

  return blockScalar |
      multiLine |
      sameLineSeq |
      singleLine |
      nextLine |
      commentNull |
      emptyNull;
}

/// Block inline value — convenience for contexts that need an inline-only
/// value parser (explicit keys, compact mappings).
Parser<ParseError, YamlValue> _blockInlineValue(int indent) =>
    _yamlAlias |
    _withNodeProps(
      _flowSequence |
          _flowMapping |
          _quotedString |
          _plainScalar(
            isFlow: false,
            blockIndent: indent,
          ).map(_resolveScalarType),
      indent: indent,
      minChildIndent: indent + 1,
    );

// ---- Indentation helpers ----

Parser<ParseError, void> _indent(int n) =>
    n == 0
        ? succeed<ParseError, void>(null)
        : char(' ').times(n).as<void>(null);

final Parser<ParseError, int> _peekIndent = char(
  ' ',
).many.capture.lookAhead.map((s) => s.length);

// ---- Block scalars (§8.1) ----

enum _Chomp { strip, clip, keep }

/// Parse a block scalar value (`|` literal or `>` folded) at [parentIndent].
Parser<ParseError, YamlValue> _blockScalarValue(int parentIndent) {
  final chomp =
      char('-').as<_Chomp>(_Chomp.strip) | char('+').as<_Chomp>(_Chomp.keep);

  final indentDigit = satisfy(
    (c) => c.compareTo('1') >= 0 && c.compareTo('9') <= 0,
    'indent digit 1-9',
  ).map(int.parse);

  // Indicators can appear in either order: -2, 2-, -, 2, or neither.
  final indicators =
      chomp.flatMap(
        (c) => indentDigit.optional.map<(_Chomp?, int?)>((i) => (c, i)),
      ) |
      indentDigit.flatMap(
        (i) => chomp.optional.map<(_Chomp?, int?)>((c) => (c, i)),
      ) |
      succeed<ParseError, (_Chomp?, int?)>((null, null));

  // Header: |/> + indicators + lineEnd
  final header = (char('|').as<bool>(false) | char('>').as<bool>(true)).flatMap(
    (folded) => indicators
        .thenSkip(_lineEnd)
        .map(
          (ind) => (
            folded: folded,
            chomp: ind.$1 ?? _Chomp.clip,
            indent: ind.$2,
          ),
        ),
  );

  return header.flatMap(
    (h) => _detectContentIndent(parentIndent, h.indent).flatMap(
      (contentIndent) => _collectBlockContent(contentIndent).map(
        (lines) =>
            YamlString(_assembleBlockScalar(lines, h.folded, h.chomp))
                as YamlValue,
      ),
    ),
  );
}

/// A truly blank line (whitespace + newline, NO comment).
/// Inside block scalars, comments are content, not blank lines.
final Parser<ParseError, void> _emptyLine = satisfy(
  (c) => c == ' ' || c == '\t',
  'space',
).many.skipThen(common.newline()).as<void>(null);

/// Detect the content indentation level for a block scalar.
///
/// If [explicit] is given, returns `parentIndent + explicit`.
/// Otherwise, peeks past empty lines to find the first content line's indent.
Parser<ParseError, int> _detectContentIndent(int parentIndent, int? explicit) {
  if (explicit != null) {
    return succeed<ParseError, int>(parentIndent + explicit);
  }
  return _emptyLine.many
      .skipThen(_peekIndent)
      .lookAhead
      .flatMap(
        (indent) =>
            indent > parentIndent
                ? succeed<ParseError, int>(indent)
                : succeed<ParseError, int>(parentIndent + 1),
      );
}

/// Collect block scalar content lines at [contentIndent].
///
/// Returns a list where non-null entries are content (text after indent),
/// and null entries are blank lines.
/// Document markers (`---`/`...`) at column 0 terminate collection.
Parser<ParseError, List<String?>> _collectBlockContent(int contentIndent) {
  // Document markers at column 0 terminate block scalar content.
  final docGuard =
      contentIndent == 0
          ? (_docStart | _docEnd).notFollowedBy
          : succeed<ParseError, void>(null);

  final contentLine = docGuard
      .skipThen(_indent(contentIndent))
      .skipThen(satisfy((c) => c != '\n', 'char').many.capture)
      .thenSkip(common.newline())
      .map<String?>((s) => s);

  final blankLine = satisfy(
    (c) => c == ' ' || c == '\t',
    'space',
  ).many.skipThen(common.newline()).as<String?>(null);

  return (contentLine | blankLine).many;
}

/// Assemble block scalar content from collected lines.
String _assembleBlockScalar(List<String?> lines, bool folded, _Chomp chomp) {
  final contentLines = lines.map((l) => l ?? '').toList();

  // Join lines: literal uses \n, folded uses smart folding.
  // Both produce the raw content ending with \n (from the join/fold).
  final raw = folded ? _foldLines(contentLines) : contentLines.join('\n');

  // Add trailing newline for the final line.
  final withNewline = '$raw\n';

  return switch (chomp) {
    _Chomp.strip => withNewline.replaceAll(RegExp(r'\n+$'), ''),
    _Chomp.clip => () {
      final stripped = withNewline.replaceAll(RegExp(r'\n+$'), '');
      return stripped.isEmpty ? '' : '$stripped\n';
    }(),
    _Chomp.keep => withNewline,
  };
}

/// Fold block scalar content lines (for `>` folded style) per YAML §8.1.3.
///
/// - Consecutive non-empty, non-more-indented lines fold with spaces
/// - Empty lines produce literal newlines
/// - More-indented lines are preserved verbatim on their own lines
/// - Transitions between regular↔more-indented produce line breaks
String _foldLines(List<String> lines) {
  if (lines.isEmpty) return '';

  bool isMoreInd(String l) =>
      l.isNotEmpty && (l.startsWith(' ') || l.startsWith('\t'));

  final buf = StringBuffer();
  // Track the last non-empty line type for transitions across blank lines.
  // null = no non-empty line seen yet.
  bool? lastNonEmptyWasMore;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final isMore = isMoreInd(line);

    if (i == 0) {
      if (line.isEmpty) {
        buf.write('\n');
      } else {
        buf.write(line);
        if (isMore) buf.write('\n');
        lastNonEmptyWasMore = isMore;
      }
    } else {
      final prev = lines[i - 1];
      final prevRegular = prev.isNotEmpty && !isMoreInd(prev);
      final prevEmpty = prev.isEmpty;

      if (line.isEmpty) {
        buf.write('\n');
      } else if (isMore) {
        // More-indented: needs its own line.
        if (prevRegular) {
          // Regular → more-indented: end paragraph, start indented block.
          buf.write('\n');
        } else if (prevEmpty && lastNonEmptyWasMore == false) {
          // Regular → empty → more-indented: need extra \n for indented block.
          // Only when there WAS a preceding regular line (not at start of content).
          buf.write('\n');
        }
        // After prev more-indented or (empty after more-indented): trailing \n
        // from prev more-indented already serves as separator.
        buf.write(line);
        buf.write('\n');
        lastNonEmptyWasMore = true;
      } else {
        // Regular line.
        if (prevRegular) {
          buf.write(' ');
        }
        // After more-indented: trailing \n already written.
        // After empty: \n already written.
        buf.write(line);
        lastNonEmptyWasMore = false;
      }
    }
  }
  return buf.toString();
}

// ---- Block mapping key ----

/// Plain (unquoted) block key — single-line plain scalar.
/// Terminates at `: ` (colon-space) or `:\n` or `#` preceded by space.
final Parser<ParseError, String> _plainBlockKey = _plainScalar(
  isFlow: false,
).map(
  (v) => switch (v) {
    YamlString(:final value) => value,
    _ => '',
  },
);

/// Block mapping key with optional node properties.
/// Returns `(keyString, anchorName?, isAliasKey)`.
final Parser<ParseError, (String, String?, bool)> _blockKeyWithProps = () {
  final regularKeyText =
      _yamlDoubleQuotedString | _yamlSingleQuotedString | _plainBlockKey;

  final aliasKey = char('*').skipThen(_anchorName).map((name) => (name, true));
  final normalKey = regularKeyText.map((key) => (key, false));
  final keyText = aliasKey | normalKey;

  // Key with node properties (tag/anchor).
  final withProps = _nodeProps.flatMap(
    (props) => common
        .hspaces1()
        .skipThen(keyText)
        .map(((String, bool) k) => (k.$1, props.anchor, k.$2)),
  );

  // Key without properties.
  final bare = keyText.map(((String, bool) k) => (k.$1, null as String?, k.$2));

  return withProps | bare;
}();

/// Block mapping key (string only, discards anchor/alias info).
final Parser<ParseError, String> _blockKey = _blockKeyWithProps.map(
  (t) => t.$1,
);

// ---- Indentation-aware block parsing ----

Parser<ParseError, YamlValue> _blockValueAt(
  int minIndent, {
  int blockScalarOffset = 0,
  int? blockScalarParent,
}) => _peekIndent.flatMap((actual) {
  if (actual < minIndent) {
    return failure<ParseError, YamlValue>(
      CustomError('expected indent >= $minIndent, got $actual', Location.zero),
    );
  }

  // Document markers at column 0 are NOT content.
  final docGuard =
      actual == 0
          ? (_docStart | _docEnd).notFollowedBy
          : succeed<ParseError, void>(null);

  // Use minIndent - 1 as blockIndent for multi-line plain scalars so that
  // continuation lines at the same indent level are accepted.
  // At top level (minIndent=0), blockIndent=-1 allows indent-0 continuations.
  // Block scalar + inline values at this indent, using the shared
  // _blockNodeValue with the indent already consumed by _indent(actual).
  final singleValue = _indent(actual).skipThen(
    // Block scalar (no lineEnd needed).
    _withNodeProps(
          _blockScalarValue(blockScalarParent ?? (actual + blockScalarOffset)),
          indent: actual,
          minChildIndent: minIndent,
        ) |
        // Inline values (lineEnd needed).
        _withNodeProps(
          _yamlAlias |
              _flowSequence |
              _flowMapping |
              _quotedString |
              _plainScalar(
                isFlow: false,
                blockIndent: minIndent - 1,
              ).map(_resolveScalarType),
          indent: actual,
          minChildIndent: minIndent,
        ).thenSkip(_lineEnd),
  );

  return docGuard.skipThen(
    _blockSequenceAt(actual) | _blockMappingAt(actual) | singleValue,
  );
});

Parser<ParseError, YamlValue> _blockMappingAt(int indent) {
  // Value after `:` — delegates to the unified _blockNodeValue.
  final mappingValue = _blockNodeValue(
    parentIndent: indent,
    minChildIndent: indent + 1,
    allowSameIndentSeq: true,
  );

  // Implicit key entry: key: value
  // Returns (key, value, keyAnchor?, isAliasKey).
  final implicitEntry = _blockKeyWithProps.flatMap((
    (String, String?, bool) keyInfo,
  ) {
    final (key, keyAnchor, isAlias) = keyInfo;
    return common
        .hspaces()
        .skipThen(char(':'))
        .skipThen(mappingValue)
        .map((value) => (key, value, keyAnchor, isAlias));
  });

  // Explicit key entry: ? key\n: value (§8.2.1)
  final explicitEntry = char('?').skipThen(
    // Key on same line or next line, or empty key.
    (common.hspaces1().skipThen(
              _blockScalarValue(indent) |
                  _blockInlineValue(indent).thenSkip(_lineEnd),
            ) |
            _lineEnd.skipThen(defer(() => _blockValueAt(indent + 1))) |
            _lineEnd.as<YamlValue>(const YamlNull()))
        .thenSkip(_blankLine.many)
        .flatMap((keyValue) {
          final key = switch (keyValue) {
            YamlString(:final value) => value,
            YamlNull() => '',
            _ => keyValue.toString(),
          };
          // Optional `: value` on next line at same indent.
          return (_indent(indent).skipThen(char(':')).skipThen(mappingValue) |
                  succeed<ParseError, YamlValue>(const YamlNull()))
              .map((value) => (key, value, null as String?, false));
        }),
  );

  // Document markers at column 0 terminate mapping entries.
  final docGuard =
      indent == 0
          ? (_docStart | _docEnd).notFollowedBy
          : succeed<ParseError, void>(null);

  final entry = docGuard
      .skipThen(_indent(indent))
      .skipThen(explicitEntry | implicitEntry);

  return entry.thenSkip(_blankLine.many).many1.map<YamlValue>((entries) {
    final pairs = <String, YamlValue>{};
    final keyAnchors = <String, String>{};
    final aliasKeys = <String>{};
    for (final (key, value, keyAnchor, isAlias) in entries) {
      pairs[key] = value;
      if (keyAnchor != null) {
        keyAnchors[keyAnchor] = key;
      }
      if (isAlias) {
        aliasKeys.add(key);
      }
    }
    return YamlMapping(pairs, keyAnchors: keyAnchors, aliasKeys: aliasKeys)
        as YamlValue;
  });
}

Parser<ParseError, YamlValue> _blockSequenceAt(int indent) {
  final inlineEntry = _blockKey.flatMap(
    (key) => common
        .hspaces()
        .skipThen(char(':'))
        .skipThen(
          common.hspaces1().skipThen(
                _blockScalarValue(indent + 2) |
                    _blockInlineValue(indent + 2).thenSkip(_lineEnd),
              ) |
              _lineEnd.skipThen(defer(() => _blockValueAt(indent + 2))),
        )
        .map((value) => (key, value)),
  );

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

  // Document markers at column 0 terminate sequence items.
  final docGuard =
      indent == 0
          ? (_docStart | _docEnd).notFollowedBy
          : succeed<ParseError, void>(null);

  // Inline nested sequence: "- - x" — parse first item inline,
  // then detect the actual indent of subsequent items from the next line.
  Parser<ParseError, YamlValue> inlineNestedSeq() {
    // Single-line inline value for nested seq items: no multi-line continuation
    // so that subsequent `- item` lines are parsed as separate seq entries.
    final singleLineInline =
        _yamlAlias |
        _withNodeProps(
          _flowSequence |
              _flowMapping |
              _quotedString |
              _plainScalar(isFlow: false).map(_resolveScalarType),
          indent: indent + 2,
          minChildIndent: indent + 3,
        );

    // First inner item: no indent needed (already at correct position).
    final firstItem = char('-').skipThen(
      common.hspaces1().skipThen(
            _blockScalarValue(indent + 2) |
                defer(inlineNestedSeq) |
                compactMapping |
                singleLineInline.thenSkip(_lineEnd),
          ) |
          _lineEnd.skipThen(
            defer(() => _blockValueAt(indent + 3)) |
                succeed<ParseError, YamlValue>(const YamlNull()),
          ),
    );

    // Combine first item with remaining items. Detect the actual indent
    // from the next line rather than hardcoding indent + 2, because the
    // inner `-` position varies with whitespace/tabs between indicators.
    // Only accept continuations deeper than the outer sequence indent to
    // prevent the inner sequence from capturing outer-level items.
    return firstItem
        .thenSkip(_blankLine.many)
        .flatMap(
          (first) => _peekIndent.flatMap((nextIndent) {
            if (nextIndent <= indent) {
              return succeed<ParseError, YamlValue>(YamlSequence([first]));
            }
            return defer(() => _blockSequenceAt(nextIndent)).optional.map((
              rest,
            ) {
              if (rest case YamlSequence(:final elements)) {
                return YamlSequence([first, ...elements]) as YamlValue;
              }
              return YamlSequence([first]) as YamlValue;
            });
          }),
        );
  }

  final item = docGuard
      .skipThen(_indent(indent))
      .skipThen(
        char('-').skipThen(
          _blockNodeValue(
            parentIndent: indent,
            minChildIndent: indent + 1,
            extraInline: defer(inlineNestedSeq) | compactMapping,
          ),
        ),
      );

  return item.thenSkip(_blankLine.many).many1.map<YamlValue>(YamlSequence.new);
}

// ---- Top-level value ----

final Parser<ParseError, YamlValue> _yamlValue =
    common.hspaces().skipThen(_flowSequence | _flowMapping) |
    _blockValueAt(0, blockScalarOffset: -1);

// ---- Document ----

/// Directive: `%YAML 1.2` or `%TAG ...`. Consumed and ignored.
final Parser<ParseError, void> _directive = char('%')
    .skipThen(satisfy((c) => c != '\n', 'directive char').many)
    .skipThen(common.newline().as<void>(null) | eof())
    .as<void>(null);

/// Document start marker: `---` followed by whitespace, newline, or EOF.
/// `---word` is NOT a document start — it's a plain scalar.
final Parser<ParseError, void> _docStart = string('---')
    .thenSkip(
      satisfy(
            (c) => c == ' ' || c == '\t' || c == '\n' || c == '\r',
            'ws',
          ).lookAhead.as<void>(null) |
          eof(),
    )
    .as<void>(null);

/// Document end marker: `...` optionally followed by whitespace/comments.
final Parser<ParseError, void> _docEnd = string('...')
    .thenSkip(common.hspaces())
    .thenSkip(_yamlComment | common.newline().as<void>(null) | eof());

/// A single document: optional directives, optional `---`, value, optional `...`.
final Parser<ParseError, YamlDocument> _singleDocument = _directive.many
    .skipThen(_blankLine.many)
    .skipThen(
      // Explicit document with --- marker.
      _docStart.skipThen(
            _blockNodeValue(
              parentIndent: -1,
              minChildIndent: 0,
            ).thenSkip(_blankLine.many),
          ) |
          // No --- marker (bare document).
          _blankLine.many.skipThen(_yamlValue).thenSkip(_blankLine.many),
    )
    .thenSkip(_docEnd.optional);

/// Parse first document, allowing remaining documents in the stream.
final Parser<ParseError, YamlDocument> _yamlDocument = _blankLine.many
    .skipThen(_singleDocument)
    .thenSkip(_ws)
    .thenSkip(
      // Allow remaining documents (multi-document stream).
      eof() | _docStart | _docEnd,
    );

/// Inter-document whitespace: blank lines, comments, and `...` markers.
final Parser<ParseError, void> _interDocWs = (_blankLine | _docEnd).many
    .as<void>(null);

/// Multiple documents separated by `---` or `...` markers.
final Parser<ParseError, List<YamlDocument>> _yamlMultiDocument = _interDocWs
    .skipThen(_singleDocument.thenSkip(_interDocWs).many1)
    .thenSkip(_ws)
    .thenSkip(eof());
