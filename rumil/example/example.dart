import 'package:rumil/rumil.dart';

void main() {
  // Parse a number.
  final number = digit().many1.capture.map(int.parse);
  print(number.run('42')); // Success(42, consumed: 2)

  // Operator precedence with Pratt + the C-family preset (recommended
  // for grammars with multiple precedence levels).
  final expr = pratt<int>(
    lexeme(number),
    cFamilyPrecedence<int>(
      sym: symbol,
      binary:
          (op, l, r) => switch (op) {
            '+' => l + r,
            '-' => l - r,
            '*' => l * r,
            '/' => l ~/ r,
            _ => throw UnsupportedError(op),
          },
      unary: (op, x) => op == '-' ? -x : x,
    ),
  );
  print(expr.run('1 + 2 * 3')); // Success(7, ...) — `*` binds tighter
  print(expr.run('-2 * 3')); // Success(-6, ...) — prefix unary minus

  // chainl1 is still available for non-precedence left folds.
  final add = symbol('+').as<int Function(int, int)>((a, b) => a + b);
  final sum = number.chainl1(add);
  print(sum.run('1+2+3')); // Success(6, consumed: 5)

  // Left-recursive grammar via rule() — Warth seed-growth, no
  // grammar transformation required.
  late final Parser<ParseError, int> e;
  e = rule(
    () =>
        defer(
          () => e,
        ).flatMap((l) => char('+').skipThen(number).map((r) => l + r)) |
        number,
  );
  print(e.run('1+2+3')); // Success(6, consumed: 5)
}
