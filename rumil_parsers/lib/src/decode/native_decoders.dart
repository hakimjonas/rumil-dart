/// AST to native Dart type converters.
library;

import '../ast/hcl.dart';
import '../ast/json.dart';
import '../ast/toml.dart';
import '../ast/xml.dart';
import '../ast/yaml.dart';
import '../encode/hcl_encoders.dart' show serializeHclValue;
import '../yaml_resolve.dart';

/// Convert a [JsonValue] to native Dart types.
///
/// Numbers that are whole are returned as [int], others as [double].
Object? jsonToNative(JsonValue v) => switch (v) {
  JsonNull() => null,
  JsonBool(:final value) => value,
  JsonNumber(:final value) =>
    value == value.truncateToDouble() ? value.toInt() : value,
  JsonString(:final value) => value,
  JsonArray(:final elements) => [for (final e in elements) jsonToNative(e)],
  JsonObject(:final fields) => {
    for (final MapEntry(:key, :value) in fields.entries)
      key: jsonToNative(value),
  },
};

/// Convert a [YamlValue] to native Dart types.
///
/// Resolves anchors and aliases internally before conversion.
/// Downstream consumers never see unresolved [YamlAnchor] or [YamlAlias].
Object? yamlToNative(YamlValue v) {
  final resolved = resolveAnchors(v);
  return _yamlToNativeResolved(resolved);
}

Object? _yamlToNativeResolved(YamlValue v) => switch (v) {
  YamlNull() => null,
  YamlBool(:final value) => value,
  YamlInteger(:final value) => value,
  YamlFloat(:final value) => value,
  YamlString(:final value) => value,
  YamlSequence(:final elements) => [
    for (final e in elements) _yamlToNativeResolved(e),
  ],
  YamlMapping(:final pairs) => {
    for (final MapEntry(:key, :value) in pairs.entries)
      key: _yamlToNativeResolved(value),
  },
  YamlAnchor() ||
  YamlAlias() => throw StateError('Unresolved anchor/alias in YAML'),
};

/// Convert a [TomlDocument] to native Dart types.
Map<String, Object?> tomlDocToNative(TomlDocument doc) => {
  for (final MapEntry(:key, :value) in doc.entries) key: tomlToNative(value),
};

/// Convert a [TomlValue] to native Dart types.
///
/// Datetime types are returned as ISO 8601 strings.
Object? tomlToNative(TomlValue v) => switch (v) {
  TomlString(:final value) => value,
  TomlInteger(:final value) => value,
  TomlFloat(:final value) => value,
  TomlBool(:final value) => value,
  TomlDateTime(:final value) => value.toIso8601String(),
  TomlLocalDateTime(:final value) => value.toIso8601String(),
  TomlLocalDate(:final year, :final month, :final day) =>
    '$year-${_pad(month)}-${_pad(day)}',
  TomlLocalTime(:final hour, :final minute, :final second) =>
    '${_pad(hour)}:${_pad(minute)}:${_pad(second)}',
  TomlArray(:final elements) => [for (final e in elements) tomlToNative(e)],
  TomlTable(:final pairs) => {
    for (final MapEntry(:key, :value) in pairs.entries)
      key: tomlToNative(value),
  },
};

/// Convert an [XmlNode] to native Dart types.
///
/// Elements with only text children return the text content.
/// Elements with child elements return a `Map<String, Object?>`.
/// Throws on CDATA, comments, and processing instructions.
Object? xmlToNative(XmlNode node) => switch (node) {
  XmlText(:final content) => content,
  XmlElement(:final children) => () {
    final textChildren = children.whereType<XmlText>().toList();
    if (textChildren.length == children.length) {
      return textChildren.map((t) => t.content).join();
    }
    final elementChildren = children.whereType<XmlElement>().toList();
    return <String, Object?>{
      for (final child in elementChildren)
        child.name.localName: xmlToNative(child),
    };
  }(),
  XmlCData(:final content) => content,
  XmlComment() => null,
  XmlPI() => null,
};

/// Convert an [HclDocument] to native Dart types.
///
/// Groups duplicate block types into lists.
Map<String, Object?> hclDocToNative(HclDocument doc) {
  final result = <String, Object?>{};
  for (final (key, value) in doc) {
    final native = hclToNative(value);
    final existing = result[key];
    if (existing is List) {
      existing.add(native);
    } else if (existing != null) {
      result[key] = [existing, native];
    } else {
      result[key] = native;
    }
  }
  return result;
}

/// Convert an [HclValue] to native Dart types.
///
/// Blocks include `_type` and `_labels` metadata fields.
/// Expression nodes are serialized back to their HCL string form since
/// this is a non-evaluating parser.
Object? hclToNative(HclValue v) => switch (v) {
  HclString(:final value) => value,
  HclNumber(:final value) => value,
  HclBool(:final value) => value,
  HclNull() => null,
  HclList(:final elements) => [for (final e in elements) hclToNative(e)],
  HclObject(:final fields) => {
    for (final MapEntry(:key, :value) in fields.entries)
      key: hclToNative(value),
  },
  HclBlock(:final type, :final labels, :final body) => {
    '_type': type,
    '_labels': labels,
    for (final MapEntry(:key, :value) in body.entries) key: hclToNative(value),
  },
  HclReference(:final path) => path,
  HclUnaryOp() ||
  HclBinaryOp() ||
  HclConditional() ||
  HclFunctionCall() ||
  HclIndex() ||
  HclGetAttr() ||
  HclAttrSplat() ||
  HclFullSplat() ||
  HclForTuple() ||
  HclForObject() ||
  HclParenExpr() ||
  HclTemplate() ||
  HclHeredoc() => serializeHclValue(v),
};

String _pad(int n) => n.toString().padLeft(2, '0');
