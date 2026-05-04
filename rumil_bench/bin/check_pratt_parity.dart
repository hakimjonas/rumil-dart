/// Quick parity check: rumil chainl1 vs rumil Pratt on the same inputs.
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
    final orig = evaluate(c);
    final pratt = evaluatePratt(c);
    final match = orig == pratt;
    print('${match ? "OK " : "BAD"}  "$c" => chainl1=$orig, pratt=$pratt');
    if (match) {
      ok++;
    } else {
      fail++;
    }
  }
  print('');
  print('$ok passed, $fail failed');
}
