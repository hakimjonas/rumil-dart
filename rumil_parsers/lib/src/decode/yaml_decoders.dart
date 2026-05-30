/// Decoders for converting [YamlValue] AST nodes into Dart types.
library;

import '../ast/yaml.dart';
import 'decoder.dart';
import 'iterative.dart';

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

/// Iterative (composite) decoders: see `_JsonList` in `json_decoders.dart`
/// and the `decode/iterative.dart` driver. The reified element-type cast is
/// confined to each typed class so the erased driver stays stack-safe to
/// arbitrary nesting depth.
final class _YamlList<A>
    implements AstDecoder<YamlValue, List<A>>, IterativeDecoder<YamlValue> {
  final AstDecoder<YamlValue, A> _element;
  const _YamlList(this._element);
  @override
  List<A> decode(YamlValue value) =>
      decodeIterative<YamlValue>(this, value) as List<A>;
  @override
  (List<(AstDecoder<YamlValue, Object?>, YamlValue)>, Reassemble) expand(
    YamlValue value,
  ) => switch (value) {
    YamlSequence(:final elements) => (
      [for (final e in elements) (_element, e)],
      (results) => results.cast<A>(),
    ),
    _ => throw DecodeException('Expected sequence, got ${value.runtimeType}'),
  };
}

final class _YamlMap<A>
    implements
        AstDecoder<YamlValue, Map<String, A>>,
        IterativeDecoder<YamlValue> {
  final AstDecoder<YamlValue, A> _value;
  const _YamlMap(this._value);
  @override
  Map<String, A> decode(YamlValue value) =>
      decodeIterative<YamlValue>(this, value) as Map<String, A>;
  @override
  (List<(AstDecoder<YamlValue, Object?>, YamlValue)>, Reassemble) expand(
    YamlValue value,
  ) => switch (value) {
    YamlMapping(:final pairs) => (
      [for (final v in pairs.values) (_value, v)],
      (results) {
        final keys = pairs.keys.toList();
        return <String, A>{
          for (var i = 0; i < keys.length; i++) keys[i]: results[i] as A,
        };
      },
    ),
    _ => throw DecodeException('Expected mapping, got ${value.runtimeType}'),
  };
}

final class _YamlNullable<A>
    implements AstDecoder<YamlValue, A?>, IterativeDecoder<YamlValue> {
  final AstDecoder<YamlValue, A> _inner;
  const _YamlNullable(this._inner);
  @override
  A? decode(YamlValue value) => decodeIterative<YamlValue>(this, value) as A?;
  @override
  (List<(AstDecoder<YamlValue, Object?>, YamlValue)>, Reassemble) expand(
    YamlValue value,
  ) => switch (value) {
    YamlNull() => (const [], (_) => null),
    _ => ([(_inner, value)], (results) => results[0] as A),
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
