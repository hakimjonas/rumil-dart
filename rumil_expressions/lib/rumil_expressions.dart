/// Formula evaluator built on Rumil.
library;

import 'package:rumil/rumil.dart';

import 'src/ast.dart';
import 'src/environment.dart';
import 'src/evaluator.dart' as eval_;
import 'src/parser.dart' as parser_;

export 'src/ast.dart';
export 'src/environment.dart';

/// Parse and evaluate an expression string.
///
/// Returns a `double`, `String`, or `bool`.
/// Throws [EvalException] on parse errors or type errors during evaluation.
Object evaluate(String expression, [Environment env = const Environment()]) {
  final result = parser_.parseExpression(expression);
  return switch (result) {
    Success<ParseError, Expr>(:final value) => eval_.eval(value, env),
    Partial<ParseError, Expr>(:final value) => eval_.eval(value, env),
    Failure<ParseError, Expr>() =>
      throw EvalException('Parse error: ${result.errors}'),
  };
}

/// Parse an expression string into an AST.
Result<ParseError, Expr> parse(String expression) =>
    parser_.parseExpression(expression);

/// Evaluate a pre-parsed AST.
Object eval(Expr ast, [Environment env = const Environment()]) =>
    eval_.eval(ast, env);
