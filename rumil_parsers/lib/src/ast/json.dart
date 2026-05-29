/// JSON AST types.
library;

import 'package:rumil/rumil.dart';

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
  bool operator ==(Object other) => identical(this, other) || other is JsonNull;
  @override
  int get hashCode => 0;
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
  bool operator ==(Object other) =>
      identical(this, other) || other is JsonBool && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => '$value';
}

/// JSON integer-shaped number.
///
/// Tokens with no decimal point and no exponent that fit in Dart's
/// [int]. Matches `dart:convert`'s classification rule: tokens whose
/// numeric value is an integer in `int` range parse to [int].
///
/// Equality with [JsonDouble] is `false` — `JsonInt(1) == JsonDouble(1.0)`
/// evaluates to `false`. Matches serde_json's `Number` enum, Jackson's
/// `NumericNode` hierarchy, and circe's `JsonNumber.fold` discrimination.
/// The source token shape is preserved through the AST.
final class JsonInt extends JsonValue {
  /// The integer value.
  final int value;

  /// Creates an integer value.
  const JsonInt(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is JsonInt && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => '$value';
}

/// JSON floating-point number.
///
/// Tokens with a decimal point, an exponent, or integer-shaped tokens
/// whose magnitude exceeds Dart's [int] range. Matches `dart:convert`'s
/// fallback to [double] for big integers.
///
/// Equality with [JsonInt] is `false` — `JsonInt(1) == JsonDouble(1.0)`
/// evaluates to `false`. The source token shape is preserved: `1.0`
/// parses to `JsonDouble(1.0)` and serializes back to `'1.0'`, not
/// `'1'`.
final class JsonDouble extends JsonValue {
  /// The floating-point value.
  final double value;

  /// Creates a floating-point value.
  const JsonDouble(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is JsonDouble && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => '$value';
}

/// JSON string.
final class JsonString extends JsonValue {
  /// The string content.
  final String value;

  /// Creates a string value.
  const JsonString(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is JsonString && other.value == value;
  @override
  int get hashCode => value.hashCode;
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
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JsonArray && listEquals(elements, other.elements);
  @override
  int get hashCode => listHash(elements);
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
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JsonObject && mapEquals(fields, other.fields);
  @override
  int get hashCode => mapHash(fields);
  @override
  String toString() =>
      '{${fields.entries.map((e) => '"${e.key}": ${e.value}').join(', ')}}';
}
