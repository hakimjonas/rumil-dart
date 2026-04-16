/// HCL (HashiCorp Configuration Language) parser.
library;

import 'package:rumil/rumil.dart';

import 'ast/hcl.dart';
import 'common.dart' as common;
import 'encode/hcl_encoders.dart' show serializeHclValue;

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

// HCL identifiers support Unicode letters (matching Go's unicode.IsLetter).
final Parser<ParseError, String> _unicodeLetter = satisfy((c) {
  final r = c.runes.first;
  return (r >= 0x41 && r <= 0x5A) || // A-Z
      (r >= 0x61 && r <= 0x7A) || // a-z
      r > 0x7F; // Non-ASCII (Unicode letters, diacritics, etc.)
}, 'letter');

final Parser<ParseError, String> _ident = (_unicodeLetter | char('_'))
    .zip((_unicodeLetter | digit() | char('_') | char('-')).many)
    .map((p) => p.$1 + p.$2.join());

Parser<ParseError, A> _lex<A>(Parser<ParseError, A> p) => p.thenSkip(_skip);

Parser<ParseError, String> _sym(String s) => _lex(string(s));

// ---- Strings ----

final Parser<ParseError, String> _hclEscapeChar = char('\\').skipThen(
  char('n').as('\n') |
      char('r').as('\r') |
      char('t').as('\t') |
      char('\\').as('\\') |
      char('"').as('"') |
      (char('u')
          .skipThen(common.hexDigit().times(4))
          .map((ds) => String.fromCharCode(int.parse(ds.join(), radix: 16)))) |
      (char('U')
          .skipThen(common.hexDigit().times(8))
          .map((ds) => String.fromCharCode(int.parse(ds.join(), radix: 16)))),
);

// Template escape parts
final Parser<ParseError, HclTemplatePart> _hclEscapePart = _hclEscapeChar
    .map<HclTemplatePart>(HclTemplateLiteral.new);

final Parser<ParseError, HclTemplatePart> _templateEscapeDollar = string(
  r'$${',
).as<HclTemplatePart>(const HclTemplateLiteral(r'${'));

final Parser<ParseError, HclTemplatePart> _templateEscapePercent = string(
  '%%{',
).as<HclTemplatePart>(const HclTemplateLiteral('%{'));

// Interpolation: ${expr} or ${~ expr ~}
final Parser<ParseError, HclTemplatePart> _hclInterpolation = string(r'${')
    .skipThen(char('~').optional)
    .flatMap(
      (stripBefore) => _skip
          .skipThen(defer(() => _hclExpression))
          .flatMap(
            (expr) => _skip
                .skipThen(char('~').optional)
                .flatMap(
                  (stripAfter) => char('}').map(
                    (_) =>
                        HclTemplateInterpolation(
                              expr,
                              stripBefore: stripBefore != null,
                              stripAfter: stripAfter != null,
                            )
                            as HclTemplatePart,
                  ),
                ),
          ),
    );

// A bare $ not followed by { or $
final Parser<ParseError, HclTemplatePart> _dollarLiteral = char(r'$')
    .thenSkip(char('{').notFollowedBy)
    .map<HclTemplatePart>(HclTemplateLiteral.new);

// Template directive: %{if expr}...%{else}...%{endif}
final Parser<ParseError, HclTemplatePart> _templateIfDirective = string(
  '%{',
).skipThen(
  _skip
      .skipThen(string('if'))
      .skipThen(
        _skip
            .skipThen(defer(() => _hclExpression))
            .flatMap(
              (cond) => _skip
                  .skipThen(char('}'))
                  .skipThen(
                    defer(() => _templatePart).many.flatMap(
                      (thenParts) => (string('%{')
                          .skipThen(_skip)
                          .skipThen(string('else'))
                          .skipThen(_skip)
                          .skipThen(char('}'))
                          .skipThen(
                            defer(() => _templatePart).many,
                          )).optional.flatMap(
                        (elseParts) => string('%{')
                            .skipThen(_skip)
                            .skipThen(string('endif'))
                            .skipThen(_skip)
                            .skipThen(char('}'))
                            .map(
                              (_) =>
                                  HclTemplateIf(cond, thenParts, elseParts)
                                      as HclTemplatePart,
                            ),
                      ),
                    ),
                  ),
            ),
      ),
);

