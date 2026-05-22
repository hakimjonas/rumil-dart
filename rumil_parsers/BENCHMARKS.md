# rumil_parsers benchmarks

JSON parser performance characteristics for `rumil_parsers`. The
canonical harness lives in `rumil_bench`'s `bench_json_perf_pass`
binary alongside the rest of the rumil-dart family benchmarks. Three
workloads tuned to surface the 0.8.0 perf changes:

- **integer_heavy** — 50k-element list of integers (JsonInt fast track).
- **float_heavy** — 50k-element list of floats (JsonDouble path).
- **mixed** — 50k records with int / string / bool fields (every path).

Each measurement is the mean μs/op across 100 measured iterations
following 100 warmup iterations. Wall clock; lower is better. The
bench harness's `benchWithSize` reports MB/s alongside, normalising
for input size.

## 0.7.0 → 0.8.0

Workstation: Linux x86_64. Dart SDK 3.11.4. Each pass ran separately
on a quiet system. AOT via `dart compile exe`; Wasm via `dart compile
wasm` invoked through `rumil_bench/tool/run_wasm.mjs` under Deno.

### AOT

| Workload       | Input   | 0.7.0 (ms) | 0.8.0 (ms) | Speedup | 0.8.0 MB/s |
|----------------|--------:|-----------:|-----------:|--------:|-----------:|
| integer_heavy  | 282 KB  |     162.1  |     154.5  |  1.05×  |       1.9  |
| float_heavy    | 380 KB  |     189.2  |     179.5  |  1.05×  |       2.2  |
| mixed          | 2.75 MB |    1368    |    1115    |  1.23×  |       2.6  |

### Wasm

| Workload       | Input   | 0.7.0 (ms) | 0.8.0 (ms) | Speedup | 0.8.0 MB/s |
|----------------|--------:|-----------:|-----------:|--------:|-----------:|
| integer_heavy  | 282 KB  |      86.8  |      64.7  |  1.34×  |       4.5  |
| float_heavy    | 380 KB  |      96.0  |      76.9  |  1.25×  |       5.1  |
| mixed          | 2.75 MB |     609.4  |     430.3  |  1.42×  |       6.7  |

The MB/s column inverts the absolute-time framing: **mixed is the
fastest workload per byte** under both AOT and Wasm. The new
capture-based string parser handles the `"user_NNNN"` field in one
substring slice per string, and the integer-shaped `id` / `score`
fields take the JsonInt fast track without the int.tryParse + double
fallback that integer_heavy pays on every token. The absolute mixed
time is ~7× the integer_heavy time because the input is ~10× larger
(200k value nodes plus 50k JsonObject allocations vs 50k JsonInt
allocations).

The Wasm column carries the larger relative wins. The JsonInt /
JsonDouble split lets dart2wasm specialize integer-vs-float code paths
through the parser pipeline (i64 vs f64 separation), which the
flattened `JsonNumber(double)` representation in 0.7.0 forced into a
single homogeneous f64 path. The capture-based number and string
parsers compound the effect: fewer intermediate allocations means
fewer Wasm GC interactions per token. The mixed workload composes
every optimization in this release at once (JsonInt/JsonDouble split
on `id`/`score`, capture-based numbers, capture-based strings on
`name`, `_lex` cleanup at every token boundary) and shows the largest
relative win — 1.42× on Wasm.

The AOT column is more modest because Dart's AOT pipeline already
specializes well on monomorphic call sites; the win surfaces under
Wasm's stricter type-flow story.

## Reproducing

```bash
# AOT
cd rumil_bench
dart compile exe bin/bench_json_perf_pass.dart -o /tmp/perf.aot
/tmp/perf.aot

# Wasm — needs Deno (or another JS host that can call
# WebAssembly.compile on a dart2wasm output). The runner is
# path-agnostic; it imports the .mjs companion alongside the .wasm
# argument and forwards remaining argv to the Dart `main`.
cd rumil_bench
dart compile wasm bin/bench_json_perf_pass.dart -o /tmp/perf.wasm
deno run --allow-read tool/run_wasm.mjs /tmp/perf.wasm
```

To compare across releases, check out the prior tag in a worktree,
backport `lib/json_perf_data.dart`, `bin/bench_json_perf_pass.dart`,
and `tool/run_wasm.mjs` into the worktree's `rumil_bench/` (the
harness only calls `parseJson`, so it is forward- and
backward-compatible across AST shapes), then run AOT and Wasm
sequentially. Use the same workstation and a quiet system; do not
run multiple bench passes in parallel.
