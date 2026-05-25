# rumil_bench

Benchmarks for the rumil-dart family. Not published to pub.dev
(`publish_to: none`); used internally to track perf characteristics
across releases and compare against alternative parser libraries
(petitparser).

## Bench binaries

Each binary lives in `bin/`. Run with `dart run` (JIT, includes warmup
overhead) or compile to AOT via `dart compile exe` for the load-bearing
measurement.

| Binary                       | What it measures                                        |
|------------------------------|---------------------------------------------------------|
| `bench_json.dart`            | JSON parsing: rumil vs petitparser (raw + typed).       |
| `bench_json_perf_pass.dart`  | rumil_parsers JSON perf-pass: int / float / mixed.      |
| `bench_expr.dart`            | rumil_expressions vs petitparser: expression eval.      |
| `bench_formats.dart`         | All 8 rumil_parsers formats.                            |
| `bench_errors.dart`          | Lazy error construction (late final thunks).            |
| `bench_lr.dart`              | Left recursion cost and capability comparison.          |
| `check_pratt_parity.dart`    | Pratt vs hand-written arithmetic-only parity check.     |
| `probe_pratt_memory.dart`    | Pratt memory + wall-clock at increasing depths.         |
| `bench_line_index.dart`      | LineIndex amortization + Location.format() walk.        |

## Running on AOT

```bash
dart compile exe bin/bench_json_perf_pass.dart -o /tmp/bench.aot
/tmp/bench.aot
```

## Running on Wasm

`dart compile wasm` emits two files: a `.wasm` module and a `.mjs`
companion with `compile()` / `instantiate()` helpers. To run, use any
JS host that can call `WebAssembly.compile` on a dart2wasm output.
This package ships `tool/run_wasm.mjs`, a Deno-hosted runner:

```bash
dart compile wasm bin/bench_json_perf_pass.dart -o /tmp/bench.wasm
deno run --allow-read tool/run_wasm.mjs /tmp/bench.wasm
```

The runner is path-agnostic: it imports the `.mjs` companion at the
same path as the `.wasm` argument and forwards remaining argv to the
Dart `main`. Pass any flags after the `.wasm` path.

## Running both at once

For changes whose effect differs between runtimes — tight loops,
small-vs-large input crossover, optimizer-sensitive paths — compile
and run both AOT and Wasm via `tool/run_both.sh`:

```bash
tool/run_both.sh bin/bench_line_index.dart
```

It writes outputs to `/tmp/<basename>.aot` and `/tmp/<basename>.wasm`
and prints both runs back to back. Requires `deno` on PATH.

## Comparing across releases

For the JSON perf-pass workloads, the canonical comparison commits
results to `rumil_parsers/BENCHMARKS.md` against a known workstation.
Reproduce by checking out the prior tag in a worktree, running
`bench_json_perf_pass.dart` under both AOT and Wasm, then repeating on
the current branch. Run each pass separately on a quiet system; do
not run multiple bench passes in parallel.
