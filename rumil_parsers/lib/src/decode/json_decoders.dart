/// Decoders for converting [JsonValue] AST nodes into Dart types.
library;

import '../ast/json.dart';
import 'decoder.dart';

// ---- Primitive decoders ----

/// Decode a JSON number as [int].
const AstDecoder<JsonValue, int> jsonInt = _JsonInt();

/// Decode a JSON number as [double].
const AstDecoder<JsonValue, double> jsonDouble = _JsonDouble();

/// Decode a JSON string as [String].
const AstDecoder<JsonValue, String> jsonString = _JsonString();

/// Decode a JSON boolean as [bool].
const AstDecoder<JsonValue, bool> jsonBool = _JsonBool();

// ---- Composite decoders ----

/// Decode a JSON array as `List<A>`.
AstDecoder<JsonValue, List<A>> jsonListOf<A>(
  AstDecoder<JsonValue, A> element,
) => _JsonList<A>(element);

/// Decode a JSON value as nullable `A?` (null-safe).
AstDecoder<JsonValue, A?> jsonNullableOf<A>(AstDecoder<JsonValue, A> inner) =>
    _JsonNullable<A>(inner);

/// Decode a JSON object as `Map<String, A>`.
AstDecoder<JsonValue, Map<String, A>> jsonMapOf<A>(
  AstDecoder<JsonValue, A> value,
) => _JsonMap<A>(value);

// ---- Object decoder ----

/// Decode a JSON object into a typed value using field accessors.
AstDecoder<JsonValue, A> fromJsonObject<A>(
  A Function(ObjectAccessor<JsonValue>) build,
) => _JsonObjectDecoder<A>(build);

/// Structural navigation for [JsonObject] fields.
const AstStruct<JsonValue> jsonStruct = _JsonStruct();

// ---- Implementations ----

final class _JsonInt implements AstDecoder<JsonValue, int> {
  const _JsonInt();
  @override
  int decode(JsonValue value) => switch (value) {
    JsonNumber(:final value) => value.toInt(),
    _ => throw DecodeException('Expected number, got ${value.runtimeType}'),
  };
}

final class _JsonDouble implements AstDecoder<JsonValue, double> {
  const _JsonDouble();
  @override
  double decode(JsonValue value) => switch (value) {
    JsonNumber(:final value) => value,
    _ => throw DecodeException('Expected number, got ${value.runtimeType}'),
  };
}

final class _JsonString implements AstDecoder<JsonValue, String> {
  const _JsonString();
  @override
  String decode(JsonValue value) => switch (value) {
    JsonString(:final value) => value,
    _ => throw DecodeException('Expected string, got ${value.runtimeType}'),
  };
}

final class _JsonBool implements AstDecoder<JsonValue, bool> {
  const _JsonBool();
  @override
  bool decode(JsonValue value) => switch (value) {
    JsonBool(:final value) => value,
    _ => throw DecodeException('Expected boolean, got ${value.runtimeType}'),
  };
}

final class _JsonList<A> implements AstDecoder<JsonValue, List<A>> {
  final AstDecoder<JsonValue, A> _element;
  const _JsonList(this._element);
  @override
  List<A> decode(JsonValue value) => switch (value) {
    JsonArray(:final elements) => elements.map(_element.decode).toList(),
    _ => throw DecodeException('Expected array, got ${value.runtimeType}'),
  };
}

final class _JsonNullable<A> implements AstDecoder<JsonValue, A?> {
  final AstDecoder<JsonValue, A> _inner;
  const _JsonNullable(this._inner);
  @override
  A? decode(JsonValue value) => switch (value) {
    JsonNull() => null,
    _ => _inner.decode(value),
  };
}

final class _JsonMap<A> implements AstDecoder<JsonValue, Map<String, A>> {
  final AstDecoder<JsonValue, A> _value;
  const _JsonMap(this._value);
  @override
  Map<String, A> decode(JsonValue value) => switch (value) {
    JsonObject(:final fields) => fields.map(
      (k, v) => MapEntry(k, _value.decode(v)),
    ),
    _ => throw DecodeException('Expected object, got ${value.runtimeType}'),
  };
}

final class _JsonStruct implements AstStruct<JsonValue> {
  const _JsonStruct();
  @override
  JsonValue? getField(JsonValue value, String name) => switch (value) {
    JsonObject(:final fields) => fields[name],
    _ => null,
  };
}

final class _JsonObjectDecoder<A> implements AstDecoder<JsonValue, A> {
  final A Function(ObjectAccessor<JsonValue>) _build;
  const _JsonObjectDecoder(this._build);
  @override
  A decode(JsonValue value) =>
      _build(ObjectAccessor<JsonValue>(value, jsonStruct));
}
