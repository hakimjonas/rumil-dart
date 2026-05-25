## 0.7.1

**`LineIndex` for O(log n) line/column resolution, and a hot/cold
split of the interpreter dispatch that lifts the format-parser suite
4–6%.** Additive on the public surface — `Location`, existing
combinators, and the rest are unchanged.

### Added

- **`LineIndex(source)`**: builds a sorted array of every `\n` offset
  in [source] in one O(n) pass, backed by a `Uint32List`. Subsequent
  `locationAt(offset)` queries run in O(log n) via binary search and
  return a [Location] with precomputed line, column, and offset
  (instead of the lazy O(n) walk and O(column) backwalk that
  [Location] performs by default). `spanAt(start, end)` resolves both
  endpoints of a [Span] in one pair of lookups.

  Motivated by streaming parsers (NDJSON, multi-document YAML) that
  produce many errors against the same input: rendering N errors to
  `line:column` was O(N·n) without an index, O(N·log n) with one.
  Mirrors the LineIndex from rumil-scala, including its
  line-terminator policy: `\n` is the sole terminator; `\r` is a
  regular character; callers normalize at the editor or LSP boundary
  before building the index. Column encoding is UTF-16 code units,
  matching the LSP default.

- **`PrecomputedLocation`**: an internal [Location] subtype carrying
  cached `line` and `column`. Constructed only via
  `LineIndex.locationAt`; existing code that constructs
  `Location(input, offset)` directly continues to use the lazy walk.

### Changed

- **`Location.format()` now does one forward walk instead of two.**
  The previous implementation read [Location.line] and
  [Location.column] separately, walking `[0, offset)` twice (once
  forward to count newlines, once backward to find the column). The
  fused version walks once, tracking both the newline count and the
  most-recent newline offset. Measured 17–21% faster on AOT across
  source sizes 1 KB / 10 KB / 100 KB.

  Behavior unchanged: same output string, same edge cases. Callers
  that read `.line` and `.column` directly still walk twice — no
  memoization (would conflict with the const constructor and the
  subtype-via-`implements` pattern). Use [LineIndex] when many
  positions need resolving against the same source.

- **Hot/cold split of `interpretI`'s ~40-case switch.** The hot
  cases stay inline (Succeed, Fail, Satisfy, StringMatch,
  StringChoice, Eof, GetPosition, Mapped, FlatMap, Zip, Or, Choice,
  FirstCharChoice, the Many/Many1/SkipMany/Capture(Many) terminal-
  shape fast paths, Defer). The cold cases (Optional, Attempt,
  LookAhead, NotFollowedBy, RecoverWith, Expect, Named, Trace,
  Debug, Memo, Pratt, Chainl1, Chainr1, the generic Many/Many1/
  SkipMany/Capture fall-throughs) move to a separate `_interpretCold`
  function called from a `default` branch.

  Pattern adapted from Eru's `runFast`/`stepCold` architecture.
  Shrinks `interpretI`'s AOT body from 11,276 → 6,824 bytes (−39.5%),
  letting the optimizer specialize the hot dispatch tightly.

  Behavior unchanged. Format parser suite (every parser in the
  family, both runtimes): every benchmark faster, range 2–9% AOT,
  2–6% WASM, average ~5%. The dispatch microbench in `rumil_bench`
  shows 9–14% improvement on the composite-Many path that surfaces
  the hot-loop dispatch overhead.

### Benchmarks (1000 ops per benchmark)

LineIndex amortization holds across runtimes — about three orders of
magnitude at 100 KB on both AOT and WASM:

| Source | AOT cached | AOT rebuilt | AOT speedup | WASM cached | WASM rebuilt | WASM speedup |
|--------|-----------:|------------:|------------:|------------:|-------------:|-------------:|
| 1 KB   |     6.5 μs |    1 049 μs |        161× |      7.6 μs |     1 128 μs |         148× |
| 10 KB  |    16.6 μs |   10 214 μs |        615× |     16.3 μs |    11 141 μs |         684× |
| 100 KB |     112 μs |  103 718 μs |        926× |      116 μs |   111 132 μs |         958× |

The fused `Location.format()` walk is a smaller polish, more visible
on AOT than WASM (which already folds some of the redundant work):

