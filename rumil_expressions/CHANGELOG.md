## 0.10.0

Dependency constraint bumped to `rumil: ^0.10.0`; version aligned with
the rumil-dart family 0.10.0 release. No source changes in this package,
but it inherits two wins from the core 0.10.0 interpreter: deeply
parenthesized expressions (`(((…)))`) now parse stack-safe to memory
rather than overflowing the native stack at moderate nesting depth, and
expression parsing is ~2× faster (AOT/JIT/Wasm). The 57-test suite passes
unchanged on the new core.

## 0.7.0

- **Parser migrated from a six-layered `chainl1` ladder to a single
  `pratt(...)` call** using rumil's new `cFamilyPrecedence` preset.
  Functionally equivalent — same operators, same binding powers, same
  `Expr` AST shape. The conditional (`? :`) stays layered above as a
  flatMap because its three-branch shape doesn't fit infix dispatch.
- **Performance:** 30–35% faster across all expression workloads on
  AOT native. Bench numbers: simple `1 + 2 * 3` 9.40 µs → 6.47 µs
  (-31%), nested 30.20 µs → 21.83 µs (-28%), 100-term chain 279 µs →
  181 µs (-35%), 50-paren depth 469 µs → 307 µs (-35%). Win comes
  from collapsing six dispatch layers into one Pratt loop and
  eliminating the recursive `_unary` definition via the explicit
  `Prefix` operator descriptor.
- Public API unchanged: `parseExpression`, `parse`, `evaluate`, `eval`,
  `Environment`, `Expr` and all subtypes preserved.
- Depends on `rumil: ^0.7.0`.

## 0.6.0

- Depends on `rumil: ^0.6.0`. Version aligned with the rumil-dart
  monorepo 0.6.0 release. No functional changes in this package.

## 0.5.0

- Depends on rumil ^0.5.0. Benefits from interpreter optimizations (5-9% AOT, 30-52% WasmGC).

## 0.4.0

- Depends on rumil ^0.4.0. Version aligned.

## 0.3.1

- Depends on rumil ^0.3.0.

## 0.3.0

- Exported shared eval helpers: asNum, asBool, typeName, applyBinaryOp, applyUnaryOp, compareValues.

## 0.2.0

- Exported shared evaluation helpers: `asNum`, `asBool`, `typeName`, `applyBinaryOp`, `applyUnaryOp`, `compareValues`.
- Depends on rumil ^0.2.0 (`fail` renamed to `failure`).

## 0.1.1

- Doc comments on all public API elements.

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
