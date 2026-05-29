/// Benchmark: incremental reparse vs. full reparse.
///
/// The question this answers: as a document grows, does an incremental edit
/// stay cheap (token-level constant, block-level ~region-sized) while a full
/// reparse grows linearly? And are the absolute numbers in keystroke-latency
/// territory (<16 ms)?
///
/// Grammar: a document is N groups; each group is `(` digits `)` `;`. A
/// "simple" token is the digit run, so editing inside one digit run is a
/// tier-1 token-level update; inserting a `+` (a non-simple token) forces a
/// tier-2 block-level reparse of just that group.
library;

import 'package:rumil/rumil.dart';

import 'package:rumil_bench/harness.dart';

enum Tok { lparen, rparen, semi, plus, num, error }

enum Syn { doc, group }

typedef G = GreenNode<Tok, Syn>;

Parser<ParseError, G> _numTok() =>
    digit().many1.capture.map((s) => GreenToken<Tok, Syn>(Tok.num, s));

Parser<ParseError, G> _plusTok() =>
    char('+').map((c) => GreenToken<Tok, Syn>(Tok.plus, c));

Parser<ParseError, G> _lparen() =>
    char('(').map((c) => GreenToken<Tok, Syn>(Tok.lparen, c));

Parser<ParseError, G> _rparen() =>
    char(')').map((c) => GreenToken<Tok, Syn>(Tok.rparen, c));

Parser<ParseError, G> _semi() =>
    char(';').map((c) => GreenToken<Tok, Syn>(Tok.semi, c));

/// group := '(' (num | '+')+ ')' ';'
Parser<ParseError, G> _group() {
  final inner = (_numTok() | _plusTok()).many1;
  return _lparen().flatMap(
    (lp) => inner.flatMap(
      (mid) => _rparen().flatMap(
        (rp) => _semi().map(
          (sc) => GreenTree<Tok, Syn>(Syn.group, [lp, ...mid, rp, sc]),
        ),
      ),
    ),
  );
}

Parser<ParseError, G> _doc() => _group().many
    .thenSkip(eof())
    .map((groups) => GreenTree<Tok, Syn>(Syn.doc, groups));

ReparseableParsers<Tok, Syn> _parsers() => ReparseableParsers(
  full: _doc(),
  byKind: {Syn.group: _group()},
  isSimpleToken: (t) => t == Tok.num,
  onParseFailure: (src) =>
      GreenUnexpected<Tok, Syn>([GreenToken<Tok, Syn>(Tok.error, src)]),
);

/// Build a document of [n] groups: "(12);(12);...".
String _buildSource(int n) {
  final b = StringBuffer();
  for (var i = 0; i < n; i++) {
    b.write('(12);');
  }
  return b.toString();
}

void main() {
  final parsers = _parsers();
  // minReparseSize must be small relative to a group so block-level fires;
  // a group is "(12+);" = 6 chars, so 4 keeps the region-vs-document guard
  // from forcing full reparse on large docs.
  const config = IncrementalConfig(minReparseSize: 4);

  // Anti-elision sink. Every benchmark body feeds an observable value
  // (a tree's textLength, or the strategy index) into this; it is printed
  // at the end so neither AOT nor dart2wasm can prove the work unobserved
  // and prune it. Without this, discarding incrementalParse's result lets
  // the optimizer elide most of the splice — which would make the numbers
  // measure dead-code elimination, not the operation.
  var sink = 0;

  for (final n in [100, 1000, 10000]) {
    final src = _buildSource(n);
    final tree = (_doc().run(src) as Success<ParseError, G>).value;
    print('=== Document: $n groups (${src.length} chars) ===');

    // Warmup / iteration budgets sized so V8 (the dart2wasm host) reaches
    // TurboFan steady state and even the sub-microsecond incremental paths
    // are measured over a tens-of-ms window, well above the timer noise
    // floor. The same generous warmup is harmless for AOT (already fully
    // compiled). Full reparse is ~ms-scale so it needs far fewer iterations
    // to fill the same window.
    const incWarmUp = 20000;
    // Scale iterations down as per-op cost rises with document size, so each
    // case runs for a bounded (~tens of ms to a few hundred ms) window
    // rather than seconds. 200k at n=100 (~sub-μs) ≈ tens of ms; 5k at
    // n=10000 (~tens of μs) ≈ a few hundred ms — both well above noise.
    final incIters = switch (n) {
      >= 10000 => 5000,
      >= 1000 => 50000,
      _ => 200000,
    };
    final fullIters = n >= 10000 ? 200 : 2000;
    const fullWarmUp = 200;

    // Baseline: full reparse from scratch.
    bench(
      'full reparse',
      () {
        final r = _doc().run(src);
        sink += (r as Success<ParseError, G>).value.textLength;
      },
      warmUp: fullWarmUp,
      iterations: fullIters,
    );

    // Tier 1: token-level edit in the FIRST group's digit run (offset 1).
    // Edits near the start are the adversarial case for any path that walks
    // from the root, so this is the honest worst-ish case for tier 1.
    final tokenEditFirst = TextEdit.insert(1, '9');
    bench(
      'token-level (first group)',
      () {
        final r = incrementalParse(tree, src, tokenEditFirst, parsers,
            config: config);
        sink += r.tree.textLength + r.strategy.index;
      },
      warmUp: incWarmUp,
      iterations: incIters,
    );

    // Tier 1: token-level edit in the LAST group's digit run.
    final lastDigitOffset = src.length - 4; // inside the last "(12);"
    final tokenEditLast = TextEdit.insert(lastDigitOffset, '9');
    bench(
      'token-level (last group)',
      () {
        final r = incrementalParse(tree, src, tokenEditLast, parsers,
            config: config);
        sink += r.tree.textLength + r.strategy.index;
      },
      warmUp: incWarmUp,
      iterations: incIters,
    );

    // Tier 2: block-level edit — insert '+' (non-simple) into the first group.
    final blockEdit = TextEdit.insert(3, '+'); // "(12+);..."
    bench(
      'block-level (first group)',
      () {
        final r =
            incrementalParse(tree, src, blockEdit, parsers, config: config);
        sink += r.tree.textLength + r.strategy.index;
      },
      warmUp: incWarmUp,
      iterations: incIters,
    );

    print('');
  }

  // Print the sink so the accumulated work cannot be eliminated.
  print('(sink: $sink)');
}
