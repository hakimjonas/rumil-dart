# Rumil Benchmarks

## Methodology

Hardware: AMD Ryzen 9 9950X3D 16-Core, 172 GB RAM, Linux 7.0.3
Dart SDK: 3.12.0 (stable)
Execution modes:
- AOT native (`dart compile exe`)
- JIT (`dart run`, warmed; steady-state, not cold-start)
- Wasm (`dart compile wasm`, WasmGC), run under Deno 2.7.14

Every parser is warmed on every input before timing. Iterations run from
100 to 50,000 depending on per-op cost. Each number is the median of
three separate runs on a quiet system; runs were not executed in
parallel. Reported in microseconds per operation (μs/op) and MB/s where
applicable.

Benchmarks live in `rumil_bench/bin/`. To reproduce, e.g.:
```bash
cd rumil_bench
# AOT
dart compile exe bin/bench_petit_turf.dart -o /tmp/turf && /tmp/turf
# JIT
dart run bin/bench_petit_turf.dart
# Wasm (needs Deno)
dart compile wasm bin/bench_petit_turf.dart -o /tmp/turf.wasm
deno run --allow-read tool/run_wasm.mjs /tmp/turf.wasm
```

0.10.0 changed two things about the numbers below. The engine is about
2× faster than 0.9.0, from the fused `skipThen`/`thenSkip` nodes and the
unified CEK trampoline (which removed per-token record allocation and
per-sub-parse interpreter re-entry). And because those changes help the
AOT optimizer most, AOT is now the fastest of the three runtimes on most
workloads, where earlier releases had WasmGC ahead. All numbers below
are from 0.10.0.

---

## Rumil vs petitparser

Measured with `bench_petit_turf.dart`. Each library runs its own
idiomatic parser on petitparser's own grammars and inputs; every compared
pair produces output verified equal at runtime before timing; parsers are
warmed on every input; and run order is rotated so no parser pays a
cold-start or first-runner penalty.

The two libraries make different choices, so two axes are reported:

- **to-typed** (engine vs engine): both `parseJson` (Rumil) and a
  hand-written petitparser grammar build the same typed `JsonValue` AST
  in one pass. This isolates the parser engine from AST-shape cost.
- **to-native** (plain `Map`/`List`/`num`): Rumil makes two passes (parse
  to `JsonValue`, then `jsonToNative`) because it always builds a typed
  tree first, while petitparser's `JsonDefinition` builds `Map`/`List` in
  one pass. `dart:convert` is the baseline. This axis reflects the cost
  if all you want is native data.

The to-native axis favors petitparser (Rumil does an extra pass it does
not), so both are shown rather than one.

### JSON to-typed — engine vs engine (μs/op; both build `JsonValue`)

Cell is **rumil / petit**.

| Input            |        AOT |        JIT |       Wasm |
|------------------|-----------:|-----------:|-----------:|
| array (55 B)     |  6.2 / 3.5 |  8.3 / 3.6 |  8.8 / 4.9 |
| object (56 B)    |  6.5 / 3.0 |  6.9 / 3.0 |  8.1 / 4.5 |
| event (636 B)    | 34.6 /29.6 | 34.3 /30.1 | 43.0 /37.7 |
| donut (476 B)    | 35.9 /28.6 | 38.6 /29.0 | 37.6 /35.2 |
| large (47.7 KB)  | 3736 /2931 | 3919 /2994 | 4678 /4189 |

Engine ratio on the large document: AOT 1.27×, JIT 1.31×, Wasm 1.12×. The
gap is widest on tiny number-dense inputs, where per-parse dispatch
dominates, and narrowest on sustained throughput.

### JSON to-native — plain `Map`/`List` (μs/op)

Cell is **rumil (2-pass) / petit (1-pass) / `dart:convert`**.

