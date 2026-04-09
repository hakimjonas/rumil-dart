/// Expression AST types.
library;

/// An expression node.
sealed class Expr {
  const Expr();
}

final class NumberLit extends Expr {
  final double value;
  const NumberLit(this.value);
}

final class StringLit extends Expr {
  final String value;
  const StringLit(this.value);
}

final class BoolLit extends Expr {
  final bool value;
  const BoolLit(this.value);
}

final class Variable extends Expr {
  final String name;
  const Variable(this.name);
}

final class UnaryOp extends Expr {
  final String op;
  final Expr operand;
  const UnaryOp(this.op, this.operand);
}

final class BinaryOp extends Expr {
  final String op;
  final Expr left;
  final Expr right;
  const BinaryOp(this.op, this.left, this.right);
}

final class FunctionCall extends Expr {
  final String name;
  final List<Expr> args;
  const FunctionCall(this.name, this.args);
}

final class Conditional extends Expr {
  final Expr condition;
  final Expr then_;
  final Expr else_;
  const Conditional(this.condition, this.then_, this.else_);
}
