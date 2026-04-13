/// TOML v1.0.0 parser.
library;

import 'package:rumil/rumil.dart';

import 'ast/toml.dart';
import 'common.dart' as common;

/// Parse a TOML document from [input].
Result<ParseError, TomlDocument> parseToml(String input) {
  try {
    return _tomlDocument.run(input);
  } on FormatException catch (e) {
    return Failure.eager([
      CustomError(e.message, Location.zero),
    ], Location.zero);
  } on RangeError catch (e) {
    return Failure.eager([
      CustomError(e.toString(), Location.zero),
    ], Location.zero);
  }
}

// ---- Whitespace & comments ----

/// TOML newline: LF or CRLF only. Bare CR is invalid.
final Parser<ParseError, String> _tomlNewline = string('\r\n') | string('\n');

final Parser<ParseError, void> _ws = satisfy(
  (c) => c == ' ' || c == '\t',
  'whitespace',
).many.as<void>(null);

final Parser<ParseError, void> _comment = char('#')
    .skipThen(
      satisfy(
        (c) => c != '\n' && c != '\r' && _isAllowedChar(c),
        'comment char',
      ).many,
    )
    .as<void>(null);

final Parser<ParseError, void> _eol = _ws
    .skipThen(_comment.optional)
    .skipThen(_tomlNewline.as<void>(null) | eof());

final Parser<ParseError, void> _skipBlankAndComments = (_tomlNewline.as<void>(
          null,
        ) |
        _ws.skipThen(_comment) |
        _ws.skipThen(_tomlNewline.as<void>(null)))
    .many
    .as<void>(null);

// ---- Control character validation ----

/// TOML forbids control chars except tab in strings and comments.
/// Bare CR (0x0D) is also forbidden — only CR+LF is valid.
bool _isAllowedChar(String c) {
  final code = c.codeUnitAt(0);
  // Allow tab (0x09), reject other control chars and bare CR.
  return code == 0x09 || (code >= 0x20 && code != 0x7F);
}

/// TOML forbids bare CR outside of CR+LF sequences.
bool _isAllowedMultilineChar(String c) {
  final code = c.codeUnitAt(0);
  // In multiline: allow tab, LF, CR (will be validated as CRLF elsewhere).
  return code == 0x09 || code == 0x0A || (code >= 0x20 && code != 0x7F);
}

// ---- Strings ----

final Parser<ParseError, String> _unicodeEscape4 = char(
  'u',
).skipThen(common.hexDigit().times(4)).flatMap((ds) {
  final cp = int.parse(ds.join(), radix: 16);
  if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
    return failure<ParseError, String>(
      CustomError(
        'Invalid Unicode codepoint: U+${cp.toRadixString(16)}',
        Location.zero,
      ),
    );
  }
  return succeed<ParseError, String>(String.fromCharCode(cp));
});

final Parser<ParseError, String> _unicodeEscape8 = char(
  'U',
).skipThen(common.hexDigit().times(8)).flatMap((ds) {
  final cp = int.parse(ds.join(), radix: 16);
  if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
    return failure<ParseError, String>(
      CustomError(
        'Invalid Unicode codepoint: U+${cp.toRadixString(16)}',
        Location.zero,
      ),
    );
  }
  return succeed<ParseError, String>(String.fromCharCode(cp));
});

final Parser<ParseError, String> _hexEscape2 = char('x')
    .skipThen(common.hexDigit().times(2))
    .map((ds) => String.fromCharCode(int.parse(ds.join(), radix: 16)));

final Parser<ParseError, String> _basicEscape = char('\\').skipThen(
  char('"').as('"') |
      char('\\').as('\\') |
      char('b').as('\b') |
      char('f').as('\f') |
      char('n').as('\n') |
      char('r').as('\r') |
      char('t').as('\t') |
      char('e').as('\x1B') |
      _hexEscape2 |
      _unicodeEscape4 |
      _unicodeEscape8 |
      // Reject unknown escape sequences.
      satisfy((_) => true, 'valid escape').flatMap(
        (c) => failure<ParseError, String>(
          CustomError('Unknown escape sequence: \\$c', Location.zero),
        ),
      ),
);

