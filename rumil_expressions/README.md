# rumil_expressions

Formula evaluator built on [Rumil](https://pub.dev/packages/rumil): arithmetic, boolean logic, string operations, variables, and custom functions.

Parses into a typed, inspectable `Expr` AST with error locations, then evaluates. Supports `chainl1` for natural operator precedence.

## Usage

```dart
import 'package:rumil_expressions/rumil_expressions.dart';

// Simple evaluation
evaluate('2 + 3 * 4');  // 14.0

// Variables and functions
final env = Environment.standard(
  variables: {'price': 100.0, 'tax': 0.25},
);
evaluate('price * (1 + tax)', env);  // 125.0

// Parse without evaluating — inspect or transform the AST
final ast = parse('a + b * c');
```

See the [main README](https://github.com/hakimjonas/rumil-dart) for full documentation.
