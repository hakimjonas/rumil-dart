import 'package:rumil_expressions/rumil_expressions.dart';

void main() {
  // Simple arithmetic
  print(evaluate('2 + 3 * 4')); // 14.0

  // Variables
  final env = Environment.standard(variables: {'price': 100.0, 'tax': 0.25});
  print(evaluate('price * (1 + tax)', env)); // 125.0

  // Custom functions
  final custom = Environment.standard(
    functions: {
      'clamp':
          (args) =>
              (args[0] as double).clamp(args[1] as double, args[2] as double),
    },
  );
  print(evaluate('clamp(150, 0, 100)', custom)); // 100.0

  // Ternary
  print(evaluate('3 > 2 ? "yes" : "no"')); // yes
}
