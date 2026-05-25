/// Microbenchmark: cached [LineIndex] vs rebuilt-per-lookup.
///
/// Mirrors the Scala JMH suite at
/// rumil/benchmarks/src/main/scala/parser/benchmarks/LineIndexBenchmarks.scala
/// using the existing `bench()` harness.
///
/// Two operations are measured at three source sizes (1 KB, 10 KB,
/// 100 KB):
///
///   - **buildAndLookup1000**: build the index once, run 1000 random
///     `locationAt` lookups. Cost is O(n) construction + O(1000 log n)
///     lookups — the intended usage pattern.
///   - **rebuildPerLookup**: build a fresh index for each of 1000
///     lookups. Cost is O(1000 × n) — the naïve "no caching" baseline.
///
/// The ratio between the two should scale linearly with source size:
/// at 100 KB the cached path should dominate the rebuild path by
/// roughly two orders of magnitude.
///
/// Source data is synthesized with ~40-character lines (typical code
/// width). Offsets are generated once per size from a fixed seed so
/// the comparison across sizes is reproducible.
library;

import 'dart:math';

import 'package:rumil/rumil.dart';
import 'package:rumil_bench/harness.dart';

const _lookups = 1000;

void main() {
  print('=== LineIndex benchmarks ===');
  print('');
  print('Each benchmark runs $_lookups random offset lookups. The "cached"');
  print('path builds the LineIndex once; the "rebuild" path rebuilds it per');
  print('lookup. Lower μs/op is better.');

  for (final size in const [1024, 10240, 102400]) {
    final src = _synthesizeSource(size);
    final offsets = _randomOffsets(src.length + 1, _lookups, seed: 0xC0FFEE);

    print('');
    print('--- ${size}B source ---');

    benchWithSize(
      'cached:  build + 1000 lookups',
      () => _cached(src, offsets),
      src.length,
      warmUp: 50,
      iterations: 200,
    );

    benchWithSize(
      'rebuild: 1000 (build + lookup)',
      () => _rebuilt(src, offsets),
      src.length,
      warmUp: 10,
      iterations: 50,
    );

    benchWithSize(
      'format:  1000 Location.format()  (fused walk)',
      () => _formatFused(src, offsets),
      src.length,
      warmUp: 10,
      iterations: 50,
    );

    benchWithSize(
      'format:  1000 \$line:\$column (legacy two-walk)',
      () => _formatLegacy(src, offsets),
      src.length,
      warmUp: 10,
      iterations: 50,
    );
  }
}

/// Build the index once, then perform [offsets.length] lookups.
void _cached(String src, List<int> offsets) {
  final idx = LineIndex(src);
  for (var i = 0; i < offsets.length; i++) {
    final loc = idx.locationAt(offsets[i]);
    // Force the cached fields to materialize so the optimizer can't
    // delete the loop body. `loc.line` on a PrecomputedLocation is a
    // field read, not a walk — the cost we want to measure is the
    // index lookup, not the line/column resolution.
    if (loc.line < 0) throw StateError('unreachable');
  }
}

/// Build a fresh index for each lookup.
void _rebuilt(String src, List<int> offsets) {
  for (var i = 0; i < offsets.length; i++) {
    final idx = LineIndex(src);
    final loc = idx.locationAt(offsets[i]);
    if (loc.line < 0) throw StateError('unreachable');
  }
}

/// Plain [Location.format] — the fused-walk path landed in 0.7.1.
/// One O(offset) walk per format call.
void _formatFused(String src, List<int> offsets) {
  for (var i = 0; i < offsets.length; i++) {
    final loc = Location(src, offsets[i]);
    final s = loc.format();
    if (s.isEmpty) throw StateError('unreachable');
  }
}

/// The pre-0.7.1 path: read [Location.line] and [Location.column]
/// separately. Two O(offset) walks per format. Kept as a baseline so
/// the win is measurable in-bench.
void _formatLegacy(String src, List<int> offsets) {
  for (var i = 0; i < offsets.length; i++) {
    final loc = Location(src, offsets[i]);
    final s = '${loc.line}:${loc.column} (offset ${loc.offset})';
    if (s.isEmpty) throw StateError('unreachable');
  }
}

/// Synthesize a deterministic source with ~40-char ASCII lines.
String _synthesizeSource(int targetSize) {
  final sb = StringBuffer();
  var i = 0;
  while (sb.length < targetSize) {
    final lineLen = 32 + (i % 16);
    for (var j = 0; j < lineLen && sb.length < targetSize; j++) {
      sb.writeCharCode(0x61 + ((i + j) % 26));
    }
    if (sb.length < targetSize) sb.writeCharCode(0x0a);
    i++;
  }
  return sb.toString();
}

/// Pre-generate [count] random offsets in `[0, max)` from [seed].
List<int> _randomOffsets(int max, int count, {required int seed}) {
  final rng = Random(seed);
  return List<int>.generate(count, (_) => rng.nextInt(max));
}
