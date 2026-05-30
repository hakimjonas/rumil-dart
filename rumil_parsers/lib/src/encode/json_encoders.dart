/// Encoders for converting Dart types into [JsonValue] AST nodes.
library;

import '../ast/json.dart';
import 'encoder.dart';
import 'escape.dart';
import 'sink_walk.dart';

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
///
/// Thin wrapper over [serializeJsonTo]: buffers into a [StringBuffer] and
/// returns the result. Output is byte-for-byte identical to the streaming
/// form; the returned `String` is bounded by available heap (see
/// [serializeJsonTo] for streaming arbitrarily-large output).
String serializeJson(
  JsonValue value, {
  JsonFormatConfig config = JsonFormatConfig.compact,
}) {
  final buffer = StringBuffer();
  serializeJsonTo(buffer, value, config: config);
  return buffer.toString();
}

/// Serialize a [JsonValue] into [sink].
///
/// Iterative (see `sink_walk.dart`): an explicit worklist replaces recursive
/// descent, so arbitrarily-deep values serialize without overflowing the Dart
/// call stack. Pretty output (a non-empty [JsonFormatConfig.indent]) emits
/// `indent * depth` padding at every level, so its total size is Θ(depth²) —
/// the same as `jq` and `JSON.stringify(_, null, 2)`. Streaming to [sink]
/// keeps *peak memory* bounded regardless of that total.
void serializeJsonTo(
  StringSink sink,
  JsonValue value, {
  JsonFormatConfig config = JsonFormatConfig.compact,
}) {
  final indent = config.indent;
  final sortKeys = config.sortKeys;
  final pretty = indent.isNotEmpty;
  final walk = SinkWalk();

  // Mutually recursive *in scheduling* only — `emit` never calls `emit`; it
  // writes this node's own literal text and schedules one step per child.
  late final void Function(JsonValue, int) emit;
  emit = (JsonValue node, int depth) {
    switch (node) {
      case JsonNull():
        sink.write('null');
      case JsonBool(:final value):
        sink.write(value);
      case JsonInt(:final value):
        sink.write(value);
      case JsonDouble(:final value):
        sink.write(_doubleString(value));
      case JsonString(:final value):
        sink
          ..write('"')
          ..write(escapeJson(value))
          ..write('"');
      case JsonArray(:final elements):
        if (elements.isEmpty) {
          sink.write('[]');
          return;
        }
        final pad = indent * depth;
        final inner = indent * (depth + 1);
        sink.write(pretty ? '[\n' : '[');
        final steps = <SinkStep>[];
        for (var i = 0; i < elements.length; i++) {
          final e = elements[i];
          if (i > 0) steps.add(() => sink.write(pretty ? ',\n' : ','));
          if (pretty) steps.add(() => sink.write(inner));
          steps.add(() => emit(e, depth + 1));
        }
        steps.add(() => sink.write(pretty ? '\n$pad]' : ']'));
        walk.pushAll(steps);
      case JsonObject(:final fields):
        if (fields.isEmpty) {
          sink.write('{}');
          return;
        }
        final entries =
            sortKeys
                ? (fields.entries.toList()
                  ..sort((a, b) => a.key.compareTo(b.key)))
                : fields.entries.toList();
        final pad = indent * depth;
        final inner = indent * (depth + 1);
        sink.write(pretty ? '{\n' : '{');
        final steps = <SinkStep>[];
        for (var i = 0; i < entries.length; i++) {
          final entry = entries[i];
          if (i > 0) steps.add(() => sink.write(pretty ? ',\n' : ','));
          if (pretty) steps.add(() => sink.write(inner));
          steps.add(() {
            sink
              ..write('"')
              ..write(escapeJson(entry.key))
              ..write(pretty ? '": ' : '":');
          });
          steps.add(() => emit(entry.value, depth + 1));
        }
        steps.add(() => sink.write(pretty ? '\n$pad}' : '}'));
        walk.pushAll(steps);
    }
  };

  emit(value, 0);
  walk.run();
}

/// Render a [JsonDouble] value in source-shape-preserving form.
///
/// An integer-valued [double] (e.g. parsed from `1.0`) renders with a
/// trailing `.0` so it round-trips as `JsonDouble`, not `JsonInt`. A
/// non-integer-valued double renders via Dart's default `toString()`.
/// Non-finite values (`NaN`, `Infinity`) are not produced by the parser
/// — RFC 8259 forbids them — but if a consumer constructs one
/// programmatically the encoder lets Dart's default toString handle it.
String _doubleString(double value) =>
    value.isFinite && value == value.truncateToDouble()
        ? '${value.toInt()}.0'
        : '$value';

// ---- Implementations ----

final class _JsonIntEncoder implements AstEncoder<int, JsonValue> {
  const _JsonIntEncoder();
  @override
  JsonValue encode(int value) => JsonInt(value);
}

final class _JsonDoubleEncoder implements AstEncoder<double, JsonValue> {
  const _JsonDoubleEncoder();
  @override
  JsonValue encode(double value) => JsonDouble(value);
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
