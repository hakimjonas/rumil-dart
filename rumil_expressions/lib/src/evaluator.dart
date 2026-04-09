/// Expression evaluator. Returns `Object` (double, String, or bool).
library;

import 'ast.dart';
import 'environment.dart';

/// Evaluate an [Expr] AST in the given [Environment].
Object eval(Expr expr, Environment env) => switch (expr) {
  NumberLit(:final value) => value,
  StringLit(:final value) => value,
  BoolLit(:final value) => value,
  Variable(:final name) => _lookupVar(name, env),
  UnaryOp(:final op, :final operand) => _evalUnary(op, operand, env),
  BinaryOp(:final op, :final left, :final right) => _evalBinary(
    op,
    left,
    right,
    env,
  ),
  FunctionCall(:final name, :final args) => _evalCall(name, args, env),
  Conditional(:final condition, :final then_, :final else_) => _evalConditional(
    condition,
    then_,
    else_,
    env,
  ),
};

Object _lookupVar(String name, Environment env) {
  final value = env.variables[name];
  if (value == null && !env.variables.containsKey(name)) {
    throw EvalException('Undefined variable: $name');
  }
  return value!;
}

Object _evalUnary(String op, Expr operand, Environment env) {
  final v = eval(operand, env);
  return switch (op) {
    '-' => -_asDouble(v, 'unary -'),
    '!' => !_asBool(v, 'unary !'),
    _ => throw EvalException('Unknown unary operator: $op'),
  };
}

Object _evalBinary(String op, Expr left, Expr right, Environment env) {
  final l = eval(left, env);
  final r = eval(right, env);

  return switch (op) {
    '+' => _add(l, r),
    '-' => _asDouble(l, '-') - _asDouble(r, '-'),
    '*' => _asDouble(l, '*') * _asDouble(r, '*'),
    '/' => _asDouble(l, '/') / _asDouble(r, '/'),
    '%' => _asDouble(l, '%') % _asDouble(r, '%'),
    '<' => _asDouble(l, '<') < _asDouble(r, '<'),
    '<=' => _asDouble(l, '<=') <= _asDouble(r, '<='),
    '>' => _asDouble(l, '>') > _asDouble(r, '>'),
    '>=' => _asDouble(l, '>=') >= _asDouble(r, '>='),
    '==' => l == r,
    '!=' => l != r,
    '&&' => _asBool(l, '&&') && _asBool(r, '&&'),
    '||' => _asBool(l, '||') || _asBool(r, '||'),
    _ => throw EvalException('Unknown binary operator: $op'),
  };
}

Object _add(Object l, Object r) {
  if (l is double && r is double) return l + r;
  if (l is String && r is String) return l + r;
  if (l is String || r is String) return l.toString() + r.toString();
  return _asDouble(l, '+') + _asDouble(r, '+');
}

Object _evalCall(String name, List<Expr> args, Environment env) {
  final fn = env.functions[name];
  if (fn == null) throw EvalException('Undefined function: $name');
  final evaluated = args.map((a) => eval(a, env)).toList();
  return fn(evaluated);
}

Object _evalConditional(
  Expr condition,
  Expr then_,
  Expr else_,
  Environment env,
) {
  final cond = _asBool(eval(condition, env), '?:');
  return cond ? eval(then_, env) : eval(else_, env);
}

double _asDouble(Object v, String ctx) {
  if (v is double) return v;
  throw EvalException('$ctx: expected number, got ${v.runtimeType}');
}

bool _asBool(Object v, String ctx) {
  if (v is bool) return v;
  throw EvalException('$ctx: expected boolean, got ${v.runtimeType}');
}
