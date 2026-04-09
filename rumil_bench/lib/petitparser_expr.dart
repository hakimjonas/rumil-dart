/// Petitparser expression evaluator for comparison.
library;

import 'package:petitparser/petitparser.dart';

final Parser<num> petitExpr = _buildExprParser();

Parser<num> _buildExprParser() {
  final builder = ExpressionBuilder<num>();
  builder.primitive(
    (pattern('+-').optional() &
            digit().plus() &
            (char('.') & digit().plus()).optional())
        .flatten()
        .trim()
        .map(num.parse),
  );
  builder.group().wrapper(
    char('(').trim(),
    char(')').trim(),
    (left, value, right) => value,
  );
  builder.group().prefix(char('-').trim(), (op, a) => -a);
  builder.group()
    ..left(char('*').trim(), (a, op, b) => a * b)
    ..left(char('/').trim(), (a, op, b) => a / b)
    ..left(char('%').trim(), (a, op, b) => a % b);
  builder.group()
    ..left(char('+').trim(), (a, op, b) => a + b)
    ..left(char('-').trim(), (a, op, b) => a - b);
  return builder.build().end();
}
