/// Decoders for converting [TomlValue] AST nodes into Dart types.
library;

import '../ast/toml.dart';
import 'decoder.dart';

// ---- Primitive decoders ----

/// Decode a TOML integer as [int].
const AstDecoder<TomlValue, int> tomlInt = _TomlInt();

/// Decode a TOML float as [double].
const AstDecoder<TomlValue, double> tomlDouble = _TomlDouble();

/// Decode a TOML string as [String].
const AstDecoder<TomlValue, String> tomlString = _TomlString();

/// Decode a TOML boolean as [bool].
const AstDecoder<TomlValue, bool> tomlBool = _TomlBool();

/// Decode a TOML offset datetime as [DateTime].
const AstDecoder<TomlValue, DateTime> tomlDateTime = _TomlDateTime();

// ---- Composite decoders ----

/// Decode a TOML array as `List<A>`.
AstDecoder<TomlValue, List<A>> tomlListOf<A>(
  AstDecoder<TomlValue, A> element,
) => _TomlList<A>(element);

// ---- Table decoder ----

/// Decode a TOML table into a typed value using field accessors.
AstDecoder<TomlValue, A> fromTomlTable<A>(
  A Function(ObjectAccessor<TomlValue>) build,
) => _TomlTableDecoder<A>(build);

/// Structural navigation for [TomlTable] fields.
const AstStruct<TomlValue> tomlStruct = _TomlStruct();

// ---- Implementations ----

final class _TomlInt implements AstDecoder<TomlValue, int> {
  const _TomlInt();
  @override
  int decode(TomlValue value) => switch (value) {
    TomlInteger(:final value) => value,
    _ => throw DecodeException('Expected integer, got ${value.runtimeType}'),
  };
}

final class _TomlDouble implements AstDecoder<TomlValue, double> {
  const _TomlDouble();
  @override
  double decode(TomlValue value) => switch (value) {
    TomlFloat(:final value) => value,
    TomlInteger(:final value) => value.toDouble(),
    _ => throw DecodeException('Expected number, got ${value.runtimeType}'),
  };
}

final class _TomlString implements AstDecoder<TomlValue, String> {
  const _TomlString();
  @override
  String decode(TomlValue value) => switch (value) {
    TomlString(:final value) => value,
    _ => throw DecodeException('Expected string, got ${value.runtimeType}'),
  };
}

final class _TomlBool implements AstDecoder<TomlValue, bool> {
  const _TomlBool();
  @override
  bool decode(TomlValue value) => switch (value) {
    TomlBool(:final value) => value,
    _ => throw DecodeException('Expected boolean, got ${value.runtimeType}'),
  };
}

final class _TomlDateTime implements AstDecoder<TomlValue, DateTime> {
  const _TomlDateTime();
  @override
  DateTime decode(TomlValue value) => switch (value) {
    TomlDateTime(:final value) => value,
    TomlLocalDateTime(:final value) => value,
    _ => throw DecodeException('Expected datetime, got ${value.runtimeType}'),
  };
}

final class _TomlList<A> implements AstDecoder<TomlValue, List<A>> {
  final AstDecoder<TomlValue, A> _element;
  const _TomlList(this._element);
  @override
  List<A> decode(TomlValue value) => switch (value) {
    TomlArray(:final elements) => elements.map(_element.decode).toList(),
    _ => throw DecodeException('Expected array, got ${value.runtimeType}'),
  };
}

final class _TomlStruct implements AstStruct<TomlValue> {
  const _TomlStruct();
  @override
  TomlValue? getField(TomlValue value, String name) => switch (value) {
    TomlTable(:final pairs) => pairs[name],
    _ => null,
  };
}

final class _TomlTableDecoder<A> implements AstDecoder<TomlValue, A> {
  final A Function(ObjectAccessor<TomlValue>) _build;
  const _TomlTableDecoder(this._build);
  @override
  A decode(TomlValue value) =>
      _build(ObjectAccessor<TomlValue>(value, tomlStruct));
}
