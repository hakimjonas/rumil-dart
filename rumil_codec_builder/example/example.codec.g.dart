// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'example.dart';

// **************************************************************************
// CodecGenerator
// **************************************************************************

class _$PersonCodec implements BinaryCodec<Person> {
  const _$PersonCodec();

  @override
  void write(ByteWriter writer, Person value) {
    stringCodec.write(writer, value.name);
    intCodec.write(writer, value.age);
  }

  @override
  Person read(ByteReader reader) =>
      Person(stringCodec.read(reader), intCodec.read(reader));
}

const personCodec = _$PersonCodec();

class _$ShapeCodec implements BinaryCodec<Shape> {
  const _$ShapeCodec();

  @override
  void write(ByteWriter writer, Shape value) {
    switch (value) {
      case Circle():
        Varint.write(writer, 0);
        doubleCodec.write(writer, value.radius);
      case Rectangle():
        Varint.write(writer, 1);
        doubleCodec.write(writer, value.width);
        doubleCodec.write(writer, value.height);
    }
  }

  @override
  Shape read(ByteReader reader) {
    final ordinal = Varint.read(reader);
    return switch (ordinal) {
      0 => Circle(doubleCodec.read(reader)),
      1 => Rectangle(doubleCodec.read(reader), doubleCodec.read(reader)),
      _ => throw InvalidOrdinal(ordinal, 1, reader.offset),
    };
  }
}

const shapeCodec = _$ShapeCodec();

class _$ExprCodec implements BinaryCodec<Expr> {
  const _$ExprCodec();

  @override
  void write(ByteWriter writer, Expr value) {
    switch (value) {
      case Lit():
        Varint.write(writer, 0);
        intCodec.write(writer, value.value);
      case Add():
        Varint.write(writer, 1);
        exprCodec.write(writer, value.left);
        exprCodec.write(writer, value.right);
      case Mul():
        Varint.write(writer, 2);
        exprCodec.write(writer, value.left);
        exprCodec.write(writer, value.right);
    }
  }

  @override
  Expr read(ByteReader reader) {
    final ordinal = Varint.read(reader);
    return switch (ordinal) {
      0 => Lit(intCodec.read(reader)),
      1 => Add(exprCodec.read(reader), exprCodec.read(reader)),
      2 => Mul(exprCodec.read(reader), exprCodec.read(reader)),
      _ => throw InvalidOrdinal(ordinal, 2, reader.offset),
    };
  }
}

const exprCodec = _$ExprCodec();
