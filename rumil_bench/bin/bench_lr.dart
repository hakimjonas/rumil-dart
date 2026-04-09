/// Benchmark 3: Left recursion cost and capability comparison.
library;

import 'package:rumil/rumil.dart';
import 'package:rumil_expressions/rumil_expressions.dart';

import 'package:rumil_bench/harness.dart';
import 'package:rumil_bench/manual_pratt.dart';

void main() {
  final env = Environment.standard();

  final inputs = {
    'tiny (3 terms)': '1 + 2 * 3',
    'small (10 terms)': List.generate(10, (i) => '${i + 1}').join(' + '),
    'medium (100 terms)': List.generate(100, (i) => '${i + 1}').join(' + '),
    'large (1000 terms)': List.generate(1000, (i) => '${i + 1}').join(' + '),
    'mixed ops (50 terms)': List.generate(
      50,
      (i) => i.isEven ? '${i + 1} * ${i + 2}' : '${i + 1}',
    ).join(' + '),
  };

  print('=== Left recursion cost: Rumil chainl1 vs hand-rolled Pratt ===');

  for (final MapEntry(:key, :value) in inputs.entries) {
    print('');
    print('$key:');
    final iters = value.length > 5000 ? 500 : 5000;
    bench(
      'rumil (chainl1)',
      () => evaluate(value, env),
      iterations: iters,
      warmUp: 100,
    );
    bench(
      'pratt (manual) ',
      () => manualEval(value),
      iterations: iters,
      warmUp: 100,
    );
  }

  print('');
  print(
    '=== Left recursion capability: rule() handles grammars petitparser cannot ===',
  );
  print('');
  print('Grammar: expr -> expr "+" digit | digit');
  print('This is directly left-recursive. Petitparser\'s ExpressionBuilder');
  print('rewrites it into precedence climbing — it cannot express the');
  print('left-recursive rule directly. Rumil\'s rule() uses Warth seed-growth');
  print('to handle it without grammar transformation.');
  print('');

  // Left-recursive expression grammar using rule()
  late final Parser<ParseError, int> expr;
  expr = rule(
    () =>
        defer(() => expr).flatMap(
          (l) => char(
            '+',
          ).skipThen(digit().map((d) => int.parse(d))).map((r) => l + r),
        ) |
        digit().map(int.parse),
  );

  final lrInputs = {
    '1 term': '5',
    '3 terms': '1+2+3',
    '10 terms': List.generate(10, (i) => '${(i + 1) % 10}').join('+'),
    '50 terms': List.generate(50, (i) => '${(i + 1) % 10}').join('+'),
  };

  for (final MapEntry(:key, :value) in lrInputs.entries) {
    final result = (expr.thenSkip(eof())).run(value);
    final sum = switch (result) {
      Success<ParseError, int>(:final value) => value,
      _ => -1,
    };
    bench(
      'rule() $key (=$sum)',
      () => (expr.thenSkip(eof())).run(value),
      iterations: 5000,
      warmUp: 200,
    );
  }
}