// Template directive: %{for var in coll}...%{endfor}
final Parser<ParseError, HclTemplatePart> _templateForDirective = string(
  '%{',
).skipThen(
  _skip
      .skipThen(string('for'))
      .skipThen(
        _skip
            .skipThen(_lex(_ident))
            .flatMap(
              (first) => (_sym(',').skipThen(_lex(_ident))).optional.flatMap(
                (second) => _sym('in')
                    .skipThen(defer(() => _hclExpression))
                    .flatMap(
                      (coll) => _skip
                          .skipThen(char('}'))
                          .skipThen(
                            defer(() => _templatePart).many.flatMap(
                              (body) => string('%{')
                                  .skipThen(_skip)
                                  .skipThen(string('endfor'))
                                  .skipThen(_skip)
                                  .skipThen(char('}'))
                                  .map(
                                    (_) =>
                                        HclTemplateFor(
                                              second != null ? first : null,
                                              second ?? first,
                                              coll,
                                              body,
                                            )
                                            as HclTemplatePart,
                                  ),
                            ),
                          ),
                    ),
              ),
            ),
      ),
);

// A bare % not followed by { or %
final Parser<ParseError, HclTemplatePart> _percentLiteral = char('%')
    .thenSkip(char('{').notFollowedBy)
    .map<HclTemplatePart>(HclTemplateLiteral.new);

// Normal string characters (not special)
final Parser<ParseError, HclTemplatePart> _templateLiteral = satisfy(
  (c) => c != '"' && c != '\n' && c != '\\' && c != r'$' && c != '%',
  'string char',
).many1.map<HclTemplatePart>((cs) => HclTemplateLiteral(cs.join()));

// A single template part in a quoted string
final Parser<ParseError, HclTemplatePart> _templatePart =
    _hclEscapePart |
    _templateEscapeDollar |
    _templateEscapePercent |
    _hclInterpolation |
    _templateIfDirective |
    _templateForDirective |
    _dollarLiteral |
    _percentLiteral |
    _templateLiteral;

// Template-aware string: if all parts are literal, produce HclString.
// Otherwise produce HclTemplate.
final Parser<ParseError, HclValue> _hclTemplateString = _lex(
  char('"').skipThen(_templatePart.many).thenSkip(char('"')).map<HclValue>((
    parts,
  ) {
    if (parts.every((p) => p is HclTemplateLiteral)) {
      return HclString(
        parts.map((p) => (p as HclTemplateLiteral).value).join(),
      );
    }
    return HclTemplate(parts);
  }),
);

// Plain string (for block labels and object keys, no template parsing).
final Parser<ParseError, String> _hclString = _lex(
  char('"')
      .skipThen(
        (_hclEscapeChar |
                satisfy(
                  (c) => c != '"' && c != '\n' && c != '\\',
                  'string char',
                ))
            .many,
      )
      .map((cs) => cs.join())
      .thenSkip(char('"')),
);

// ---- Heredoc strings ----

/// Parse the heredoc body line by line until the marker is found.
Parser<ParseError, HclValue> _heredocBody(String marker, bool indented) {
  final contentChar = satisfy((c) => c != '\n', 'heredoc char');
  final lineContent = contentChar.many.capture;
  final newline = char('\n');

  return _heredocLines(lineContent, newline, marker, indented);
}

