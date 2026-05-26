# Rumil Benchmarks

## Methodology

Hardware: AMD Ryzen 9 9950X3D 16-Core, 172 GB RAM, Linux 6.18.20
Dart SDK: 3.11.4 (stable)
Compilation: `dart compile exe` (AOT native), `dart compile wasm` (WasmGC via Deno 2.7.12)
Warmup: 100-500 iterations discarded before measurement
Iterations: 500-100,000 depending on per-op cost (target: 1-10s total)
Reported: microseconds per operation (μs/op) and MB/s where applicable

All benchmarks live in `rumil_bench/bin/`. To reproduce:
```bash
export PATH="/path/to/dart-sdk/bin:$PATH"
cd rumil_bench
dart compile exe bin/bench_json.dart -o bench_json && ./bench_json
```

---

## Rumil vs petitparser

Same grammars, same inputs. The two libraries make different architectural choices: petitparser uses virtual method dispatch for throughput, Rumil uses a sealed ADT with an external interpreter for inspectability and extensibility.

### JSON parsing, fair comparison (AOT native, Rumil 0.7.1)

Rumil builds typed `JsonValue` AST nodes. To isolate parser dispatch overhead from AST construction cost, petitparser is benchmarked in two modes: returning raw `dynamic` values and building the same `JsonValue` types as Rumil.

| Input          | petit-raw (dynamic) | petit-typed (JsonValue) | Rumil (JsonValue) |
|----------------|---------------------|-------------------------|-------------------|
| Small (39 B)   | 2.0 μs              | 2.0 μs                  | 15.9 μs           |
| Medium (45 KB) | 2.7 ms              | 2.8 ms                  | 22.7 ms           |
| Large (803 KB) | 45 ms               | 47 ms                   | 256 ms            |

AST construction adds 3–6% to petitparser's time. The gap is almost entirely parser dispatch cost.

| Comparison                  | Small | Medium | Large |
|-----------------------------|-------|--------|-------|
| Rumil vs petit-raw          | 8.0×  | 8.4×   | 5.7×  |
| Rumil vs petit-typed (fair) | 8.0×  | 8.0×   | 5.5×  |

The large-input AOT case has now dropped below 6×. Trajectory across versions:

| Version | Small AOT | Large AOT | Notes |
|---------|----------:|----------:|-------|
| 0.6     |     ~26 × |     ~10 × | Pre-Pratt, pre-`firstCharChoice`. |
| 0.7.0   |      13 × |      10 × | Pratt, `firstCharChoice`, FIRST-set Or, fast paths. |
| 0.7.1   |     8.0 × |     5.5 × | Hot/cold split (interpreter dispatch −39 % AOT body). |

### Expression evaluation (AOT native, Rumil 0.7.1)

| Input             | rumil_expressions | petitparser | Ratio |
|-------------------|-------------------|-------------|-------|
| `1 + 2 * 3`       | 6.4 μs            | 0.75 μs     | 8.5×  |
| `((1+2)*(3+4))+5` | 20.7 μs           | 2.0 μs      | 10.6× |
| 100-term chain    | 169 μs            | 27 μs       | 6.2×  |
| 50-deep parens    | 276 μs            | 29 μs       | 9.4×  |

### Where the overhead comes from

The remaining gap is architectural. Per parser step, Rumil does a trampoline loop iteration (a type check on the current parser), a sealed-class dispatch through the `interpretI` switch (the hot/cold split keeps the hot body small), a `Success`/`Partial`/`Failure` allocation, and a continuation dispatch. Petitparser does one virtual method call.

### What Rumil offers in exchange

The interpreter architecture costs throughput but buys a different set of properties:

- **Pratt-as-a-combinator for operator precedence.** Atoms and operator symbols are ordinary Rumil parsers, composed into a `pratt(...)` node. The interpreter walks operators iteratively over an explicit frame stack — chain depth lives in heap-allocated frames, not in the Dart call stack. When every operator symbol is a literal prefix, the builder compiles a first-code-unit dispatch table with longest-prefix-first ordering and optional word-boundary or not-followed-by guards for keyword and ambiguity cases. Inspired by Lean 4's Pratt-in-combinators approach (Pratt embedded in the combinator framework, leading/trailing split, first-token dispatch). `rule()` (Warth seed-growth) is still available for directly-left-recursive grammars that don't reduce to a binding-power table.
- **Stack safety to 10 M steps, verified in CI** — see the dedicated section below.
- **Typed errors with location.** `ParseError` is a sealed hierarchy carrying line, column, and offset; backtracking branches that fail never construct their error message, thanks to nullable-cache thunks.
- **Inspectable parsers.** Sealed-ADT nodes can be analyzed and rewritten at construction time — FIRST-set `Or` rewrite, `Capture(Many)` fusion, the RadixNode in `stringChoice`, and the Pratt op-table compilation all use this.
- **Memoization.** Opt-in via `.memoize`, or automatic via `rule()`.

