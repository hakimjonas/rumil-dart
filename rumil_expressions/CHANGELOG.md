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
