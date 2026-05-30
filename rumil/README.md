# rumil

Parser combinator library for Dart 3 with operator precedence, typed errors, and stack safety.

Sealed ADT with 34 parser subtypes, external interpreter built as a unified eval/apply (CEK) trampoline, and lazy error construction. Zero external dependencies.

Operator precedence is handled by `pratt(...)`, an iterative Pratt-as-a-combinator inspired by Lean 4: atoms and operator symbols are ordinary Rumil parsers, and chain depth lives on a heap-allocated frame stack instead of the Dart call stack. As of 0.10.0 every sub-parse re-entry rides the continuation chain, so stack safety is bounded by available memory on both operator width and structural nesting. This is verified in CI at 10 M operands (width) and 50 K levels (nesting), and validated locally at 1 B operands. `rule()` (Warth seed-growth) is also available for directly-left-recursive grammars that don't reduce to a binding-power table.

As of 0.10.0, the engine parses within about 1.1–1.3× of petitparser building the same typed AST (AOT 1.27×, JIT 1.31×, Wasm 1.12× on a large JSON doc); the 0.10 `SkipLeft`/`SkipRight` fusion and unified trampoline made it about 2× faster than 0.9.0. See [BENCHMARKS.md](../BENCHMARKS.md).

As of 0.9.0, rumil also produces lossless **green/red syntax trees** (the rust-analyzer/Rowan architecture, as combinators) with resilient error recovery and incremental reparse, for language tooling, linters, formatters, and code generators that need to keep a tree in sync with edits.

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

## Green/red trees and incremental reparse

Parsers can produce a position-independent, lossless `GreenNode` tree
instead of a plain value. A `RedTree` projects positions onto it on
demand; resilient combinators record errors *in* the tree; and an edit
updates the tree by reparsing only the affected region.

```dart
// A grammar declares its own token/syntax-node alphabets.
enum Tok { lparen, rparen, digit }
enum Syn { group }

// Build green trees with treeOf; recover with expectToken / syncUntil.
final group = treeOf<Tok, Syn>(Syn.group, [
  char('(').map((c) => GreenToken<Tok, Syn>(Tok.lparen, c)),
  digit().map((c) => GreenToken<Tok, Syn>(Tok.digit, c)),
  expectToken(Tok.rparen, // missing ')' becomes an in-tree placeholder
      char(')').map((c) => GreenToken<Tok, Syn>(Tok.rparen, c))),
]);

final result = group.run('(5');           // Partial: ')' is GreenMissing
final tree = (result as Partial).value;
GreenNodeOps.toSource<Tok, Syn>(tree);     // '(5' — lossless

// Edit incrementally: reparse only the affected region, share the rest.
final edit = TextEdit.insert(1, '9');      // '(95'
final updated = tree.applyEdit('(5', edit, parsers);  // structural sharing
```

An incremental edit reparses only the affected region rather than the
whole document — see the CHANGELOG and `rumil_bench/` for measured
per-edit numbers on AOT and dart2wasm.

See the [main README](https://github.com/hakimjonas/rumil-dart) for full documentation, combinator reference, and benchmarks.
