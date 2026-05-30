# rumil_parsers benchmarks

JSON parser performance characteristics for `rumil_parsers`. The
canonical harness is `rumil_bench`'s `bench_json_perf_pass` binary,
alongside the rest of the rumil-dart family benchmarks. Three workloads,
each tuned to surface a different path through the JSON parser:

- **integer_heavy** — 50k-element list of integers (the `JsonInt` fast
  track).
- **float_heavy** — 50k-element list of floats (the `JsonDouble` path).
- **mixed** — 50k records with int / string / bool fields (every path
  composed at once).

Each measurement is the **median of three runs**, each the mean μs/op
across 100 measured iterations following warmup. Wall clock, lower is
better; the harness's `benchWithSize` also reports MB/s, normalizing for
input size. See the root [BENCHMARKS.md](../BENCHMARKS.md) for the
rumil-vs-petitparser head-to-head and the family-wide methodology.

## 0.10.0 (current)

Hardware: AMD Ryzen 9 9950X3D, 172 GB RAM, Linux 7.0.3. Dart SDK 3.12.0.
AOT via `dart compile exe`; JIT via `dart run` (warmed); Wasm via
`dart compile wasm` run under Deno 2.7.14. Each pass ran separately on a
quiet system.

| Workload      | Input   |     AOT |     JIT |    Wasm | AOT MB/s |
|---------------|--------:|--------:|--------:|--------:|---------:|
| integer_heavy | 282 KB  | 20.8 ms | 25.9 ms | 35.5 ms |   13.9   |
| float_heavy   | 380 KB  | 22.9 ms | 28.9 ms | 41.6 ms |   16.9   |
| mixed         | 2.75 MB |  237 ms |  237 ms |  305 ms |   12.2   |

Per byte, `mixed` is close to the other two despite its larger absolute
time. Its absolute time is about 10× `integer_heavy` because the input is
about 10× larger (200k value nodes plus 50k `JsonObject` allocations vs
50k `JsonInt` allocations). Per byte,
the capture-based string parser handles each `"user_NNNN"` field in one
substring slice, and the integer-shaped `id` / `score` fields take the
`JsonInt` fast track without the `int.tryParse` + double fallback that
`integer_heavy` pays on every token.

### Runtime notes

- AOT is the fastest runtime here, as it is across the rumil-dart family
  in 0.10.0. The 0.10 engine changes (the fused `SkipLeft`/`SkipRight`
  nodes and the unified CEK trampoline) help the AOT optimizer most.
- Wasm runs about 1.3–1.8× slower than AOT on these workloads. The
  `JsonInt` / `JsonDouble` representation split helps dart2wasm separate
  integer and float code paths (i64 vs f64), so the gap is smallest on
  `mixed` (1.29×) and largest on the homogeneous numeric lists (integer
  1.71×, float 1.81×). Earlier family docs had Wasm ahead of AOT; the
  0.10 change was AOT improving, not Wasm regressing.
- JIT sits between AOT and Wasm, and matches AOT on `mixed`, where the
  working set is large enough that steady-state JIT code quality matches
  AOT.

The current shape of this parser comes from a 0.8.0 pass that split
`JsonNumber(double)` into `JsonInt` / `JsonDouble`, moved numbers and
strings onto capture-based parsing (one slice per token, fewer
intermediate allocations), and cleaned up `_lex` at every token boundary.
0.10.0 added the family-wide engine changes on top.

## Reproducing

```bash
cd rumil_bench

# AOT
dart compile exe bin/bench_json_perf_pass.dart -o /tmp/perf.aot
/tmp/perf.aot

# JIT
dart run bin/bench_json_perf_pass.dart

# Wasm — needs Deno (or another host that can call
# WebAssembly.compile on a dart2wasm output). The runner imports the
# .mjs companion alongside the .wasm argument and forwards argv to main.
dart compile wasm bin/bench_json_perf_pass.dart -o /tmp/perf.wasm
deno run --allow-read tool/run_wasm.mjs /tmp/perf.wasm
```

To compare across releases, check out the prior tag in a worktree,
backport `lib/json_perf_data.dart`, `bin/bench_json_perf_pass.dart`, and
`tool/run_wasm.mjs` into the worktree's `rumil_bench/` (the harness only
calls `parseJson`, so it is forward- and backward-compatible across AST
shapes), then run AOT, JIT, and Wasm sequentially. Use the same
workstation and a quiet system; do not run multiple bench passes in
parallel.
