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

### JSON parsing, fair comparison (AOT native)

Rumil builds typed `JsonValue` AST nodes. To isolate parser dispatch overhead from AST construction cost, petitparser is benchmarked in two modes: returning raw `dynamic` values and building the same `JsonValue` types as Rumil.

| Input          | petit-raw (dynamic) | petit-typed (JsonValue) | Rumil (JsonValue) |
|----------------|---------------------|-------------------------|-------------------|
| Small (39 B)   | 2.0 μs              | 2.1 μs                  | 26 μs             |
| Medium (45 KB) | 2.9 ms              | 3.1 ms                  | 38 ms             |
| Large (803 KB) | 48 ms               | 50 ms                   | 478 ms            |

AST construction adds 3-6% to petitparser's time. The gap is almost entirely parser dispatch cost.

| Comparison                  | Small | Medium | Large |
|-----------------------------|-------|--------|-------|
| Rumil vs petit-raw          | 13x   | 13x    | 10x   |
| Rumil vs petit-typed (fair) | 12x   | 12x    | 10x   |

### Expression evaluation (AOT native)

| Input             | Rumil (parse+AST+eval) | Petitparser (parse+eval) | Ratio |
|-------------------|------------------------|--------------------------|-------|
| `1 + 2 * 3`       | 11 μs                  | 1.0 μs                   | 11x   |
| `((1+2)*(3+4))+5` | 34 μs                  | 2.0 μs                   | 17x   |
| 100-term chain    | 320 μs                 | 28 μs                    | 11x   |
| 50-deep parens    | 480 μs                 | 29 μs                    | 17x   |

### Where the overhead comes from

The 10-13x gap is architectural. Per parser step, Rumil does:
1. Trampoline loop iteration (while + is-check on `currentParser`)
2. `interpretI` switch (26-case sealed class dispatch)
3. Result construction (Success/Partial/Failure allocation)
4. Continuation switch (7-case `_Cont` dispatch)

Petitparser does one virtual method call (`parseOn`).

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
| Small (39 B)   | 26 μs      | 18 μs   | 1.4x faster  |
| Medium (45 KB) | 38 ms      | 28 ms   | 1.4x faster  |
| Large (803 KB) | 478 ms     | 371 ms  | 1.3x faster  |

### Expression evaluation

| Input             | AOT native | WasmGC  | Wasm speedup |
|-------------------|------------|---------|--------------|
| `1 + 2 * 3`       | 11 μs      | 7.7 μs  | 1.4x faster  |
| `((1+2)*(3+4))+5` | 34 μs      | 25 μs   | 1.4x faster  |
| 100-term chain    | 320 μs     | 279 μs  | 1.1x faster  |
| 50-deep parens    | 480 μs     | 390 μs  | 1.2x faster  |

### Fair Wasm comparison (both building JsonValue AST)

| Input          | Rumil (Wasm) | petit-typed (Wasm) | Ratio |
|----------------|--------------|--------------------|-------|
| Small (39 B)   | 18 μs        | 5.0 μs             | 3.6x  |
| Medium (45 KB) | 28 ms        | 7.3 ms             | 3.8x  |
| Large (803 KB) | 371 ms       | 120 ms             | 3.1x  |

### How Wasm changes the picture

|                     | AOT native | WasmGC  | Change       |
|---------------------|------------|---------|--------------|
| Rumil               | 38 ms      | 28 ms   | 1.4x faster  |
| Petitparser (typed) | 3.1 ms     | 7.3 ms  | 2.4x slower  |
| Rumil/petit ratio   | 12x        | 3.8x    |              |

Rumil gets ~1.4x faster under WasmGC. Petitparser gets ~2.4x slower. The gap narrows from 12x (AOT) to 3.8x (Wasm).

Likely explanation: Rumil's sealed class hierarchy compiles to WasmGC struct types with `br_on_cast` dispatch, which V8's WasmGC optimizer handles well. Petitparser's virtual dispatch compiles to indirect `call_ref`, which WasmGC optimizes less aggressively.

---

## Left recursion

### chainl1 vs hand-rolled Pratt (AOT native)

| Input      | Rumil chainl1 | Hand-rolled Pratt | Ratio |
|------------|---------------|-------------------|-------|
| 3 terms    | 14 μs         | 0.48 μs           | 30x   |
| 10 terms   | 32 μs         | 0.30 μs           | 105x  |
| 100 terms  | 306 μs        | 3.8 μs            | 82x   |
| 1000 terms | 4,794 μs      | 43 μs             | 111x  |

