/// Pratt-based rumil expression parser for benchmarking.
///
/// Builds the same arithmetic grammar `rumil_expressions` parses but uses
/// the new `pratt` combinator instead of layered `chainl1` calls. Same input
/// strings, same AST shape ([Expr]).
///
/// Note: the pratt builder auto-enables a char-indexed opTable fast-path
/// only when every operator symbol is a bare `char(c)`. This grammar wraps
/// operators with whitespace consumption (`lex`), so opTable is null and
/// the interpreter uses the general `getOp` dispatch — matching what a
/// real consumer with whitespace-sensitive grammars sees.
library;

import 'package:rumil/rumil.dart';
import 'package:rumil_expressions/rumil_expressions.dart';

final Parser<ParseError, String> _ws =
    satisfy((String c) => c == ' ' || c == '\t', 'ws').skipMany.as<String>('');

Parser<ParseError, A> _lex<A>(Parser<ParseError, A> p) =>
    _ws.skipThen(p).thenSkip(_ws);

final Parser<ParseError, Expr> _number = _lex(
  digit().many1.map<Expr>(
    (List<String> digits) => NumberLit(double.parse(digits.join())),
  ),
);

final Parser<ParseError, Expr> _atom = _number.or(
  _lex(char('('))
      .skipThen(defer<ParseError, Expr>(() => _expr))
      .thenSkip(_lex(char(')'))),
);

final Parser<ParseError, Expr> _expr = pratt<Expr>(
  defer<ParseError, Expr>(() => _atom),
  [
    InfixLeft(_lex(char('+')), 10, (Expr a, Expr b) => BinaryOp('+', a, b)),
    InfixLeft(_lex(char('-')), 10, (Expr a, Expr b) => BinaryOp('-', a, b)),
    InfixLeft(_lex(char('*')), 20, (Expr a, Expr b) => BinaryOp('*', a, b)),
    InfixLeft(_lex(char('/')), 20, (Expr a, Expr b) => BinaryOp('/', a, b)),
    InfixLeft(_lex(char('%')), 20, (Expr a, Expr b) => BinaryOp('%', a, b)),
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
