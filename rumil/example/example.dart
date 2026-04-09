import 'package:rumil/rumil.dart';

void main() {
  // Parse a number
  final number = digit().many1.capture.map(int.parse);
  print(number.run('42')); // Success(42, consumed: 2)

  // Left-associative operator chain
  final add = symbol('+').as<int Function(int, int)>((a, b) => a + b);
  final expr = number.chainl1(add);
  print(expr.run('1+2+3')); // Success(6, consumed: 5)

  // Left-recursive grammar via rule()
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
