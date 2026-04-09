/// Expression AST types.
library;

/// An expression node.
sealed class Expr {
  /// Base constructor.
  const Expr();
}

/// Numeric literal, e.g. `42` or `3.14`.
final class NumberLit extends Expr {
  /// The numeric value.
  final double value;

  /// Creates a number literal with [value].
  const NumberLit(this.value);
}

/// String literal, e.g. `"hello"`.
final class StringLit extends Expr {
  /// The string value.
  final String value;

  /// Creates a string literal with [value].
  const StringLit(this.value);
}

/// Boolean literal: `true` or `false`.
final class BoolLit extends Expr {
  /// The boolean value.
  final bool value;

  /// Creates a boolean literal with [value].
  const BoolLit(this.value);
}

/// Variable reference, e.g. `x` or `price`.
final class Variable extends Expr {
  /// The variable name.
  final String name;

  /// Creates a variable reference to [name].
  const Variable(this.name);
}

/// Unary operator application, e.g. `-x` or `!flag`.
final class UnaryOp extends Expr {
  /// The operator (`-` or `!`).
  final String op;

  /// The operand expression.
  final Expr operand;

  /// Creates a unary operation.
  const UnaryOp(this.op, this.operand);
}

/// Binary operator application, e.g. `a + b` or `x == y`.
final class BinaryOp extends Expr {
  /// The operator (`+`, `-`, `*`, `/`, `%`, `<`, `<=`, `>`, `>=`, `==`, `!=`, `&&`, `||`).
  final String op;

  /// The left operand.
  final Expr left;

  /// The right operand.
  final Expr right;

  /// Creates a binary operation.
  const BinaryOp(this.op, this.left, this.right);
}

/// Function call, e.g. `sqrt(x)` or `min(a, b)`.
final class FunctionCall extends Expr {
  /// The function name.
  final String name;

  /// The argument expressions.
  final List<Expr> args;

  /// Creates a function call.
  const FunctionCall(this.name, this.args);
}

/// Ternary conditional, e.g. `x > 0 ? x : -x`.
final class Conditional extends Expr {
  /// The condition expression (must evaluate to bool).
  final Expr condition;

  /// The expression returned when [condition] is true.
  final Expr then_;

  /// The expression returned when [condition] is false.
  final Expr else_;

  /// Creates a conditional expression.
  const Conditional(this.condition, this.then_, this.else_);
}
