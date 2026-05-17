/// Parity check: full rumil_expressions parser (Pratt + conditional layer)
/// vs the standalone arithmetic-only Pratt builder. Sanity-checks that both
/// paths agree on common arithmetic shapes; mismatches would indicate a
/// regression in the Pratt loop, the binding-power table, or the operator
/// dispatch in either path.
library;

import 'package:rumil_bench/rumil_pratt_expr.dart';
import 'package:rumil_expressions/rumil_expressions.dart';

void main() {
  final cases = [
    '1 + 2 * 3',
    '((1 + 2) * (3 + 4)) + 5',
    '100 - 50 + 25',
    '10 / 2 / 2',
    '5 - 3 - 1',
    '2 * 3 + 4',
  ];
  var ok = 0;
  var fail = 0;
  for (final c in cases) {
    final exprResult = evaluate(c);
    final prattResult = evaluatePratt(c);
    final match = exprResult == prattResult;
    print(
      '${match ? "OK " : "BAD"}  "$c" => '
      'rumil_expr=$exprResult, pratt-arith=$prattResult',
    );
    if (match) {
      ok++;
    } else {
      fail++;
    }
  }
  print('');
  print('$ok passed, $fail failed');
}
