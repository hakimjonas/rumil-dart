# rumil

Parser combinator library for Dart 3 with operator precedence, typed errors, and stack safety.

Sealed ADT with 26 parser subtypes, external interpreter with a defunctionalized trampoline, and lazy error construction. Zero external dependencies.

Operator precedence is handled by `pratt(...)`, an iterative Pratt-as-a-combinator inspired by Lean 4: atoms and operator symbols are ordinary Rumil parsers, and chain depth lives on a heap-allocated frame stack instead of the Dart call stack. Stack safety is bounded by available memory rather than the call stack — verified in CI at 10 M operands as a time-budget regression test, and locally at 1 B. `rule()` (Warth seed-growth) is also available for directly-left-recursive grammars that don't reduce to a binding-power table.

As of 0.7.1, runs within 1.7–3.2× of petitparser on dart2wasm and 5.5–10× on AOT, narrowing each release.

## Usage

```dart
import 'package:rumil/rumil.dart';

// Parse a number
final number = digit().many1.capture.map(int.parse);
number.run('42'); // Success(42, consumed: 2)

// Compose with operators
final add = symbol('+').as<int Function(int, int)>((a, b) => a + b);
final expr = number.chainl1(add);
expr.run('1+2+3'); // Success(6, consumed: 5)

// Left-recursive grammars work directly
late final Parser<ParseError, int> e;
e = rule(() =>
    defer(() => e).flatMap((l) =>
        char('+').skipThen(number).map((r) => l + r)) |
    number);
e.run('1+2+3'); // Success(6, consumed: 5)
```

See the [main README](https://github.com/hakimjonas/rumil-dart) for full documentation, combinator reference, and benchmarks.