---

## AOT native vs dart2wasm

Same benchmarks compiled two ways.

### JSON parsing (Rumil 0.7.1)

| Input          | AOT native | WasmGC  | Wasm speedup |
|----------------|------------|---------|--------------|
| Small (39 B)   | 15.9 μs    | 5.6 μs  | 2.8× faster  |
| Medium (45 KB) | 22.7 ms    | 9.3 ms  | 2.4× faster  |
| Large (803 KB) | 256 ms     | 107 ms  | 2.4× faster  |

### Expression evaluation (Rumil 0.7.1)

| Input             | AOT native | WasmGC  | Wasm speedup |
|-------------------|------------|---------|--------------|
| `1 + 2 * 3`       | 6.4 μs     | 3.5 μs  | 1.8× faster  |
| `((1+2)*(3+4))+5` | 20.7 μs    | 9.1 μs  | 2.3× faster  |
| 100-term chain    | 169 μs     | 95 μs   | 1.8× faster  |
| 50-deep parens    | 276 μs     | 128 μs  | 2.2× faster  |

### Fair Wasm comparison (both building JsonValue AST, Rumil 0.7.1)

| Input          | Rumil (Wasm) | petit-typed (Wasm) | Ratio |
|----------------|--------------|--------------------|-------|
| Small (39 B)   | 5.6 μs       | 2.6 μs             | 2.2×  |
| Medium (45 KB) | 9.3 ms       | 3.8 ms             | 2.4×  |
| Large (803 KB) | 107 ms       | 63 ms              | 1.7×  |

### How Wasm changes the picture

|                     | AOT native | WasmGC  | Change       |
|---------------------|------------|---------|--------------|
| Rumil               | 22.7 ms    | 9.3 ms  | 2.4× faster  |
| Petitparser (typed) | 2.8 ms     | 3.8 ms  | 1.4× slower  |
| Rumil/petit ratio   | 8.0×       | 2.4×    |              |

Rumil gets ~2× faster under WasmGC. Petitparser gets ~1.4× slower. The gap narrows from 8.0× (AOT) to 2.4× (Wasm) on this workload — and to 1.7× on the 803 KB input.

Rumil's sealed class hierarchy compiles to WasmGC struct types with `br_on_cast` dispatch, which V8's WasmGC optimizer handles well. The 0.7.1 hot/cold split shrunk the interpreter dispatch hot body from 11 276 → 6 824 bytes (−39 %) AOT, making the optimizer's job easier on both backends. Interpreter optimizations (lazy line/column tracking, nullable error caches, fused `Capture(Many)`) disproportionately benefit WasmGC where write barriers and object sizes are more visible.

---

## Left recursion and stack safety

### chainl1 vs hand-rolled Pratt (AOT native, Rumil 0.7.1)

| Input      | Rumil chainl1 | Hand-rolled Pratt | Ratio |
|------------|---------------|-------------------|-------|
| 3 terms    | 6.3 μs        | 0.15 μs           | 42×   |
| 10 terms   | 17.6 μs       | 0.58 μs           | 30×   |
| 100 terms  | 163 μs        | 6.6 μs            | 25×   |
| 1000 terms | 1 639 μs      | 72 μs             | 23×   |

The hand-rolled Pratt parser is raw Dart: no parser nodes, no dispatch, no allocation per step. It sets a useful ceiling for what an interpreter that goes through a sealed-ADT switch and a continuation stack can hope to reach.

### rule(): direct left recursion

Rumil parses directly left-recursive grammars without grammar transformation, using the Warth et al. seed-growth algorithm:

```dart
// expr -> expr '+' digit | digit  (directly left-recursive)
final expr = rule(() =>
    defer(() => expr).flatMap((l) =>
        char('+').skipThen(digit().map(int.parse)).map((r) => l + r)) |
    digit().map(int.parse));
```