| Input            |              AOT |              JIT |             Wasm |
|------------------|-----------------:|-----------------:|-----------------:|
| array (55 B)     |   9.2 / 2.3 / 0.2 |   8.6 / 2.1 / 0.2 |   9.4 / 3.8 / 0.3 |
| object (56 B)    |   8.2 / 2.0 / 0.3 |   7.4 / 2.0 / 0.3 |   8.9 / 3.5 / 0.4 |
| event (636 B)    |  42.9 /17.4 / 1.9 |  36.6 /16.9 / 1.8 |  45.5 /25.7 / 1.5 |
| donut (476 B)    |  45.7 /14.7 / 2.1 |  40.3 /14.0 / 2.1 |  40.6 /19.6 / 1.4 |
| large (47.7 KB)  |  4870 /1492 / 206 |  4306 /1415 / 209 |  5111 /2294 / 122 |

To-native ratio on the large document vs petitparser: AOT 3.26×, JIT
3.04×, Wasm 2.23×. Most of this is the second pass. `dart:convert` is a
hand-tuned native decoder and is the right choice when you only want
`Map`/`List`; Rumil is for grammars that benefit from a typed,
inspectable tree.

### CSV (μs/op; both build `List<List<String>>`)

| Input            |        AOT |        JIT |       Wasm |
|------------------|-----------:|-----------:|-----------:|
| csv-10 (309 B)   | 28.9 /10.3 | 31.8 / 8.9 | 33.0 /13.5 |
| csv-1000 (40 KB) | 3267 /1304 | 3705 /1135 | 4138 /1756 |

---

## Expression evaluation

`bench_expr.dart`. `rumil_expr` is `rumil_expressions`: `pratt(...)` with
prefix unary, six binary precedence levels, and a ternary on top.
`pratt-arith` is a bare-arithmetic Pratt parser with no whitespace
wrappers, included as a no-`_lex` reference. `petit` is petitparser's
`ExpressionBuilder`.

μs/op:

| Input             | rumil_expr (AOT/JIT/Wasm) | pratt-arith | petit |
|-------------------|--------------------------:|------------:|------:|
| `1 + 2 * 3`       |        3.2 / 5.2 / 4.2     | 1.6/2.7/2.3 | 0.8/0.8/1.1 |
| `((1+2)*(3+4))+5` |        8.9 / 13.7 / 11.4   | 4.3/7.0/6.3 | 1.9/1.8/2.6 |
| 100-term chain    |       110 / 168 / 147      |  38/56/60   | 27/26/44 |
| 50-deep parens    |       121 / 183 / 172      |  57/89/88   | 29/24/38 |

`rumil_expr` carries a fixed per-token cost for the full operator table
and whitespace handling. The `pratt-arith` lane shows that roughly half
of `rumil_expr`'s time is that wrapper overhead, not the Pratt engine.
Against petitparser's `ExpressionBuilder`, the full `rumil_expressions`
is about 4× on AOT and 3.4× on Wasm for simple inputs, narrowing as input
grows.

---

## Format parser throughput

`bench_formats.dart`, all eight `rumil_parsers` formats. Time is μs/op
for sub-millisecond cases and ms/op otherwise; MB/s is AOT, for size
normalization.

| Format    | Input                |     AOT |     JIT |    Wasm | AOT MB/s |
|-----------|----------------------|--------:|--------:|--------:|---------:|
| JSON      | small (58 B)         |  6.7 μs | 19.0 μs |  8.5 μs |   8.7    |
| CSV       | 100 rows (5.0 KB)    |  602 μs |  712 μs |  743 μs |   8.3    |
| CSV       | 1000 rows (98 KB)    | 6.93 ms | 8.07 ms | 9.88 ms |  14.1    |
| TOML      | config (372 B)       |   78 μs |  101 μs |   90 μs |   4.8    |
| TOML      | 50 services (5.6 KB) | 1.34 ms | 1.59 ms | 1.55 ms |   4.2    |
| XML       | 20 elements (3.3 KB) |  768 μs |  811 μs |  805 μs |   4.3    |
| XML       | 200 elements (39 KB) | 8.57 ms | 9.30 ms | 9.75 ms |   4.5    |
| YAML      | config (317 B)       |  224 μs |  215 μs |  231 μs |   1.4    |
| YAML      | 100 services (20 KB) | 11.7 ms | 12.1 ms | 13.0 ms |   1.7    |
| HCL       | config (303 B)       |   73 μs |   97 μs |   86 μs |   4.2    |
| HCL       | 50 resources (12 KB) | 2.98 ms | 3.69 ms | 3.71 ms |   4.1    |
| Proto3    | schema (499 B)       |  104 μs |  129 μs |  123 μs |   4.8    |
| Proto3    | 50 messages (16 KB)  | 3.17 ms | 3.86 ms | 3.89 ms |   5.0    |
| Markdown  | README (969 B)       | 1.41 ms | 1.71 ms | 1.33 ms |   0.7    |
| Markdown  | 20 sections (14 KB)  | 26.2 ms | 30.8 ms | 25.5 ms |   0.6    |

