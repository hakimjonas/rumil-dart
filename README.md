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

// Compose parsers
final number = digit().many1.capture.map(int.parse);
final add = symbol('+').map((_) => (int a, int b) => a + b);
final expr = number.chainl1(add);
expr.run('1+2+3');
// Success(6, consumed: 5), left-associative
```

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

| Operation      | Syntax                    |
|----------------|---------------------------|
| Sequence       | `p1.zip(p2)`              |
| Keep left      | `p1.thenSkip(p2)`         |
| Keep right     | `p1.skipThen(p2)`         |
| Alternation    | `p1.or(p2)` or `p1 \| p2` |
| Map            | `p.map(f)`                |
| FlatMap        | `p.flatMap(f)`            |
| Many (0+)      | `p.many`                  |
| Many (1+)      | `p.many1`                 |
| Optional       | `p.optional`              |
| Separated      | `p.sepBy(sep)`            |
| Between        | `p.between(l, r)`         |
| Left chain     | `p.chainl1(op)`           |
| Right chain    | `p.chainr1(op)`           |
| Capture text   | `p.capture`               |
| Memoize        | `p.memoize`               |
| Left recursion | `rule(() => ...)`         |

## Design

Rumil represents parsers as a sealed ADT with 26 subtypes. An external interpreter dispatches over them via pattern matching. This separates data from behavior, which makes parsers inspectable and enables features like RadixNode optimization and construction-time map fusion.

Errors are typed (`ParseError` sealed hierarchy with line, column, and offset) and lazily constructed. On backtracking, error thunks for failing branches are never evaluated if another branch succeeds.

The trampoline is defunctionalized: Parser nodes are stored in the continuation stack and functions are applied within their declaring scope via `applyF`. This keeps FlatMap chains stack-safe to arbitrary depth.

No external runtime dependencies. Only `dart:typed_data` and `dart:convert`.

## Performance

Benchmarked against [petitparser](https://pub.dev/packages/petitparser). Both parsers build the same typed `JsonValue` AST to keep the comparison fair.

| Benchmark              | Rumil  | petitparser | Ratio |
|------------------------|--------|-------------|-------|
| JSON small (39B)       | 25 μs  | 2.0 μs      | 13x   |
| JSON large (803KB)     | 449 ms | 45 ms       | 10x   |
| Expression (simple)    | 11 μs  | 1.0 μs      | 11x   |
| Expression (100 terms) | 320 μs | 28 μs       | 11x   |

Rumil is 10-13x slower than petitparser on native AOT. This is the cost of the ADT interpreter architecture. Under dart2wasm the gap narrows to 3-4x because sealed class dispatch compiles efficiently to WasmGC `br_on_cast` while petitparser's virtual dispatch compiles less efficiently to WasmGC indirect calls. WasmGC is now consistently 2x faster than AOT native for Rumil parsers.

See [BENCHMARKS.md](BENCHMARKS.md) for methodology, the fair comparison breakdown, dart2wasm numbers, and format parser throughput.

**Different tradeoffs from petitparser:**

Petitparser uses virtual dispatch and mutable parsers, which gives it excellent throughput. Rumil uses a sealed ADT, immutable parsers, and an external interpreter. This costs throughput but adds left recursion (`rule()`), typed errors with source location, memoization, parser inspection, lazy error construction, and stack safety via trampolining. Different tradeoffs for different needs.

## License

MIT
