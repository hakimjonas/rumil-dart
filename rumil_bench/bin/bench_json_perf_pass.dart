/// Benchmark: rumil_parsers JSON parser perf-pass.
///
/// Three workloads tuned to surface the 0.8.0 perf changes:
///   - integer_heavy: 50k integers — JsonInt fast track.
///   - float_heavy:   50k floats   — JsonDouble path.
///   - mixed:         50k records  — every path composed.
///
/// Runs against AOT (`dart compile exe`) and Wasm (`dart compile wasm`
/// invoked through `tool/run_wasm.mjs`). Same binary in both cases —
/// the harness uses `print` only so the Wasm target works without
/// any `dart:io` coupling.
library;

import 'package:rumil_parsers/rumil_parsers.dart';

import 'package:rumil_bench/harness.dart';
import 'package:rumil_bench/json_perf_data.dart';

void main() {
  final intHeavy = intHeavyJson();
  final floatHeavy = floatHeavyJson();
  final mixed = mixedJson();

  print('=== rumil_parsers JSON perf-pass ===');
  print('');

  print('integer_heavy (${intHeavy.length} bytes):');
  benchWithSize(
    'rumil',
    () => parseJson(intHeavy),
    intHeavy.length,
    iterations: 100,
  );

  print('');
  print('float_heavy (${floatHeavy.length} bytes):');
  benchWithSize(
    'rumil',
    () => parseJson(floatHeavy),
    floatHeavy.length,
    iterations: 100,
  );

  print('');
  print('mixed (${mixed.length} bytes):');
  benchWithSize('rumil', () => parseJson(mixed), mixed.length, iterations: 100);
}
