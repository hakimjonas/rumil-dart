/// Apples-to-apples: the SAME left-recursive grammar, three ways.
///
/// Grammar: `expr -> expr '+' digit | digit`, left-associative sum over
/// single digits. Expressed three ways that all produce the identical
/// integer result on the identical input:
///   - rule()   : Warth et al. seed-growth, the directly-left-recursive
///                form, host-recursive on left-recursion depth.
///   - chainl1  : the flat left-fold combinator (iterative).
///   - pratt    : the operator-precedence table (iterative).
///
/// This is the comparison `bench_lr.dart` does NOT make: there, each
/// strategy runs on a different grammar/input, so the numbers are not
/// directly comparable. Here every lane parses the same string to the
/// same sum, verified equal before timing.
///
/// Run under all three modes (they diverge):
///   JIT : dart run bin/bench_lr_vs_pratt.dart
///   AOT : dart compile exe ... && run
///   WASM: dart compile wasm ... && deno run tool/run_wasm.mjs ...
library;

import 'package:rumil/rumil.dart';

import 'package:rumil_bench/harness.dart';

/// `expr -> expr '+' digit | digit` via Warth seed-growth.
Parser<ParseError, int> ruleExpr() {
  late final Parser<ParseError, int> expr;
  expr = rule(
    () =>
        defer(() => expr).flatMap(
          (l) => char('+').skipThen(digit().map(int.parse)).map((r) => l + r),
        ) |
        digit().map(int.parse),
  );
  return expr.thenSkip(eof());
}

/// Same grammar via the flat left-fold combinator.
Parser<ParseError, int> chainExpr() => digit()
    .map(int.parse)
    .chainl1(char('+').map((_) => (int a, int b) => a + b))
    .thenSkip(eof());

/// Same grammar via the Pratt operator table.
Parser<ParseError, int> prattExpr() => pratt<int>(digit().map(int.parse), [
  InfixLeft(char('+'), 10, (int a, int b) => a + b),
]).thenSkip(eof());

int _eval(Parser<ParseError, int> p, String input) => switch (p.run(input)) {
  Success<ParseError, int>(:final value) => value,
  Partial<ParseError, int>(:final value) => value,
  Failure() => throw StateError('parse failed: $input'),
};

void main() {
  // Single-digit operands joined by '+', sum is well-defined and equal
  // across all three lanes. Digits cycle 1..9,0 so the value is stable.
  String doc(int terms) =>
      List.generate(terms, (i) => '${(i % 9) + 1}').join('+');

  final sizes = [3, 10, 50, 100, 300];

  final rule = ruleExpr();
  final chain = chainExpr();
  final pr = prattExpr();

  // Verify all three agree on every input before timing anything.
  for (final n in sizes) {
    final input = doc(n);
    final r = _eval(rule, input);
    final c = _eval(chain, input);
    final p = _eval(pr, input);
    if (r != c || r != p) {
      throw StateError('mismatch at $n terms: rule=$r chain=$c pratt=$p');
    }
  }
  print('all three lanes agree on every input; timing follows');
  print('');
  print('=== same left-recursive grammar: rule() vs chainl1 vs pratt ===');

  for (final n in sizes) {
    final input = doc(n);
    final iters = n >= 100 ? 5000 : 20000;
    print('');
    print('$n terms (${input.length} B):');
    bench('rule()  ', () => rule.run(input), iterations: iters, warmUp: 500);
    bench('chainl1 ', () => chain.run(input), iterations: iters, warmUp: 500);
    bench('pratt   ', () => pr.run(input), iterations: iters, warmUp: 500);
  }
}
