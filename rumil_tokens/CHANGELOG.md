## 0.1.0

Initial in-tree cut. Source code tokenizer built on Rumil. Not
published to pub.dev; consumed via path dependency from elsewhere
in the monorepo.

### Tokens

- Sealed `Token` ADT: `Keyword`, `TypeName`, `StringLit`, `NumberLit`,
  `Comment`, `Punctuation`, `Operator`, `Variable`, `Identifier`,
  `Annotation`, `Whitespace`, `Plain`.

### API

- `tokenize(source, grammar)` returns a lossless `List<Token>`;
  concatenating `token.text` reconstructs the source exactly.
- `tokenizeSpans(source, grammar)` returns `List<Spanned<Token>>`
  carrying byte offsets. Spans are half-open `[start, end)`,
  contiguous, and anchored to `[0, source.length)`.
- `Spanned<T extends Token>` is an extension type over
  `(T, int, int)`. Narrow types upcast to wider ones.

### Built-in grammars

- `dart`, `scala`, `yaml`, `json`, `shell`.
- `grammarFor(name)` returns the matching grammar or `null`.

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

- `rumil: ^0.6.0` for the `position()` primitive.
