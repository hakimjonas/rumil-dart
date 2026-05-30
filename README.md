# Rumil

[![CI](https://github.com/hakimjonas/rumil-dart/actions/workflows/ci.yml/badge.svg)](https://github.com/hakimjonas/rumil-dart/actions/workflows/ci.yml)

Parser combinators for Dart 3 with operator precedence, typed line/column errors, and memory-bounded stack safety, alongside spec-conformant parsers for JSON, YAML, TOML, HCL, CSV, XML, Proto3, and CommonMark Markdown built on the same primitives.

*Rumil invented the first writing system (the Sarati) in Tolkien's legendarium. This library parses text into structure.*

## Packages

| Package             | Description                                                                                                     |
|---------------------|-----------------------------------------------------------------------------------------------------------------|
| `rumil`             | Core combinator framework. Sealed Parser ADT, defunctionalized trampoline, Pratt-as-a-combinator, memoization.  |
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

- **Performance.** Single-pass operator dispatch replaces a stack of layered `chainl1` calls. Measured 30–35% faster on `rumil_expressions` and 11–13% faster on HCL across the full bench matrix.
- **Stack safety.** Pratt's iterative interpretation handles right-associative chains and chained prefixes to memory-only depth. `chainl1` and `chainr1` are also first-class ADT cases with iterative interpretation.
- **Typed errors with location, lazy error construction, parser inspection, and memoization are unchanged.** `rule()` (Warth seed-growth) remains available for directly-left-recursive grammars that don't reduce to a binding-power table.
- **`chainl1` and `chainr1` still ship** for non-precedence folds. Reach for `pratt` when you have actual operator precedence; `chainl1` is enough for a flat left-fold.

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

Rumil represents parsers as a sealed ADT with 34 subtypes. An external interpreter dispatches over them via pattern matching. This separates data from behavior, which makes parsers inspectable and enables features like RadixNode optimization, construction-time map fusion, and the `skipThen`/`thenSkip` → `SkipLeft`/`SkipRight` rewrite.

Errors are typed (`ParseError` sealed hierarchy with line, column, and offset) and lazily constructed. On backtracking, error thunks for failing branches are never evaluated if another branch succeeds.

The interpreter is a single eval/apply trampoline (a defunctionalized CEK machine) in which every sub-parse re-entry rides a heap-allocated continuation chain rather than the Dart call stack. This keeps parsing memory-bounded, not call-stack-bounded, on both operator width and structural nesting depth.

No external runtime dependencies. Only `dart:typed_data` and `dart:convert`.

## Performance

Benchmarked against [petitparser](https://pub.dev/packages/petitparser). Each library runs its own idiomatic parser on petitparser's own grammars and inputs, with output verified equal before timing. Two axes are reported because the libraries make different choices: **to-typed** (both build the same typed `JsonValue` AST, isolating the parser engine) and **to-native** (plain `Map`/`List`, where Rumil makes a second conversion pass petitparser does not). Numbers are medians of three runs on a Ryzen 9 9950X3D, Dart 3.12.0.

### JSON to-typed — engine vs engine (μs/op, large 47.7 KB doc)

| Runtime | Rumil | petitparser | Ratio |
|---------|------:|------------:|------:|
| AOT     |  3736 |        2931 | 1.27× |
| JIT     |  3919 |        2994 | 1.31× |
| Wasm    |  4678 |        4189 | 1.12× |

As of 0.10.0 the engine parses within about 1.1–1.3× of petitparser building the same typed tree. On plain native `Map`/`List` output the ratio is about 2.2–3.3× (AOT 3.3×, Wasm 2.2×), almost all of it the second conversion pass; `dart:convert` is the right tool when you only want native data.

The AOT gap has come down from 10–13× in 0.6 and 5.5–10× in 0.7.1. The 0.10.0 `skipThen`/`thenSkip` → `SkipLeft`/`SkipRight` fusion and unified CEK trampoline (which also made nesting stack-safe) made the engine about 2× faster than 0.9.0.

AOT is the fastest runtime in 0.10.0, where earlier releases had WasmGC ahead. The 0.10 changes reduce dispatch and allocation, and the AOT optimizer benefits from that more than dart2wasm does. Rumil on Wasm runs about 1.05–1.8× slower than on AOT (Markdown is slightly faster on Wasm). Two things hold up under WasmGC: Rumil's sealed-ADT `br_on_cast` dispatch degrades less from AOT to Wasm than petitparser's virtual dispatch (1.25× vs 1.43× on the large doc), so the gap to petitparser narrows from 1.27× on AOT to 1.12× on Wasm; and `dart:convert`'s native decoder is itself faster on Wasm than AOT in these runs, so WasmGC is not a penalty here.

See [BENCHMARKS.md](BENCHMARKS.md) for the full AOT/JIT/Wasm matrix, expression and format-parser throughput, stack-safety verification, and methodology.

### What Rumil offers in exchange

The interpreter architecture costs throughput but buys a different set of properties:

- **Pratt-as-a-combinator for operator precedence.** Atoms and operator symbols are ordinary Rumil parsers, composed into a `pratt(...)` node. The interpreter walks operators iteratively over an explicit frame stack, so chain depth lives in heap-allocated frames, not in the Dart call stack. When every operator symbol is a literal prefix, the builder compiles a first-code-unit dispatch table with longest-prefix-first ordering and optional word-boundary or not-followed-by guards for keyword and ambiguity cases. Inspired by Lean 4's Pratt-in-combinators approach (Pratt embedded in the combinator framework, leading/trailing split, first-token dispatch). `rule()` (Warth seed-growth) is still available for directly-left-recursive grammars that don't reduce to a binding-power table.
- **Memory-bounded stack safety on both width and nesting.** The unified CEK trampoline keeps the Dart call stack constant regardless of grammar depth or input length; pending operations live on heap-allocated frame stacks. This holds on both axes: operator width (flat chains such as `flatMap`, `chainl1`, `chainr1`, and Pratt operator runs, exercised at 10 million operands in CI and validated locally at 1 billion) and structural nesting (`[[[…]]]`, `(((…)))`, deeply nested objects, exercised at 50,000 levels in CI across the four sub-parse shapes). Before 0.10.0 the nesting axis recursed on the host stack and overflowed at roughly 600–2000 levels; it is now bounded by heap, like width. The practical ceiling is available memory, not the call stack.
- **Typed errors with location.** `ParseError` is a sealed hierarchy carrying line, column, and offset; backtracking branches that fail never construct their error message, thanks to nullable-cache thunks.
- **Inspectable parsers.** Sealed-ADT nodes can be analyzed and rewritten at construction time; the FIRST-set `Or` rewrite, `Capture(Many)` fusion, and the Pratt op-table compilation all use this.

## License

MIT
