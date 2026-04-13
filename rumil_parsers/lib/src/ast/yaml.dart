/// YAML AST types.
library;

import '_equality.dart';

/// A YAML value.
sealed class YamlValue {
  /// Base constructor.
  const YamlValue();
}

/// YAML null.
final class YamlNull extends YamlValue {
  /// Creates a null value.
  const YamlNull();

  @override
  bool operator ==(Object other) => identical(this, other) || other is YamlNull;
  @override
  int get hashCode => 0;
}

/// YAML boolean.
final class YamlBool extends YamlValue {
  /// The boolean value.
  final bool value;

  /// Creates a boolean value.
  const YamlBool(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is YamlBool && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// YAML integer.
final class YamlInteger extends YamlValue {
  /// The integer value.
  final int value;

  /// Creates an integer value.
  const YamlInteger(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is YamlInteger && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// YAML float.
final class YamlFloat extends YamlValue {
  /// The float value.
  final double value;

  /// Creates a float value.
  const YamlFloat(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is YamlFloat && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// YAML string.
final class YamlString extends YamlValue {
  /// The string content.
  final String value;

  /// Creates a string value.
  const YamlString(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is YamlString && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// YAML sequence (list).
final class YamlSequence extends YamlValue {
  /// The sequence elements.
  final List<YamlValue> elements;

  /// Creates a sequence value.
  const YamlSequence(this.elements);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is YamlSequence && listEquals(elements, other.elements);
  @override
  int get hashCode => listHash(elements);
}

/// YAML mapping (key-value pairs).
final class YamlMapping extends YamlValue {
  /// The key-value pairs.
  final Map<String, YamlValue> pairs;

  /// Anchors defined on mapping keys: anchor name → key string.
  /// Used by [resolveAnchors] to register key anchors before resolving values.
  final Map<String, String> keyAnchors;

  /// Keys that are aliases (alias name used as key string).
  /// Resolved to the anchor's string value during [resolveAnchors].
  final Set<String> aliasKeys;

  /// Creates a mapping value.
  const YamlMapping(
    this.pairs, {
    this.keyAnchors = const {},
    this.aliasKeys = const {},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is YamlMapping && mapEquals(pairs, other.pairs);
  @override
  int get hashCode => mapHash(pairs);
}

/// A YAML anchor: `&name value`.
final class YamlAnchor extends YamlValue {
  /// The anchor name.
  final String name;

  /// The anchored value.
  final YamlValue value;

  /// Creates an anchor.
  const YamlAnchor(this.name, this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is YamlAnchor && other.name == name && other.value == value;
  @override
  int get hashCode => Object.hash(name, value);
}

/// A YAML alias: `*name`.
final class YamlAlias extends YamlValue {
  /// The alias name (references an anchor).
  final String name;

  /// Creates an alias.
  const YamlAlias(this.name);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is YamlAlias && other.name == name;
  @override
  int get hashCode => name.hashCode;
}

/// A YAML document (simplified: just the root value).
typedef YamlDocument = YamlValue;
