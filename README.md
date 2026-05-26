# Rumil

[![CI](https://github.com/hakimjonas/rumil-dart/actions/workflows/ci.yml/badge.svg)](https://github.com/hakimjonas/rumil-dart/actions/workflows/ci.yml)

Parser combinators for Dart 3 with operator precedence, typed line/column errors, and memory-bounded stack safety — alongside spec-conformant parsers for JSON, YAML, TOML, HCL, CSV, XML, Proto3, and CommonMark Markdown built on the same primitives.

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

Rumil represents parsers as a sealed ADT with 26 subtypes. An external interpreter dispatches over them via pattern matching. This separates data from behavior, which makes parsers inspectable and enables features like RadixNode optimization and construction-time map fusion.

Errors are typed (`ParseError` sealed hierarchy with line, column, and offset) and lazily constructed. On backtracking, error thunks for failing branches are never evaluated if another branch succeeds.

The trampoline is defunctionalized: Parser nodes are stored in the continuation stack and functions are applied within their declaring scope via `applyF`. This keeps FlatMap chains stack-safe to arbitrary depth.

No external runtime dependencies. Only `dart:typed_data` and `dart:convert`.

## Performance

Benchmarked against [petitparser](https://pub.dev/packages/petitparser). Both parsers build the same typed `JsonValue` AST so the comparison is fair.

### AOT native

| Benchmark              | Rumil 0.7.1 | petitparser | Ratio |
|------------------------|-------------|-------------|-------|
| JSON small (39 B)      | 15.9 μs     | 2.0 μs      | 8.0×  |
| JSON medium (45 KB)    | 22.7 ms     | 2.8 ms      | 8.0×  |
| JSON large (803 KB)    | 256 ms      | 47 ms       | 5.5×  |
| Expression (simple)    | 6.4 μs      | 0.75 μs     | 8.5×  |
| Expression (100 terms) | 169 μs      | 27 μs       | 6.2×  |

### dart2wasm (WasmGC)

| Benchmark              | Rumil 0.7.1 | petitparser | Ratio |
|------------------------|-------------|-------------|-------|
| JSON small (39 B)      | 5.6 μs      | 2.6 μs      | 2.2×  |
| JSON medium (45 KB)    | 9.3 ms      | 3.8 ms      | 2.4×  |
| JSON large (803 KB)    | 107 ms      | 63 ms       | 1.7×  |
| Expression (simple)    | 3.5 μs      | 1.2 μs      | 2.9×  |
| Expression (100 terms) | 95 μs       | 47 μs       | 2.0×  |

Trajectory: AOT was 10–13× slower in 0.6, 6–10× in 0.7.0, and 5.5–10× in 0.7.1 — the large-input case has dropped below 6×. WASM was 3–4.4× in 0.7.0 and is 1.7–3.2× in 0.7.1.

The gap narrows because sealed-ADT dispatch compiles efficiently to WasmGC's `br_on_cast`, while petitparser's virtual dispatch compiles to WasmGC indirect calls — and because the 0.7.1 hot/cold split shrank the interpreter's hot dispatch path by 39%. WasmGC is consistently around 2× faster than AOT native for Rumil; petitparser is around 1.4× *slower* under WasmGC than AOT.

The 0.7.x wins come from `pratt(...)` + `cFamilyPrecedence` (–30% on `rumil_expressions`, –11–13% on HCL), `firstCharChoice` (–24–27% on JSON), the FIRST-set `Or` dispatch and `Many(StringMatch)` fast paths (4–6% across the format suite in 0.7.0), and the 0.7.1 hot/cold split (a further 4–6% on the format suite, 9–14% on the dispatch microbench).

See [BENCHMARKS.md](BENCHMARKS.md) for methodology, the fair-comparison breakdown, dart2wasm numbers, and format parser throughput.

### What Rumil offers in exchange

The interpreter architecture costs throughput but buys a different set of properties:

- **Pratt-as-a-combinator for operator precedence.** Atoms and operator symbols are ordinary Rumil parsers, composed into a `pratt(...)` node. The interpreter walks operators iteratively over an explicit frame stack — chain depth lives in heap-allocated frames, not in the Dart call stack. When every operator symbol is a literal prefix, the builder compiles a first-code-unit dispatch table with longest-prefix-first ordering and optional word-boundary or not-followed-by guards for keyword and ambiguity cases. Inspired by Lean 4's Pratt-in-combinators approach (Pratt embedded in the combinator framework, leading/trailing split, first-token dispatch). `rule()` (Warth seed-growth) is still available for directly-left-recursive grammars that don't reduce to a binding-power table.
- **Memory-bounded stack safety.** The defunctionalized trampoline keeps the Dart call stack constant regardless of grammar depth or input length; pending operations live on heap-allocated frame stacks. The chain primitives (`flatMap`, `chainl1`, `chainr1`, Pratt left-/right-associative, Pratt prefix) are exercised at 10 million operands in CI as a time-budget regression test, and have been validated locally at 1 billion operands. The practical ceiling is available memory, not the call stack.
- **Typed errors with location.** `ParseError` is a sealed hierarchy carrying line, column, and offset; backtracking branches that fail never construct their error message, thanks to nullable-cache thunks.
- **Inspectable parsers.** Sealed-ADT nodes can be analyzed and rewritten at construction time — the FIRST-set `Or` rewrite, `Capture(Many)` fusion, and the Pratt op-table compilation all use this.

## License

MIT
