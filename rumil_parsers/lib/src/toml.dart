/// TOML v1.0.0 parser.
library;

import 'package:rumil/rumil.dart';

import 'ast/toml.dart';
import 'common.dart' as common;

/// Parse a TOML document from [input].
Result<ParseError, TomlDocument> parseToml(String input) =>
    _tomlDocument.run(input);

// ---- Whitespace & comments ----

final Parser<ParseError, void> _ws = satisfy(
  (c) => c == ' ' || c == '\t',
  'whitespace',
).many.as<void>(null);

final Parser<ParseError, void> _comment = char(
  '#',
).skipThen(satisfy((c) => c != '\n', 'comment char').many).as<void>(null);

final Parser<ParseError, void> _eol = _ws
    .skipThen(_comment.optional)
    .skipThen(common.newline().as<void>(null) | eof());

final Parser<ParseError, void> _skipBlankAndComments =
    (common.newline().as<void>(null) | _ws.skipThen(_comment)).many.as<void>(
      null,
    );

// ---- Strings ----

final Parser<ParseError, String> _unicodeEscape4 = char('u')
    .skipThen(common.hexDigit().times(4))
    .map((ds) => String.fromCharCode(int.parse(ds.join(), radix: 16)));

final Parser<ParseError, String> _unicodeEscape8 = char('U')
    .skipThen(common.hexDigit().times(8))
    .map((ds) => String.fromCharCode(int.parse(ds.join(), radix: 16)));

final Parser<ParseError, String> _basicEscape = char('\\').skipThen(
  char('"').as('"') |
      char('\\').as('\\') |
      char('b').as('\b') |
      char('f').as('\f') |
      char('n').as('\n') |
      char('r').as('\r') |
      char('t').as('\t') |
      _unicodeEscape4 |
      _unicodeEscape8,
);

final Parser<ParseError, String> _basicString = char('"')
    .skipThen(
      (_basicEscape |
              satisfy((c) => c != '"' && c != '\\' && c != '\n', 'string char'))
          .many,
    )
    .map((cs) => cs.join())
    .thenSkip(char('"'));

final Parser<ParseError, String> _literalString = char("'")
    .skipThen(satisfy((c) => c != "'" && c != '\n', 'literal string char').many)
    .map((cs) => cs.join())
    .thenSkip(char("'"));

final Parser<ParseError, String> _multiLineBasicString = () {
  final escape = char('\\').skipThen(
    char('"').as('"') |
        char('\\').as('\\') |
        char('b').as('\b') |
        char('f').as('\f') |
        char('n').as('\n') |
        char('r').as('\r') |
        char('t').as('\t') |
        common.newline().as('') |
        _unicodeEscape4 |
        _unicodeEscape8,
  );

  final contentChar =
      escape | (string('"""').notFollowedBy.skipThen(anyChar()));

  return string('"""')
      .skipThen(common.newline().optional)
      .skipThen(contentChar.many)
      .map((cs) => cs.join())
      .thenSkip(string('"""'));
}();

