/// HOCON (Human-Optimized Config Object Notation) parser.
///
/// Implements the lightbend/config HOCON syntax: `#` and `//` comments,
/// optional root braces, dotted keys, `=` / `:` / `+=` separators,
/// substitutions (`${path}`, `${?path}`), value concatenations (with
/// the spec's whitespace-preservation rules), triple-quoted strings,
/// and `include` statements. Number formats follow JSON; leading-zero
/// numbers and bare `+` signs are rejected, matching the spec's
/// "unchanged from JSON" rule.
///
/// The parser produces the *source-shaped* AST from `ast/hocon.dart`:
/// substitutions, concatenations, and includes stay unresolved. Use
/// `resolveHocon` (in `hocon_resolve.dart`) to produce the final
/// configuration tree, then `hoconToNative` for native Dart values.
///
/// Like every format parser in this package, the parse runs on rumil's
/// trampolined interpreter, so deeply-nested documents parse without
/// call-stack growth.
library;

import 'package:rumil/rumil.dart';

import 'ast/hocon.dart';
import 'common.dart' as common;

/// Parse a HOCON document from [input].
///
/// Returns the document root: a [HoconObject] (possibly empty for an
/// empty or comment-only file) or a [HoconArray] for a bracketed root
/// array.
Result<ParseError, HoconValue> parseHocon(String input) => _document.run(input);

// ---- Internal token wrapper ----

/// One lexical value token: its AST node plus the string form used when
/// the token participates in a string value concatenation.
///
/// `text` is null for objects, arrays, and substitutions (which do not
/// participate as strings; whitespace around them is preserved as its
/// own whitespace-only string part instead).
class _Tok {
  final HoconValue node;
  final String? text;
  const _Tok(this.node, this.text);
}

// ---- Whitespace and comments ----

/// Horizontal whitespace (space or tab).
final Parser<ParseError, String> _hspace = satisfy(
  (c) => c == ' ' || c == '\t',
  'whitespace',
);

final Parser<ParseError, List<String>> _hspaces = _hspace.many;

/// HOCON newline: `\n`, `\r\n`, or `\r`.
final Parser<ParseError, void> _newline = stringIn([
  '\r\n',
  '\n',
  '\r',
]).as<void>(null);

/// A comment: `# ...` or `// ...` running to end of line.
final Parser<ParseError, void> _comment = (char('#') | string('//'))
    .skipThen(satisfy((c) => c != '\n' && c != '\r', 'comment character').many)
    .as<void>(null);

/// Inter-token junk: any amount of whitespace, newlines, and comments.
final Parser<ParseError, void> _junk =
    (_hspace.as<void>(null) | _newline | _comment).many.as<void>(null);

// ---- Character classes ----

/// Forbidden in unquoted strings and keys (HOCON spec).
bool _isForbidden(String c) => switch (c) {
  r'$' ||
  '"' ||
  '{' ||
  '}' ||
  '[' ||
  ']' ||
  ':' ||
  '=' ||
  ',' ||
  '+' ||
  '#' ||
  '`' ||
  '^' ||
  '?' ||
  '!' ||
  '@' ||
  '*' ||
  '&' ||
  '\\' => true,
  _ => false,
};