| Source | AOT fused | AOT legacy | AOT win | WASM fused | WASM legacy | WASM win |
|--------|----------:|-----------:|--------:|-----------:|------------:|---------:|
| 1 KB   |    330 μs |     390 μs |   1.18× |     444 μs |      439 μs |  ~1.00×  |
| 10 KB  |  2 691 μs |   3 154 μs |   1.17× |   3 293 μs |    3 709 μs |    1.13× |
| 100 KB | 25 562 μs |  30 843 μs |   1.21× |  32 328 μs |   36 330 μs |    1.12× |

Reproduce from `rumil_bench/`:

```bash
# AOT
dart compile exe bin/bench_line_index.dart -o /tmp/bench_li
/tmp/bench_li

# WASM (Deno required)
dart compile wasm bin/bench_line_index.dart -o /tmp/bench_li.wasm
deno run --allow-read tool/run_wasm.mjs /tmp/bench_li.wasm
```

## 0.7.0

**Pratt operator-precedence parsing, stack-safe chain combinators,
operator preset, first-char dispatch.** Synchronized release across
all rumil-dart packages.

### New combinators

- **`pratt(...)`**: Top-Down Operator Precedence (TDOP) combinator. Takes
  an atom parser and a list of `PrattOperator<A>` descriptors —
  `InfixLeft<A>`, `InfixRight<A>`, `Prefix<A>`, `Postfix<A>` — with
  binding powers and node constructors. Single-pass operator-precedence
  parsing in place of layered `chainl1` calls.
- **`cFamilyPrecedence<A>(...)`**: convenience preset returning the
  standard 15-operator C-family precedence ladder
  (`||`/`&&`/`==`/`!=`/comparison/additive/multiplicative + prefix
  `-`/`!`). Consumers pass binary/unary node constructors and the symbol
  parser; per-symbol customization is via dispatch on the input string.
- **`firstCharChoice<A>(...)`**: O(1) dispatch to one of several
  alternatives based on the leading code unit at the current position.
  Map keys are strings of one or more chars (e.g. `'tf'` binds both `t`
  and `f`, `'-0123456789'` binds 11 chars). Optional `fallback` runs on
  miss. Used in JSON's value dispatch (24–27% faster across all input
  sizes vs the previous `Or`-chain form).
- **`choice([...])` auto-fuses to `FirstCharChoice`** when alternatives
  have statically decidable, mutually disjoint leading chars (≥3
  alternatives required). The introspector peels through `Mapped` /
  `Named` / `Expect` / `LookAhead` / `Memo` / `Zip-left` / `Capture`
  and recurses into `Or` / `Choice`; bails on `Defer` / `FlatMap` /
  opaque-predicate `Satisfy`. Recursive grammars that need the
  optimization should use the explicit `firstCharChoice` builder.
- **`Chainl1<E, A>` and `Chainr1<E, A>`** are now first-class Parser ADT
  cases. `chainl1(p, op)` and `chainr1(p, op)` continue to be the public
  builders; they construct these nodes directly.

### Stack safety

- **chainl1 / chainr1** are now stack-safe to memory-only depth (was
  StackOverflow at ~850 chain steps under the previous recursive
  `Or` + `FlatMap` expansion).
- **Pratt right-associative chains** scale to 1M+ depth via an explicit
  operator stack.
- **Pratt prefix chains** (`--5`, `---5`, `!-x`) compose correctly and
  scale to 1M+ depth.

### Performance

- **FIRST-set dispatch on `Or`**: peeks at one character to skip doomed
  left branches when the leading shape is decidable (`Satisfy`,
  `StringMatch`, `StringChoice`, `Eof` plus `Mapped`/`Zip`-left/
  `LookAhead` peeling).
- **`Many(StringMatch)` / `SkipMany(simple)` fast paths**: bypass
  per-iteration error-thunk allocation in repetition loops.
- **Pratt opTable fast path**: when all infix/postfix operator symbols
  are literal-prefix parsers, dispatch via a code-unit-indexed table
  with optional word-boundary / not-followed-by-char guards.

### Correctness fixes

- **`Named<A>` / `Expect<A>` type erasure**: previous code inferred
  `A=dynamic` and the resulting `Result<E, dynamic>` failed the runtime
  cast to `Result<E, A>`. Fix uses explicit `interpretI<ParseError, A>`
  with typed pattern matching. Was dormant until consumers wrapped
  Named parsers inside Pratt expressions.

### Trade-offs

