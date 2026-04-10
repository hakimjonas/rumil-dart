/// YAML AST types.
library;

/// A YAML value.
sealed class YamlValue {
  /// Base constructor.
  const YamlValue();
}

/// YAML null.
final class YamlNull extends YamlValue {
  /// Creates a null value.
  const YamlNull();
}

/// YAML boolean.
final class YamlBool extends YamlValue {
  /// The boolean value.
  final bool value;

  /// Creates a boolean value.
  const YamlBool(this.value);
}

/// YAML integer.
final class YamlInteger extends YamlValue {
  /// The integer value.
  final int value;

  /// Creates an integer value.
  const YamlInteger(this.value);
}

/// YAML float.
final class YamlFloat extends YamlValue {
  /// The float value.
  final double value;

  /// Creates a float value.
  const YamlFloat(this.value);
}

/// YAML string.
final class YamlString extends YamlValue {
  /// The string content.
  final String value;

  /// Creates a string value.
  const YamlString(this.value);
}

/// YAML sequence (list).
final class YamlSequence extends YamlValue {
  /// The sequence elements.
  final List<YamlValue> elements;

  /// Creates a sequence value.
  const YamlSequence(this.elements);
}

/// YAML mapping (key-value pairs).
final class YamlMapping extends YamlValue {
  /// The key-value pairs.
  final Map<String, YamlValue> pairs;

  /// Creates a mapping value.
  const YamlMapping(this.pairs);
}

/// A YAML document (simplified: just the root value).
typedef YamlDocument = YamlValue;
