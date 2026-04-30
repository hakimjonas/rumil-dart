## 0.6.0

- Depends on `rumil_codec: ^0.6.0`, `rumil_parsers: ^0.6.0`. Version
  aligned with the rumil-dart monorepo 0.6.0 release.

## 0.5.0

- Depends on `rumil_codec: ^0.5.0`, `rumil_parsers: ^0.5.0`. Version aligned.

## 0.4.0

- Fix: `rumil_parsers` dev dependency uses version constraint (was path).
- Depends on `rumil_codec: ^0.4.0`. Version aligned.

## 0.3.0

- AstEncoderGenerator: generates AstEncoder<T, JsonValue> for @AstSerializable classes.
- Sealed class support with type discriminator field.

## 0.2.0

- Depends on rumil_codec ^0.2.0 (version aligned).

## 0.1.1

- Move sample code to example/ for correct pub.dev analysis
- Tighten analyzer dependency lower bound
- Add doc comments to public API

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
