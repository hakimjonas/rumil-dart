/// Microbenchmark: `_interpretMany` dispatch overhead vs fast-path.
///
/// The interpreter has specialized fast paths for terminal-shaped
/// `Many` (e.g. `Many(StringMatch)` → `_collectManyString`,
/// `Many(Satisfy)` → `_collectMany`). When `Many` wraps a composite
/// parser like `Mapped(...)`, it falls through to the generic
/// `_interpretMany`, which calls `interpretI(p, state)` per
/// iteration — a full dispatch cycle through the interpreter switch.
///
/// This bench measures the gap between the two paths. Both
/// configurations do the same atomic work per iteration (match the
/// string `"x"`); the difference is whether each iteration goes
/// through the fast path or the composite dispatch path.
///
/// If the gap is large, dispatch overhead is the bottleneck and
/// special-casing common composite shapes (e.g. `Many(Mapped(...))`)
/// in the interpreter would yield a measurable win. If the gap is
/// small, dispatch is already cheap and inlining wouldn't help.
library;

import 'package:rumil/rumil.dart';
import 'package:rumil_bench/harness.dart';

void main() {
  // Workload: parse a long stream of `x` characters via `Many(...)`.
  final src10k = 'x' * (10 * 1024);
  final src100k = 'x' * (100 * 1024);

  // A: terminal-shaped Many — hits `_collectManyString` fast path.
  final pFast = string('x').many;

  // B: composite-shaped Many — goes through `_interpretMany` and a
  // full `interpretI` dispatch per iteration. The `.map((s) => s)`
  // wraps `string('x')` in a Mapped node with an identity function,
  // forcing the composite path. The Mapped case routes through the
  // trampoline, which itself unwinds the same atomic StringMatch.
  final pComposite = string('x').map((s) => s).many;

  print('=== Many dispatch overhead bench ===');
  print('');
  print('Same atomic work per iteration (match `x`); A hits the fast');
  print('path, B forces the generic _interpretMany composite path.');

  for (final entry in <(String, String)>[
    ('10 KB', src10k),
    ('100 KB', src100k),
  ]) {
    final label = entry.$1;
    final src = entry.$2;

    print('');
    print('--- $label stream ---');

    benchWithSize(
      'A: Many(string)              [fast path]',
      () => pFast.run(src),
      src.length,
      warmUp: 20,
      iterations: 200,
    );

    benchWithSize(
      'B: Many(string.map(id))      [composite]',
      () => pComposite.run(src),
      src.length,
      warmUp: 20,
      iterations: 200,
    );
  }
}
