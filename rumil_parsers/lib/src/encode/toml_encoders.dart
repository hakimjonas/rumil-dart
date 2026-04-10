/// Encoders and serializer for TOML.
library;

import '../ast/toml.dart';
import 'encoder.dart';
import 'escape.dart';

// ---- Primitive encoders ----

/// Encode an [int] as a TOML integer.
const AstEncoder<int, TomlValue> tomlIntEncoder = _TomlIntEncoder();

/// Encode a [double] as a TOML float.
const AstEncoder<double, TomlValue> tomlDoubleEncoder = _TomlDoubleEncoder();

/// Encode a [String] as a TOML string.
const AstEncoder<String, TomlValue> tomlStringEncoder = _TomlStringEncoder();

/// Encode a [bool] as a TOML boolean.
const AstEncoder<bool, TomlValue> tomlBoolEncoder = _TomlBoolEncoder();

/// Encode a [DateTime] as a TOML datetime.
const AstEncoder<DateTime, TomlValue> tomlDateTimeEncoder =
    _TomlDateTimeEncoder();

// ---- Composite encoders ----

/// Encode a `List<A>` as a TOML array.
AstEncoder<List<A>, TomlValue> tomlListEncoder<A>(
  AstEncoder<A, TomlValue> element,
) => _TomlListEncoder<A>(element);

/// Encode a `Map<String, A>` as a TOML table.
AstEncoder<Map<String, A>, TomlValue> tomlMapEncoder<A>(
  AstEncoder<A, TomlValue> value,
) => _TomlMapEncoder<A>(value);

/// Encode a nullable `A?` (null becomes empty string — TOML has no null).
AstEncoder<A?, TomlValue> tomlNullableEncoder<A>(
  AstEncoder<A, TomlValue> inner,
) => _TomlNullableEncoder<A>(inner);

// ---- Table encoder ----

/// Encode a typed value as a TOML table using field builders.
AstEncoder<A, TomlValue> toTomlTable<A>(
  void Function(ObjectBuilder<TomlValue> builder, A value) build,
) => _TomlTableEncoder<A>(build);

// ---- Serializer ----

/// Serialize a [TomlDocument] to a TOML string.
String serializeToml(TomlDocument doc) {
  final sb = StringBuffer();
  _serializeTable(sb, doc, []);
  return sb.toString();
}

String _quoteTomlKey(String key) {
  if (key.contains(RegExp(r'[.\s"\\#=\[\]]'))) return '"${escapeToml(key)}"';
  return key;
}

/// Iterates entries twice: inline values first, then subtables. Output
/// groups all scalars before all table sections, which may differ from
/// input order.
void _serializeTable(
  StringBuffer sb,
  Map<String, TomlValue> table,
  List<String> path,
) {
  for (final MapEntry(:key, :value) in table.entries) {
    if (value is TomlTable) continue;
    if (value is TomlArray && value.elements.every((e) => e is TomlTable)) {
      continue;
    }
    sb.writeln('${_quoteTomlKey(key)} = ${_serializeValue(value)}');
  }
  for (final MapEntry(:key, :value) in table.entries) {
    if (value is TomlTable) {
      final subPath = [...path, key];
      sb.writeln('');
      sb.writeln('[${subPath.join('.')}]');
      _serializeTable(sb, value.pairs, subPath);
    }
    if (value is TomlArray && value.elements.every((e) => e is TomlTable)) {
      for (final element in value.elements) {
        final subPath = [...path, key];
        sb.writeln('');
        sb.writeln('[[${subPath.join('.')}]]');
        _serializeTable(sb, (element as TomlTable).pairs, subPath);
      }
    }
  }
}

String _serializeValue(TomlValue value) => switch (value) {
  TomlString(:final value) => '"${escapeToml(value)}"',
  TomlInteger(:final value) => '$value',
  TomlFloat(:final value) =>
    value.isNaN
        ? 'nan'
        : value.isInfinite
        ? (value.isNegative ? '-inf' : 'inf')
        : '$value',
  TomlBool(:final value) => '$value',
  TomlDateTime(:final value) => value.toIso8601String(),
  TomlLocalDateTime(:final value) => value.toIso8601String(),
  TomlLocalDate(:final year, :final month, :final day) =>
    '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
  TomlLocalTime(:final hour, :final minute, :final second) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}',
  TomlArray(:final elements) => '[${elements.map(_serializeValue).join(', ')}]',
  TomlTable(:final pairs) =>
    '{${pairs.entries.map((e) => '${e.key} = ${_serializeValue(e.value)}').join(', ')}}',
};

// ---- Implementations ----

final class _TomlIntEncoder implements AstEncoder<int, TomlValue> {
  const _TomlIntEncoder();
  @override
  TomlValue encode(int value) => TomlInteger(value);
}

final class _TomlDoubleEncoder implements AstEncoder<double, TomlValue> {
  const _TomlDoubleEncoder();
  @override
  TomlValue encode(double value) => TomlFloat(value);
}

final class _TomlStringEncoder implements AstEncoder<String, TomlValue> {
  const _TomlStringEncoder();
  @override
  TomlValue encode(String value) => TomlString(value);
}

final class _TomlBoolEncoder implements AstEncoder<bool, TomlValue> {
  const _TomlBoolEncoder();
  @override
  TomlValue encode(bool value) => TomlBool(value);
}

final class _TomlDateTimeEncoder implements AstEncoder<DateTime, TomlValue> {
  const _TomlDateTimeEncoder();
  @override
  TomlValue encode(DateTime value) => TomlDateTime(value);
}

final class _TomlListEncoder<A> implements AstEncoder<List<A>, TomlValue> {
  final AstEncoder<A, TomlValue> _element;
  const _TomlListEncoder(this._element);
  @override
  TomlValue encode(List<A> value) =>
      TomlArray(value.map(_element.encode).toList());
}

final class _TomlTableEncoder<A> implements AstEncoder<A, TomlValue> {
  final void Function(ObjectBuilder<TomlValue>, A) _build;
  const _TomlTableEncoder(this._build);
  @override
  TomlValue encode(A value) {
    final builder = ObjectBuilder<TomlValue>();
    _build(builder, value);
    return TomlTable(
      Map.fromEntries(builder.entries.map((f) => MapEntry(f.$1, f.$2))),
    );
  }
}

final class _TomlMapEncoder<A>
    implements AstEncoder<Map<String, A>, TomlValue> {
  final AstEncoder<A, TomlValue> _value;
  const _TomlMapEncoder(this._value);
  @override
  TomlValue encode(Map<String, A> value) =>
      TomlTable(value.map((k, v) => MapEntry(k, _value.encode(v))));
}

final class _TomlNullableEncoder<A> implements AstEncoder<A?, TomlValue> {
  final AstEncoder<A, TomlValue> _inner;
  const _TomlNullableEncoder(this._inner);
  @override
  TomlValue encode(A? value) =>
      value == null ? const TomlString('') : _inner.encode(value);
}
