/// Shared evaluation helpers for expression evaluators.
///
/// Type coercion, operator dispatch, and value comparison used by
/// rumil_expressions and downstream evaluators (e.g. Lambé).
library;

import 'environment.dart';

/// Cast [v] to [num] or throw with context message.
num asNum(Object? v, String ctx) {
  if (v is num) return v;
  throw EvalException('$ctx: expected number, got ${typeName(v)}');
}

/// Cast [v] to [bool] or throw with context message.
bool asBool(Object? v, String ctx) {
  if (v is bool) return v;
  throw EvalException('$ctx: expected boolean, got ${typeName(v)}');
}

/// Human-readable type name for error messages.
String typeName(Object? v) {
  if (v == null) return 'null';
  if (v is int) return 'int';
  if (v is double) return 'double';
  if (v is String) return 'string';
  if (v is bool) return 'bool';
  if (v is List) return 'list';
  if (v is Map) return 'map';
  return v.runtimeType.toString();
}

/// Evaluate a binary operator on two values.
///
/// Supports: `+`, `-`, `*`, `/`, `%`, `<`, `<=`, `>`, `>=`, `==`, `!=`, `&&`, `||`.
Object applyBinaryOp(String op, Object? l, Object? r) => switch (op) {
  '+' => _add(l, r),
  '-' => asNum(l, '-') - asNum(r, '-'),
  '*' => asNum(l, '*') * asNum(r, '*'),
  '/' => asNum(l, '/') / asNum(r, '/'),
  '%' => asNum(l, '%').toDouble() % asNum(r, '%').toDouble(),
  '<' => asNum(l, '<') < asNum(r, '<'),
  '<=' => asNum(l, '<=') <= asNum(r, '<='),
  '>' => asNum(l, '>') > asNum(r, '>'),
  '>=' => asNum(l, '>=') >= asNum(r, '>='),
  '==' => l == r,
  '!=' => l != r,
  '&&' => asBool(l, '&&') && asBool(r, '&&'),
  '||' => asBool(l, '||') || asBool(r, '||'),
  _ => throw EvalException('Unknown operator: $op'),
};

/// Evaluate a unary operator.
Object applyUnaryOp(String op, Object? value) => switch (op) {
  '-' => -asNum(value, 'unary -'),
  '!' => !asBool(value, 'unary !'),
  _ => throw EvalException('Unknown unary operator: $op'),
};

/// Compare two values of the same type.
///
/// Numbers, strings, and bools are comparable. Throws on incompatible types.
int compareValues(Object? a, Object? b) {
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  if (a is bool && b is bool) return a.toString().compareTo(b.toString());
  throw EvalException('Cannot compare ${typeName(a)} with ${typeName(b)}');
}

Object _add(Object? l, Object? r) {
  if (l is num && r is num) return l + r;
  if (l is String && r is String) return l + r;
  if (l is String || r is String) return l.toString() + r.toString();
  return asNum(l, '+') + asNum(r, '+');
}
