/// JSON AST types.
library;

/// A JSON value.
sealed class JsonValue {
  const JsonValue();
}

final class JsonNull extends JsonValue {
  const JsonNull();
  @override
  String toString() => 'null';
}

final class JsonBool extends JsonValue {
  final bool value;
  const JsonBool(this.value);
  @override
  String toString() => '$value';
}

final class JsonNumber extends JsonValue {
  final double value;
  const JsonNumber(this.value);
  @override
  String toString() =>
      value == value.truncateToDouble() ? value.toInt().toString() : '$value';
}

final class JsonString extends JsonValue {
  final String value;
  const JsonString(this.value);
  @override
  String toString() => '"$value"';
}

final class JsonArray extends JsonValue {
  final List<JsonValue> elements;
  const JsonArray(this.elements);
  @override
  String toString() => '[${elements.join(', ')}]';
}

final class JsonObject extends JsonValue {
  final Map<String, JsonValue> fields;
  const JsonObject(this.fields);
  @override
  String toString() =>
      '{${fields.entries.map((e) => '"${e.key}": ${e.value}').join(', ')}}';
}
