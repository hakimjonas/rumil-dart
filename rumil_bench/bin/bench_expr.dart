/// Benchmark 1b: Rumil chainl1 vs Rumil Pratt vs petitparser — expression evaluation.
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

  print('=== Rumil chainl1 vs Rumil Pratt vs petitparser ===');
  print('');

  print('Simple "$simple":');
  bench('rumil chainl', () => evaluate(simple, env), iterations: 50000);
  bench('rumil pratt ', () => evaluatePratt(simple, env), iterations: 50000);
  bench('petit       ', () => petitExpr.parse(simple), iterations: 50000);

  print('');
  print('Nested "$nested":');
  bench('rumil chainl', () => evaluate(nested, env), iterations: 50000);
  bench('rumil pratt ', () => evaluatePratt(nested, env), iterations: 50000);
  bench('petit       ', () => petitExpr.parse(nested), iterations: 50000);

  print('');
  print('Long chain (100 terms):');
  bench('rumil chainl', () => evaluate(long, env), iterations: 5000);
  bench('rumil pratt ', () => evaluatePratt(long, env), iterations: 5000);
  bench('petit       ', () => petitExpr.parse(long), iterations: 5000);

  print('');
  print('Deeply nested (50 parens):');
  bench('rumil chainl', () => evaluate(deep, env), iterations: 5000);
  bench('rumil pratt ', () => evaluatePratt(deep, env), iterations: 5000);
  bench('petit       ', () => petitExpr.parse(deep), iterations: 5000);
}
