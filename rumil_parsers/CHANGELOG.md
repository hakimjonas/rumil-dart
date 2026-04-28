## 0.6.0

- Depends on `rumil: ^0.6.0`. Version aligned with the rumil-dart
  monorepo 0.6.0 release. No functional changes in this package.

## 0.5.0

**CommonMark Markdown parser. Architecture audit. 7376 tests.**

- **Markdown:** 652/652 CommonMark 0.31.2 spec conformance. Typed `MdNode` AST with structured fields (`MdHeading.level`, `MdLink.href`, `MdImage.alt`) — separates parsing from rendering. Public API: `parseMarkdown(String) → Result<ParseError, MdDocument>`.
- **TOML:** Replace `throw`/`try-catch` with `Result`-based error flow. Zero exceptions in the parser.
- **XML:** Replace manual `indexOf`/`substring` with combinators for QName parsing, entity reference validation, and attribute value expansion.
- **Delimited:** Replace `while`-loop field splitter and `RegExp` with combinator parsers.
- **All formats:** Apply `.capture` optimization (12 sites) — each benefits from fused `Capture(Many)` interpreter fast path.
- **TOML:** Deduplicate unicode escape parsers into parameterized `_unicodeEscape(marker, count)`.
- Depends on rumil ^0.5.0.

## 0.4.0

**All parsers to spec conformance. 6724 tests, zero analyzer warnings.**

- **HCL full spec:** expression tower (operators, ternary, for-expressions,
  function calls), string templates `${expr}`, heredocs `<<EOF`/`<<-EOF`,
  template directives `%{if}`/`%{for}`, index/splat `[*]`/`.*`, scientific
  notation, Unicode identifiers, parenthesized object keys, object element
  commas. 2760/2760 including 2717 terraform-provider-aws `.tf` files.
- **XML 1.0 5e:** W3C conformance suite — 1506/1506. DOCTYPE/DTD parsing,
  external entity resolution, namespace validation, Unicode names,
  attribute uniqueness, `--` restriction in comments.
- **Delimited overhaul:** three-tier architecture (explicit config /
  auto-detect dialect / per-row robust), BOM stripping, ragged row policies,
  `detectDialect()`, `parseDelimitedRobust()`. 100 tests.
- **YAML 1.2:** anchors, aliases, merge keys, block scalars, multi-document,
  full escape set, `resolveAnchors()`, `YamlParseConfig`. 333/333.
- **JSON:** 318/318. **TOML 1.1:** 681/681. **Proto3:** 101/101.
- Conformance test runners for all formats in `test/conformance/`.

## 0.3.1

- Doc on `ObjectBuilder` constructor.
- Depends on rumil ^0.3.0.

## 0.3.0

- AST encoders + serializers for JSON, TOML, YAML, XML, CSV, Proto3, HCL.
- AstBuilder with nativeToAst for JSON, YAML, TOML, XML, HCL.
- Native decoders: jsonToNative, yamlToNative, tomlToNative, xmlToNative, hclToNative.
- Shared escape utilities.
- operator == and hashCode on all AST classes.
- YAML indentation-based nested block parsing.
- HCL parser (attributes, blocks, comments, references).
- 278 tests.

## 0.2.0

- Doc comments on all public API elements.
- Depends on rumil ^0.2.0 (`fail` renamed to `failure`).

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