bool _isWsChar(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';

/// One character of an unquoted string: never a forbidden character,
/// never whitespace, and never the start of a `//` comment.
final Parser<ParseError, String> _unquotedChar =
    satisfy(
      (c) => !_isForbidden(c) && !_isWsChar(c) && c != '/',
      'unquoted string character',
    ) |
    char('/').skipThen(char('/').notFollowedBy).as<String>('/');

/// One character of an unquoted key: like an unquoted string character
/// but `.` is reserved as the path separator.
final Parser<ParseError, String> _keyChar = satisfy(
  (c) => !_isForbidden(c) && !_isWsChar(c) && c != '/' && c != '.',
  'key character',
);

// ---- Strings ----

final Parser<ParseError, String> _escape = char('\\').skipThen(
  char('"').as('"') |
      char('\\').as('\\') |
      char('/').as('/') |
      char('b').as('\b') |
      char('f').as('\f') |
      char('n').as('\n') |
      char('r').as('\r') |
      char('t').as('\t') |
      (char('u')
          .skipThen(common.hexDigit().times(4))
          .map(
            (hex) => String.fromCharCode(int.parse(hex.join(), radix: 16)),
          )) |
      satisfy((_) => true, 'valid escape').flatMap(
        (c) => failure<ParseError, String>(
          CustomError('Unknown escape sequence: \\$c', Location.zero),
        ),
      ),
);

/// A JSON-format quoted string (no newlines, no raw control chars).
final Parser<ParseError, String> _quotedString = char('"')
    .skipThen(
      (_escape |
              satisfy(
                (c) =>
                    c != '"' &&
                    c != '\\' &&
                    c != '\n' &&
                    c != '\r' &&
                    c.codeUnitAt(0) >= 0x20,
                'string character',
              ))
          .many,
    )
    .map((cs) => cs.join())
    .thenSkip(char('"'));

/// Content unit of a triple-quoted string: a non-quote character, a
/// lone quote, or a two-quote run that is not the start of a closing
/// `"""` sequence.
final Parser<ParseError, String> _tripleUnit =
    satisfy((c) => c != '"', 'triple-quoted string character') |
    char('"').skipThen(char('"').notFollowedBy).as<String>('"') |
    string('""').skipThen(char('"').notFollowedBy).as<String>('""');

/// Closing run of at least three quotes; any extra quotes beyond the
/// three that close the string belong to the content (Scala rule).
final Parser<ParseError, String> _tripleClose = char('"').many1.flatMap(
  (run) =>
      run.length < 3
          ? failure<ParseError, String>(
            CustomError('Unterminated multi-line string', Location.zero),
          )
          : succeed<ParseError, String>('"' * (run.length - 3)),
);

/// A `"""..."""` multi-line string: no escape processing, newlines and
/// whitespace taken literally.
final Parser<ParseError, String> _tripleString = string('"""')
    .skipThen(_tripleUnit.many.map((cs) => cs.join()))
    .flatMap<String>((body) => _tripleClose.map((extra) => '$body$extra'));

// ---- Numbers ----

final Parser<ParseError, void> _minus = char('-').as<void>(null);

/// JSON integer part: `0` or a non-zero digit followed by digits.
final Parser<ParseError, void> _jsonInt = (char('0').as<void>(null) |
        _nonZeroDigit().skipThen(digit().many.as<void>(null)))
    .as<void>(null);

final Parser<ParseError, void> _jsonFrac = char(
  '.',
).skipThen(digit().many1).as<void>(null);

final Parser<ParseError, void> _jsonExp = oneOf('eE')
    .skipThen((char('+') | char('-')).optional)
    .skipThen(digit().many1)
    .as<void>(null);

Parser<ParseError, String> _nonZeroDigit() => satisfy(
  (c) => c.compareTo('1') >= 0 && c.compareTo('9') <= 0,
  'non-zero digit',
);

/// A JSON-format number. The raw source slice is kept for string value
/// concatenation (the spec requires numbers to be re-rendered exactly
/// as written, e.g. `1E5`, not `100000.0`).
final Parser<ParseError, _Tok> _numberToken = (_minus.optional
    .skipThen(_jsonInt)
    .skipThen(_jsonFrac.optional)
    .skipThen(_jsonExp.optional)).capture.flatMap((raw) {
  final intValue = int.tryParse(raw);
  if (intValue != null) {
    return succeed<ParseError, _Tok>(_Tok(HoconInt(intValue), raw));
  }
  final doubleValue = double.tryParse(raw);
  if (doubleValue != null) {
    return succeed<ParseError, _Tok>(_Tok(HoconDouble(doubleValue), raw));
  }
  return failure<ParseError, _Tok>(
    CustomError('Invalid number: $raw', Location.zero),
  );
});

final Parser<ParseError, _Tok> _trueToken = string(
  'true',
).map((_) => const _Tok(HoconBool(true), 'true'));
final Parser<ParseError, _Tok> _falseToken = string(
  'false',
).map((_) => const _Tok(HoconBool(false), 'false'));
final Parser<ParseError, _Tok> _nullToken = string(
  'null',
).map((_) => const _Tok(HoconNull(), 'null'));

/// Unquoted string. May not *begin* with a digit or `-` (those start
/// JSON numbers, which are matched by [_numberToken] first).
final Parser<ParseError, _Tok> _unquotedToken = (digit() | char('-'))
    .notFollowedBy
    .skipThen(_unquotedChar.many1)
    .map((cs) {
      final s = cs.join();
      return _Tok(HoconString(s), s);
    });

// ---- Substitutions ----

/// A dotted path inside `${...}`: quoted or unquoted segments joined
/// with `.`, no whitespace, no substitutions.
final Parser<ParseError, String> _subPath = _pathSegment
    .sepBy1(char('.'))
    .map((segs) => segs.join('.'));

final Parser<ParseError, String> _pathSegment =
    _quotedString | _keyChar.many1.map((cs) => cs.join());

final Parser<ParseError, _Tok> _substitutionToken = (string(
          r'${?',
        ).map((_) => true) |
        string(r'${').map((_) => false))
    .zip(_subPath)
    .thenSkip(char('}'))
    .map((pair) => _Tok(HoconSubstitution(pair.$2, optional: pair.$1), null));

// ---- Keys ----

/// A dotted key path: `a`, `a.b.c`, `a."b.c"`. Split into segments.
final Parser<ParseError, List<String>> _keyPath =
    (_quotedString | _keyChar.many1.map((cs) => cs.join())).sepBy1(char('.'));

// ---- Values ----

/// A braced object token: `{ fields }`. Newlines and comments are junk
/// inside the braces; fields may be separated by commas, newlines, or
/// both, and a single trailing comma is ignored.
final Parser<ParseError, _Tok> _objectToken = char('{')
    .skipThen(_junk)
    // defer breaks the static-initialization cycle _valueToken →
    // _objectToken → _fields → _field → _value → _valueToken.
    .skipThen(defer(() => _fields))
    .thenSkip(_junk)
    .thenSkip(char('}'))
    .map((entries) => _Tok(HoconObject(entries), null));

/// A bracketed array token: `[ elements ]`. Elements are separated by
/// commas and/or newlines; non-newline whitespace between two simple
/// values concatenates them instead of separating elements.
final Parser<ParseError, _Tok> _arrayToken = char('[')
    .skipThen(_junk)
    // defer breaks the static-initialization cycle through _value.
    .skipThen(defer(() => _elements))
    .thenSkip(_junk)
    .thenSkip(char(']'))
    .map((elements) => _Tok(HoconArray(elements), null));

/// One value token.
final Parser<ParseError, _Tok> _valueToken =
    _substitutionToken |
    _tripleString.map(_tokString) |
    _quotedString.map(_tokString) |
    _objectToken |
    _arrayToken |
    _numberToken |
    _trueToken |
    _falseToken |
    _nullToken |
    _unquotedToken;

_Tok _tokString(String s) => _Tok(HoconString(s), s);

/// A continuation of a value: the exact whitespace between the previous
/// token and this one (possibly empty — adjacent tokens concatenate,
/// per the spec's tokenizer), plus the next token. A comment or newline
/// here ends the value.
final Parser<ParseError, (String, _Tok)> _valueTailUnit = _hspaces
    .map((ws) => ws.join())
    .flatMap(
      (gap) =>
          _comment.notFollowedBy.skipThen(_valueToken).map((tok) => (gap, tok)),
    );

/// A value: one or more same-line tokens folded into a single
/// [HoconValue] (single token) or a [HoconConcat].
final Parser<ParseError, HoconValue> _value = _valueToken.flatMap(
  (first) => _valueTailUnit.many.map((tail) => _foldValue(first, tail)),
);

/// Fold a token sequence into a value. String-participating tokens are
/// merged left-to-right with their separating whitespace; objects,
/// arrays, and substitutions become standalone parts with whitespace
/// preserved as whitespace-only string parts between them.
HoconValue _foldValue(_Tok first, List<(String, _Tok)> tail) {
  if (tail.isEmpty) return first.node;
  final parts = <HoconValue>[];
  void pushString(String text) {
    if (parts.isNotEmpty && parts.last is HoconString) {
      final last = parts.removeLast() as HoconString;
      parts.add(HoconString(last.value + text));
    } else {
      parts.add(HoconString(text));
    }
  }

  for (final (gap, tok) in [('', first), ...tail]) {
    final text = tok.text;
    if (text != null) {
      pushString(gap + text);
    } else {
      if (gap.isNotEmpty) parts.add(HoconString(gap));
      parts.add(tok.node);
    }
  }
  if (parts.length == 1) return parts.single;
  return HoconConcat(parts);
}

// ---- Fields ----

/// An `include` statement in field position.
final Parser<ParseError, HoconEntry> _includeStatement = string(
  'include',
).skipThen(_junk).skipThen(_includeBody).map(HoconIncludeEntry.new);

final Parser<ParseError, HoconInclude> _includeBody =
    _includeResource.map((r) => HoconInclude(r, required: false)) |
    string('required')
        .skipThen(_junk)
        .skipThen(char('('))
        .skipThen(_junk)
        .skipThen(_includeResource)
        .thenSkip(_junk)
        .thenSkip(char(')'))
        .map((r) => HoconInclude(r, required: true));

final Parser<ParseError, String> _includeResource =
    _quotedString |
    _includeFn('file') |
    _includeFn('url') |
    _includeFn('classpath');

Parser<ParseError, String> _includeFn(String name) => string(name)
    .skipThen(_junk)
    .skipThen(char('('))
    .skipThen(_junk)
    .skipThen(_quotedString)
    .thenSkip(_junk)
    .thenSkip(char(')'));

/// A `key = value`, `key : value`, `key += v`, or `key { ... }` field
/// (the separator is omissible only before `{`).
final Parser<ParseError, HoconEntry> _assignment = _keyPath.flatMap(_afterKey);

Parser<ParseError, HoconEntry> _afterKey(List<String> path) {
  // `a += b` desugars to `a = ${?a} [b]`.
  final append = _hspaces
      .as<void>(null)
      .skipThen(string(r'+='))
      .skipThen(_junk)
      .skipThen(_value)
      .map(
        (v) => HoconAssignment(
          path,
          HoconConcat([
            HoconSubstitution(path.join('.'), optional: true),
            HoconArray([v]),
          ]),
        ),
      );
  final separator = _hspaces
      .as<void>(null)
      .skipThen(char('=') | char(':'))
      .skipThen(_junk)
      .skipThen(_value)
      .map((v) => HoconAssignment(path, v));
  final omitted = _junk
      .skipThen(_objectFirstValue)
      .map((v) => HoconAssignment(path, v));
  return append | separator | omitted;
}

/// Value whose first token is required to be an object — the omitted-
/// separator form (`key { ... }`).
final Parser<ParseError, HoconValue> _objectFirstValue = _objectToken.flatMap(
  (first) => _valueTailUnit.many.map((tail) => _foldValue(first, tail)),
);

final Parser<ParseError, HoconEntry> _field = _includeStatement | _assignment;

/// Separation between fields/elements: junk, an optional comma, junk.
/// One trailing comma is tolerated; two are not.
final Parser<ParseError, void> _fieldSep = _junk
    .skipThen(char(',').as<void>(null).optional)
    .skipThen(_junk);

final Parser<ParseError, List<HoconEntry>> _fields = _field
    .zip(_fieldSep)
    .many
    .zip(_field.optional)
    .map(
      (pair) => [...pair.$1.map((e) => e.$1), if (pair.$2 != null) pair.$2!],
    );

final Parser<ParseError, List<HoconValue>> _elements = defer(() => _value)
    .zip(_fieldSep)
    .many
    .zip(_value.optional)
    .map(
      (pair) => [...pair.$1.map((e) => e.$1), if (pair.$2 != null) pair.$2!],
    );

// ---- Document ----

/// Root: junk, then a braced object, a bracketed array, or an unbraced
/// object body (which also covers the empty document as an empty root
/// object), then junk, then end of input.
final Parser<ParseError, HoconValue> _document = _junk
    .skipThen(
      _bracedRoot |
          _bracketedRoot |
          _fields.map((entries) => HoconObject(entries) as HoconValue),
    )
    .thenSkip(_junk)
    .thenSkip(eof());

final Parser<ParseError, HoconValue> _bracedRoot = char('{')
    .skipThen(_junk)
    .skipThen(_fields)
    .thenSkip(_junk)
    .thenSkip(char('}'))
    .map((entries) => HoconObject(entries) as HoconValue);

final Parser<ParseError, HoconValue> _bracketedRoot = char('[')
    .skipThen(_junk)
    .skipThen(_elements)
    .thenSkip(_junk)
    .thenSkip(char(']'))
    .map((elements) => HoconArray(elements) as HoconValue);