CSV is fastest per byte (simple grammar, no backtracking). Markdown is
slowest (context-sensitive, two-pass link resolution, emphasis delimiter
algorithm, heavy backtracking), and is the one format where Wasm runs
slightly faster than AOT (about 3–6%).

---

## AOT vs JIT vs Wasm

Earlier releases had WasmGC ahead of AOT for Rumil. In 0.10.0 the order
changed: the fused `SkipLeft`/`SkipRight` nodes and the unified CEK
trampoline reduce dispatch and allocation, and the AOT optimizer benefits
from that more than dart2wasm does, so AOT moved ahead on most workloads.
Wasm did not regress in absolute terms; AOT gained more.

| Workload (Rumil)                | Wasm / AOT | JIT / AOT |
|---------------------------------|-----------:|----------:|
| JSON to-typed, large            |     1.25×  |    1.05×  |
| Expression, 100-term chain      |     1.33×  |    1.52×  |
| chainl1, 100 terms              |     1.29×  |    1.43×  |
| Format suite (typical)          | 1.05–1.43× | 1.0–1.3×  |
| `rumil_parsers` integer_heavy   |     1.71×  |    1.25×  |
| Markdown (20 sections)          |     0.97×  |    1.17×  |

(>1 means AOT is faster.) Rumil on Wasm runs about 1.05–1.8× slower than
on AOT, depending on workload; Markdown is slightly faster on Wasm, and a
few cases are near parity (YAML config, small XML). This is a modest tax,
not a large one.

Two things about the WasmGC behavior are worth recording, since they
bear on whether Rumil fits a Wasm target:

- Rumil's dispatch degrades less under WasmGC than petitparser's does.
  From AOT to Wasm on the large to-typed document, Rumil slows by 1.25×
  while petitparser slows by 1.43×. The rumil:petit ratio therefore
  narrows from 1.27× on AOT to 1.12× on Wasm. Rumil's sealed-ADT
  `br_on_cast` dispatch maps onto WasmGC more directly than petitparser's
  virtual dispatch.
- WasmGC is not a penalty here. `dart:convert`'s native JSON decoder is
  faster on Wasm than on AOT in these runs (122 vs 206 μs on the large
  document), and Markdown is faster on Wasm for
  Rumil. The 0.10.0 reversal is about AOT improving, not Wasm being slow.

---

## Left recursion and stack safety

### chainl1 vs hand-rolled Pratt (μs/op)

`bench_lr.dart`. The hand-rolled Pratt parser is raw Dart, with no parser
nodes, dispatch, or per-step allocation. It sets a lower bound for an
interpreter that goes through a sealed-ADT switch and a continuation
chain.

| Input      | rumil chainl1 (AOT/JIT/Wasm) | manual Pratt |
|------------|-----------------------------:|-------------:|
| 3 terms    |          3.3 / 16.8 / 6.8     | 0.14/0.41/0.76 |
| 10 terms   |         11.3 / 16.6 / 15.6     | 0.57/0.31/1.16 |
| 100 terms  |          115 / 164 / 148       |  6.5/3.8/12.2  |
| 1000 terms |         1206 / 1709 / 1649      |  70/43/124     |

### rule(): direct left recursion (μs/op, AOT)

