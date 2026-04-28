## 0.6.0

First pub.dev publish. Adds byte-offset spans, two new token classes,
and per-grammar corrections.

### Spans

- `tokenizeSpans(source, grammar) → List<Spanned<Token>>`. Each
  `Spanned` carries `start`/`end` byte offsets alongside the classified
  token. Spans are half-open `[start, end)`, contiguous, and anchored
  to `[0, source.length)`.
- `Spanned<T extends Token>` is an extension type over `(T, int, int)`.
  Narrow types upcast to wider ones (`Spanned<Keyword>` to
  `Spanned<Token>`).
- `tokenize` is now a wrapper over `tokenizeSpans`. Behaviour is
  unchanged; all prior tests still pass.

### Token vocabulary

- `Operator` token class, separate from `Punctuation`. Value-computing
  operators (`+`, `*`, `==`, `&&`, `=>`) are `Operator`; structural
  delimiters (`(`, `)`, `{`, `}`, `,`, `;`) stay `Punctuation`.
- `Variable` token class for shell variable references
  (`$HOME`, `${PATH:-/bin}`).

### Grammar API additions

`LangGrammar` gained eight optional fields, all backwards-compatible:

- `operatorChars`: single-character operator alphabet. Runs do not
  coalesce; multi-character operators must be declared explicitly.
- `multiCharOperators`: explicit multi-character operator vocabulary
  (`==`, `<=`, `&&`, `=>`, `??=`). Matched longest-first before
  single-char operator or punctuation fallback.
- `identifiersAllowDollar`: whether `$` is legal in identifier names.
- `rawStringPrefix`: recognizes `r'...'`, `r"..."` as one `StringLit`
  including the prefix character.
- `identifierStringPrefix`: recognizes `s"..."`, `f"..."`,
  `my_interp"..."` as one `StringLit` including the identifier prefix.
- `backtickIdentifiers`: recognizes `` `type` `` as one `Identifier`
  even when the bracketed content is a keyword.
- `shellVariables`: recognizes `$NAME` and `${...}` as one `Variable`.
- `backtickCommandSubstitution`: recognizes `` `cmd` `` backticks as
  `Punctuation` delimiters.
- `heredocs`: recognizes `<<EOF...EOF`, `<<-EOF`, `<<'EOF'` as one
  `StringLit` covering the whole construct.

### Grammar fixes

- Dart: raw strings (`r'...'`, `r"..."`, `r'''...'''`, `r"""..."""`)
  are one `StringLit` including the prefix.
- Scala: backtick identifiers are one `Identifier`. Interpolator
  prefixes (`s"..."`, `f"..."`, any-ident) are one `StringLit`.
- JSON: negative numbers (`-1`, `-3.14`, `-1e10`) tokenize as one
  `NumberLit`.
- YAML: flow collections (`[1, 2]`, `{a: 1}`) classify delimiters.
  YAML 1.1 legacy keywords (`yes`, `no`, `on`, `off`) removed.
- Shell: `$HOME`, `${PATH}`, `$(cmd)` produce `Variable` tokens.
  Backtick command substitution produces `Punctuation` backticks.
  Heredocs capture as a single `StringLit`.

### Dependencies

- `rumil: ^0.6.0` for the `position()` primitive.

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

## 0.5.0

- Sealed `Token` ADT: keyword, string, comment, number, type,
  punctuation, identifier, whitespace, plain.
- `tokenize(source, grammar)` produces a lossless token stream;
  concatenating token texts reconstructs the original source.
- `LangGrammar` record: keywords, type names, comment syntax, string
  delimiters.
- Built-in grammars: Dart, Scala, YAML, JSON, shell.
- Built on `rumil` combinators.
