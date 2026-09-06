## 0.11.0

Dependency constraint bumped to `rumil: ^0.11.0`; version aligned with the
rumil-dart family 0.11.0 release. No source changes in this package. The
tokenizer test suite passes unchanged.

## 0.10.0

Dependency constraint bumped to `rumil: ^0.10.0`; version aligned with
the rumil-dart family 0.10.0 release (jumping 0.1.0 → 0.10.0 to join
lockstep — this is the version of `rumil_tokens` built on the 0.10.0
core). No source changes. The tokenizer is a flat lexer, so the core's
structural-nesting stack-safety fix doesn't apply to it, but it inherits
the ~2× faster parse engine. The 207-test suite passes unchanged.

## 0.1.0

First public release. Lossless source code tokenizer built on Rumil
parser combinators. Classifies source text into typed token spans
with byte offsets.

Developed in-tree within the rumil-dart monorepo since 2026-04 and
used by `rem` and `lambe`; first publication to pub.dev with the
rumil 0.7 family release.

### Tokens

- Sealed `Token` ADT: `Keyword`, `TypeName`, `StringLit`, `NumberLit`,
  `Comment`, `Punctuation`, `Operator`, `Variable`, `Identifier`,
  `Annotation`, `Whitespace`, `Plain`. Lossless: concatenating every
  token's `text` reproduces the source exactly.

### API

- `tokenize(source, grammar)` returns a lossless `List<Token>`.
- `tokenizeSpans(source, grammar)` returns `List<Spanned<Token>>`
  with byte offsets. Spans are half-open `[start, end)`, contiguous,
  anchored to `[0, source.length)`.
- `buildTokenizer(grammar)` returns the underlying
  `Parser<ParseError, List<Spanned<Token>>>` for callers that
  tokenize many sources against one grammar — building once and
  reusing avoids the per-call parser-construction cost.
- `Spanned<T extends Token>` is an extension type over
  `(T, int, int)`. Narrow types upcast to wider ones.

### Built-in grammars

- `dart`, `scala`, `yaml`, `json`, `shell`.
- `grammarFor(name)` looks up by name (with aliases like `yml` →
  `yaml`, `bash`/`sh`/`zsh` → `shell`).
- `builtinGrammars` is a list of all five for enumeration.

### `LangGrammar` fields

- Lexical: `keywords`, `types`, `lineComment`, `blockComment`,
  `stringDelimiters`, `multiLineStringDelimiters`, `annotationPrefix`,
  `punctuationChars`, `operatorChars`, `multiCharOperators`.
- Flags: `identifiersAllowDollar`, `rawStringPrefix`,
  `identifierStringPrefix`, `backtickIdentifiers`, `shellVariables`,
  `backtickCommandSubstitution`, `heredocs`.

### Known limitations

- YAML block scalars (`|`, `>`) tokenize the indented body as regular
  YAML content rather than one string literal.
- Dart string interpolation (`"$x"`, `"${expr}"`) remains one
  `StringLit`; no structured tokens for the interpolated parts.
- Shell braced expansions do not balance nested braces: `${x:-${y}}`
  closes the outer expansion prematurely.
- Heredoc body is one `StringLit`; per-component coloring is not
  available.
- Nested generic close (`List<Map<String, int>>`) highlights the outer
  `>>` as the right-shift operator.

### Dependencies

- `rumil: ^0.7.0` for the `position()` primitive and `Choice<E, A>`
  ADT.
