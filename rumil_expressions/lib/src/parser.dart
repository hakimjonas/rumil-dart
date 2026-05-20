/// Expression parser. Operator precedence is handled by a single `pratt`
/// combinator: prefix unary operators, six levels of binary operators with
/// binding powers, and a ternary conditional layered on top.
library;

import 'package:rumil/rumil.dart';

import 'ast.dart';

/// Parse an expression string into an [Expr] AST.
Result<ParseError, Expr> parseExpression(String input) =>
    _ws.skipThen(_expr).thenSkip(_ws).thenSkip(eof()).run(input);

// ---- Whitespace ----

final Parser<ParseError, void> _ws = satisfy(
  (c) => c == ' ' || c == '\t' || c == '\r' || c == '\n',
  'whitespace',
).many.as<void>(null);

Parser<ParseError, A> _lex<A>(Parser<ParseError, A> p) => p.thenSkip(_ws);

Parser<ParseError, String> _sym(String s) => _lex(string(s));

// ---- Atoms ----

final Parser<ParseError, Expr> _number = _lex(
  char('-').optional.flatMap(
    (neg) => digit().many1.flatMap(
      (whole) => char('.').skipThen(digit().many1).optional.map((frac) {
        final str =
            frac != null ? '${whole.join()}.${frac.join()}' : whole.join();
        final value = double.parse(str);
        return NumberLit(neg != null ? -value : value) as Expr;
      }),
    ),
  ),
).named('number');

final Parser<ParseError, Expr> _stringLit = _lex(
  char('"')
      .skipThen(satisfy((c) => c != '"' && c != '\n', 'string char').many)
      .map((cs) => StringLit(cs.join()) as Expr)
      .thenSkip(char('"'))
      .named('string'),
);

final Parser<ParseError, Expr> _boolLit = _lex(
  keywords<Expr>({'true': const BoolLit(true), 'false': const BoolLit(false)}),
).named('boolean');

final Parser<ParseError, String> _identifier = _lex(
  (letter() | char('_'))
      .zip((alphaNum() | char('_')).many)
      .map((pair) => pair.$1 + pair.$2.join()),
);

final Parser<ParseError, Expr> _variable = _identifier.map<Expr>(Variable.new);

final Parser<ParseError, Expr> _parenExpr = _sym(
  '(',
).skipThen(defer(() => _expr)).thenSkip(_sym(')'));

final Parser<ParseError, Expr> _primary =
    _number |
    _stringLit |
    _boolLit |
    _parenExpr |
    defer(() => _functionCall) |
    _variable;

// ---- Function calls ----

final Parser<ParseError, Expr> _functionCall = _identifier.flatMap(
  (name) => _sym('(')
      .skipThen(defer(() => _expr).sepBy(_sym(',')))
      .flatMap(
        (args) => _sym(')').map((_) => FunctionCall(name, args) as Expr),
      ),
);

// ---- Operators (Pratt) ----
//
// Single Pratt parse covers prefix unary `-`/`!` and six precedence levels
// of binary operators via the C-family preset. The conditional `? :` is
// layered above Pratt because its shape (LHS `?` THEN `:` ELSE) needs a
// flatMap to express the two-branch lookahead.

final Parser<ParseError, Expr> _operators = pratt<Expr>(
  _primary,
  cFamilyPrecedence<Expr>(sym: _sym, binary: BinaryOp.new, unary: UnaryOp.new),
);

// ---- Conditional ----

final Parser<ParseError, Expr> _conditional = _operators.flatMap(
  (cond) => (_sym('?')
      .skipThen(defer(() => _expr))
      .flatMap(
        (then_) => _sym(':')
            .skipThen(defer(() => _expr))
            .map((else_) => Conditional(cond, then_, else_) as Expr),
      )).optional.map((ternary) => ternary ?? cond),
);

// ---- Top-level ----

final Parser<ParseError, Expr> _expr = _conditional;