Parser<ParseError, HclValue> _heredocLines(
  Parser<ParseError, String> lineContent,
  Parser<ParseError, String> newline,
  String marker,
  bool indented,
) {
  final terminator = satisfy(
    (c) => c == ' ' || c == '\t',
    'indent',
  ).many.capture.flatMap(
    (indent) => string(
      marker,
    ).flatMap((_) => (newline.as<void>(null) | eof()).map((_) => indent)),
  );

  Parser<ParseError, HclValue> go(List<String> lines) =>
      terminator.map<HclValue>((terminatorIndent) {
        if (!indented) {
          return HclString(lines.join('\n'));
        }
        return HclString(_stripHeredocIndent(lines, terminatorIndent));
      }) |
      lineContent.flatMap(
        (line) => newline.flatMap((_) => go([...lines, line])),
      );

  return go([]);
}

/// Strip indentation from heredoc lines based on the terminator indent.
String _stripHeredocIndent(List<String> lines, String terminatorIndent) {
  final stripCount = terminatorIndent.length;
  if (stripCount == 0) return lines.join('\n');

  return lines
      .map((line) {
        if (line.isEmpty) return line;
        var count = 0;
        for (var i = 0; i < line.length && count < stripCount; i++) {
          if (line[i] == ' ' || line[i] == '\t') {
            count++;
          } else {
            break;
          }
        }
        return line.substring(count);
      })
      .join('\n');
}

final Parser<ParseError, HclValue> _hclHeredoc = _lex(
  (string('<<-').as(true) | string('<<').as(false)).flatMap(
    (indented) => _ident.flatMap(
      (marker) => char('\n').flatMap((_) => _heredocBody(marker, indented)),
    ),
  ),
);

// ---- Values ----

final Parser<ParseError, void> _notIdentCont =
    (_unicodeLetter | digit() | char('_') | char('-')).notFollowedBy;

final Parser<ParseError, HclValue> _hclNull = _lex(
  string('null').thenSkip(_notIdentCont),
).as<HclValue>(const HclNull());

final Parser<ParseError, HclValue> _hclBool = _lex(
  (string('true').thenSkip(_notIdentCont).as<HclValue>(const HclBool(true))) |
      (string(
        'false',
      ).thenSkip(_notIdentCont).as<HclValue>(const HclBool(false))),
);

final Parser<ParseError, HclValue> _hclNumber = _lex(
  digit().many1.flatMap(
    (whole) => char('.')
        .skipThen(digit().many1)
        .optional
        .flatMap(
          (frac) => oneOf('eE')
              .skipThen(
                (char('+') | char('-')).optional.flatMap(
                  (sign) =>
                      digit().many1.map((ds) => '${sign ?? ''}${ds.join()}'),
                ),
              )
              .optional
              .map((exp) {
                final base =
                    frac != null
                        ? '${whole.join()}.${frac.join()}'
                        : whole.join();
                final str = exp != null ? '${base}e$exp' : base;
                return HclNumber(num.parse(str)) as HclValue;
              }),
        ),
  ),
);

final Parser<ParseError, HclValue> _hclStringValue = _hclTemplateString;

// ---- Collections ----

final Parser<ParseError, HclValue> _hclList = _sym('[')
    .skipThen(defer(() => _hclExpression).sepBy(_sym(',')))
    .flatMap(
      (elements) => _sym(
        ',',
      ).optional.skipThen(_sym(']')).map((_) => HclList(elements) as HclValue),
    );

/// Object key: identifier, string, or parenthesized expression.
final Parser<ParseError, String> _hclObjectKey =
    _lex(_ident) |
    _hclString |
    (_sym('(')
        .skipThen(defer(() => _hclExpression))
        .thenSkip(_sym(')'))
        .map(serializeHclValue));

/// Object element: `key (= | :) value`.
final Parser<ParseError, (String, HclValue)> _hclObjectElem = _hclObjectKey
    .flatMap(
      (key) => (_sym('=') | _sym(':')).skipThen(
        defer(() => _hclExpression).map((val) => (key, val)),
      ),
    );

final Parser<ParseError, HclValue> _hclObject = _sym('{')
    .skipThen(_hclObjectElem.thenSkip(_sym(',').optional).many)
    .flatMap(
      (attrs) => _sym('}').map(
        (_) =>
            HclObject(Map.fromEntries(attrs.map((a) => MapEntry(a.$1, a.$2))))
                as HclValue,
      ),
    );

