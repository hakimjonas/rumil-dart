/// Encoders and serializer for TOML.
library;

import '../ast/toml.dart';
import 'encoder.dart';
import 'escape.dart';
import 'sink_walk.dart';

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
///
/// Thin wrapper over [serializeTomlTo]; output is byte-for-byte identical.
String serializeToml(TomlDocument doc) {
  final buffer = StringBuffer();
  serializeTomlTo(buffer, doc);
  return buffer.toString();
}

/// Serialize a [TomlDocument] into [sink].
///
/// Iterative on both recursion axes (see `sink_walk.dart`): the table axis
/// ([_serializeTableTo] — nested subtables and `[[array.of.tables]]`) and the
/// inline-value axis ([_serializeValueTo] — inline arrays and inline tables)
/// each drain an explicit worklist, so deeply-nested documents serialize
/// without overflowing the Dart call stack. Section ordering (all scalar keys
/// first, then subtables) and `[[array.of.tables]]` emission are unchanged.
void serializeTomlTo(StringSink sink, TomlDocument doc) {
  _serializeTableTo(sink, doc, const []);
}

String _quoteTomlKey(String key) {
  if (key.contains(RegExp(r'[.\s"\\#=\[\]]'))) return '"${escapeToml(key)}"';
  return key;
}

/// Iterates entries twice: inline values first, then subtables. Output
/// groups all scalars before all table sections, which may differ from
/// input order.
///
/// The subtable axis is driven by an explicit worklist rather than recursion.
/// Each work item is a `(table, path)` pair; expanding it emits the table's
/// scalar lines immediately, then schedules one child item per subtable /
/// array-of-tables section in source order, so output is identical to the
/// recursive walk.
void _serializeTableTo(
  StringSink sink,
  Map<String, TomlValue> rootTable,
  List<String> rootPath,
) {
  final walk = SinkWalk();

  void expand(Map<String, TomlValue> table, List<String> path) {
    for (final MapEntry(:key, :value) in table.entries) {
      if (value is TomlTable) continue;
      if (value is TomlArray && value.elements.every((e) => e is TomlTable)) {
        continue;
      }
      sink.write('${_quoteTomlKey(key)} = ');
      _serializeValueTo(sink, value);
      sink.write('\n');
    }
    final steps = <SinkStep>[];
    for (final MapEntry(:key, :value) in table.entries) {
      if (value is TomlTable) {
        final subPath = [...path, key];
        steps.add(() {
          sink.write('\n[${subPath.join('.')}]\n');
          expand(value.pairs, subPath);
        });
      }
      if (value is TomlArray && value.elements.every((e) => e is TomlTable)) {
        for (final element in value.elements) {
          final subPath = [...path, key];
          steps.add(() {
            sink.write('\n[[${subPath.join('.')}]]\n');
            expand((element as TomlTable).pairs, subPath);
          });
        }
      }
    }
    walk.pushAll(steps);
  }

  expand(rootTable, rootPath);
  walk.run();
}

/// Serialize a single [TomlValue] into [sink].
///
/// Iterative on the inline-value axis (see `sink_walk.dart`): inline arrays
/// and inline tables can nest arbitrarily, so the walk schedules child
/// emissions rather than recursing.
void _serializeValueTo(StringSink sink, TomlValue root) {
  final walk = SinkWalk();

  late final void Function(TomlValue) emit;
  emit = (TomlValue value) {
    switch (value) {
      case TomlString(:final value):
        sink.write('"${escapeToml(value)}"');
      case TomlInteger(:final value):
        sink.write('$value');
      case TomlFloat(:final value):
        sink.write(
          value.isNaN
              ? 'nan'
              : value.isInfinite
              ? (value.isNegative ? '-inf' : 'inf')
              : '$value',
        );
      case TomlBool(:final value):
        sink.write('$value');
      case TomlDateTime(:final value):
        sink.write(value.toIso8601String());
      case TomlLocalDateTime(:final value):
        sink.write(value.toIso8601String());
      case TomlLocalDate(:final year, :final month, :final day):
        sink.write(
          '${year.toString().padLeft(4, '0')}-'
          '${month.toString().padLeft(2, '0')}-'
          '${day.toString().padLeft(2, '0')}',
        );
      case TomlLocalTime(:final hour, :final minute, :final second):
        sink.write(
          '${hour.toString().padLeft(2, '0')}:'
          '${minute.toString().padLeft(2, '0')}:'
          '${second.toString().padLeft(2, '0')}',
        );
      case TomlArray(:final elements):
        sink.write('[');
        final steps = <SinkStep>[];
        for (var i = 0; i < elements.length; i++) {
          final e = elements[i];
          if (i > 0) steps.add(() => sink.write(', '));
          steps.add(() => emit(e));
        }
        steps.add(() => sink.write(']'));
        walk.pushAll(steps);
      case TomlTable(:final pairs):
        sink.write('{');
        final entries = pairs.entries.toList();
        final steps = <SinkStep>[];
        for (var i = 0; i < entries.length; i++) {
          final entry = entries[i];
          if (i > 0) steps.add(() => sink.write(', '));
          steps.add(() => sink.write('${entry.key} = '));
          steps.add(() => emit(entry.value));
        }
        steps.add(() => sink.write('}'));
        walk.pushAll(steps);
    }
  };

  emit(root);
  walk.run();
}

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
