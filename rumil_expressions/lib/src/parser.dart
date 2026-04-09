/// Expression parser. Operator precedence is handled by layered `chainl1` calls.
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

// ---- Unary ----

final Parser<ParseError, Expr> _unary =
    (_sym('-').as('-') | _sym('!').as('!')).flatMap(
      (op) =>
          defer(() => _unary).map((operand) => UnaryOp(op, operand) as Expr),
    ) |
    _primary;

// ---- Binary operators (chainl1 per precedence level) ----

Parser<ParseError, Expr Function(Expr, Expr)> _binOp(String op) =>
    _sym(op).as<Expr Function(Expr, Expr)>((l, r) => BinaryOp(op, l, r));

Parser<ParseError, Expr Function(Expr, Expr)> _binOps(List<String> ops) {
  var p = _binOp(ops.first);
  for (var i = 1; i < ops.length; i++) {
    p = p | _binOp(ops[i]);
  }
  return p;
}

final Parser<ParseError, Expr> _multiplicative = _unary.chainl1(
  _binOps(['*', '/', '%']),
);

final Parser<ParseError, Expr> _additive = _multiplicative.chainl1(
  _binOps(['+', '-']),
);

final Parser<ParseError, Expr> _comparison = () {
  final ops = _binOp('<=') | _binOp('>=') | _binOp('<') | _binOp('>');
  return _additive.chainl1(ops);
}();

final Parser<ParseError, Expr> _equality = _comparison.chainl1(
  _binOps(['==', '!=']),
);

final Parser<ParseError, Expr> _logicAnd = _equality.chainl1(_binOp('&&'));

final Parser<ParseError, Expr> _logicOr = _logicAnd.chainl1(_binOp('||'));

// ---- Conditional ----

final Parser<ParseError, Expr> _conditional = _logicOr.flatMap(
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