| Input                    | rule() time | Result |
|--------------------------|-------------|--------|
| `5` (1 term)             | 1.9 μs      | 5      |
| `1+2+3` (3 terms)        | 4.0 μs      | 6      |
| `1+2+...+9+0` (10 terms) | 11.3 μs     | 45     |
| 50 terms                 | 52 μs       | 225    |

### Stack safety: memory-bounded, not call-stack-bounded

The defunctionalized trampoline keeps the Dart call stack constant regardless of grammar depth or input length. Pratt and the chain combinators interpret iteratively, with pending operations held on a heap-allocated frame stack. The practical ceiling on chain depth is therefore available memory, not the call stack.

`rumil/test/stack_safety_test.dart` exercises every chain primitive at 10 million operands as a CI time-budget regression test (whole suite ~16 s on the reference hardware):

| Construct                                | CI depth     |
|------------------------------------------|-------------:|
| `flatMap` chain                          |  10 000 000  |
| `chainl1` (10 M `+` operands)            |  10 000 000  |
| `chainr1` (10 M `+` operands)            |  10 000 000  |
| Pratt left-associative chain             |  10 000 000  |
| Pratt right-associative chain            |  10 000 000  |
| Pratt prefix chain (10 M unary minuses)  |  10 000 000  |

The same primitives have also been validated locally at 1 000 000 000 operands (172 GB RAM, JIT with `--old_gen_heap_size=131072`). Run times scale roughly linearly; what gives out at extreme depth is heap, not stack:

| Construct                                | n             | Run time | Notes                                         |
|------------------------------------------|--------------:|---------:|-----------------------------------------------|
| `flatMap` chain                          | 1 000 000 000 |   413 s  | No input — pure trampoline + continuation     |
| `chainl1` (1 B `+`)                      | 1 000 000 000 |   114 s  | 2 GB input string                             |
| `chainr1` (1 B `+`)                      | 1 000 000 000 |   380 s  | Frame-per-step                                |
| Pratt left-associative                   | 1 000 000 000 |   104 s  | Fastest of the input-driven cases             |
| Pratt right-associative                  | 1 000 000 000 |   200 s  | 1 B `_PrattInfixFrame` live at peak           |
| Pratt prefix (`-` × 1 B)                 | 1 000 000 000 |   153 s  | 1 B `_PrattPrefixFrame` live at peak          |

These extreme-depth runs are not in CI — they take minutes and several gigabytes of memory each. They exist as a periodic sanity check that no future change has accidentally introduced a per-step Dart-recursion path that would only show up past 10 M.

---

## Format parser throughput (Rumil 0.7.1)

### AOT native

| Format    | Input                | Time     | Throughput |
|-----------|----------------------|----------|------------|
| JSON      | Small (58 B)         | 38 μs    | 1.5 MB/s   |
| CSV       | 100 rows (5 KB)      | 1.7 ms   | 3.0 MB/s   |
| CSV       | 1000 rows (98 KB)    | 14.5 ms  | 6.8 MB/s   |
| TOML      | Config (372 B)       | 229 μs   | 1.6 MB/s   |
| TOML      | 50 services (5.6 KB) | 4.1 ms   | 1.4 MB/s   |
| XML       | 20 elements (3.3 KB) | 2.6 ms   | 1.3 MB/s   |
| XML       | 200 elements (39 KB) | 28 ms    | 1.4 MB/s   |
| YAML      | Config (317 B)       | 452 μs   | 0.7 MB/s   |
| YAML      | 100 services (20 KB) | 25 ms    | 0.8 MB/s   |
| HCL       | Config (303 B)       | 212 μs   | 1.4 MB/s   |
| HCL       | 50 resources (12 KB) | 8.8 ms   | 1.4 MB/s   |
| Proto3    | Schema (499 B)       | 365 μs   | 1.4 MB/s   |
| Proto3    | 50 messages (16 KB)  | 11.3 ms  | 1.4 MB/s   |
| Markdown  | README (969 B)       | 4.4 ms   | 0.2 MB/s   |
| Markdown  | 20 sections (14 KB)  | 78 ms    | 0.2 MB/s   |

### WasmGC

