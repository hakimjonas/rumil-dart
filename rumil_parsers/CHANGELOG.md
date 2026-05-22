## 0.8.0

JSON parser, principled and fast. Three logical chunks ship together:
the HCL decoder fix originally scoped as 0.7.1, a JSON AST split
(`JsonNumber` → `JsonInt | JsonDouble`), and a JSON parser perf
overhaul.

### Changed (breaking)

- **`JsonNumber` is now a sealed sum of `JsonInt(int)` and
  `JsonDouble(double)`.** The previous single-`JsonNumber(double)`
  representation flattened integer-shaped and float-shaped tokens at
  the AST layer, silently losing precision for integers above 2^53 and
  denying downstream consumers the type discrimination they need to
  specialize integer-vs-float paths.

  The new shape matches the discrimination already present in
  `dart:convert` (where `jsonDecode` returns `int` or `double` based
  on token shape), serde_json's `Number` enum
  (`PosInt`/`NegInt`/`Float`), simdjson's `number_type`
  (`signed_integer`/`unsigned_integer`/`floating_point_number`), and
  Jackson's `NumericNode` hierarchy. Pattern matching on `JsonNumber`
  becomes pattern matching on `JsonInt` or `JsonDouble`. Equality
  across the variants is `false`: `JsonInt(1) != JsonDouble(1.0)`.

  Big integers exceeding Dart's `int` range fall back to `JsonDouble`,
  matching `dart:convert`'s rule. Adding an explicit `JsonBigInt`
  variant is reserved for a future release if real consumers need it.

  Round-trip fidelity is improved as a side effect: `parseJson('1.0')`
  now serializes back as `'1.0'` rather than `'1'`. The source token
  shape is preserved.

  Decoders are tolerant of either variant — `jsonInt.decode(JsonDouble)`
  narrows via `value.toInt()`, `jsonDouble.decode(JsonInt)` widens via
  `value.toDouble()`. Documented on each decoder.

### Fixed

- **HCL decoder is now consistent across N=1 vs N≥2 same-labeled
  blocks.** `hclDocToNative` previously returned a single block as a
  non-list (`{...}`) and multiple blocks as a list. Now blocks always
  return as lists, regardless of count, using the `HclBlock`
  discriminator already present in the AST. Attributes are unchanged.
  Consumers that pattern-matched on `result['variable'] is Map` for the
  N=1 case must switch to `result['variable'] is List` (always). The
  previous behavior threw away structural information from the parser
  AST and made common Terraform patterns (one `terraform`, one
  `provider`, single `variable`) require defensive shape checks.

### Performance

The JSON parser is now substantially faster on every workload, with
the largest wins under Wasm where the JsonInt/JsonDouble split unlocks
i64-vs-f64 specialization that the flattened representation forced
into a single homogeneous f64 path.

Mean μs/op across 100 measured iterations + 100 warmup, Linux x86_64,
Dart SDK 3.11.4. Each pass run separately on a quiet system. Full
table and per-byte MB/s in `BENCHMARKS.md`.

| Workload       | 0.7.0 AOT | 0.8.0 AOT | AOT speedup | 0.7.0 Wasm | 0.8.0 Wasm | Wasm speedup |
|----------------|----------:|----------:|------------:|-----------:|-----------:|-------------:|
| integer_heavy  |   162.1 ms|   154.5 ms|        1.05×|     86.8 ms|     64.7 ms|         1.34×|
| float_heavy    |   189.2 ms|   179.5 ms|        1.05×|     96.0 ms|     76.9 ms|         1.25×|
| mixed          |    1368 ms|    1115 ms|        1.23×|    609.4 ms|    430.3 ms|         1.42×|

Wins come from three changes: capture-based number parsing (one
allocation per token instead of a per-character interpolation chain),
capture-based string runs (one substring slice in the unescaped fast
path instead of O(n) per-character allocations), and elimination of
the redundant leading `_ws` in `_lex` (every token paid a leading skip
that the previous token's trailing skip had already consumed). The
combinator architecture's affinity for Wasm codegen surfaces in the
Wasm column — the `mixed` workload composes all four optimizations
(numbers, strings, dispatch, lex) and shows the largest relative win.

Reproduce via `rumil_bench`'s `bench_json_perf_pass`:

```bash
cd rumil_bench
dart compile exe bin/bench_json_perf_pass.dart -o /tmp/perf.aot
/tmp/perf.aot
```

For the Wasm column, see `BENCHMARKS.md` for the full instructions.

## 0.7.0

- **JSON:** value-dispatch parser migrated from a 6-way `Or` chain to
  rumil's new `firstCharChoice` combinator. JSON values have cleanly
  disjoint leading chars (`n`, `t`/`f`, digits/`-`, `"`, `[`, `{`),
  so the O(1) dispatch replaces the linear scan. Bench numbers (AOT
  native, 6 runs): json-small 24.0 µs → 18.4 µs (-23%), json-medium
  35.0 ms → 25.7 ms (-27%), json-large 429 ms → 312 ms (-27%). vs
  petitparser ratio improves from 13× to ~10× small / ~9× large.
  All RFC 8259 conformance tests pass unchanged.
- **HCL:** operator precedence parser migrated from a six-layered
  `chainl1` ladder + recursive `_unary` to a single `pratt(...)` call
  using rumil's new `cFamilyPrecedence` preset. Functionally
  equivalent — same operators, same binding powers, same AST. Bench
  numbers: hcl-config 253 µs → 225 µs (-11%), hcl-50res 10.7 ms →
  9.32 ms (-13%) on AOT native. All HCL conformance tests
  (specsuite, fuzz corpus, terraform-provider-aws .tf files) pass
  unchanged.
- Other format parsers (CSV, TOML, XML, YAML, Proto3, Markdown) are
  unchanged at the source level. They benefit transparently from
  rumil 0.7's `Many(StringMatch)` / `SkipMany(simple)` fast paths
  (CSV measured 10–22% faster) and from the FIRST-set Or dispatch
  optimization (small wins on alternation-heavy grammars).
- Depends on `rumil: ^0.7.0`.

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
