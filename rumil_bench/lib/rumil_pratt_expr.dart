/// Pratt-based rumil expression parser for benchmarking.
///
/// Builds the same arithmetic grammar `rumil_expressions` parses but uses the
/// new `pratt` combinator instead of layered `chainl1` calls. Same input
/// strings, same AST shape (`Expr`).
library;

import 'package:rumil/rumil.dart';
import 'package:rumil_expressions/rumil_expressions.dart';

final Parser<ParseError, String> _skipWs =
    satisfy((String c) => c == ' ' || c == '\t', 'ws').skipMany.as<String>('');

Parser<ParseError, A> _lex<A>(Parser<ParseError, A> p) =>
    _skipWs.skipThen(p).thenSkip(_skipWs);

final Parser<ParseError, Expr> _number = _lex<Expr>(
  digit().many1.map<Expr>(
    (List<String> digits) => NumberLit(double.parse(digits.join())),
  ),
);

final Parser<ParseError, Expr> _atom = _number.or(
  _lex<String>(char('('))
      .skipThen(defer<ParseError, Expr>(() => _expr))
      .thenSkip(_lex<String>(char(')'))),
);

final Parser<ParseError, Expr> _expr = pratt<Expr>(
  defer<ParseError, Expr>(() => _atom),
  [
    InfixLeft<Expr>(
      _lex<String>(char('+')),
      10,
      (Expr a, Expr b) => BinaryOp('+', a, b),
    ),
    InfixLeft<Expr>(
      _lex<String>(char('-')),
      10,
      (Expr a, Expr b) => BinaryOp('-', a, b),
    ),
    InfixLeft<Expr>(
      _lex<String>(char('*')),
      20,
      (Expr a, Expr b) => BinaryOp('*', a, b),
    ),
    InfixLeft<Expr>(
      _lex<String>(char('/')),
      20,
      (Expr a, Expr b) => BinaryOp('/', a, b),
    ),
    InfixLeft<Expr>(
      _lex<String>(char('%')),
      20,
      (Expr a, Expr b) => BinaryOp('%', a, b),
    ),
  ],
);

/// Parse and evaluate an expression using the Pratt-based parser.
Object evaluatePratt(
  String expression, [
  Environment env = const Environment(),
]) {
  final result = _expr.run(expression);
  return switch (result) {
    Success<ParseError, Expr>(:final value) => eval(value, env),
    Partial<ParseError, Expr>(:final value) => eval(value, env),
    Failure<ParseError, Expr>() =>
      throw StateError('Parse error: ${result.errors}'),
  };
}