final Parser<ParseError, String> _multiLineLiteralString = () {
  final contentChar = string("'''").notFollowedBy.skipThen(anyChar());

  return string("'''")
      .skipThen(common.newline().optional)
      .skipThen(contentChar.many)
      .map((cs) => cs.join())
      .thenSkip(string("'''"));
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
      .map((ds) => int.parse(stripUnderscores(ds), radix: 16));

  final oct = string('0o')
      .skipThen(octDigitU.many1)
      .map((ds) => int.parse(stripUnderscores(ds), radix: 8));

  final bin = string('0b')
      .skipThen(binDigitU.many1)
      .map((ds) => int.parse(stripUnderscores(ds), radix: 2));

  final decimal = (char('-') | char('+')).optional.flatMap(
    (sign) => digitU.many1.map((ds) {
      final value = int.parse(stripUnderscores(ds));
      return sign == '-' ? -value : value;
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

  final withFraction = (char('-') | char('+')).optional.flatMap(
    (sign) => digitU.many1.flatMap(
      (whole) => char('.')
          .skipThen(digitU.many1)
          .flatMap(
            (frac) => exponent.optional.map((exp) {
              final s = sign == '-' ? '-' : '';
              final expStr =
                  exp != null ? 'e${exp.$1 ?? ''}${strip(exp.$2)}' : '';
              return double.parse('$s${strip(whole)}.${strip(frac)}$expStr');
            }),
          ),
    ),
  );

  final onlyExponent = (char('-') | char('+')).optional.flatMap(
    (sign) => digitU.many1.flatMap(
      (whole) => exponent.map((exp) {
        final s = sign == '-' ? '-' : '';
        return double.parse(
          '$s${strip(whole)}e${exp.$1 ?? ''}${strip(exp.$2)}',
        );
      }),
    ),
  );

  return (special | withFraction | onlyExponent).map<TomlValue>(TomlFloat.new);
}();

// ---- Datetimes ----

typedef _DateParts = (int year, int month, int day);
typedef _TimeParts = (int hour, int minute, int second, int nanosecond);

final Parser<ParseError, _DateParts> _datePrefix = digit()
    .times(4)
    .flatMap(
      (y) => char('-')
          .skipThen(digit().times(2))
          .flatMap(
            (m) => char('-')
                .skipThen(digit().times(2))
                .map(
                  (d) => (
                    int.parse(y.join()),
                    int.parse(m.join()),
                    int.parse(d.join()),
                  ),
                ),
          ),
    );

final Parser<ParseError, _TimeParts> _timePart = digit()
    .times(2)
    .flatMap(
      (h) => char(':')
          .skipThen(digit().times(2))
          .flatMap(
            (m) => char(':')
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
                ),
          ),
    );

final Parser<ParseError, Duration> _offset =
    char('Z').as(Duration.zero) |
    (oneOf('+-')
        .zip(digit().times(2).zip(char(':').skipThen(digit().times(2))))
        .map((pair) {
          final sign = pair.$1 == '-' ? -1 : 1;
          final hours = int.parse(pair.$2.$1.join());
          final minutes = int.parse(pair.$2.$2.join());
          return Duration(hours: sign * hours, minutes: sign * minutes);
        }));

final Parser<ParseError, TomlValue> _tomlDateTimeValue = _datePrefix.flatMap(
  (date) => oneOf('Tt').skipThen(_timePart).optional.flatMap((time) {
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
          (_arraySep.skipThen(char(',')).skipThen(_arraySep)).optional.skipThen(
            _arraySep
                .skipThen(char(']'))
                .map((_) => TomlArray(elements) as TomlValue),
          ),
    );

final Parser<ParseError, TomlValue> _inlineTable = () {
  final pair = _simpleKey.flatMap(
    (key) => _ws
        .skipThen(char('='))
        .skipThen(_ws)
        .skipThen(defer(() => _tomlValue))
        .map((value) => (key, value)),
  );

  return char('{')
      .skipThen(_ws)
      .skipThen(pair.sepBy(_ws.skipThen(char(',')).skipThen(_ws)))
      .flatMap(
        (pairs) => _ws
            .skipThen(char('}'))
            .map(
              (_) =>
                  TomlTable(
                        Map.fromEntries(pairs.map((p) => MapEntry(p.$1, p.$2))),
                      )
                      as TomlValue,
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

final Parser<ParseError, _KVPair> _keyValue = _dottedKey.flatMap(
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
            .skipThen(eof())
            .map((_) => _buildDocument(rootPairs, sections)),
      ),
    );

// ---- Document assembly ----

TomlDocument _buildDocument(List<_KVPair> rootPairs, List<_Section> sections) {
  final doc = <String, TomlValue>{};

  for (final (keys, value) in rootPairs) {
    _setNested(doc, keys, value);
  }

  for (final (isArray, path, pairs) in sections) {
    if (isArray) {
      final table = <String, TomlValue>{};
      for (final (keys, value) in pairs) {
        _setNested(table, keys, value);
      }
      _appendArrayTable(doc, path, table);
    } else {
      final target = _ensureTable(doc, path);
      for (final (keys, value) in pairs) {
        _setNested(target, keys, value);
      }
    }
  }

  return doc;
}

void _setNested(
  Map<String, TomlValue> target,
  List<String> keys,
  TomlValue value,
) {
  var current = target;
  for (var i = 0; i < keys.length - 1; i++) {
    final existing = current[keys[i]];
    if (existing is TomlTable) {
      current = existing.pairs;
    } else {
      final sub = <String, TomlValue>{};
      current[keys[i]] = TomlTable(sub);
      current = sub;
    }
  }
  current[keys.last] = value;
}

Map<String, TomlValue> _ensureTable(
  Map<String, TomlValue> root,
  List<String> path,
) {
  var current = root;
  for (final key in path) {
    final existing = current[key];
    if (existing is TomlTable) {
      current = existing.pairs;
    } else if (existing is TomlArray && existing.elements.isNotEmpty) {
      final last = existing.elements.last;
      if (last is TomlTable) {
        current = last.pairs;
      } else {
        final sub = <String, TomlValue>{};
        current[key] = TomlTable(sub);
        current = sub;
      }
    } else {
      final sub = <String, TomlValue>{};
      current[key] = TomlTable(sub);
      current = sub;
    }
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
    final existing = current[path[i]];
    if (existing is TomlTable) {
      current = existing.pairs;
    } else if (existing is TomlArray && existing.elements.isNotEmpty) {
      final last = existing.elements.last;
      if (last is TomlTable) {
        current = last.pairs;
      }
    } else {
      final sub = <String, TomlValue>{};
      current[path[i]] = TomlTable(sub);
      current = sub;
    }
  }

  final key = path.last;
  final existing = current[key];
  if (existing is TomlArray) {
    current[key] = TomlArray([...existing.elements, TomlTable(table)]);
  } else {
    current[key] = TomlArray([TomlTable(table)]);
  }
}
