/// AstBuilder: convert native Dart values to format-specific AST nodes.
library;

import '../ast/hcl.dart';
import '../ast/json.dart';
import '../ast/toml.dart';
import '../ast/xml.dart';
import '../ast/yaml.dart';

/// Builds format-specific AST nodes from primitive Dart values.
abstract interface class AstBuilder<AST> {
  /// Create an object/mapping node from named fields.
  AST createObject(Map<String, AST> fields);

  /// Create an array/sequence node from elements.
  AST createArray(List<AST> elements);

  /// Create a string node.
  AST fromString(String s);

  /// Create a number node from an integer.
  ///
  /// For JSON, integers above 2^53 lose precision (JSON numbers are doubles).
  AST fromInt(int n);

  /// Create a number node from a double.
  AST fromDouble(double n);

  /// Create a boolean node.
  AST fromBool(bool b);

  /// Create a null/empty node.
  AST fromNull();
}

/// Convert a native Dart value to a format-specific AST using [builder].
///
/// Handles: `Map<String, Object?>`, `List<Object?>`, `String`, `int`,
/// `double`, `bool`, `null`.
AST nativeToAst<AST>(Object? value, AstBuilder<AST> builder) {
  if (value == null) return builder.fromNull();
  if (value is bool) return builder.fromBool(value);
  if (value is int) return builder.fromInt(value);
  if (value is double) return builder.fromDouble(value);
  if (value is String) return builder.fromString(value);
  if (value is List) {
    return builder.createArray([
      for (final e in value) nativeToAst(e, builder),
    ]);
  }
  if (value is Map<String, Object?>) {
    return builder.createObject({
      for (final MapEntry(:key, value: entryValue) in value.entries)
        key: nativeToAst(entryValue, builder),
    });
  }
  throw ArgumentError('Unsupported type: ${value.runtimeType}');
}

/// AstBuilder for JSON.
const AstBuilder<JsonValue> jsonBuilder = _JsonAstBuilder();

/// AstBuilder for YAML.
const AstBuilder<YamlValue> yamlBuilder = _YamlAstBuilder();

/// AstBuilder for TOML (no null — uses empty string).
const AstBuilder<TomlValue> tomlBuilder = _TomlAstBuilder();

/// AstBuilder for XML (values become text nodes).
const AstBuilder<XmlNode> xmlBuilder = _XmlAstBuilder();

/// AstBuilder for HCL.
const AstBuilder<HclValue> hclBuilder = _HclAstBuilder();

// ---- Implementations ----

final class _JsonAstBuilder implements AstBuilder<JsonValue> {
  const _JsonAstBuilder();
  @override
  JsonValue createObject(Map<String, JsonValue> fields) => JsonObject(fields);
  @override
  JsonValue createArray(List<JsonValue> elements) => JsonArray(elements);
  @override
  JsonValue fromString(String s) => JsonString(s);
  @override
  JsonValue fromInt(int n) => JsonNumber(n.toDouble());
  @override
  JsonValue fromDouble(double n) => JsonNumber(n);
  @override
  JsonValue fromBool(bool b) => JsonBool(b);
  @override
  JsonValue fromNull() => const JsonNull();
}

final class _YamlAstBuilder implements AstBuilder<YamlValue> {
  const _YamlAstBuilder();
  @override
  YamlValue createObject(Map<String, YamlValue> fields) => YamlMapping(fields);
  @override
  YamlValue createArray(List<YamlValue> elements) => YamlSequence(elements);
  @override
  YamlValue fromString(String s) => YamlString(s);
  @override
  YamlValue fromInt(int n) => YamlInteger(n);
  @override
  YamlValue fromDouble(double n) => YamlFloat(n);
  @override
  YamlValue fromBool(bool b) => YamlBool(b);
  @override
  YamlValue fromNull() => const YamlNull();
}

final class _TomlAstBuilder implements AstBuilder<TomlValue> {
  const _TomlAstBuilder();
  @override
  TomlValue createObject(Map<String, TomlValue> fields) => TomlTable(fields);
  @override
  TomlValue createArray(List<TomlValue> elements) => TomlArray(elements);
  @override
  TomlValue fromString(String s) => TomlString(s);
  @override
  TomlValue fromInt(int n) => TomlInteger(n);
  @override
  TomlValue fromDouble(double n) => TomlFloat(n);
  @override
  TomlValue fromBool(bool b) => TomlBool(b);
  @override
  TomlValue fromNull() => const TomlString('');
}

final class _XmlAstBuilder implements AstBuilder<XmlNode> {
  const _XmlAstBuilder();
  @override
  XmlNode createObject(Map<String, XmlNode> fields) => XmlElement(
    const QName('object'),
    const [],
    fields.entries
        .map((e) => XmlElement(QName(e.key), const [], [e.value]))
        .toList(),
  );
  @override
  XmlNode createArray(List<XmlNode> elements) => XmlElement(
    const QName('array'),
    const [],
    elements
        .map((e) => XmlElement(const QName('item'), const [], [e]))
        .toList(),
  );
  @override
  XmlNode fromString(String s) => XmlText(s);
  @override
  XmlNode fromInt(int n) => XmlText('$n');
  @override
  XmlNode fromDouble(double n) => XmlText('$n');
  @override
  XmlNode fromBool(bool b) => XmlText('$b');
  @override
  XmlNode fromNull() => const XmlText('');
}

final class _HclAstBuilder implements AstBuilder<HclValue> {
  const _HclAstBuilder();
  @override
  HclValue createObject(Map<String, HclValue> fields) => HclObject(fields);
  @override
  HclValue createArray(List<HclValue> elements) => HclList(elements);
  @override
  HclValue fromString(String s) => HclString(s);
  @override
  HclValue fromInt(int n) => HclNumber(n);
  @override
  HclValue fromDouble(double n) => HclNumber(n);
  @override
  HclValue fromBool(bool b) => HclBool(b);
  @override
  HclValue fromNull() => const HclNull();
}
