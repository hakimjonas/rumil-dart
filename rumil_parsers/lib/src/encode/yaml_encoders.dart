/// Encoders and serializer for YAML.
library;

import '../ast/yaml.dart';
import 'encoder.dart';
import 'escape.dart';

// ---- Primitive encoders ----

/// Encode an [int] as a YAML integer.
const AstEncoder<int, YamlValue> yamlIntEncoder = _YamlIntEncoder();

/// Encode a [double] as a YAML float.
const AstEncoder<double, YamlValue> yamlDoubleEncoder = _YamlDoubleEncoder();

/// Encode a [String] as a YAML string.
const AstEncoder<String, YamlValue> yamlStringEncoder = _YamlStringEncoder();

/// Encode a [bool] as a YAML boolean.
const AstEncoder<bool, YamlValue> yamlBoolEncoder = _YamlBoolEncoder();

// ---- Composite encoders ----

/// Encode a `List<A>` as a YAML sequence.
AstEncoder<List<A>, YamlValue> yamlListEncoder<A>(
  AstEncoder<A, YamlValue> element,
) => _YamlListEncoder<A>(element);

/// Encode a nullable `A?` (null becomes YAML null).
AstEncoder<A?, YamlValue> yamlNullableEncoder<A>(
  AstEncoder<A, YamlValue> inner,
) => _YamlNullableEncoder<A>(inner);

/// Encode a `Map<String, A>` as a YAML mapping.
AstEncoder<Map<String, A>, YamlValue> yamlMapEncoder<A>(
  AstEncoder<A, YamlValue> value,
) => _YamlMapEncoder<A>(value);

// ---- Mapping encoder ----

/// Encode a typed value as a YAML mapping using field builders.
AstEncoder<A, YamlValue> toYamlMapping<A>(
  void Function(ObjectBuilder<YamlValue> builder, A value) build,
) => _YamlMappingEncoder<A>(build);

// ---- Implementations ----

final class _YamlIntEncoder implements AstEncoder<int, YamlValue> {
  const _YamlIntEncoder();
  @override
  YamlValue encode(int value) => YamlInteger(value);
}

final class _YamlDoubleEncoder implements AstEncoder<double, YamlValue> {
  const _YamlDoubleEncoder();
  @override
  YamlValue encode(double value) => YamlFloat(value);
}

final class _YamlStringEncoder implements AstEncoder<String, YamlValue> {
  const _YamlStringEncoder();
  @override
  YamlValue encode(String value) => YamlString(value);
}

final class _YamlBoolEncoder implements AstEncoder<bool, YamlValue> {
  const _YamlBoolEncoder();
  @override
  YamlValue encode(bool value) => YamlBool(value);
}

final class _YamlListEncoder<A> implements AstEncoder<List<A>, YamlValue> {
  final AstEncoder<A, YamlValue> _element;
  const _YamlListEncoder(this._element);
  @override
  YamlValue encode(List<A> value) =>
      YamlSequence(value.map(_element.encode).toList());
}

final class _YamlNullableEncoder<A> implements AstEncoder<A?, YamlValue> {
  final AstEncoder<A, YamlValue> _inner;
  const _YamlNullableEncoder(this._inner);
  @override
  YamlValue encode(A? value) =>
      value == null ? const YamlNull() : _inner.encode(value);
}

final class _YamlMapEncoder<A>
    implements AstEncoder<Map<String, A>, YamlValue> {
  final AstEncoder<A, YamlValue> _value;
  const _YamlMapEncoder(this._value);
  @override
  YamlValue encode(Map<String, A> value) =>
      YamlMapping(value.map((k, v) => MapEntry(k, _value.encode(v))));
}

final class _YamlMappingEncoder<A> implements AstEncoder<A, YamlValue> {
  final void Function(ObjectBuilder<YamlValue>, A) _build;
  const _YamlMappingEncoder(this._build);
  @override
  YamlValue encode(A value) {
    final builder = ObjectBuilder<YamlValue>();
    _build(builder, value);
    return YamlMapping(
      Map.fromEntries(builder.entries.map((f) => MapEntry(f.$1, f.$2))),
    );
  }
}

// ---- Serializer ----

/// Serialize a [YamlValue] to a YAML string (block style).
String serializeYaml(YamlValue value, {int indent = 2, int depth = 0}) {
  final pad = ' ' * (indent * depth);
  return switch (value) {
    YamlNull() => '${pad}null',
    YamlBool(:final value) => '$pad$value',
    YamlInteger(:final value) => '$pad$value',
    YamlFloat(:final value) => switch (value) {
      _ when value.isNaN => '$pad.nan',
      _ when value == double.infinity => '$pad.inf',
      _ when value == double.negativeInfinity => '$pad-.inf',
      _ => '$pad$value',
    },
    YamlString(:final value) =>
      value.contains('\n')
          ? '$pad${_blockScalarString(value, indent, depth + 1)}'
          : '$pad${_quoteYamlString(value)}',
    YamlSequence(:final elements) =>
      elements.isEmpty
          ? '$pad[]'
          : elements
              .map(
                (e) =>
                    '$pad- ${serializeYaml(e, indent: indent, depth: depth + 1).trimLeft()}',
              )
              .join('\n'),
    YamlMapping(:final pairs) =>
      pairs.isEmpty
          ? '$pad{}'
          : pairs.entries
              .map((e) {
                final key = '$pad${_quoteYamlKey(e.key)}';
                return switch (e.value) {
                  YamlMapping() || YamlSequence() =>
                    '$key:\n${serializeYaml(e.value, indent: indent, depth: depth + 1)}',
                  YamlString(:final value) when value.contains('\n') =>
                    '$key: ${_blockScalarString(value, indent, depth + 1)}',
                  _ =>
                    '$key: ${serializeYaml(e.value, indent: indent, depth: 0).trimLeft()}',
                };
              })
              .join('\n'),
    YamlAnchor(:final name, :final value) =>
      '$pad&$name ${serializeYaml(value, indent: indent, depth: depth).trimLeft()}',
    YamlAlias(:final name) => '$pad*$name',
  };
}

/// Serialize a YAML document with `---` marker.
String serializeYamlDocument(YamlValue root) => '---\n${serializeYaml(root)}';

/// Emit a multi-line string as a literal block scalar (`|`).
///
/// [contentDepth] is the depth at which content lines are indented.
String _blockScalarString(String s, int indent, int contentDepth) {
  final contentPad = ' ' * (indent * contentDepth);
  // Determine chomping: strip if no trailing newline, clip if one, keep if multiple.
  final chomp = s.endsWith('\n') ? (s.endsWith('\n\n') ? '+' : '') : '-';
  final lines = s.endsWith('\n') ? s.substring(0, s.length - 1) : s;
  final indented = lines.split('\n').map((l) => '$contentPad$l').join('\n');
  return '|$chomp\n$indented';
}

String _quoteYamlString(String s) {
  if (s == 'true' || s == 'false' || s == 'null' || s == '~' || s.isEmpty) {
    return '"${escapeYaml(s)}"';
  }
  if (s.contains(
    RegExp(
      r'[:#\n"'
      "'"
      r'{}\[\],]',
    ),
  )) {
    return '"${escapeYaml(s)}"';
  }
  return s;
}

String _quoteYamlKey(String key) {
  if (key == 'true' ||
      key == 'false' ||
      key == 'null' ||
      key == '~' ||
      key.isEmpty) {
    return '"$key"';
  }
  if (key.contains(RegExp(r'[:# {}\[\],]'))) {
    return '"$key"';
  }
  return key;
}
