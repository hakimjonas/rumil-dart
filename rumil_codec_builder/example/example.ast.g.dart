// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'example.dart';

// **************************************************************************
// AstEncoderGenerator
// **************************************************************************

class _$PersonJsonEncoder implements AstEncoder<Person, JsonValue> {
  const _$PersonJsonEncoder();

  @override
  JsonValue encode(Person value) {
    final b = ObjectBuilder<JsonValue>();
    b.field('name', value.name, jsonStringEncoder);
    b.field('age', value.age, jsonIntEncoder);
    return JsonObject(
      Map.fromEntries(b.entries.map((e) => MapEntry(e.$1, e.$2))),
    );
  }
}

const personJsonEncoder = _$PersonJsonEncoder();

class _$ShapeJsonEncoder implements AstEncoder<Shape, JsonValue> {
  const _$ShapeJsonEncoder();

  @override
  JsonValue encode(Shape value) {
    final b = ObjectBuilder<JsonValue>();
    switch (value) {
      case Circle():
        b.field('type', 'Circle', jsonStringEncoder);
        b.field('radius', value.radius, jsonDoubleEncoder);
      case Rectangle():
        b.field('type', 'Rectangle', jsonStringEncoder);
        b.field('width', value.width, jsonDoubleEncoder);
        b.field('height', value.height, jsonDoubleEncoder);
    }
    return JsonObject(
      Map.fromEntries(b.entries.map((e) => MapEntry(e.$1, e.$2))),
    );
  }
}

const shapeJsonEncoder = _$ShapeJsonEncoder();
