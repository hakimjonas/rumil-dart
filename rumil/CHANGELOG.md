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
