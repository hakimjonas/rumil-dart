# Rumil

[![CI](https://github.com/hakimjonas/rumil-dart/actions/workflows/ci.yml/badge.svg)](https://github.com/hakimjonas/rumil-dart/actions/workflows/ci.yml)

Parser combinators for Dart 3. Typed errors, left recursion, stack-safe trampolining.

*Rumil invented the first writing system (the Sarati) in Tolkien's legendarium. This library parses text into structure.*

## Packages

| Package             | Description                                                                                                     |
|---------------------|-----------------------------------------------------------------------------------------------------------------|
| `rumil`             | Core combinator framework. Sealed Parser ADT, interpreter, trampoline, memoization, Warth left recursion.       |
| `rumil_parsers`     | Format parsers and serializers for JSON, CSV, XML, TOML, YAML, Proto3, HCL, and CommonMark Markdown.            |
| `rumil_codec`       | Binary codec with ZigZag, Varint, ByteWriter/Reader, and composable `BinaryCodec` via `xmap` and `product2..6`. |
| `rumil_expressions` | Formula evaluator with arithmetic, boolean logic, variables, and custom functions.                              |
| `rumil_bench`       | Benchmarks against petitparser and hand-written Pratt parsers.                                                  |

## Quick start

```dart
import 'package:rumil/rumil.dart';

// Parse a single character
final r = char('a').run('abc');
// Success('a', consumed: 1)

// Compose parsers — `lexeme` consumes trailing whitespace so the
// operators below can match without explicit whitespace handling.
final number = lexeme(digit().many1.capture.map(int.parse));

// Operator precedence with Pratt + the C-family preset
final expr = pratt<int>(
  number,
  cFamilyPrecedence<int>(
    sym: symbol,
    binary: (op, l, r) => switch (op) {
      '+' => l + r,
      '-' => l - r,
      '*' => l * r,
      '/' => l ~/ r,
      _ => throw UnsupportedError(op),
    },
    unary: (op, x) => op == '-' ? -x : x,
  ),
);
expr.run('1 + 2 * 3');
// Success(7, ...) — multiplicative binds tighter than additive
```

### Why Pratt + the preset

This was the natural shape of expression grammars in earlier rumil
versions too — six layered `chainl1` calls, one per precedence level.
0.7.0 unifies it:

- **Performance.** Single-pass operator dispatch replaces six dispatch
  layers. Measured 30–35% faster on `rumil_expressions` and 11–13%
  faster on HCL across the full bench matrix.
- **Stack safety.** `pratt`'s explicit operator stack handles
  right-associative chains and chained prefixes to memory-only depth.
  `chainl1` and `chainr1` were also promoted to first-class ADT cases
  with iterative interpretation (was StackOverflow at ~850 chain
  steps under the previous expansion).
- **Same correctness guarantees.** Left recursion via `rule()`
  (Warth seed-growth) still works as before — Pratt sits inside that
  story, not orthogonal to it. Typed errors with location, lazy error
  construction, parser inspection, memoization, all unchanged.
- **`chainl1` and `chainr1` still ship** for non-precedence folds.
  Pratt is recommended when you have actual operator precedence;
  `chainl1` is fine for a flat left-fold.

## Left recursion

Define left-recursive grammars directly. No transformation needed.

```dart
late final Parser<ParseError, int> expr;
expr = rule(() =>
    expr.thenSkip(char('+')).zip(digit().map(int.parse)).map(
          (pair) => pair.$1 + pair.$2)
        .or(digit().map(int.parse)));

expr.run('1+2+3'); // Success(6), parsed as (1+2)+3
```

Uses the Warth et al. seed-growth algorithm.

## Format parsers

```dart
import 'package:rumil_parsers/rumil_parsers.dart';

parseJson('{"name": "Rumil", "version": 1}');
parseCsv('a,b,c\n1,2,3');
parseXml('<root><child attr="v"/></root>');
parseToml('[server]\nhost = "localhost"\nport = 8080');
parseYaml('name: Alice\ntags:\n  - admin\n  - user\n');
parseHcl('resource "aws_instance" "web" {\n  ami = "abc"\n}\n');
```

All formats tested at 100% against their official spec test suites (7376 tests). See [rumil_parsers/CONFORMANCE.md](rumil_parsers/CONFORMANCE.md).

## Serialization

Every format has a serializer. Parse, transform, serialize back.

```dart
// JSON round-trip
final ast = parseJson('{"name":"Alice"}');
final json = serializeJson(ast, config: JsonFormatConfig.pretty);

// Encode Dart types to AST
final encoder = toJsonObject<Person>((b, p) {
  b.field('name', p.name, jsonStringEncoder);
  b.field('age', p.age, jsonIntEncoder);
});
final personJson = serializeJson(encoder.encode(person));
```

Serializers: `serializeJson`, `serializeToml`, `serializeYaml`, `serializeXml`, `serializeCsv`, `serializeProto`, `serializeHcl`.

## Expression evaluator

Parses into a typed `Expr` AST with error locations, then evaluates. The AST is inspectable and transformable before evaluation.

```dart
import 'package:rumil_expressions/rumil_expressions.dart';

evaluate('2 + 3 * 4');  // 14.0

final env = Environment.standard(
  variables: {'price': 100.0, 'tax': 0.25},
);
evaluate('price * (1 + tax)', env);  // 125.0

// Parse without evaluating
final ast = parse('a + b * c');
// BinaryOp('+', Variable('a'), BinaryOp('*', Variable('b'), Variable('c')))
```

## Binary codec

```dart
import 'package:rumil_codec/rumil_codec.dart';

// Primitive codecs
final bytes = intCodec.encode(42);     // ZigZag + LEB128 varint
final value = intCodec.decode(bytes);  // 42

// Compose for domain types
final personCodec = product2(stringCodec, intCodec).xmap(
  (r) => Person(r.$1, r.$2),
  (p) => (p.name, p.age),
);
```

## Combinator DSL

| Operation              | Syntax                              |
|------------------------|-------------------------------------|
| Sequence               | `p1.zip(p2)`                        |
| Keep left              | `p1.thenSkip(p2)`                   |
| Keep right             | `p1.skipThen(p2)`                   |
| Alternation            | `p1.or(p2)` or `p1 \| p2`           |
| Multi-way choice       | `choice([p1, p2, p3, ...])`         |
| First-char dispatch    | `firstCharChoice({'a': pa, ...})`   |
| Map                    | `p.map(f)`                          |
| FlatMap                | `p.flatMap(f)`                      |
| Many (0+)              | `p.many`                            |
| Many (1+)              | `p.many1`                           |
| Optional               | `p.optional`                        |
| Separated              | `p.sepBy(sep)`                      |
| Between                | `p.between(l, r)`                   |
| Operator precedence    | `pratt(atom, [InfixLeft(...), ...])`|
| Standard ops preset    | `cFamilyPrecedence(...)`            |
| Left chain (flat fold) | `p.chainl1(op)`                     |
| Right chain (flat fold)| `p.chainr1(op)`                     |
| Capture text           | `p.capture`                         |
| Memoize                | `p.memoize`                         |
| Left recursion         | `rule(() => ...)`                   |

## Design

Rumil represents parsers as a sealed ADT with 26 subtypes. An external interpreter dispatches over them via pattern matching. This separates data from behavior, which makes parsers inspectable and enables features like RadixNode optimization and construction-time map fusion.

Errors are typed (`ParseError` sealed hierarchy with line, column, and offset) and lazily constructed. On backtracking, error thunks for failing branches are never evaluated if another branch succeeds.

The trampoline is defunctionalized: Parser nodes are stored in the continuation stack and functions are applied within their declaring scope via `applyF`. This keeps FlatMap chains stack-safe to arbitrary depth.

No external runtime dependencies. Only `dart:typed_data` and `dart:convert`.

## Performance

Benchmarked against [petitparser](https://pub.dev/packages/petitparser). Both parsers build the same typed `JsonValue` AST to keep the comparison fair.

| Benchmark              | Rumil 0.7 | petitparser | Ratio |
|------------------------|-----------|-------------|-------|
| JSON small (39B)       | 18 μs     | 1.9 μs      | 10x   |
| JSON large (803KB)     | 312 ms    | 44 ms       | 7x    |
| Expression (simple)    | 6.5 μs    | 0.8 μs      | 8x    |
| Expression (100 terms) | 181 μs    | 28 μs       | 6x    |

Rumil is 6–10× slower than petitparser on native AOT, down from 10–13× in 0.6. This is the cost of the ADT interpreter architecture. Under dart2wasm the gap narrows further because sealed class dispatch compiles efficiently to WasmGC `br_on_cast` while petitparser's virtual dispatch compiles less efficiently to WasmGC indirect calls. WasmGC is consistently 2× faster than AOT native for Rumil parsers.

The 0.7 wins come from `pratt(...)` + `cFamilyPrecedence` (–30% on `rumil_expressions`, –11–13% on HCL) and `firstCharChoice` (–24–27% on JSON across all sizes), plus interpreter-level optimizations that apply transparently (FIRST-set Or dispatch, `Many(StringMatch)` / `SkipMany(simple)` fast paths, `Capture(Many)` fusion).

See [BENCHMARKS.md](BENCHMARKS.md) for methodology, the fair comparison breakdown, dart2wasm numbers, and format parser throughput. (BENCHMARKS.md is being refreshed for 0.7.0; the table above is the updated headline.)

**Different tradeoffs from petitparser:**

Petitparser uses virtual dispatch and mutable parsers, which gives it excellent throughput. Rumil uses a sealed ADT, immutable parsers, and an external interpreter. This costs throughput but adds left recursion (`rule()`), typed errors with source location, memoization, parser inspection, lazy error construction, and stack safety via trampolining. Different tradeoffs for different needs.

## License

MIT
