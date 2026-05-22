/// JSON parser micro-benchmark.
///
/// Three workloads exercise different code paths in `parseJson`:
///   - **integer-heavy**: 50k-element list of integers, exercises the
///     capture-based number path on the JsonInt fast track.
///   - **float-heavy**: 50k-element list of floats, exercises the
///     JsonDouble fall-through.
///   - **mixed**: 50k records with int / string / bool fields,
///     exercises the firstCharChoice dispatch and string runs in
///     proportion to a realistic API-response shape.
///
/// Output is a JSON document on stdout for machine-readable
/// consumption (BENCHMARKS.md ingestion, comparison tooling). Each
/// workload reports min / median / max / mean wall-clock ms across N
/// runs.
///
/// Run modes:
///   - `dart run tool/bench/json_bench.dart` — JIT, includes warmup.
///   - `dart compile exe tool/bench/json_bench.dart -o /tmp/json_bench`
///     then `/tmp/json_bench` — AOT, the load-bearing measurement.
///   - `dart compile wasm tool/bench/json_bench.dart -o /tmp/json_bench.wasm`
///     then `dart run wasm /tmp/json_bench.wasm` — Wasm, exercises
///     i64-vs-f64 specialization through the JsonInt/JsonDouble split.
///
/// Pass `--runs N` to override the default of 11 runs (10 measured +
/// 1 warmup that is discarded). Pass `--platform LABEL` to tag the
/// output (e.g. `aot`, `wasm`, `jit`).
library;

import 'dart:convert';

import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';

void main(List<String> args) {
  var runs = 11;
  var platform = 'jit';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--runs' && i + 1 < args.length) {
      runs = int.parse(args[i + 1]);
    }
    if (args[i] == '--platform' && i + 1 < args.length) {
      platform = args[i + 1];
    }
  }

  final intHeavy = _intHeavy();
  final floatHeavy = _floatHeavy();
  final mixed = _mixed();

  final results = [
    _measure('integer_heavy', intHeavy, runs),
    _measure('float_heavy', floatHeavy, runs),
    _measure('mixed', mixed, runs),
  ];

  final report = {
    'platform': platform,
    'runs': runs - 1, // first run is warmup, discarded from measured set
    'workloads': results,
  };

  // `print` rather than `stdout.writeln` so the binary works under
  // `dart compile wasm` (dart2wasm does not implement `dart:io`'s
  // stdio surface).
  print(const JsonEncoder.withIndent('  ').convert(report));
}

Map<String, Object?> _measure(String label, String input, int runs) {
  final samples = <int>[];
  // First run is warmup; discard.
  for (var i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    final result = parseJson(input);
    sw.stop();
    if (result is Failure) {
      throw StateError('Bench input failed to parse: $label');
    }
    if (i > 0) samples.add(sw.elapsedMicroseconds);
  }
  samples.sort();
  return {
    'workload': label,
    'input_bytes': input.length,
    'min_us': samples.first,
    'median_us': samples[samples.length ~/ 2],
    'max_us': samples.last,
    'mean_us': samples.reduce((a, b) => a + b) ~/ samples.length,
  };
}

/// 50k integers, one per element. Exercises the JsonInt fast track in
/// `_jsonNumber`.
String _intHeavy() {
  final buf = StringBuffer('[');
  for (var i = 0; i < 50000; i++) {
    if (i > 0) buf.write(',');
    buf.write(i);
  }
  buf.write(']');
  return buf.toString();
}

/// 50k floats with a fractional part. Exercises the JsonDouble path.
String _floatHeavy() {
  final buf = StringBuffer('[');
  for (var i = 0; i < 50000; i++) {
    if (i > 0) buf.write(',');
    buf.write('${i + 0.1}');
  }
  buf.write(']');
  return buf.toString();
}

/// 50k records with mixed int / string / bool fields. Roughly the
/// shape of an API response listing or a log batch.
String _mixed() {
  final buf = StringBuffer('[');
  for (var i = 0; i < 50000; i++) {
    if (i > 0) buf.write(',');
    buf.write('{"id":');
    buf.write(i);
    buf.write(',"name":"user_');
    buf.write(i);
    buf.write('","active":');
    buf.write(i % 5 != 0);
    buf.write(',"score":');
    buf.write(i % 100);
    buf.write('}');
  }
  buf.write(']');
  return buf.toString();
}