Rumil parses directly left-recursive grammars without grammar
transformation, using the Warth et al. seed-growth algorithm.
petitparser's `ExpressionBuilder` does not support this directly; it
rewrites such grammars into precedence climbing.

```dart
// expr -> expr '+' digit | digit  (directly left-recursive)
final expr = rule(() =>
    defer(() => expr).flatMap((l) =>
        char('+').skipThen(digit().map(int.parse)).map((r) => l + r)) |
    digit().map(int.parse));
```

| Input    | AOT  | JIT  | Wasm |
|----------|-----:|-----:|-----:|
| 1 term   | 0.6  | 10.8 | 1.4  |
| 3 terms  | 1.1  | 2.7  | 1.8  |
| 10 terms | 2.9  | 3.3  | 3.6  |
| 50 terms | 12.9 | 14.2 | 15.7 |

### rule() vs chainl1 vs pratt, same grammar (μs/op)

The three strategies are usually written over different grammars, which
makes them hard to compare directly. `bench_lr_vs_pratt.dart` puts them
on one grammar (`expr -> expr '+' digit | digit`, a left-associative sum
of single digits) expressed three ways: `rule()` (Warth seed-growth),
`chainl1` (the flat left-fold), and `pratt` (the operator-precedence
table). All three return the same sum on the same input, verified before
timing. Median μs/op:

| Terms |  rule() (AOT/JIT/Wasm) |    chainl1 |      pratt |
|-------|-----------------------:|-----------:|-----------:|
| 10    |     2.34 / 3.11 / 2.93 | 0.58/1.00/0.97 | 0.66/0.76/0.83 |
| 50    |   10.19 / 13.52 / 11.69 | 2.96/4.68/4.36 | 3.35/3.51/3.88 |
| 100   |   19.92 / 26.79 / 22.31 | 5.91/9.24/8.64 | 6.64/6.99/7.72 |
| 300   |   57.26 / 80.23 / 65.67 | 17.33/27.97/25.42 | 19.96/21.17/22.82 |

On this grammar `rule()` is the slowest of the three on every runtime
and size, about 2.9× (AOT, Wasm) to 3.8× (JIT) slower than `pratt` at
300 terms. Seed-growth memoizes and re-runs a growing seed per position,
while `chainl1` and `pratt` fold iteratively in one pass. Between the two
iterative strategies the order depends on the runtime: `chainl1` is
slightly ahead on AOT (about 1.13×), `pratt` slightly ahead on JIT and
Wasm (about 0.76× and 0.89×).

This grammar reduces to a binding-power table, so `pratt` or `chainl1`
is the better choice for it. `rule()` accepts directly-left-recursive
grammars written in their natural form, without first rewriting them into
a precedence table or a fold. For a grammar that does reduce, prefer
`pratt` or `chainl1`; reach for `rule()` when the grammar does not, for
example a left-recursive postfix chain with several heterogeneous forms.
Such a grammar can still be rewritten as a postfix fold, so this is about
how a grammar is expressed rather than a hard expressivity limit.

`rule()` is the least-used of rumil's three left-recursion strategies and
the slowest. It may be reconsidered in a future major version, after the
known left-recursive grammars built on it have a fold-based form. It is
not going anywhere in the 0.x line.

### Stack safety: memory-bounded on width and nesting

As of 0.10.0 the interpreter is a single eval/apply trampoline (a
defunctionalized CEK machine) in which every sub-parse re-entry rides a
heap-allocated continuation chain instead of the Dart call stack. Rumil
is therefore memory-bounded, not call-stack-bounded, on both axes:

- **Operator width** (flat chains: `1+1+1+…`, `many`, `chainl1`/`chainr1`,
  Pratt operator runs). Trampolined before 0.10.
- **Structural nesting** (`[[[…]]]`, `(((…)))`, deeply nested
  objects/elements, where a parser re-enters itself through a sub-parse).
  Before 0.10 this recursed on the host stack and overflowed at roughly
  600–2000 levels. It is now bounded by heap as well. This was an
  original property of the interpreter, not a regression.

