# rumil

Parser combinator library for Dart 3 with left recursion, typed errors, and stack safety.

Sealed ADT with 26 parser subtypes, external interpreter with defunctionalized trampoline, Warth seed-growth left recursion, and lazy error construction. Zero external dependencies.

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
