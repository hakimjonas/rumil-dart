/// Encoders and serializer for YAML.
library;

import '../ast/yaml.dart';
import 'encoder.dart';
import 'escape.dart';
import 'sink_walk.dart';

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
///
/// Thin wrapper over [serializeYamlTo]; output is byte-for-byte identical.
String serializeYaml(YamlValue value, {int indent = 2, int depth = 0}) {
  final buffer = StringBuffer();
  serializeYamlTo(buffer, value, indent: indent, depth: depth);
  return buffer.toString();
}

/// Serialize a [YamlValue] into [sink] (block style).
///
/// Iterative (see `sink_walk.dart`): a deeply-nested mapping or sequence
/// serializes without overflowing the Dart call stack.
///
/// The recursive form rendered each child then called `.trimLeft()` on it
/// (sequence items, scalar mapping values, and anchored values are written
/// inline after a `- `, `: `, or `&name ` prefix). Streaming has no child
/// string to trim, so a [_YamlTrimSink] reproduces it exactly: armed just
/// before a trimmed child, it swallows the leading whitespace run of that
/// child's contiguous output (its own indentation pad, plus any leading
/// whitespace in the rare unquoted-plain-scalar case) and passes the rest
/// through. It is disarmed once the child's subtree fully drains, so a child
/// that renders to nothing but whitespace (an unquoted all-spaces scalar,
/// which `trimLeft` collapses to empty) cannot swallow the following
/// separator.
void serializeYamlTo(
  StringSink sink,
  YamlValue value, {
  int indent = 2,
  int depth = 0,
}) {
  final out = _YamlTrimSink(sink);
  final walk = SinkWalk();

  // Mutually recursive *in scheduling* only — see `sink_walk.dart`.
  late final void Function(YamlValue, int) emit;

  // Schedule [child] as a trimmed inline value: arm the trim gate, emit the
  // subtree, then disarm once it has fully drained.
  void scheduleTrimmed(YamlValue child, int childDepth) {
    walk.pushAll([
      () => out.trimming = true,
      () => emit(child, childDepth),
      () => out.trimming = false,
    ]);
  }

  emit = (YamlValue node, int depth) {
    final pad = ' ' * (indent * depth);
    switch (node) {
      case YamlNull():
        out.write('${pad}null');
      case YamlBool(:final value):
        out.write('$pad$value');
      case YamlInteger(:final value):
        out.write('$pad$value');
      case YamlFloat(:final value):
        out.write(switch (value) {
          _ when value.isNaN => '$pad.nan',
          _ when value == double.infinity => '$pad.inf',
          _ when value == double.negativeInfinity => '$pad-.inf',
          _ => '$pad$value',
        });
      case YamlString(:final value):
        out.write(
          value.contains('\n')
              ? '$pad${_blockScalarString(value, indent, depth + 1)}'
              : '$pad${_quoteYamlString(value)}',
        );
      case YamlSequence(:final elements):
        if (elements.isEmpty) {
          out.write('$pad[]');
          return;
        }
        final steps = <SinkStep>[];
        for (var i = 0; i < elements.length; i++) {
          final e = elements[i];
          steps.add(() => out.write(i == 0 ? '$pad- ' : '\n$pad- '));
          steps.add(() => scheduleTrimmed(e, depth + 1));
        }
        walk.pushAll(steps);
      case YamlMapping(:final pairs):
        if (pairs.isEmpty) {
          out.write('$pad{}');
          return;
        }
        final entries = pairs.entries.toList();
        final steps = <SinkStep>[];
        for (var i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final keyText =
              '${i == 0 ? '' : '\n'}$pad${_quoteYamlKey(entry.key)}';
          final v = entry.value;
          switch (v) {
            case YamlMapping() || YamlSequence():
              steps.add(() => out.write('$keyText:\n'));
              steps.add(() => emit(v, depth + 1)); // not trimmed
            case YamlString(:final value) when value.contains('\n'):
              steps.add(
                () => out.write(
                  '$keyText: ${_blockScalarString(value, indent, depth + 1)}',
                ),
              );
            default:
              steps.add(() => out.write('$keyText: '));
              steps.add(() => scheduleTrimmed(v, 0));
          }
        }
        walk.pushAll(steps);
      case YamlAnchor(:final name, :final value):
        out.write('$pad&$name ');
        scheduleTrimmed(value, depth);
      case YamlAlias(:final name):
        out.write('$pad*$name');
    }
  };

  emit(value, depth);
  walk.run();
}

/// A [StringSink] wrapper that reproduces the recursive serializer's
/// `child.trimLeft()`: while [trimming] is set it drops the leading
/// whitespace run of what is written, clearing [trimming] on the first
/// non-whitespace character (matching `String.trimLeft`'s Unicode
/// whitespace set). See [serializeYamlTo].
final class _YamlTrimSink implements StringSink {
  final StringSink _inner;

  /// Whether the leading-whitespace gate is active.
  bool trimming = false;

  _YamlTrimSink(this._inner);

  @override
  void write(Object? obj) {
    var s = '$obj';
    if (trimming) {
      var i = 0;
      while (i < s.length && _isYamlTrimWhitespace(s.codeUnitAt(i))) {
        i++;
      }
      if (i == s.length) return; // all whitespace: stay armed
      s = i == 0 ? s : s.substring(i);
      trimming = false;
    }
    _inner.write(s);
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    var first = true;
    for (final o in objects) {
      if (!first && separator.isNotEmpty) write(separator);
      write(o);
      first = false;
    }
  }

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? obj = '']) {
    write(obj);
    write('\n');
  }
}

/// Whitespace code units stripped by [String.trimLeft], so the trim gate
/// matches the recursive `.trimLeft()` byte-for-byte.
bool _isYamlTrimWhitespace(int u) =>
    (u >= 0x09 && u <= 0x0D) || // tab, LF, VT, FF, CR
    u == 0x20 || // space
    u == 0x85 || // NEL
    u == 0xA0 || // NBSP
    u == 0x1680 ||
    (u >= 0x2000 && u <= 0x200A) ||
    u == 0x2028 ||
    u == 0x2029 ||
    u == 0x202F ||
    u == 0x205F ||
    u == 0x3000 ||
    u == 0xFEFF;

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