- chainl1/chainr1 now go through a dedicated ADT case rather than the
  recursive `Or`+`FlatMap` expansion. Shallow-chain workloads pay ~5–7%
  more per iteration in dispatch overhead in exchange for the
  unbounded stack safety. The recommended path for new precedence-driven
  grammars is `pratt(...)` + `cFamilyPrecedence`, which delivers a net
  win on every workload measured. All three rumil consumers
  (rumil_expressions, rumil_parsers/HCL, lambe) have been migrated.

### Documentation

- `state.dart` documents the mutability boundary: `ParserState` is the
  one mutable object in the parsing pipeline, scoped to a single
  `parser.run(input)` call, never escapes to user code.

### Naming

- The Pratt operator-descriptor sealed class is named `PrattOperator<A>`
  (parent of `InfixLeft<A>`/`InfixRight<A>`/`Prefix<A>`/`Postfix<A>`).
  This frees the bare `Operator` name for downstream consumers that
  have their own `Operator` types — notably `rumil_tokens`, where
  `Operator` is a `Token` subclass for value-computing operator
  characters in source code. Subclass names (`InfixLeft`, etc.) are
  unchanged.

## 0.6.0

Synchronized release across all rumil-dart packages. Additive for
`rumil`.

- `position()` primitive: a zero-width parser that yields the current
  byte offset. Combines with `Zip` for span capture:
  `position().zip(p).zip(position())` produces `((start, value), end)`
  in one pass.

## 0.5.0

**Interpreter optimizations and API refinements.**

- **Breaking:** `Location` changed from `extension type` to `final class`. Line/column now computed lazily from offset — eliminates per-character write barriers. Constructor changed from named parameters to `Location(input, offset)`.
- **Breaking:** `Snapshot` typedef removed. `ParserState.save()` returns `int`, `restore()` takes `int`. `ParserState.line`/`column` getters removed — use `state.location.line` instead.
- **Perf:** Eliminate terminal re-boxing in trampoline (no intermediate Result allocation per terminal dispatch).
- **Perf:** Replace `late final` with nullable cache (`??=`) in `Partial`/`Failure` error fields — removes hidden initialization check on WasmGC.
- **Perf:** Add `Parser.isSimple` property for save/restore skipping in `Or`, `Optional`, `Many`, `SkipMany`.
- **Perf:** Fuse `Capture(Many(p))` / `Capture(Many1(p))` in interpreter — skip intermediate list allocation.
- **5-9% faster on AOT native, 30-52% faster on WasmGC** across all format parser benchmarks.

## 0.4.0

- **Fix:** `RecoverWith` eagerly evaluates error thunks at recovery time.
  Lazy thunks in `_satisfyMany` closed over `ParserState` and read stale
  offsets when evaluated later, causing `RangeError` on `.errors` access.
- `_satisfyMany` captures `state.currentChar` into a local before closures.

## 0.3.0

- Doc on `MemoKey.id`.
- `public_member_api_docs` lint enforced.
- Version aligned with other rumil packages.

## 0.2.0

- **Breaking:** `fail()` renamed to `failure()` to avoid conflict with `package:test`.
- Doc comments on all public API elements.
- `rule()` doc: guidance on placement (postfix level, not top level).
- `lexeme()` doc: note about whitespace handling for `chainl1` operands.

## 0.1.0

- Core parser combinators: sealed Parser ADT with 26 subtypes, external interpreter, defunctionalized trampoline
- Warth seed-growth left recursion via `rule()`
- Stack-safe to 10M+ operations
- Typed errors with source location (line, column, offset)
- Lazy error construction via `late final` thunks
- RadixNode O(m) string matching
- Full combinator DSL: `.zip()`, `.thenSkip()`, `.skipThen()`, `|`, `.map`, `.flatMap`, `.many`, `.sepBy`, `.chainl1`, `.chainr1`, `.between`, `.capture`, `.memoize`
- Format parsers: JSON (RFC 8259), CSV (RFC 4180), XML, TOML (v1.0.0), YAML (simplified 1.2), Proto3 schema
- AST decoders for JSON, TOML, YAML with `ObjectAccessor` pattern
- Formula evaluator with operator precedence via `chainl1`, variables, custom functions
- Binary codec: ZigZag, LEB128 Varint, BinaryCodec with `xmap` + `product2`–`product6` composition
- build_runner codegen for `@binarySerializable` classes and sealed hierarchies
