/// Expression evaluator. Returns `Object` (double, String, or bool).
library;

import 'ast.dart';
import 'environment.dart';
import 'eval_helpers.dart';

/// Evaluate an [Expr] AST in the given [Environment].
Object eval(Expr expr, Environment env) => switch (expr) {
  NumberLit(:final value) => value,
  StringLit(:final value) => value,
  BoolLit(:final value) => value,
  Variable(:final name) => _lookupVar(name, env),
  UnaryOp(:final op, :final operand) => applyUnaryOp(op, eval(operand, env)),
  BinaryOp(:final op, :final left, :final right) =>
    applyBinaryOp(op, eval(left, env), eval(right, env)),
  FunctionCall(:final name, :final args) => _evalCall(name, args, env),
  Conditional(:final condition, :final then_, :final else_) =>
    asBool(eval(condition, env), '?:')
        ? eval(then_, env)
        : eval(else_, env),
};

Object _lookupVar(String name, Environment env) {
  final value = env.variables[name];
  if (value == null && !env.variables.containsKey(name)) {
    throw EvalException('Undefined variable: $name');
  }
  return value!;
}

Object _evalCall(String name, List<Expr> args, Environment env) {
  final fn = env.functions[name];
  if (fn == null) throw EvalException('Undefined function: $name');
  final evaluated = args.map((a) => eval(a, env)).toList();
  return fn(evaluated);
}
