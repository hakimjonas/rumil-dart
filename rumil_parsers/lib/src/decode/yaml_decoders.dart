/// Decoders for converting [YamlValue] AST nodes into Dart types.
library;

import '../ast/yaml.dart';
import 'decoder.dart';

// ---- Primitive decoders ----

/// Decode a YAML integer as [int].
const AstDecoder<YamlValue, int> yamlInt = _YamlInt();

/// Decode a YAML number as [double].
const AstDecoder<YamlValue, double> yamlDouble = _YamlDouble();

/// Decode a YAML string as [String].
const AstDecoder<YamlValue, String> yamlString = _YamlString();

/// Decode a YAML boolean as [bool].
const AstDecoder<YamlValue, bool> yamlBool = _YamlBool();

// ---- Composite decoders ----

/// Decode a YAML sequence as `List<A>`.
AstDecoder<YamlValue, List<A>> yamlListOf<A>(
  AstDecoder<YamlValue, A> element,
) => _YamlList<A>(element);

/// Decode a YAML mapping as `Map<String, A>`.
AstDecoder<YamlValue, Map<String, A>> yamlMapOf<A>(
  AstDecoder<YamlValue, A> value,
) => _YamlMap<A>(value);

/// Decode a YAML value as nullable `A?` (null-safe).
AstDecoder<YamlValue, A?> yamlNullableOf<A>(AstDecoder<YamlValue, A> inner) =>
    _YamlNullable<A>(inner);

// ---- Mapping decoder ----

/// Decode a YAML mapping into a typed value using field accessors.
AstDecoder<YamlValue, A> fromYamlMapping<A>(
  A Function(ObjectAccessor<YamlValue>) build,
) => _YamlMappingDecoder<A>(build);

/// Structural navigation for [YamlMapping] fields.
const AstStruct<YamlValue> yamlStruct = _YamlStruct();

// ---- Implementations ----

final class _YamlInt implements AstDecoder<YamlValue, int> {
  const _YamlInt();
  @override
  int decode(YamlValue value) => switch (value) {
    YamlInteger(:final value) => value,
    _ => throw DecodeException('Expected integer, got ${value.runtimeType}'),
  };
}

final class _YamlDouble implements AstDecoder<YamlValue, double> {
  const _YamlDouble();
  @override
  double decode(YamlValue value) => switch (value) {
    YamlFloat(:final value) => value,
    YamlInteger(:final value) => value.toDouble(),
    _ => throw DecodeException('Expected number, got ${value.runtimeType}'),
  };
}

final class _YamlString implements AstDecoder<YamlValue, String> {
  const _YamlString();
  @override
  String decode(YamlValue value) => switch (value) {
    YamlString(:final value) => value,
    _ => throw DecodeException('Expected string, got ${value.runtimeType}'),
  };
}

final class _YamlBool implements AstDecoder<YamlValue, bool> {
  const _YamlBool();
  @override
  bool decode(YamlValue value) => switch (value) {
    YamlBool(:final value) => value,
    _ => throw DecodeException('Expected boolean, got ${value.runtimeType}'),
  };
}

final class _YamlList<A> implements AstDecoder<YamlValue, List<A>> {
  final AstDecoder<YamlValue, A> _element;
  const _YamlList(this._element);
  @override
  List<A> decode(YamlValue value) => switch (value) {
    YamlSequence(:final elements) => elements.map(_element.decode).toList(),
    _ => throw DecodeException('Expected sequence, got ${value.runtimeType}'),
  };
}

final class _YamlMap<A> implements AstDecoder<YamlValue, Map<String, A>> {
  final AstDecoder<YamlValue, A> _value;
  const _YamlMap(this._value);
  @override
  Map<String, A> decode(YamlValue value) => switch (value) {
    YamlMapping(:final pairs) => pairs.map(
      (k, v) => MapEntry(k, _value.decode(v)),
    ),
    _ => throw DecodeException('Expected mapping, got ${value.runtimeType}'),
  };
}

final class _YamlNullable<A> implements AstDecoder<YamlValue, A?> {
  final AstDecoder<YamlValue, A> _inner;
  const _YamlNullable(this._inner);
  @override
  A? decode(YamlValue value) => switch (value) {
    YamlNull() => null,
    _ => _inner.decode(value),
  };
}

final class _YamlStruct implements AstStruct<YamlValue> {
  const _YamlStruct();
  @override
  YamlValue? getField(YamlValue value, String name) => switch (value) {
    YamlMapping(:final pairs) => pairs[name],
    _ => null,
  };
}

final class _YamlMappingDecoder<A> implements AstDecoder<YamlValue, A> {
  final A Function(ObjectAccessor<YamlValue>) _build;
  const _YamlMappingDecoder(this._build);
  @override
  A decode(YamlValue value) =>
      _build(ObjectAccessor<YamlValue>(value, yamlStruct));
}
