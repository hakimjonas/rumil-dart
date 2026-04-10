/// HCL (HashiCorp Configuration Language) parser.
library;

import 'package:rumil/rumil.dart';

import 'ast/hcl.dart';
import 'common.dart' as common;

/// Parse an HCL document from [input].
Result<ParseError, HclDocument> parseHcl(String input) =>
    _hclDocument.run(input);

// ---- Whitespace & comments ----

final Parser<ParseError, void> _ws1 = satisfy(
  (c) => c == ' ' || c == '\t' || c == '\r' || c == '\n',
  'whitespace',
).as<void>(null);

final Parser<ParseError, void> _lineComment = (string('#') | string('//'))
    .skipThen(satisfy((c) => c != '\n', 'comment char').many)
    .skipThen(common.newline().as<void>(null) | eof())
    .as<void>(null);

final Parser<ParseError, void> _blockComment = string('/*')
    .skipThen((string('*/').notFollowedBy.skipThen(anyChar())).many)
    .skipThen(string('*/'))
    .as<void>(null);

final Parser<ParseError, void> _skip = (_ws1 | _lineComment | _blockComment)
    .many
    .as<void>(null);

// ---- Identifiers ----

final Parser<ParseError, String> _ident = (letter() | char('_'))
    .zip((alphaNum() | char('_') | char('-')).many)
    .map((p) => p.$1 + p.$2.join());

Parser<ParseError, A> _lex<A>(Parser<ParseError, A> p) => p.thenSkip(_skip);

Parser<ParseError, String> _sym(String s) => _lex(string(s));

// ---- Strings ----

final Parser<ParseError, String> _hclString = _lex(
  char('"')
      .skipThen(
        (char('\\').skipThen(anyChar()) |
                satisfy((c) => c != '"' && c != '\n', 'string char'))
            .many,
      )
      .map((cs) => cs.join())
      .thenSkip(char('"')),
);

// ---- Values ----

final Parser<ParseError, HclValue> _hclNull = _lex(
  string('null'),
).as<HclValue>(const HclNull());

final Parser<ParseError, HclValue> _hclBool = _lex(
  keywords<HclValue>({
    'true': const HclBool(true),
    'false': const HclBool(false),
  }),
);

final Parser<ParseError, HclValue> _hclNumber = _lex(
  char('-').optional.flatMap(
    (neg) => digit().many1.flatMap(
      (whole) => char('.').skipThen(digit().many1).optional.map((frac) {
        final str =
            frac != null ? '${whole.join()}.${frac.join()}' : whole.join();
        final n = num.parse(str);
        return HclNumber(neg != null ? -n : n) as HclValue;
      }),
    ),
  ),
);

final Parser<ParseError, HclValue> _hclStringValue = _hclString.map<HclValue>(
  HclString.new,
);

final Parser<ParseError, HclValue> _hclReference = _lex(
  _ident.sepBy1(char('.')),
).map<HclValue>(
  (parts) =>
      parts.length == 1
          ? HclString(parts.first)
          : HclReference(parts.join('.')),
);

final Parser<ParseError, HclValue> _hclList = _sym('[')
    .skipThen(defer(() => _hclExpression).sepBy(_sym(',')))
    .flatMap(
      (elements) => _sym(
        ',',
      ).optional.skipThen(_sym(']')).map((_) => HclList(elements) as HclValue),
    );

final Parser<ParseError, HclValue> _hclObject = _sym('{')
    .skipThen(defer(() => _hclAttribute).many)
    .flatMap(
      (attrs) => _sym('}').map(
        (_) =>
            HclObject(Map.fromEntries(attrs.map((a) => MapEntry(a.$1, a.$2))))
                as HclValue,
      ),
    );

final Parser<ParseError, HclValue> _hclExpression =
    _hclNull |
    _hclBool |
    _hclNumber |
    _hclStringValue |
    _hclList |
    _hclObject |
    _hclReference;

// ---- Attributes and blocks ----

final Parser<ParseError, (String, HclValue)> _hclAttribute = _lex(
  _ident,
).flatMap(
  (key) => _sym('=').skipThen(_hclExpression).map((value) => (key, value)),
);

final Parser<ParseError, (String, HclValue)> _hclBlock = _lex(_ident).flatMap(
  (type) => _hclString.many.flatMap(
    (labels) => _sym('{')
        .skipThen(defer(() => _hclBodyEntry).many)
        .flatMap(
          (entries) => _sym('}').map(
            (_) => (
              type,
              HclBlock(
                    type,
                    labels,
                    Map.fromEntries(entries.map((e) => MapEntry(e.$1, e.$2))),
                  )
                  as HclValue,
            ),
          ),
        ),
  ),
);

final Parser<ParseError, (String, HclValue)> _hclBodyEntry =
    defer(() => _hclBlock) | _hclAttribute;

// ---- Document ----

final Parser<ParseError, HclDocument> _hclDocument = _skip
    .skipThen(_hclBodyEntry.many)
    .flatMap(
      (entries) => _skip
          .skipThen(eof())
          .map(
            (_) => entries,
          ),
    );
