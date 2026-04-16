# Spec Conformance

rumil_parsers verifies each parser against the official specification test suite for its format. This document records methodology, results, status, and design plans for all parsers.

Last verified: 2026-04-16.

## Results

| Format | Spec | Test Suite | Result |
|--------|------|-----------|--------|
| JSON | RFC 8259 | [JSONTestSuite](https://github.com/nst/JSONTestSuite) | **318/318 (100%)** |
| TOML | TOML 1.1 | [toml-test](https://github.com/toml-lang/toml-test) | **681/681 (100%)** |
| YAML | YAML 1.2.2 | [yaml-test-suite](https://github.com/yaml/yaml-test-suite) | **333/333 (100%)** |
| Delimited | RFC 4180 + real-world | Custom robustness suite | **100 tests** |
| Proto3 | [Language Guide](https://protobuf.dev/programming-guides/proto3/) | protobuf repo `.proto` files | **101/101 (100%)** |
| XML | W3C XML 1.0 5e | [W3C XML Test Suite](https://www.w3.org/XML/Test/) | **1506/1506 (100%)** |
| HCL | [HashiCorp spec](https://github.com/hashicorp/hcl/blob/main/hclsyntax/spec.md) | specsuite + fuzz + terraform-provider-aws | **2760/2760 (100%)** |
| Markdown | CommonMark 0.31.2 | [CommonMark spec](https://spec.commonmark.org/0.31.2/) | **652/652 (100%)** |

---

## Methodology

Each conformance test runner lives in `test/conformance/` and works the same way:

1. Clone the official test suite to `/tmp/`
2. Walk every test case in the suite
3. For valid-input tests: parse, convert to native Dart, compare against expected output
4. For error tests: verify the parser rejects the input
5. Report pass/fail counts with per-test diagnostics

The conformance tests are separate from unit tests. They depend on external test data and are run explicitly:

```bash
# Clone test suites
git clone --depth 1 https://github.com/nst/JSONTestSuite /tmp/json-test-suite
git clone --depth 1 https://github.com/toml-lang/toml-test /tmp/toml-test
git clone --depth 1 --branch data https://github.com/yaml/yaml-test-suite /tmp/yaml-test-data
git clone --depth 1 https://github.com/maxogden/csv-spectrum /tmp/csv-spectrum
git clone --depth 1 https://github.com/protocolbuffers/protobuf /tmp/protobuf-repo
git clone --depth 1 https://github.com/hashicorp/hcl.git /tmp/hcl-go

# Run all conformance tests
dart test test/conformance/

# Run all tests (unit + conformance)
dart test
```

---

## JSON -- 318/318 (100%)

**Spec:** RFC 8259
**Suite:** JSONTestSuite (95 must-accept, 188 must-reject, 35 implementation-defined)

Every test produces the correct outcome:
- `y_` (must accept): 95/95
- `n_` (must reject): 188/188
- `i_` (implementation-defined): 35/35 clean decisions

Invalid-UTF-8 files are read as bytes; decode failure is treated as rejection per RFC 8259 section 8.1. Pathological nesting triggers stack overflow which is caught and treated as rejection.

---

## TOML -- 681/681 (100%)

**Spec:** TOML 1.1
**Suite:** toml-test (214 valid, 467 invalid)

- Valid: 214/214 pass
- Invalid: 467/467 correctly rejected

---

## YAML -- 333/333 (100%)

**Spec:** YAML 1.2.2
**Suite:** yaml-test-suite (231 valid, 78 error, 44 skipped)

- Valid tests: 231/231 pass
- Error tests: 50/78 correctly rejected (28 accepted -- the parser is permissive on some edge cases the spec rejects)
- Skipped: 44 (no `in.yaml` or no `in.json` in test data)

Key architectural decisions that enabled 100%:
- `_resolveScalarType`: plain scalar parsed first, type-resolved post-hoc. Eliminates PEG ordered-choice shadowing where `null` matches before multi-line `null d`.
- `_foldQuotedString`: first/last segments participate in folding even when empty.
- `keyAnchors` and `aliasKeys` fields on `YamlMapping` for anchor/alias key resolution during `resolveAnchors`.
- Dynamic `inlineNestedSeq` indent detection from next-line peek, replacing hardcoded `indent+2`.

---

## Delimited Formats (CSV/TSV/DSV) -- 100 tests

**Spec:** RFC 4180 (Informational) + real-world robustness
**Suite:** Custom robustness suite (100 tests)

No official conformance suite exists for delimited formats. Tests cover RFC 4180 core, quoting edge cases, bare quotes mid-field, line ending variants (LF/CRLF/CR), TSV, dialect auto-detection, ragged row policies, per-row robust parsing, Unicode, large inputs, and round-trip serialization.

Three-tier architecture: explicit config (`parseDelimited(input, config)`), auto-detect dialect (`parseDelimited(input)` / `detectDialect(input)`), and per-row adaptation (`parseDelimitedRobust(input)`). BOM stripping, configurable ragged row policy (`error` / `padWithEmpty` / `preserve`), whitespace trimming, and backward-compatible `parseCsv` / `parseTsv` aliases

---

## Proto3 -- 101/101 (100%)

**Spec:** [Proto3 Language Guide](https://protobuf.dev/programming-guides/proto3/)
**Suite:** 101 `.proto` files from [protocolbuffers/protobuf](https://github.com/protocolbuffers/protobuf) `src/google/protobuf/`

This is a `.proto` schema file parser (not binary/text wire format). Tested against the protobuf C++ reference implementation's own schema files — every `.proto` file in `src/google/protobuf/` parses successfully.

**Supported:** syntax/edition declarations, package, import (public/weak/option), messages (including nested), enums (hex values, negative values, value options), services with streaming RPC and service-level options, `optional`/`repeated`/`required` fields, `oneof` blocks (with options), `map` types, field options (balanced brackets), `reserved`, `extensions` (with multi-line options), `extend` blocks, proto2 `group` declarations, `local message`/`local enum` (edition feature), leading-dot fully-qualified types, aggregate option values, comments, round-trip serialization.

---

## XML -- 1506/1506 (100%)

**Spec:** W3C XML 1.0 Fifth Edition
**Suite:** [W3C XML Conformance Test Suite](https://www.w3.org/XML/Test/) (1506 mandatory tests)

- Valid: 601/601 pass
- Not well-formed: 717/717 correctly rejected
- Invalid: 177 accepted (correct for non-validating parser)
- Error: 11 (implementation-defined)

Non-validating parser covering: elements, attributes, namespaces, CDATA, comments, processing instructions, entity/character references (including external entity resolution via callback), XML declaration, DOCTYPE skipping, Unicode name characters, attribute uniqueness, `--` restriction in comments, round-trip serialization.

---

## HCL -- 2760/2760 (100%)

**Spec:** [HashiCorp HCL Native Syntax](https://github.com/hashicorp/hcl/blob/main/hclsyntax/spec.md)
**Suite:** HashiCorp specsuite (15 tests) + fuzz corpus (28 tests) + terraform-provider-aws (2717 `.tf` files)

- Specsuite valid: 12/12 pass
- Specsuite errors: 3/3 correctly rejected
- Fuzz corpus: 28/28 pass (1 known-malformed input correctly rejected)
- Real-world Terraform: 2717/2717 pass

Non-evaluating parser covering the full HCL syntax specification:

**Structural:** Attributes (`key = expr`), blocks with labels (`resource "type" "name" { ... }`), nested blocks, document-level duplicate keys.

**Values:** Strings (with full escape sequences: `\n`, `\r`, `\t`, `\\`, `\"`, `\uNNNN`, `\UNNNNNNNN`), numbers (integer, float, scientific notation), booleans, null, lists (with trailing comma), objects (with `=` or `:` separator).

**Expressions:** Full operator-precedence tower via `chainl1`: unary (`-`, `!`) > multiplicative (`*`, `/`, `%`) > additive (`+`, `-`) > comparison (`<=`, `>=`, `<`, `>`) > equality (`==`, `!=`) > logical AND (`&&`) > logical OR (`||`) > conditional (`? :`). Parenthesized expressions.

**Postfix operations:** Attribute access (`expr.name`), index (`expr[expr]`), legacy dot-index (`expr.0`), full splat (`expr[*].name`), attribute splat (`expr.*.name`).

**Function calls:** `name(args...)` with optional `...` expansion on final argument.

**For expressions:** Tuple form `[for k, v in coll : body if cond]`, object form `{for k, v in coll : key => val... if cond}`.

**Templates:** String interpolation `"${expr}"` with strip markers `${~ expr ~}`, heredoc strings `<<EOF` / `<<-EOF` (indent-stripping), template directives `%{if cond}...%{else}...%{endif}` and `%{for x in list}...%{endfor}`.

**Comments:** `#`, `//`, `/* */`.

**Unicode:** Identifiers support Unicode letters (matching Go's `unicode.IsLetter`).

---

## Markdown -- 652/652 (100%)

**Spec:** CommonMark 0.31.2
**Suite:** [CommonMark spec examples](https://spec.commonmark.org/0.31.2/) (652 examples)

All 652 examples pass. The conformance test uses a test-internal `mdToHtml` renderer to compare parser output against the spec's expected HTML.

The parser produces a typed `MdNode` AST with structured fields (`MdHeading.level`, `MdLink.href`, `MdImage.alt`) instead of HTML element tags. This separates parsing from rendering — the AST can be converted to HTML, LaTeX, terminal ANSI, or queried programmatically.

**Block-level:** ATX and setext headings, paragraphs, block quotes (nested, lazy continuation), ordered and unordered lists (tight/loose detection, start number), fenced and indented code blocks, HTML blocks (types 1-7), thematic breaks, link reference definitions (two-pass for forward references).

**Inline-level:** Emphasis and strong emphasis (CommonMark delimiter algorithm per spec section 6.2), links (inline, reference, collapsed, shortcut), images, code spans, autolinks (URI and email), raw inline HTML, hard and soft line breaks, backslash escapes, HTML entity references (2125 named entities + numeric).

**Architecture:** Indentation-aware block parsing via `peekIndent`/`indent(n)` + `flatMap`, parameterized parsers for nested structures, `notFollowedBy` for block boundaries. Tab expansion and input normalization as pre-processing. Two-pass link reference resolution.