| Format    | Input                | Time     | Throughput | vs AOT       |
|-----------|----------------------|----------|------------|--------------|
| JSON      | Small (58 B)         | 14.6 μs  | 4.0 MB/s   | 2.6× faster  |
| CSV       | 100 rows (5 KB)      | 862 μs   | 5.8 MB/s   | 2.0× faster  |
| CSV       | 1000 rows (98 KB)    | 9.4 ms   | 10.4 MB/s  | 1.5× faster  |
| TOML      | Config (372 B)       | 120 μs   | 3.1 MB/s   | 1.9× faster  |
| TOML      | 50 services (5.6 KB) | 2.1 ms   | 2.7 MB/s   | 2.0× faster  |
| XML       | 20 elements (3.3 KB) | 1.1 ms   | 2.9 MB/s   | 2.3× faster  |
| XML       | 200 elements (39 KB) | 13 ms    | 3.0 MB/s   | 2.1× faster  |
| YAML      | Config (317 B)       | 295 μs   | 1.1 MB/s   | 1.5× faster  |
| YAML      | 100 services (20 KB) | 15 ms    | 1.3 MB/s   | 1.6× faster  |
| HCL       | Config (303 B)       | 96 μs    | 3.2 MB/s   | 2.2× faster  |
| HCL       | 50 resources (12 KB) | 4.1 ms   | 3.0 MB/s   | 2.2× faster  |
| Proto3    | Schema (499 B)       | 169 μs   | 3.0 MB/s   | 2.2× faster  |
| Proto3    | 50 messages (16 KB)  | 5.3 ms   | 3.0 MB/s   | 2.1× faster  |
| Markdown  | README (969 B)       | 1.8 ms   | 0.5 MB/s   | 2.5× faster  |
| Markdown  | 20 sections (14 KB)  | 33 ms    | 0.4 MB/s   | 2.4× faster  |

CSV is fastest (simple grammar, no backtracking). Markdown is slowest (context-sensitive, two-pass link resolution, emphasis delimiter algorithm, heavy backtracking). WasmGC is consistently 1.5–2.6× faster than AOT native across all formats.

---

## Lazy error construction (AOT native)

The nullable-cache thunk optimization avoids constructing error messages for failing alternatives during backtracking.

| Scenario                                           | Time               |
|----------------------------------------------------|--------------------|
| 20-way Or (last matches)                           | 1.2 μs             |
| Parse invalid + access errors                      | 3.5 μs             |
| 100-object array (many failing branches per value) | 1.2 ms (2.2 MB/s)  |
| 1000-object array                                  | 12 ms (2.5 MB/s)   |

---

## Summary

As of 0.7.1, Rumil is 5.5–10× slower than petitparser on AOT native and 1.7–3.2× slower on WasmGC, depending on input size and grammar shape. The trajectory is consistently downward: 0.6 was 10–13× on AOT, 0.7.0 was 6–10×, 0.7.1 is 5.5–10× — and on the largest JSON input the AOT gap has dropped below 6×. WasmGC has narrowed from 3–4.4× in 0.7.0 to 1.7–3.2× in 0.7.1.

That is the cost of the sealed-ADT interpreter architecture. In return:

- Pratt-as-a-combinator for operator precedence, with iterative interpretation and a first-code-unit dispatch table; `rule()` (Warth seed-growth) is also available for directly-left-recursive grammars that don't reduce to a binding-power table.
- Memory-bounded stack safety: chain depth lives on heap-allocated frame stacks, not the Dart call stack. Every chain primitive is exercised at 10 M operands in CI and validated to 1 B locally.
- Typed errors with line/column/offset and lazy construction on backtracking.
- Inspectable parsers, with construction-time rewrites (FIRST-set `Or`, `Capture(Many)` fusion, RadixNode for `stringChoice`).
- Memoization, both opt-in and automatic via `rule()`.

WasmGC is consistently 1.5–2.6× faster than AOT native for Rumil. The interpreter optimizations — lazy line/column tracking, nullable error caches, fused `Capture(Many)`, and the 0.7.1 hot/cold dispatch split — disproportionately benefit WasmGC, where write barriers and per-object size are explicit costs the runtime cannot hide behind JIT speculation.

For maximum throughput on fixed formats, `dart:convert` and handwritten parsers will always be faster. Rumil is for grammars that benefit from combinator composition, precise error reporting, or stack-safety guarantees that scale into the millions.
