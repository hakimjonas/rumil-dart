# Rumil Benchmarks

## Methodology

Hardware: AMD Ryzen 9 9950X3D 16-Core, 172 GB RAM, Linux 6.18.20
Dart SDK: 3.11.4 (stable)
Compilation: `dart compile exe` (AOT native), `dart compile wasm` (WasmGC via Deno 2.7.11)
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

### JSON parsing, fair comparison (AOT native)

Rumil builds typed `JsonValue` AST nodes. To isolate parser dispatch overhead from AST construction cost, petitparser is benchmarked in two modes: returning raw `dynamic` values and building the same `JsonValue` types as Rumil.

| Input          | petit-raw (dynamic) | petit-typed (JsonValue) | Rumil (JsonValue) |
|----------------|---------------------|-------------------------|-------------------|
| Small (39 B)   | 2.0 μs              | 2.0 μs                  | 25.5 μs           |
| Medium (45 KB) | 2.7 ms              | 2.8 ms                  | 35.7 ms           |
| Large (803 KB) | 42 ms               | 44 ms                   | 452 ms            |

AST construction adds 3-4% to petitparser's time. It is not a significant factor. The gap is almost entirely parser dispatch cost.

| Comparison                  | Small | Medium | Large |
|-----------------------------|-------|--------|-------|
| Rumil vs petit-raw          | 13x   | 13x    | 11x   |
| Rumil vs petit-typed (fair) | 13x   | 13x    | 10x   |

### Expression evaluation (AOT native)

Rumil builds an `Expr` AST that can be inspected and transformed, then evaluates it in a second pass. Petitparser's `ExpressionBuilder` evaluates in a single pass with inline callbacks. This is a design tradeoff: Rumil gives you an AST, petitparser gives you speed.

| Input             | Rumil (parse+AST+eval) | Petitparser (parse+eval) | Ratio |
|-------------------|------------------------|--------------------------|-------|
| `1 + 2 * 3`       | 10.1 μs                | 0.75 μs                  | 13x   |
| `((1+2)*(3+4))+5` | 32.5 μs                | 1.9 μs                   | 17x   |
| 100-term chain    | 300 μs                 | 27 μs                    | 11x   |
| 50-deep parens    | 460 μs                 | 30 μs                    | 15x   |

### Where the overhead comes from

The 10-13x gap is architectural. Per parser step, Rumil does:
1. Trampoline loop iteration (while + is-check on `currentParser`)
2. `interpretI` switch (26-case sealed class dispatch)
3. Result construction (Success/Partial/Failure allocation)
4. Continuation switch (7-case `_Cont` dispatch)

Petitparser does one virtual method call (`parseOn`), which is why it's faster per step.

### Different tradeoffs

Petitparser optimizes for throughput via virtual dispatch and mutable parser graphs. Rumil optimizes for a different set of properties via sealed ADT and an external interpreter:

- Left recursion (`rule()`) via Warth seed-growth
- Typed errors with location (`ParseError` sealed hierarchy with line/column/offset)
- Stack safety via defunctionalized trampoline (tested to 10M depth)
- Lazy error construction (`late final` thunks skip error building on backtracking success paths)
- Parser inspection (ADT nodes can be analyzed, transformed, and optimized at construction time)
- Memoization (opt-in with `.memoize` or automatic via `rule()`)

---

## AOT native vs dart2wasm

Same benchmarks compiled two ways.

### JSON parsing

| Input          | AOT native | WasmGC  | Wasm speedup |
|----------------|------------|---------|--------------|
| Small (39 B)   | 24.6 μs    | 10.8 μs | 2.3x faster  |
| Medium (45 KB) | 35.3 ms    | 17.3 ms | 2.0x faster  |
| Large (803 KB) | 449 ms     | 225 ms  | 2.0x faster  |

### Expression evaluation

| Input             | AOT native | WasmGC  | Wasm speedup |
|-------------------|------------|---------|--------------|
| `1 + 2 * 3`       | 10.1 μs    | 5.4 μs  | 1.9x faster  |
| `((1+2)*(3+4))+5` | 32.5 μs    | 16.6 μs | 2.0x faster  |
| 100-term chain    | 300 μs     | 173 μs  | 1.7x faster  |
| 50-deep parens    | 460 μs     | 249 μs  | 1.8x faster  |

### Fair Wasm comparison (both building JsonValue AST)

| Input          | Rumil (Wasm) | petit-typed (Wasm) | Ratio |
|----------------|--------------|--------------------|-------|
| Small (39 B)   | 11.2 μs      | 2.5 μs             | 4.5x  |
| Medium (45 KB) | 17.9 ms      | 3.8 ms             | 4.7x  |
| Large (803 KB) | 242 ms       | 66 ms              | 3.6x  |

### How Wasm changes the picture

|                     | AOT native | WasmGC  | Change      |
|---------------------|------------|---------|-------------|
| Rumil               | 35.7 ms    | 17.9 ms | 2.0x faster |
| Petitparser (typed) | 2.8 ms     | 3.8 ms  | 36% slower  |
| Rumil/petit ratio   | 13x        | 4.7x    |             |