// ---- For expressions ----

/// Shared for-intro: `ident [, ident] in expr :`
final Parser<
  ParseError,
  ({String? keyVar, String valueVar, HclValue collection})
>
_forIntro = _lex(_ident).flatMap(
  (first) => (_sym(',').skipThen(_lex(_ident))).optional.flatMap(
    (second) => _sym('in')
        .skipThen(defer(() => _hclExpression))
        .flatMap(
          (coll) => _sym(':').map(
            (_) =>
                second != null
                    ? (keyVar: first, valueVar: second, collection: coll)
                    : (
                      keyVar: null as String?,
                      valueVar: first,
                      collection: coll,
                    ),
          ),
        ),
  ),
);

/// For-tuple: `[for k, v in coll : body if cond]`.
final Parser<ParseError, HclValue> _hclForTuple = _sym('[')
    .skipThen(_sym('for'))
    .skipThen(_forIntro)
    .flatMap(
      (intro) => defer(() => _hclExpression).flatMap(
        (body) =>
            (_sym('if').skipThen(defer(() => _hclExpression))).optional.flatMap(
              (cond) => _sym(']').map(
                (_) =>
                    HclForTuple(
                          intro.keyVar,
                          intro.valueVar,
                          intro.collection,
                          body,
                          cond,
                        )
                        as HclValue,
              ),
            ),
      ),
    );

/// For-object: `{for k, v in coll : keyExpr => valExpr... if cond}`.
final Parser<ParseError, HclValue> _hclForObject = _sym('{')
    .skipThen(_sym('for'))
    .skipThen(_forIntro)
    .flatMap(
      (intro) => defer(() => _hclExpression).flatMap(
        (keyExpr) => _sym('=>')
            .skipThen(defer(() => _hclExpression))
            .flatMap(
              (valExpr) => _sym('...').optional.flatMap(
                (grouping) => (_sym(
                  'if',
                ).skipThen(defer(() => _hclExpression))).optional.flatMap(
                  (cond) => _sym('}').map(
                    (_) =>
                        HclForObject(
                              intro.keyVar,
                              intro.valueVar,
                              intro.collection,
                              keyExpr,
                              valExpr,
                              grouping != null,
                              cond,
                            )
                            as HclValue,
                  ),
                ),
              ),
            ),
      ),
    );

// ---- Expression tower ----

/// Variable reference: a bare identifier.
final Parser<ParseError, HclValue> _hclVariable = _lex(
  _ident,
).map<HclValue>(HclReference.new);

/// Parenthesized expression.
final Parser<ParseError, HclValue> _hclParenExpr = _sym('(')
    .skipThen(defer(() => _hclExpression))
    .thenSkip(_sym(')'))
    .map<HclValue>(HclParenExpr.new);

/// Function call: `name(arg, arg, ...arg...?)`.
final Parser<ParseError, HclValue> _hclFunctionCall = _lex(_ident).flatMap(
  (name) => _sym('(')
      .skipThen(defer(() => _hclExpression).sepBy(_sym(',')))
      .flatMap(
        (args) => _sym('...').optional.flatMap(
          (expand) => _sym(',').optional
              .skipThen(_sym(')'))
              .map(
                (_) => HclFunctionCall(name, args, expand != null) as HclValue,
              ),
        ),
      ),
);

/// Primary expressions (atoms).
/// For-expressions must be tried before list/object since they share opening
/// brackets. Rumil backtracks on failure, so ordered choice is sufficient.
final Parser<ParseError, HclValue> _hclPrimary =
    _hclNull |
    _hclBool |
    _hclNumber |
    _hclStringValue |
    _hclHeredoc |
    _hclParenExpr |
    defer(() => _hclFunctionCall) |
    _hclForTuple |
    _hclList |
    _hclForObject |
    _hclObject |
    _hclVariable;

