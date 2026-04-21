## Unreleased

- **New:** `position()` primitive — a zero-width parser that yields the current byte offset. Combines with `Zip` for span capture: `position().zip(p).zip(position())` gives `((start, value), end)` in one pass. Discovered as a gap while building Doxa on Rumil.

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
