/// JSON AST types.
library;

/// A JSON value.
sealed class JsonValue {
  /// Base constructor.
  const JsonValue();
}

/// JSON `null`.
final class JsonNull extends JsonValue {
  /// Creates a null value.
  const JsonNull();
  @override
  String toString() => 'null';
}

/// JSON boolean.
final class JsonBool extends JsonValue {
  /// The boolean value.
  final bool value;

  /// Creates a boolean value.
  const JsonBool(this.value);
  @override
  String toString() => '$value';
}

/// JSON number (stored as double).
final class JsonNumber extends JsonValue {
  /// The numeric value.
  final double value;

  /// Creates a number value.
  const JsonNumber(this.value);
  @override
  String toString() =>
      value == value.truncateToDouble() ? value.toInt().toString() : '$value';
}

/// JSON string.
final class JsonString extends JsonValue {
  /// The string content.
  final String value;

  /// Creates a string value.
  const JsonString(this.value);
  @override
  String toString() => '"$value"';
}

/// JSON array.
final class JsonArray extends JsonValue {
  /// The array elements.
  final List<JsonValue> elements;

  /// Creates an array value.
  const JsonArray(this.elements);
  @override
  String toString() => '[${elements.join(', ')}]';
}

/// JSON object.
final class JsonObject extends JsonValue {
  /// The key-value pairs.
  final Map<String, JsonValue> fields;

  /// Creates an object value.
  const JsonObject(this.fields);
  @override
  String toString() =>
      '{${fields.entries.map((e) => '"${e.key}": ${e.value}').join(', ')}}';
}