final Parser<ParseError, String> _basicString = char('"')
    .skipThen(
      (_basicEscape |
              satisfy(
                (c) => c != '"' && c != '\\' && c != '\n' && _isAllowedChar(c),
                'string char',
              ))
          .many,
    )
    .map((cs) => cs.join())
    .thenSkip(char('"'));

final Parser<ParseError, String> _literalString = char("'")
    .skipThen(
      satisfy(
        (c) => c != "'" && c != '\n' && _isAllowedChar(c),
        'literal string char',
      ).many,
    )
    .map((cs) => cs.join())
    .thenSkip(char("'"));

final Parser<ParseError, String> _multiLineBasicString = () {
  // Line continuation: \ + optional trailing spaces/tabs + newline, then trim
  // all following whitespace (spaces, tabs, newlines) until non-whitespace.
  final lineContinuation = satisfy((c) => c == ' ' || c == '\t', 'trailing ws')
      .many
      .skipThen(_tomlNewline)
      .as('')
      .thenSkip(
        satisfy(
          (c) => c == ' ' || c == '\t' || c == '\n' || c == '\r',
          'continuation ws',
        ).many,
      );

  final escape = char('\\').skipThen(
    char('"').as('"') |
        char('\\').as('\\') |
        char('b').as('\b') |
        char('f').as('\f') |
        char('n').as('\n') |
        char('r').as('\r') |
        char('t').as('\t') |
        char('e').as('\x1B') |
        lineContinuation |
        _hexEscape2 |
        _unicodeEscape4 |
        _unicodeEscape8 |
        // Reject unknown escape sequences.
        satisfy((_) => true, 'valid escape').flatMap(
          (c) => failure<ParseError, String>(
            CustomError('Unknown escape sequence: \\$c', Location.zero),
          ),
        ),
  );

  final contentChar =
      escape |
      (string('"""').notFollowedBy.skipThen(
        // CR is only valid as part of CRLF.
        string('\r\n').as('\n') |
            satisfy(
              (c) => c != '\\' && c != '\r' && _isAllowedMultilineChar(c),
              'string char',
            ),
      ));

  // Up to 2 quotes can appear before the closing """.
  final close =
      string('"""""').as('""') | string('""""').as('"') | string('"""').as('');

  return string('"""')
      .skipThen(_tomlNewline.optional)
      .skipThen(contentChar.many)
      .flatMap((cs) => close.map((extra) => '${cs.join()}$extra'));
}();

final Parser<ParseError, String> _multiLineLiteralString = () {
  final contentChar = string("'''").notFollowedBy.skipThen(
    string('\r\n').as('\n') |
        satisfy(
          (c) => c != '\r' && _isAllowedMultilineChar(c),
          'literal string char',
        ),
  );

  // Up to 2 quotes can appear before the closing '''.
  final close =
      string("'''''").as("''") | string("''''").as("'") | string("'''").as('');

  return string("'''")
      .skipThen(_tomlNewline.optional)
      .skipThen(contentChar.many)
      .flatMap((cs) => close.map((extra) => '${cs.join()}$extra'));
}();

final Parser<ParseError, TomlValue> _tomlString = (_multiLineBasicString |
        _multiLineLiteralString |
        _basicString |
        _literalString)
    .map<TomlValue>(TomlString.new);

// ---- Keys ----

