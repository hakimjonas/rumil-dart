/// Shared parser utilities for format parsers.
library;

import 'dart:math' as math;

import 'package:rumil/rumil.dart';

/// Hex digit (0-9, a-f, A-F).
Parser<ParseError, String> hexDigit() => satisfy(
  (c) =>
      (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
      (c.compareTo('a') >= 0 && c.compareTo('f') <= 0) ||
      (c.compareTo('A') >= 0 && c.compareTo('F') <= 0),
  'hex digit',
);

/// Unicode escape (\uXXXX) → single character string.
Parser<ParseError, String> unicodeEscape() =>
    char('\\').skipThen(char('u')).skipThen(hexDigit().times(4)).map((digits) {
      final hex = digits.join();
      return String.fromCharCode(int.parse(hex, radix: 16));
    });

/// Optional sign (+/-), returns 1 or -1.
Parser<ParseError, int> sign() =>
    (char('+').as<int>(1) | char('-').as<int>(-1)).optional.map((s) => s ?? 1);

/// Unsigned integer.
Parser<ParseError, int> unsignedInt() =>
    digit().many1.map((ds) => int.parse(ds.join()));

/// Signed integer.
Parser<ParseError, int> signedInt() => sign()
    .zip(digit().many1)
    .map((pair) => pair.$1 * int.parse(pair.$2.join()));

/// Floating point number with optional sign, decimal, and exponent.
Parser<ParseError, double> floatingPoint() => sign().flatMap(
  (s) => digit().many1.flatMap(
    (whole) => char('.')
        .skipThen(digit().many1)
        .optional
        .flatMap(
          (frac) => oneOf('eE').skipThen(signedInt()).optional.map((exp) {
            final base =
                frac != null ? '${whole.join()}.${frac.join()}' : whole.join();
            final value = double.parse(base);
            final withExp = exp != null ? value * math.pow(10, exp) : value;
            return withExp * s;
          }),
        ),
  ),
);

/// Horizontal whitespace (space/tab).
Parser<ParseError, String> hspace() =>
    satisfy((c) => c == ' ' || c == '\t', 'horizontal whitespace');

/// Zero or more horizontal whitespace.
Parser<ParseError, List<String>> hspaces() => hspace().many;

/// One or more horizontal whitespace.
Parser<ParseError, List<String>> hspaces1() => hspace().many1;

/// Newline (LF, CR, or CRLF).
Parser<ParseError, String> newline() => stringIn(['\r\n', '\n', '\r']);

/// End of line or end of file.
Parser<ParseError, void> eol() =>
    (newline().as<void>(null) | eof()).named('end of line');

/// Common escape sequences.
const Map<String, String> commonEscapes = {
  'n': '\n',
  'r': '\r',
  't': '\t',
  '\\': '\\',
  '"': '"',
  "'": "'",
  'b': '\b',
  'f': '\f',
};

/// String between [quote] characters with [escapes].
Parser<ParseError, String> quotedString(
  String quote,
  Map<String, String> escapes,
) {
  final escapeChar = char('\\')
      .skipThen(satisfy((c) => escapes.containsKey(c), 'escape char'))
      .map((c) => escapes[c]!);
  final normalChar = satisfy((c) => c != quote && c != '\\', 'string char');

  return char(quote)
      .skipThen((escapeChar | normalChar).many)
      .zip(char(quote).as<void>(null))
      .map(((List<String>, void) pair) => pair.$1.join());
}

/// Double-quoted string with common escapes.
Parser<ParseError, String> doubleQuotedString() =>
    quotedString('"', {...commonEscapes, '"': '"'});

/// Single-quoted string with common escapes.
Parser<ParseError, String> singleQuotedString() =>
    quotedString("'", {...commonEscapes, "'": "'"});

/// Identifier: letter/underscore start, then alphanumeric/underscore.
Parser<ParseError, String> identifier() => (letter() | char('_'))
    .zip((alphaNum() | char('_')).many)
    .map((pair) => pair.$1 + pair.$2.join());

/// Skip a line comment starting with [prefix].
Parser<ParseError, void> lineComment(String prefix) => string(prefix)
    .skipThen(satisfy((c) => c != '\n', 'any char').many)
    .skipThen(eol())
    .as<void>(null);

/// Skip a block comment between [open] and [close].
Parser<ParseError, void> blockComment(String open, String close) => string(open)
    .skipThen(noneOf(close.substring(0, 1)).many)
    .skipThen(string(close))
    .as<void>(null);
