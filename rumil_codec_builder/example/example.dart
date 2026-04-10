import 'package:rumil_codec/rumil_codec.dart';
import 'package:rumil_parsers/rumil_parsers.dart';

part 'example.codec.g.dart';
part 'example.ast.g.dart';

@binarySerializable
@astSerializable
class Person {
  final String name;
  final int age;
  const Person(this.name, this.age);
}

@binarySerializable
@astSerializable
sealed class Shape {}

final class Circle extends Shape {
  final double radius;
  Circle(this.radius);
}

final class Rectangle extends Shape {
  final double width;
  final double height;
  Rectangle(this.width, this.height);
}

@binarySerializable
sealed class Expr {}

final class Lit extends Expr {
  final int value;
  Lit(this.value);
}

sealed class BinOp extends Expr {
  final Expr left;
  final Expr right;
  BinOp(this.left, this.right);
}

final class Add extends BinOp {
  Add(super.left, super.right);
}

final class Mul extends BinOp {
  Mul(super.left, super.right);
}