/// A single postfix operation for splat accessor chains.
final Parser<ParseError, HclPostfixOp> _splatAccessor =
    (char(
      '.',
    ).skipThen(_lex(_ident)).map<HclPostfixOp>(HclPostfixGetAttr.new)) |
    (_sym('[')
        .skipThen(defer(() => _hclExpression))
        .thenSkip(_sym(']'))
        .map<HclPostfixOp>(HclPostfixIndex.new));

/// A single postfix operation on an expression.
final Parser<ParseError, HclValue Function(HclValue)> _postfixOp =
    (string('[*]')
        .thenSkip(_skip)
        .skipThen(_splatAccessor.many)
        .map((ops) => (HclValue base) => HclFullSplat(base, ops) as HclValue)) |
    (_sym('[')
        .skipThen(defer(() => _hclExpression))
        .thenSkip(_sym(']'))
        .map((idx) => (HclValue base) => HclIndex(base, idx) as HclValue)) |
    (string('.*')
        .thenSkip(_skip)
        .skipThen(char('.').skipThen(_lex(_ident)).many)
        .map(
          (attrs) => (HclValue base) => HclAttrSplat(base, attrs) as HclValue,
        )) |
    (char('.')
        .skipThen(_lex(digit().many1.map((ds) => ds.join())))
        .map(
          (n) =>
              (HclValue base) =>
                  HclIndex(base, HclNumber(int.parse(n))) as HclValue,
        )) |
    (char('.')
        .skipThen(_lex(_ident))
        .map((name) => (HclValue base) => HclGetAttr(base, name) as HclValue));

/// Expression term: primary followed by zero or more postfix operations.
final Parser<ParseError, HclValue> _exprTerm = _hclPrimary.flatMap(
  (base) => _postfixOp.many.map(
    (ops) => ops.fold<HclValue>(base, (acc, op) => op(acc)),
  ),
);

/// Unary operators: `-expr` and `!expr`.
final Parser<ParseError, HclValue> _unary =
    (_sym('-').as('-') | _sym('!').as('!')).flatMap(
      (op) => defer(
        () => _unary,
      ).map((operand) => HclUnaryOp(op, operand) as HclValue),
    ) |
    _exprTerm;

// Binary operator helpers.
Parser<ParseError, HclValue Function(HclValue, HclValue)> _binOp(String op) =>
    _sym(op).as<HclValue Function(HclValue, HclValue)>(
      (l, r) => HclBinaryOp(op, l, r),
    );

Parser<ParseError, HclValue Function(HclValue, HclValue)> _binOps(
  List<String> ops,
) {
  var p = _binOp(ops.first);
  for (var i = 1; i < ops.length; i++) {
    p = p | _binOp(ops[i]);
  }
  return p;
}

final Parser<ParseError, HclValue> _multiplicative = _unary.chainl1(
  _binOps(['*', '/', '%']),
);

final Parser<ParseError, HclValue> _additive = _multiplicative.chainl1(
  _binOps(['+', '-']),
);

final Parser<ParseError, HclValue> _comparison = () {
  final ops = _binOp('<=') | _binOp('>=') | _binOp('<') | _binOp('>');
  return _additive.chainl1(ops);
}();

final Parser<ParseError, HclValue> _equality = _comparison.chainl1(
  _binOps(['==', '!=']),
);

final Parser<ParseError, HclValue> _logicAnd = _equality.chainl1(_binOp('&&'));

final Parser<ParseError, HclValue> _logicOr = _logicAnd.chainl1(_binOp('||'));

/// Conditional (ternary): `cond ? then : else`.
final Parser<ParseError, HclValue> _conditional = _logicOr.flatMap(
  (cond) => (_sym('?')
      .skipThen(defer(() => _hclExpression))
      .flatMap(
        (then_) => _sym(':')
            .skipThen(defer(() => _hclExpression))
            .map((else_) => HclConditional(cond, then_, else_) as HclValue),
      )).optional.map((ternary) => ternary ?? cond),
);

/// Top-level expression.
final Parser<ParseError, HclValue> _hclExpression = _conditional;

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
    .flatMap((entries) => _skip.skipThen(eof()).map((_) => entries));
