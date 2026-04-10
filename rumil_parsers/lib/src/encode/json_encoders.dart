/// Encoders for converting Dart types into [JsonValue] AST nodes.
library;

import '../ast/json.dart';
import 'encoder.dart';
import 'escape.dart';

// ---- Primitive encoders ----

/// Encode an [int] as a JSON number.
const AstEncoder<int, JsonValue> jsonIntEncoder = _JsonIntEncoder();

/// Encode a [double] as a JSON number.
const AstEncoder<double, JsonValue> jsonDoubleEncoder = _JsonDoubleEncoder();

/// Encode a [String] as a JSON string.
const AstEncoder<String, JsonValue> jsonStringEncoder = _JsonStringEncoder();

/// Encode a [bool] as a JSON boolean.
const AstEncoder<bool, JsonValue> jsonBoolEncoder = _JsonBoolEncoder();

// ---- Composite encoders ----

/// Encode a `List<A>` as a JSON array.
AstEncoder<List<A>, JsonValue> jsonListEncoder<A>(
  AstEncoder<A, JsonValue> element,
) => _JsonListEncoder<A>(element);

/// Encode a nullable `A?` (null becomes JSON null).
AstEncoder<A?, JsonValue> jsonNullableEncoder<A>(
  AstEncoder<A, JsonValue> inner,
) => _JsonNullableEncoder<A>(inner);

/// Encode a `Map<String, A>` as a JSON object.
AstEncoder<Map<String, A>, JsonValue> jsonMapEncoder<A>(
  AstEncoder<A, JsonValue> value,
) => _JsonMapEncoder<A>(value);

// ---- Object encoder ----

/// Encode a typed value as a JSON object using field builders.
AstEncoder<A, JsonValue> toJsonObject<A>(
  void Function(ObjectBuilder<JsonValue> builder, A value) build,
) => _JsonObjectEncoder<A>(build);

// ---- Configuration ----

/// Configuration for JSON serialization.
class JsonFormatConfig {
  /// Indentation string (empty = compact).
  final String indent;

  /// Whether to sort object keys alphabetically.
  final bool sortKeys;

  /// Creates a format configuration.
  const JsonFormatConfig({this.indent = '', this.sortKeys = false});

  /// Compact output, no whitespace.
  static const compact = JsonFormatConfig();

  /// Pretty-printed with 2-space indent.
  static const pretty = JsonFormatConfig(indent: '  ');
}

// ---- Serializer ----

/// Serialize a [JsonValue] to a JSON string.
String serializeJson(
  JsonValue value, {
  JsonFormatConfig config = JsonFormatConfig.compact,
}) =>
    config.indent.isEmpty
        ? _compact(value, config.sortKeys)
        : _pretty(value, config.indent, config.sortKeys, 0);

String _compact(JsonValue value, bool sortKeys) => switch (value) {
  JsonNull() => 'null',
  JsonBool(:final value) => '$value',
  JsonNumber(:final value) =>
    value == value.truncateToDouble() ? value.toInt().toString() : '$value',
  JsonString(:final value) => '"${escapeJson(value)}"',
  JsonArray(:final elements) =>
    '[${elements.map((e) => _compact(e, sortKeys)).join(',')}]',
  JsonObject(:final fields) => () {
    final entries =
        sortKeys
            ? (fields.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
            : fields.entries;
    return '{${entries.map((e) => '"${escapeJson(e.key)}":${_compact(e.value, sortKeys)}').join(',')}}';
  }(),
};

String _pretty(JsonValue value, String indent, bool sortKeys, int depth) {
  final pad = indent * depth;
  final inner = indent * (depth + 1);
  return switch (value) {
    JsonNull() => 'null',
    JsonBool(:final value) => '$value',
    JsonNumber(:final value) =>
      value == value.truncateToDouble() ? value.toInt().toString() : '$value',
    JsonString(:final value) => '"${escapeJson(value)}"',
    JsonArray(:final elements) =>
      elements.isEmpty
          ? '[]'
          : '[\n${elements.map((e) => '$inner${_pretty(e, indent, sortKeys, depth + 1)}').join(',\n')}\n$pad]',
    JsonObject(:final fields) => () {
      final entries =
          sortKeys
              ? (fields.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key)))
              : fields.entries;
      return fields.isEmpty
          ? '{}'
          : '{\n${entries.map((e) => '$inner"${escapeJson(e.key)}": ${_pretty(e.value, indent, sortKeys, depth + 1)}').join(',\n')}\n$pad}';
    }(),
  };
}

// ---- Implementations ----

final class _JsonIntEncoder implements AstEncoder<int, JsonValue> {
  const _JsonIntEncoder();
  @override
  JsonValue encode(int value) => JsonNumber(value.toDouble());
}

final class _JsonDoubleEncoder implements AstEncoder<double, JsonValue> {
  const _JsonDoubleEncoder();
  @override
  JsonValue encode(double value) => JsonNumber(value);
}

final class _JsonStringEncoder implements AstEncoder<String, JsonValue> {
  const _JsonStringEncoder();
  @override
  JsonValue encode(String value) => JsonString(value);
}

final class _JsonBoolEncoder implements AstEncoder<bool, JsonValue> {
  const _JsonBoolEncoder();
  @override
  JsonValue encode(bool value) => JsonBool(value);
}

final class _JsonListEncoder<A> implements AstEncoder<List<A>, JsonValue> {
  final AstEncoder<A, JsonValue> _element;
  const _JsonListEncoder(this._element);
  @override
  JsonValue encode(List<A> value) =>
      JsonArray(value.map(_element.encode).toList());
}

final class _JsonNullableEncoder<A> implements AstEncoder<A?, JsonValue> {
  final AstEncoder<A, JsonValue> _inner;
  const _JsonNullableEncoder(this._inner);
  @override
  JsonValue encode(A? value) =>
      value == null ? const JsonNull() : _inner.encode(value);
}

final class _JsonMapEncoder<A>
    implements AstEncoder<Map<String, A>, JsonValue> {
  final AstEncoder<A, JsonValue> _value;
  const _JsonMapEncoder(this._value);
  @override
  JsonValue encode(Map<String, A> value) =>
      JsonObject(value.map((k, v) => MapEntry(k, _value.encode(v))));
}

final class _JsonObjectEncoder<A> implements AstEncoder<A, JsonValue> {
  final void Function(ObjectBuilder<JsonValue>, A) _build;
  const _JsonObjectEncoder(this._build);
  @override
  JsonValue encode(A value) {
    final builder = ObjectBuilder<JsonValue>();
    _build(builder, value);
    return JsonObject(
      Map.fromEntries(builder.entries.map((f) => MapEntry(f.$1, f.$2))),
    );
  }
}
