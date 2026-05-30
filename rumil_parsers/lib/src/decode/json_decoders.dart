/// Decoders for converting [JsonValue] AST nodes into Dart types.
library;

import '../ast/json.dart';
import 'decoder.dart';
import 'iterative.dart';

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

/// Decoder for JSON integer-shaped numbers.
///
/// Accepts both [JsonInt] (returned directly) and [JsonDouble] (lossy
/// narrowing via `value.toInt()` — the fractional part is discarded).
/// Matches the pre-0.8.0 behaviour on edge cases where the value was
/// stored as a double but the consumer wanted an int.
final class _JsonInt implements AstDecoder<JsonValue, int> {
  const _JsonInt();
  @override
  int decode(JsonValue value) => switch (value) {
    JsonInt(:final value) => value,
    JsonDouble(:final value) => value.toInt(),
    _ => throw DecodeException('Expected number, got ${value.runtimeType}'),
  };
}

/// Decoder for JSON floating-point numbers.
///
/// Accepts both [JsonDouble] (returned directly) and [JsonInt]
/// (widening via `value.toDouble()` — exact for values up to 2^53,
/// lossy beyond). Matches the pre-0.8.0 behaviour where any number
/// could be read as a double.
final class _JsonDouble implements AstDecoder<JsonValue, double> {
  const _JsonDouble();
  @override
  double decode(JsonValue value) => switch (value) {
    JsonDouble(:final value) => value,
    JsonInt(:final value) => value.toDouble(),
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

/// Iterative (composite) decoders carry the reified element-type cast inside
/// the typed class so the erased [decodeIterative] driver stays stack-safe to
/// arbitrary nesting depth. `decode` keeps its direct recursive form for the
/// shallow case and delegates to the driver, casting the erased result back to
/// the declared type at the one confined boundary.
final class _JsonList<A>
    implements AstDecoder<JsonValue, List<A>>, IterativeDecoder<JsonValue> {
  final AstDecoder<JsonValue, A> _element;
  const _JsonList(this._element);
  @override
  List<A> decode(JsonValue value) =>
      decodeIterative<JsonValue>(this, value) as List<A>;
  @override
  (List<(AstDecoder<JsonValue, Object?>, JsonValue)>, Reassemble) expand(
    JsonValue value,
  ) => switch (value) {
    JsonArray(:final elements) => (
      [for (final e in elements) (_element, e)],
      (results) => results.cast<A>(),
    ),
    _ => throw DecodeException('Expected array, got ${value.runtimeType}'),
  };
}

final class _JsonNullable<A>
    implements AstDecoder<JsonValue, A?>, IterativeDecoder<JsonValue> {
  final AstDecoder<JsonValue, A> _inner;
  const _JsonNullable(this._inner);
  @override
  A? decode(JsonValue value) => decodeIterative<JsonValue>(this, value) as A?;
  @override
  (List<(AstDecoder<JsonValue, Object?>, JsonValue)>, Reassemble) expand(
    JsonValue value,
  ) => switch (value) {
    JsonNull() => (const [], (_) => null),
    _ => ([(_inner, value)], (results) => results[0] as A),
  };
}

final class _JsonMap<A>
    implements
        AstDecoder<JsonValue, Map<String, A>>,
        IterativeDecoder<JsonValue> {
  final AstDecoder<JsonValue, A> _value;
  const _JsonMap(this._value);
  @override
  Map<String, A> decode(JsonValue value) =>
      decodeIterative<JsonValue>(this, value) as Map<String, A>;
  @override
  (List<(AstDecoder<JsonValue, Object?>, JsonValue)>, Reassemble) expand(
    JsonValue value,
  ) => switch (value) {
    JsonObject(:final fields) => (
      [for (final v in fields.values) (_value, v)],
      (results) {
        final keys = fields.keys.toList();
        return <String, A>{
          for (var i = 0; i < keys.length; i++) keys[i]: results[i] as A,
        };
      },
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