The Pratt parser is raw Dart with no abstraction: no parser nodes, no dispatch, no allocation. No combinator library can match it. This is the ceiling.

### rule(): left recursion that petitparser cannot express

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
| `5` (1 term)             | 6.9 μs      | 5      |
| `1+2+3` (3 terms)        | 3.6 μs      | 6      |
| `1+2+...+9+0` (10 terms) | 7.1 μs      | 45     |
| 50 terms                 | 32 μs       | 225    |

---

## Format parser throughput

### AOT native

| Format    | Input                | Time     | Throughput |
|-----------|----------------------|----------|------------|
| CSV       | 100 rows (5 KB)      | 1.4 ms   | 3.5 MB/s   |
| CSV       | 1000 rows (98 KB)    | 22 ms    | 4.4 MB/s   |
| TOML      | Config (372 B)       | 254 μs   | 1.5 MB/s   |
| TOML      | 50 services (5.6 KB) | 4.6 ms   | 1.2 MB/s   |
| XML       | 20 elements (3.3 KB) | 2.6 ms   | 1.3 MB/s   |
| XML       | 200 elements (39 KB) | 28 ms    | 1.4 MB/s   |
| YAML      | Config (317 B)       | 539 μs   | 0.6 MB/s   |
| YAML      | 100 services (20 KB) | 29 ms    | 0.7 MB/s   |
| HCL       | Config (303 B)       | 273 μs   | 1.1 MB/s   |
| HCL       | 50 resources (12 KB) | 11 ms    | 1.1 MB/s   |
| Proto3    | Schema (499 B)       | 416 μs   | 1.2 MB/s   |
| Proto3    | 50 messages (16 KB)  | 13 ms    | 1.2 MB/s   |

### WasmGC

| Format    | Input                | Time     | Throughput | vs AOT       |
|-----------|----------------------|----------|------------|--------------|
| CSV       | 100 rows (5 KB)      | 1.4 ms   | 3.5 MB/s   | 1.0x         |
| CSV       | 1000 rows (98 KB)    | 27 ms    | 3.7 MB/s   | 0.8x slower  |
| TOML      | Config (372 B)       | 234 μs   | 1.6 MB/s   | 1.1x faster  |
| TOML      | 50 services (5.6 KB) | 4.3 ms   | 1.3 MB/s   | 1.1x faster  |
| XML       | 20 elements (3.3 KB) | 1.9 ms   | 1.7 MB/s   | 1.3x faster  |
| XML       | 200 elements (39 KB) | 22 ms    | 1.7 MB/s   | 1.2x faster  |
| YAML      | Config (317 B)       | 425 μs   | 0.7 MB/s   | 1.2x faster  |
| YAML      | 100 services (20 KB) | 25 ms    | 0.8 MB/s   | 1.1x faster  |
| HCL       | Config (303 B)       | 188 μs   | 1.6 MB/s   | 1.5x faster  |
| HCL       | 50 resources (12 KB) | 8.1 ms   | 1.5 MB/s   | 1.4x faster  |
| Proto3    | Schema (499 B)       | 278 μs   | 1.8 MB/s   | 1.5x faster  |
| Proto3    | 50 messages (16 KB)  | 8.9 ms   | 1.8 MB/s   | 1.5x faster  |

CSV is fastest (simple grammar, no backtracking). YAML is slowest (indentation-sensitive, heavy backtracking). WasmGC is 1.1-1.5x faster than AOT native for most formats.

---

## Lazy error construction (AOT native)

The `late final` thunk optimization avoids constructing error messages for failing alternatives during backtracking.

| Scenario                                           | Time               |
|----------------------------------------------------|--------------------|
| 20-way Or (last matches)                           | 1.2 μs             |
| Parse invalid + access errors                      | 3.5 μs             |
| 100-object array (many failing branches per value) | 1.2 ms (2.2 MB/s)  |
| 1000-object array                                  | 12 ms (2.5 MB/s)   |

---

## Summary

Rumil is 10-12x slower than petitparser on AOT native and 3-4x slower on WasmGC. This is the cost of the sealed ADT interpreter architecture that enables typed errors, left recursion, parser inspection, memoization, and stack safety.

WasmGC narrows the gap because V8 optimizes sealed class dispatch (`br_on_cast`) better than Dart AOT does, while petitparser's virtual dispatch compiles less efficiently to WasmGC indirect calls.

For maximum throughput on fixed formats, use `dart:convert` or handwritten parsers. Rumil is for grammars that need combinator composition, precise error reporting, or left recursion.