final Parser<ParseError, String> _bareKey = satisfy(
  (c) =>
      (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
      (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
      (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
      c == '-' ||
      c == '_',
  'bare key char',
).many1.map((cs) => cs.join());

final Parser<ParseError, String> _simpleKey =
    _bareKey | _basicString | _literalString;

final Parser<ParseError, List<String>> _dottedKey = _simpleKey.sepBy1(
  _ws.skipThen(char('.')).skipThen(_ws),
);

// ---- Booleans ----

final Parser<ParseError, TomlValue> _tomlBool = keywords<TomlValue>({
  'true': const TomlBool(true),
  'false': const TomlBool(false),
});

// ---- Integers ----

/// Validate underscore placement: no leading, trailing, or double underscores.
Parser<ParseError, List<String>> _validateUs(List<String> cs) {
  final s = cs.join();
  if (s.startsWith('_') || s.endsWith('_') || s.contains('__')) {
    return failure<ParseError, List<String>>(
      CustomError('Invalid underscore in number', Location.zero),
    );
  }
  return succeed<ParseError, List<String>>(cs);
}

Parser<ParseError, String> _digitOrUnderscore(
  bool Function(String) pred,
  String expected,
) => satisfy((c) => pred(c) || c == '_', expected);

final Parser<ParseError, TomlValue> _tomlInteger = () {
  final hexDigitU = _digitOrUnderscore(
    (c) =>
        (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
        (c.compareTo('a') >= 0 && c.compareTo('f') <= 0) ||
        (c.compareTo('A') >= 0 && c.compareTo('F') <= 0),
    'hex digit',
  );

  final octDigitU = _digitOrUnderscore(
    (c) => c.compareTo('0') >= 0 && c.compareTo('7') <= 0,
    'octal digit',
  );

  final binDigitU = _digitOrUnderscore(
    (c) => c == '0' || c == '1',
    'binary digit',
  );

  final digitU = _digitOrUnderscore(
    (c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0,
    'digit',
  );

  String stripUnderscores(List<String> cs) => cs.where((c) => c != '_').join();

  final hex = string('0x')
      .skipThen(hexDigitU.many1)
      .flatMap(_validateUs)
      .map((ds) => int.parse(stripUnderscores(ds), radix: 16));

  final oct = string('0o')
      .skipThen(octDigitU.many1)
      .flatMap(_validateUs)
      .map((ds) => int.parse(stripUnderscores(ds), radix: 8));

  final bin = string('0b')
      .skipThen(binDigitU.many1)
      .flatMap(_validateUs)
      .map((ds) => int.parse(stripUnderscores(ds), radix: 2));

  final decimal = (char('-') | char('+')).optional.flatMap(
    (sign) => digitU.many1.flatMap(_validateUs).flatMap((ds) {
      final raw = stripUnderscores(ds);
      // No leading zeros (except bare 0).
      if (raw.length > 1 && raw.startsWith('0')) {
        return failure<ParseError, int>(
          CustomError('Leading zeros not allowed in integers', Location.zero),
        );
      }
      // Parse with sign to handle int64 min correctly.
      final signed = sign == '-' ? '-$raw' : raw;
      final value = int.tryParse(signed);
      if (value == null) {
        return failure<ParseError, int>(
          CustomError('Integer overflow: $signed', Location.zero),
        );
      }
      return succeed<ParseError, int>(value);
    }),
  );

  return (hex | oct | bin | decimal).map<TomlValue>(TomlInteger.new);
}();

// ---- Floats ----

final Parser<ParseError, TomlValue> _tomlFloat = () {
  final special = keywords<double>({
    'inf': double.infinity,
    '+inf': double.infinity,
    '-inf': double.negativeInfinity,
    'nan': double.nan,
    '+nan': double.nan,
    '-nan': double.nan,
  });

  final digitU = _digitOrUnderscore(
    (c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0,
    'digit',
  );

  String strip(List<String> cs) => cs.where((c) => c != '_').join();

  final exponent = oneOf(
    'eE',
  ).skipThen((char('-') | char('+')).optional.zip(digitU.many1));

  /// Validate exponent underscore placement.
  Parser<ParseError, (String?, List<String>)> validatedExponent() =>
      exponent.flatMap((exp) => _validateUs(exp.$2).map((_) => exp));

  /// Validate whole part: no leading zeros, valid underscores.
  Parser<ParseError, String> validatedWhole(
    Parser<ParseError, List<String>> digits,
  ) => digits.flatMap(_validateUs).flatMap((ds) {
    final s = strip(ds);
    if (s.length > 1 && s.startsWith('0')) {
      return failure<ParseError, String>(
        CustomError('Leading zeros not allowed', Location.zero),
      );
    }
    return succeed<ParseError, String>(s);
  });

  final withFraction = (char('-') | char('+')).optional.flatMap(
    (sign) => validatedWhole(digitU.many1).flatMap(
      (wholeStr) => char('.')
          .skipThen(digitU.many1)
          .flatMap(_validateUs)
          .flatMap(
            (frac) => validatedExponent().optional.map((exp) {
              final s = sign == '-' ? '-' : '';
              final expStr =
                  exp != null ? 'e${exp.$1 ?? ''}${strip(exp.$2)}' : '';
              return double.parse('$s$wholeStr.${strip(frac)}$expStr');
            }),
          ),
    ),
  );

  final onlyExponent = (char('-') | char('+')).optional.flatMap(
    (sign) => validatedWhole(digitU.many1).flatMap(
      (wholeStr) => validatedExponent().map((exp) {
        final s = sign == '-' ? '-' : '';
        return double.parse('$s${wholeStr}e${exp.$1 ?? ''}${strip(exp.$2)}');
      }),
    ),
  );

  return (special | withFraction | onlyExponent).map<TomlValue>(TomlFloat.new);
}();

// ---- Datetimes ----

typedef _DateParts = (int year, int month, int day);
typedef _TimeParts = (int hour, int minute, int second, int nanosecond);

int _daysInMonth(int year, int month) => switch (month) {
  1 || 3 || 5 || 7 || 8 || 10 || 12 => 31,
  4 || 6 || 9 || 11 => 30,
  2 => (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 29 : 28,
  _ => 0,
};

final Parser<ParseError, _DateParts> _datePrefix = digit()
    .times(4)
    .flatMap(
      (y) => char('-')
          .skipThen(digit().times(2))
          .flatMap(
            (m) => char('-').skipThen(digit().times(2)).flatMap((d) {
              final year = int.parse(y.join());
              final month = int.parse(m.join());
              final day = int.parse(d.join());
              if (month < 1 || month > 12 || day < 1) {
                return failure<ParseError, _DateParts>(
                  CustomError('Invalid date', Location.zero),
                );
              }
              final maxDay = _daysInMonth(year, month);
              if (day > maxDay) {
                return failure<ParseError, _DateParts>(
                  CustomError('Invalid date', Location.zero),
                );
              }
              return succeed<ParseError, _DateParts>((year, month, day));
            }),
          ),
    );

final Parser<ParseError, _TimeParts> _timePart = digit()
    .times(2)
    .flatMap(
      (h) => char(':')
          .skipThen(digit().times(2))
          .flatMap(
            (m) =>
            // Seconds are optional (TOML 1.1).
            (char(':')
                .skipThen(digit().times(2))
                .flatMap(
                  (s) =>
                      (char('.').skipThen(digit().many1)).optional.map((frac) {
                        final ns =
                            frac != null
                                ? int.parse(
                                  frac.join().padRight(9, '0').substring(0, 9),
                                )
                                : 0;
                        return (
                          int.parse(h.join()),
                          int.parse(m.join()),
                          int.parse(s.join()),
                          ns,
                        );
                      }),
                )).optional.flatMap((full) {
              final t =
                  full ?? (int.parse(h.join()), int.parse(m.join()), 0, 0);
              if (t.$1 > 23 || t.$2 > 59 || t.$3 > 59) {
                return failure<ParseError, _TimeParts>(
                  CustomError('Invalid time', Location.zero),
                );
              }
              return succeed<ParseError, _TimeParts>(t);
            }),
          ),
    );

final Parser<ParseError, Duration> _offset =
    oneOf('Zz').as(Duration.zero) |
    (oneOf('+-')
        .zip(digit().times(2).zip(char(':').skipThen(digit().times(2))))
        .flatMap((pair) {
          final sign = pair.$1 == '-' ? -1 : 1;
          final hours = int.parse(pair.$2.$1.join());
          final minutes = int.parse(pair.$2.$2.join());
          if (hours > 23 || minutes > 59) {
            return failure<ParseError, Duration>(
              CustomError('Invalid timezone offset', Location.zero),
            );
          }
          return succeed<ParseError, Duration>(
            Duration(hours: sign * hours, minutes: sign * minutes),
          );
        }));

final Parser<ParseError, TomlValue> _tomlDateTimeValue = _datePrefix.flatMap(
  (date) => oneOf('Tt ').skipThen(_timePart).optional.flatMap((time) {
    if (time == null) {
      return succeed<ParseError, TomlValue>(
        TomlLocalDate(date.$1, date.$2, date.$3),
      );
    }
    return _offset.optional.map<TomlValue>((off) {
      if (off != null) {
        final utc = DateTime.utc(
          date.$1,
          date.$2,
          date.$3,
          time.$1,
          time.$2,
          time.$3,
          time.$4 ~/ 1000000,
          (time.$4 ~/ 1000) % 1000,
        ).subtract(off);
        return TomlDateTime(utc);
      }
      return TomlLocalDateTime(
        DateTime(
          date.$1,
          date.$2,
          date.$3,
          time.$1,
          time.$2,
          time.$3,
          time.$4 ~/ 1000000,
          (time.$4 ~/ 1000) % 1000,
        ),
      );
    });
  }),
);

final Parser<ParseError, TomlValue> _tomlLocalTimeValue = _timePart
    .map<TomlValue>((t) => TomlLocalTime(t.$1, t.$2, t.$3, t.$4));

// ---- Containers ----

final Parser<ParseError, void> _arraySep = _skipBlankAndComments.skipThen(_ws);

final Parser<ParseError, TomlValue> _tomlArray = char('[')
    .skipThen(_arraySep)
    .skipThen(
      defer(
        () => _tomlValue,
      ).sepBy(_arraySep.skipThen(char(',')).skipThen(_arraySep)),
    )
    .flatMap(
      (elements) =>
      // Trailing comma only allowed after at least one element.
      (elements.isNotEmpty
              ? (_arraySep.skipThen(char(',')).skipThen(_arraySep)).optional
              : succeed<ParseError, void>(null))
          .skipThen(
            _arraySep
                .skipThen(char(']'))
                .map((_) => TomlArray(elements) as TomlValue),
          ),
    );

final Parser<ParseError, TomlValue> _inlineTable = () {
  // TOML 1.1: inline tables allow newlines and comments.
  final inlineWs = _skipBlankAndComments.skipThen(_ws);

  final pair = _ws
      .skipThen(_dottedKey)
      .flatMap(
        (keys) => _ws
            .skipThen(char('='))
            .skipThen(_ws)
            .skipThen(defer(() => _tomlValue))
            .map((value) => (keys, value)),
      );

  return char('{')
      .skipThen(inlineWs)
      .skipThen(pair.sepBy(inlineWs.skipThen(char(',')).skipThen(inlineWs)))
      .flatMap(
        (pairs) =>
        // TOML 1.1: trailing comma allowed (only after at least one pair).
        (pairs.isNotEmpty
                ? (inlineWs.skipThen(char(',')).skipThen(inlineWs)).optional
                : succeed<ParseError, void>(null))
            .skipThen(
              inlineWs.skipThen(char('}')).map((_) {
                final table = <String, TomlValue>{};
                final inlineDefined = <String>{};
                final inlineFrozen = <String>{};
                for (final (keys, value) in pairs) {
                  // Check intermediate paths aren't frozen.
                  for (var i = 1; i < keys.length; i++) {
                    final p = keys.sublist(0, i).map(_esc).join('.');
                    if (inlineFrozen.contains(p)) {
                      throw FormatException(
                        'Cannot extend inline table key: $p',
                      );
                    }
                  }
                  _setNested(table, keys, value, defined: inlineDefined);
                  // Freeze inline table values.
                  final fullPath = keys.map(_esc).join('.');
                  if (value is TomlTable) {
                    inlineFrozen.add(fullPath);
                    _freezePaths(inlineFrozen, fullPath, value);
                  }
                }
                return TomlTable(table) as TomlValue;
              }),
            ),
      );
}();

// ---- Value ----

final Parser<ParseError, TomlValue> _tomlValue = (_tomlString |
        _tomlBool |
        _tomlDateTimeValue |
        _tomlLocalTimeValue |
        _tomlFloat |
        _tomlInteger |
        _tomlArray |
        _inlineTable)
    .named('value');

// ---- Document structure ----

typedef _KVPair = (List<String>, TomlValue);

final Parser<ParseError, _KVPair> _keyValue = _ws
    .skipThen(_dottedKey)
    .flatMap(
      (key) => _ws
          .skipThen(char('='))
          .skipThen(_ws)
          .skipThen(_tomlValue)
          .flatMap((value) => _eol.map((_) => (key, value))),
    );

final Parser<ParseError, List<String>> _tableHeader = char('[')
    .skipThen(_ws)
    .skipThen(_dottedKey)
    .thenSkip(_ws)
    .thenSkip(char(']'))
    .thenSkip(_eol);

final Parser<ParseError, List<String>> _arrayTableHeader = string('[[')
    .skipThen(_ws)
    .skipThen(_dottedKey)
    .thenSkip(_ws)
    .thenSkip(string(']]'))
    .thenSkip(_eol);

typedef _Section = (bool isArray, List<String> path, List<_KVPair> pairs);

final Parser<ParseError, _Section> _section = _skipBlankAndComments
    .skipThen(_ws)
    .skipThen(
      (_arrayTableHeader.map((p) => (true, p)) |
          _tableHeader.map((p) => (false, p))),
    )
    .flatMap(
      (header) => _skipBlankAndComments
          .skipThen(_keyValue.sepBy(_skipBlankAndComments))
          .map((pairs) => (header.$1, header.$2, pairs)),
    );

final Parser<ParseError, TomlDocument> _tomlDocument = _skipBlankAndComments
    .skipThen(_keyValue.sepBy(_skipBlankAndComments))
    .flatMap(
      (rootPairs) => _section.many.flatMap(
        (sections) => _skipBlankAndComments
            .skipThen(_ws)
            .skipThen(eof())
            .map((_) => _buildDocument(rootPairs, sections)),
      ),
    );

// ---- Document assembly ----

TomlDocument _buildDocument(List<_KVPair> rootPairs, List<_Section> sections) {
  final doc = <String, TomlValue>{};
  final t = _TableTracker();

  void setInSection(
    Map<String, TomlValue> target,
    List<_KVPair> pairs,
    String sectionPrefix,
  ) {
    for (final (keys, value) in pairs) {
      final fullPath = _joinPath(sectionPrefix, keys.map(_esc).join('.'));

      // Check we're not extending a frozen (inline-table) path.
      t.checkNotFrozen(fullPath);

      // Track intermediate dotted-key tables and check constraints.
      for (var i = 1; i < keys.length; i++) {
        final intermediate = _joinPath(
          sectionPrefix,
          keys.sublist(0, i).map(_esc).join('.'),
        );
        t.checkNotFrozen(intermediate);
        // Dotted keys from one section can't extend an explicit table.
        if (t.explicitTables.contains(intermediate) &&
            intermediate != sectionPrefix) {
          throw FormatException(
            'Cannot extend [$intermediate] via dotted keys',
          );
        }
        t.dottedTables.add(intermediate);
      }

      // Cannot overwrite a key already used as a dotted-key intermediate.
      if (keys.length == 1 && t.dottedTables.contains(fullPath)) {
        throw FormatException('Cannot overwrite key: $fullPath');
      }

      _setNested(
        target,
        keys,
        value,
        defined: t.definedKeys,
        prefix: sectionPrefix,
      );

      // If value is an inline table, freeze it and all sub-paths.
      if (value is TomlTable) {
        t.freezeInlineTable(fullPath, value);
      }
      // If value is a static array, mark it as frozen.
      if (value is TomlArray) {
        t.frozen.add(fullPath);
      }
    }
  }

  setInSection(doc, rootPairs, '');

  for (final (isArray, path, pairs) in sections) {
    final pathStr = path.map(_esc).join('.');

    if (isArray) {
      // Cannot overwrite a scalar key or a frozen table.
      if (t.definedKeys.contains(pathStr)) {
        throw FormatException('Cannot redefine key as array: $pathStr');
      }
      t.checkNotFrozen(pathStr);
      // Cannot mix [[array]] with [table] at the same path.
      if (t.explicitTables.contains(pathStr)) {
        throw FormatException(
          'Cannot define [[array]] after [table]: $pathStr',
        );
      }
      // Cannot use [[array]] if path was created via dotted keys.
      if (t.dottedTables.contains(pathStr)) {
        throw FormatException(
          'Cannot define [[array]] — $pathStr was defined via dotted keys',
        );
      }
      // Cannot use [[array]] if path was implicitly used as a non-array table
      // by a previous [[nested.path]] (e.g. [[a.b]] before [[a]]).
      if (t.implicitTables.contains(pathStr) &&
          !t.arrayTables.contains(pathStr)) {
        throw FormatException(
          'Cannot define [[array]] — $pathStr was used as implicit table',
        );
      }
      t.arrayTables.add(pathStr);
      // Track intermediate paths as implicit tables (only if not already arrays).
      for (var i = 1; i < path.length; i++) {
        final implicit = path.sublist(0, i).map(_esc).join('.');
        if (!t.arrayTables.contains(implicit)) {
          t.implicitTables.add(implicit);
        }
      }

      final table = <String, TomlValue>{};
      for (final (keys, value) in pairs) {
        _setNested(table, keys, value);
      }
      _appendArrayTable(doc, path, table);
      // New array entry resets sub-table/key tracking for this scope.
      t.explicitTables.removeWhere((k) => k.startsWith('$pathStr.'));
      t.definedKeys.removeWhere((k) => k.startsWith('$pathStr.'));
      t.dottedTables.removeWhere((k) => k.startsWith('$pathStr.'));
    } else {
      // Cannot mix [table] with [[array]] at the same path.
      if (t.arrayTables.contains(pathStr)) {
        throw FormatException(
          'Cannot define [table] after [[array]]: $pathStr',
        );
      }
      // Cannot redefine explicit table.
      if (t.explicitTables.contains(pathStr)) {
        throw FormatException('Duplicate table: [$pathStr]');
      }
      t.explicitTables.add(pathStr);
      // Cannot redefine scalar key as table.
      if (t.definedKeys.contains(pathStr)) {
        throw FormatException('Cannot redefine key as table: $pathStr');
      }
      // Cannot extend inline table.
      t.checkNotFrozen(pathStr);
      // Cannot extend via dotted keys from another section.
      if (t.dottedTables.contains(pathStr)) {
        throw FormatException(
          'Cannot define [$pathStr] — already used via dotted keys',
        );
      }

      final target = _ensureTable(doc, path);
      setInSection(target, pairs, pathStr);
    }
  }

  return doc;
}

String _joinPath(String prefix, String suffix) =>
    prefix.isEmpty ? suffix : '$prefix.$suffix';

class _TableTracker {
  /// Paths frozen by inline tables — completely immutable.
  final frozen = <String>{};

  /// Leaf keys (scalars, static arrays).
  final definedKeys = <String>{};

  /// Explicit `[header]` paths.
  final explicitTables = <String>{};

  /// `[[array]]` paths.
  final arrayTables = <String>{};

  /// Tables created via dotted keys in a section.
  final dottedTables = <String>{};

  /// Tables implicitly created by `[[a.b]]` path navigation.
  final implicitTables = <String>{};

  /// Throws if any prefix of [path] is frozen (inline-table immutability).
  void checkNotFrozen(String path) {
    if (frozen.contains(path)) {
      throw FormatException('Cannot extend inline table: $path');
    }
    // Also check if any PARENT of the path is frozen.
    final parts = path.split('.');
    for (var i = 1; i < parts.length; i++) {
      final parent = parts.sublist(0, i).join('.');
      if (frozen.contains(parent)) {
        throw FormatException('Cannot extend inline table: $parent');
      }
    }
  }

  /// Recursively freeze an inline table and all its sub-paths.
  void freezeInlineTable(String path, TomlTable table) {
    frozen.add(path);
    for (final entry in table.pairs.entries) {
      final childPath = '$path.${_esc(entry.key)}';
      frozen.add(childPath);
      if (entry.value is TomlTable) {
        freezeInlineTable(childPath, entry.value as TomlTable);
      }
    }
  }
}

/// Set a nested value, throwing on duplicate keys.
void _setNested(
  Map<String, TomlValue> target,
  List<String> keys,
  TomlValue value, {
  Set<String>? defined,
  String prefix = '',
}) {
  var current = target;
  var path = prefix;
  for (var i = 0; i < keys.length - 1; i++) {
    path = path.isEmpty ? _esc(keys[i]) : '$path.${_esc(keys[i])}';
    final existing = current[keys[i]];
    if (existing is TomlTable) {
      current = existing.pairs;
    } else if (existing != null) {
      throw FormatException('Cannot redefine key as table: $path');
    } else {
      final sub = <String, TomlValue>{};
      current[keys[i]] = TomlTable(sub);
      current = sub;
    }
  }
  final fullPath = path.isEmpty ? _esc(keys.last) : '$path.${_esc(keys.last)}';
  if (defined != null && !defined.add(fullPath)) {
    throw FormatException('Duplicate key: $fullPath');
  }
  final existing = current[keys.last];
  if (existing != null) {
    // Can extend an existing table (from intermediate dotted keys), but
    // can't overwrite anything with a scalar or overwrite a scalar.
    if (existing is! TomlTable || value is! TomlTable) {
      throw FormatException('Duplicate key: $fullPath');
    }
  }
  current[keys.last] = value;
}

/// Escape a key for use in canonical paths (handles dots in quoted keys).
String _esc(String key) => key.contains('.') ? '"$key"' : key;

/// Recursively add all paths in [table] to [frozen].
void _freezePaths(Set<String> frozen, String prefix, TomlTable table) {
  for (final entry in table.pairs.entries) {
    final childPath = '$prefix.${_esc(entry.key)}';
    frozen.add(childPath);
    if (entry.value is TomlTable) {
      _freezePaths(frozen, childPath, entry.value as TomlTable);
    }
  }
}

Map<String, TomlValue> _ensureTable(
  Map<String, TomlValue> root,
  List<String> path,
) {
  var current = root;
  for (final key in path) {
    current = _navigateInto(current, key);
  }
  return current;
}

void _appendArrayTable(
  Map<String, TomlValue> root,
  List<String> path,
  Map<String, TomlValue> table,
) {
  var current = root;
  for (var i = 0; i < path.length - 1; i++) {
    current = _navigateInto(current, path[i]);
  }

  final key = path.last;
  final existing = current[key];
  if (existing is TomlArray) {
    current[key] = TomlArray([...existing.elements, TomlTable(table)]);
  } else {
    current[key] = TomlArray([TomlTable(table)]);
  }
}

/// Navigate into a table or the last element of an array-of-tables.
Map<String, TomlValue> _navigateInto(
  Map<String, TomlValue> current,
  String key,
) {
  final existing = current[key];
  if (existing is TomlTable) {
    return existing.pairs;
  } else if (existing is TomlArray && existing.elements.isNotEmpty) {
    final last = existing.elements.last;
    if (last is TomlTable) {
      return last.pairs;
    }
  } else if (existing != null) {
    // Scalar/array value — can't navigate into it.
    throw FormatException('Cannot use key "$key" as a table — already defined');
  }
  final sub = <String, TomlValue>{};
  current[key] = TomlTable(sub);
  return sub;
}
