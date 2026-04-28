# rumil_tokens

Source code tokenizer built on [Rumil](https://pub.dev/packages/rumil)
parser combinators. Classifies source text into typed token spans:
keywords, strings, comments, numbers, types, annotations, operators,
variables, and punctuation. Token streams are lossless; concatenating
`token.text` across a stream reconstructs the input exactly.

## Usage

```dart
import 'package:rumil_tokens/rumil_tokens.dart';

final tokens = tokenize('final x = 42; // answer', dart);
for (final token in tokens) {
  print('${token.runtimeType}: ${token.text}');
}
```

Use a built-in grammar (`dart`, `scala`, `yaml`, `json`, `shell`) or define
your own:

```dart
const rust = LangGrammar(
  name: 'rust',
  keywords: ['fn', 'let', 'mut', 'if', 'else', 'match', 'impl', 'struct'],
  types: ['i32', 'u64', 'String', 'Vec', 'Option', 'Result', 'bool'],
  lineComment: '//',
  blockComment: ('/*', '*/'),
  stringDelimiters: ['"'],
  annotationPrefix: '#',
);

final tokens = tokenize(source, rust);
```

Look up a grammar by name:

```dart
final grammar = grammarFor('dart'); // returns null for unknown languages
```

## Lossless property

Concatenating `token.text` for every token reconstructs the original source:

```dart
assert(tokens.map((t) => t.text).join() == source);
```

## Positions

For tooling that needs byte offsets, use `tokenizeSpans`:

```dart
final spans = tokenizeSpans(source, dart);
for (final s in spans) {
  print('[${s.start}, ${s.end}) ${s.token}');
  assert(source.substring(s.start, s.end) == s.token.text);
}
```

`Spanned<Token>` is an extension type over `(Token, int, int)`.
The `[start, end)` interval is half-open; spans are contiguous
(`spans[i].end == spans[i+1].start`) and anchored (`spans.first.start == 0`,
`spans.last.end == source.length`).

## Grammar coverage

Known limitations as of 0.6.0 (see `CHANGELOG.md`):

- YAML block scalars (`|`, `>`) tokenize the indented body as regular
  YAML content rather than one string literal.
- Dart string interpolation (`"$x"`, `"${expr}"`) remains one
  `StringLit`.
- Shell braced expansions do not balance nested braces.
- Heredoc body is one `StringLit`.
- Nested generic close renders the outer `>>` as right-shift.

Part of the [rumil-dart](https://github.com/hakimjonas/rumil-dart) monorepo.