Rumil gets 2x faster under WasmGC. Petitparser gets 36% slower. The gap narrows from 13x (AOT) to 4.7x (Wasm).

Likely explanation: Rumil's sealed class hierarchy compiles to WasmGC struct types with `br_on_cast` dispatch, which V8's WasmGC optimizer handles well. Petitparser's virtual dispatch compiles to indirect `call_ref`, which WasmGC optimizes less aggressively.

This is a good signal for dart2wasm: idiomatic Dart 3 patterns (sealed classes, exhaustive switch, final fields) map well to WasmGC primitives.

---

## Left recursion

### chainl1 vs hand-rolled Pratt (AOT native)

| Input      | Rumil chainl1 | Hand-rolled Pratt | Ratio |
|------------|---------------|-------------------|-------|
| 3 terms    | 10.4 μs       | 0.15 μs           | 69x   |
| 10 terms   | 30.0 μs       | 0.56 μs           | 54x   |
| 100 terms  | 300 μs        | 6.3 μs            | 48x   |
| 1000 terms | 4,272 μs      | 69 μs             | 62x   |

The Pratt parser is raw Dart with no abstraction: no parser nodes, no dispatch, no allocation. No combinator library can match it. This is the ceiling.

### rule(): left recursion that petitparser cannot express

Rumil's `rule()` handles directly left-recursive grammars via Warth seed-growth:

```dart
// expr -> expr '+' digit | digit
// Directly left-recursive. Petitparser's ExpressionBuilder
// uses precedence climbing instead. Rumil handles it as written.
final expr = rule(() =>
    defer(() => expr).flatMap((l) =>
        char('+').skipThen(digit().map(int.parse)).map((r) => l + r)) |
    digit().map(int.parse));
```

| Input                    | rule() time | Result |
|--------------------------|-------------|--------|
| `5` (1 term)             | 1.8 μs      | 5      |
| `1+2+3` (3 terms)        | 3.8 μs      | 6      |
| `1+2+...+9+0` (10 terms) | 10.5 μs     | 45     |
| 50 terms                 | 48.7 μs     | 225    |

This is a capability comparison. Petitparser's `ExpressionBuilder` handles operator precedence well but requires the grammar to be written in a specific way. Rumil accepts the grammar as-is.

---

## Format parser throughput (AOT native)

No petitparser comparison. It does not have these formats.

| Format | Input                | Time    | Throughput |
|--------|----------------------|---------|------------|
| CSV    | 100 rows (5 KB)      | 1.3 ms  | 3.9 MB/s   |
| CSV    | 1000 rows (98 KB)    | 21.5 ms | 4.6 MB/s   |
| TOML   | Config (372 B)       | 203 μs  | 1.8 MB/s   |
| TOML   | 50 services (5.6 KB) | 3.6 ms  | 1.5 MB/s   |
| XML    | 20 elements (3.3 KB) | 2.1 ms  | 1.6 MB/s   |
| XML    | 200 elements (39 KB) | 22.6 ms | 1.7 MB/s   |

CSV is fastest (simple grammar, no backtracking). XML and TOML are similar (more alternation and nesting).

---

## Lazy error construction (AOT native)

The `late final` thunk optimization avoids constructing error messages for failing alternatives during backtracking.

| Scenario                                           | Time               |
|----------------------------------------------------|--------------------|
| 20-way Or (last matches)                           | 0.92 μs            |
| Parse invalid + access errors                      | 2.85 μs            |
| 100-object array (many failing branches per value) | 1.4 ms (1.9 MB/s)  |
| 1000-object array                                  | 13.8 ms (2.1 MB/s) |

The 20-way Or test shows negligible overhead from lazy thunks on the success path. 19 error thunks are constructed but never evaluated.

---

## Optimization trajectory

Measured on JSON medium (45 KB) during development:

| Optimization                                 | Time    | vs petitparser | Cumulative     |
|----------------------------------------------|---------|----------------|----------------|
| Baseline (recursive interpretI)              | 111 ms  | 42x            | 1.0x           |
| Trampoline for all FlatMap/Mapped/Zip        | 45 ms   | 17x            | 2.5x           |
| Construction-time map/flatMap fusion         | 45 ms   | 17x            | ~0% additional |
| Fused Satisfy scan (Many(Satisfy) fast path) | 35.5 ms | 13x            | 3.1x           |
| regionMatches (avoid substring alloc)        | 35.3 ms | 13x            | 3.1x           |

The trampoline fix was the biggest win at 2.5x. It eliminated recursive `interpretWith` callback chains that caused both stack overflow and unnecessary overhead. The fused Satisfy scan gave another 21% by replacing per-character interpreter dispatch with a tight loop.

---

## Summary

Rumil is 10-13x slower than petitparser on AOT native and 4-5x slower on WasmGC. This is the cost of the sealed ADT interpreter architecture that enables typed errors, left recursion, parser inspection, memoization, and stack safety.

For maximum throughput on fixed formats, use `dart:convert` or handwritten parsers. Rumil is for grammars that need combinator composition, precise error reporting, or left recursion.
