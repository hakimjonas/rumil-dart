/// Pure-core interpreter microbench.
///
/// Exercises the CEK trampoline directly through `run(...)` on tiny grammars,
/// isolating the interpreter from any format/value layer. The lanes mirror the
/// constructs touched by the stack-safe-nesting rewrite and the erasure-cleanup
/// pass — Pratt/chain operator width, flat `sepBy`, structural array nesting,
/// and the FlatMap/Map/Zip spine — so a before/after run confirms the per-node
/// typed-boundary indirection introduces no regression.
///
/// `chainl1`/`pratt`/`chainr1` are the most-re-entrant constructs and the ones
/// whose combiners cross the erased-driver boundary, so they are the lanes that
/// would reveal any cost from confining the `as A` cast inside the node.
library;

import 'package:rumil/rumil.dart';

import 'package:rumil_bench/harness.dart';

void main() {
  // pratt width 200: 1+1+1+... (200 operands), folded through PrattOpInfix.
  final prattInput = List.filled(200, '1').join('+');
  final prattParser = pratt<int>(digit().map(int.parse), [
    InfixLeft(char('+'), 10, (int a, int b) => a + b),
  ]);

  // chainl1 width 200: left-fold through Chainl1.combineStep.
  final chainInput = List.filled(200, '1').join('+');
  final chainParser = digit()
      .map(int.parse)
      .chainl1(char('+').map((_) => (int a, int b) => a + b));

  // chainr1 width 200: deferred right-fold through Chainr1.combineStep.
  final chainrParser = digit()
      .map(int.parse)
      .chainr1(char('^').map((_) => (int a, int b) => a + b));
  final chainrInput = List.filled(200, '1').join('^');

  // sepBy flat 200: cast-free lane, calibrates run-to-run variance.
  final sepInput = List.filled(200, '1').join(',');
  final sepParser = digit().map(int.parse).sepBy(char(','));

  // nested arrays d30: [[[...0...]]] — structural nesting on the cont chain.
  late Parser<ParseError, Object?> arr;
  arr = Defer(
    () => char(
      '0',
    ).map<Object?>((_) => 0).or(char('[').skipThen(arr).thenSkip(char(']'))),
  );
  final nestedParser = arr;
  final nestedInput = '${'[' * 30}0${']' * 30}';

  // zip/skipThen spine: FlatMap/Map/Zip flattening hot path.
  final zipParser = char(
    'a',
  ).skipThen(char('b')).skipThen(char('c')).skipThen(char('d'));
  const zipInput = 'abcd';

  print('=== pure-core interpreter microbench ===');
  bench(
    'pratt width 200',
    () => run(prattParser, prattInput),
    iterations: 20000,
  );
  bench(
    'chainl1 width 200',
    () => run(chainParser, chainInput),
    iterations: 20000,
  );
  bench(
    'chainr1 width 200',
    () => run(chainrParser, chainrInput),
    iterations: 20000,
  );
  bench('sepBy flat 200', () => run(sepParser, sepInput), iterations: 20000);
  bench(
    'nested arrays d30',
    () => run(nestedParser, nestedInput),
    iterations: 20000,
  );
  bench(
    'zip/skipThen spine',
    () => run(zipParser, zipInput),
    iterations: 200000,
  );
}
