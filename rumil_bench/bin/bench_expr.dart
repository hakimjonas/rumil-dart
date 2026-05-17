/// Benchmark 1b: rumil_expressions vs petitparser — expression evaluation.
///
/// `rumil_expressions` is built on rumil's `pratt(...)` combinator with prefix
/// unary, six binary precedence levels, and a ternary conditional layered on
/// top. The `pratt-arith` lane is a standalone Pratt parser with bare
/// arithmetic operators only — included as a no-`_lex` reference so the
/// per-op overhead of the whitespace-skipping wrappers is visible.
library;

import 'package:rumil_expressions/rumil_expressions.dart';

import 'package:rumil_bench/harness.dart';
import 'package:rumil_bench/petitparser_expr.dart';
import 'package:rumil_bench/rumil_pratt_expr.dart';

void main() {
  final env = Environment.standard();

  final simple = '1 + 2 * 3';
  final nested = '((1 + 2) * (3 + 4)) + 5';
  final long = List.generate(100, (i) => '${i + 1}').join(' + ');
  final deep =
      '${List.generate(50, (_) => '(').join()}'
      '1'
      '${List.generate(50, (i) => ' + ${i + 2})').join()}';

  print('=== rumil_expressions vs petitparser (expr evaluation) ===');
  print('');

  print('Simple "$simple":');
  bench('rumil_expr ', () => evaluate(simple, env), iterations: 50000);
  bench('pratt-arith', () => evaluatePratt(simple, env), iterations: 50000);
  bench('petit      ', () => petitExpr.parse(simple), iterations: 50000);

  print('');
  print('Nested "$nested":');
  bench('rumil_expr ', () => evaluate(nested, env), iterations: 50000);
  bench('pratt-arith', () => evaluatePratt(nested, env), iterations: 50000);
  bench('petit      ', () => petitExpr.parse(nested), iterations: 50000);

  print('');
  print('Long chain (100 terms):');
  bench('rumil_expr ', () => evaluate(long, env), iterations: 5000);
  bench('pratt-arith', () => evaluatePratt(long, env), iterations: 5000);
  bench('petit      ', () => petitExpr.parse(long), iterations: 5000);

  print('');
  print('Deeply nested (50 parens):');
  bench('rumil_expr ', () => evaluate(deep, env), iterations: 5000);
  bench('pratt-arith', () => evaluatePratt(deep, env), iterations: 5000);
  bench('petit      ', () => petitExpr.parse(deep), iterations: 5000);
}
