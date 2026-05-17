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
// of binary operators. Higher binding power binds tighter. The conditional
// `? :` is layered above Pratt because its shape (LHS `?` THEN `:` ELSE)
// needs a flatMap to express the two-branch lookahead.

Expr _binOp(String op, Expr a, Expr b) => BinaryOp(op, a, b);

final Parser<ParseError, Expr> _operators = pratt<Expr>(_primary, [
  // Logical OR (lowest precedence).
  InfixLeft(_sym('||'), 10, (Expr a, Expr b) => _binOp('||', a, b)),
  // Logical AND.
  InfixLeft(_sym('&&'), 20, (Expr a, Expr b) => _binOp('&&', a, b)),
  // Equality.
  InfixLeft(_sym('=='), 30, (Expr a, Expr b) => _binOp('==', a, b)),
  InfixLeft(_sym('!='), 30, (Expr a, Expr b) => _binOp('!=', a, b)),
  // Comparison.
  InfixLeft(_sym('<='), 40, (Expr a, Expr b) => _binOp('<=', a, b)),
  InfixLeft(_sym('>='), 40, (Expr a, Expr b) => _binOp('>=', a, b)),
  InfixLeft(_sym('<'), 40, (Expr a, Expr b) => _binOp('<', a, b)),
  InfixLeft(_sym('>'), 40, (Expr a, Expr b) => _binOp('>', a, b)),
  // Additive.
  InfixLeft(_sym('+'), 50, (Expr a, Expr b) => _binOp('+', a, b)),
  InfixLeft(_sym('-'), 50, (Expr a, Expr b) => _binOp('-', a, b)),
  // Multiplicative.
  InfixLeft(_sym('*'), 60, (Expr a, Expr b) => _binOp('*', a, b)),
  InfixLeft(_sym('/'), 60, (Expr a, Expr b) => _binOp('/', a, b)),
  InfixLeft(_sym('%'), 60, (Expr a, Expr b) => _binOp('%', a, b)),
  // Prefix unary (highest precedence).
  Prefix(_sym('-'), 70, (Expr e) => UnaryOp('-', e)),
  Prefix(_sym('!'), 70, (Expr e) => UnaryOp('!', e)),
]);

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