`rumil/test/stack_safety_test.dart` exercises width at 10 million
operands across every chain primitive (a CI time-budget regression test),
and nesting at 50,000 levels across the four sub-parse shapes (Pratt
parenthesized atom, `chainl1` parenthesized operand, self-referential
`many`, self-referential `zip`), each past the old 600–2000 host-stack
ceiling:

| Axis    | Construct                                 | CI depth   |
|---------|-------------------------------------------|-----------:|
| width   | `flatMap` chain                           | 10 000 000 |
| width   | `chainl1` / `chainr1` (10 M operands)     | 10 000 000 |
| width   | Pratt left- / right-assoc / prefix chain  | 10 000 000 |
| nesting | Pratt with parenthesized atom             |     50 000 |
| nesting | `chainl1` with parenthesized operand      |     50 000 |
| nesting | self-referential `many` (`[ v* ]`)        |     50 000 |
| nesting | self-referential `zip` (`( v )`)          |     50 000 |

The width primitives have also been validated locally at 1,000,000,000
operands (172 GB RAM, JIT with `--old_gen_heap_size=131072`); run times
scale roughly linearly, and what gives out at extreme depth is heap, not
stack. Those runs take minutes and gigabytes each and are not in CI; they
are a periodic check that no change has reintroduced a per-step
host-recursion path that would only surface past 10 M.

The one sub-parse that remains host-recursive by design is LR-enabled
`Memo` (`rule()`, Warth seed-growth), which nests by left-recursion depth
rather than structural depth.

---

## Lazy error construction (μs/op)

`bench_errors.dart`. The nullable-cache thunk optimization avoids
constructing error messages for failing alternatives during backtracking.

| Scenario                                       | AOT  | JIT  | Wasm |
|------------------------------------------------|-----:|-----:|-----:|
| 20-way Or (last matches)                       | 0.21 | 1.12 | 0.36 |
| Parse invalid + access errors                  | 1.31 | 2.53 | 1.58 |
| 100-object array (failing branches per value)  |  322 |  425 |  382 |
| 1000-object array                              | 3514 | 4357 | 4515 |

---

## Summary

As of 0.10.0, Rumil parses within about 1.1–1.3× of petitparser building
the same typed AST, and about 2.2–3.3× on plain native `Map`/`List`
output, where it makes a second conversion pass petitparser does not.
Across versions the AOT gap has come down from 10–13× in 0.6 and 5.5–10×
in 0.7.1; the 0.10.0 fusion and unified trampoline account for most of
the recent change. AOT is the fastest runtime in 0.10.0, Wasm runs about
1.05–1.8× behind it (Markdown excepted), and JIT sits between.

This is the cost of the sealed-ADT interpreter. In exchange:

- **Pratt-as-a-combinator** for operator precedence: atoms and operator
  symbols are ordinary parsers, walked iteratively over a heap frame
  stack, with a first-code-unit dispatch table when symbols are literal
  prefixes. `rule()` (Warth seed-growth) handles directly-left-recursive
  grammars that do not reduce to a binding-power table.
- **Memory-bounded stack safety on width and nesting**: chain depth and
  structural nesting live on heap frames, not the Dart call stack. Width
  is exercised at 10 M operands and validated to 1 B; nesting at 50 K
  levels, in CI.
- **Typed errors** with line/column/offset, constructed lazily on
  backtracking.
- **Inspectable parsers** with construction-time rewrites (FIRST-set
  `Or`, `Capture(Many)` fusion, RadixNode for `stringChoice`, Pratt
  op-table compilation, `skipThen`/`thenSkip` to `SkipLeft`/`SkipRight`).
- **Memoization**, opt-in via `.memoize` or automatic via `rule()`.
- A **lossless green/red syntax-tree layer** (0.9.0) for language
  tooling, on the same primitives.

For maximum throughput on a fixed format, `dart:convert` and handwritten
parsers will be faster. Rumil is for grammars that benefit from
combinator composition, error reporting with location, an
inspectable or lossless tree, or stack safety at depth.
