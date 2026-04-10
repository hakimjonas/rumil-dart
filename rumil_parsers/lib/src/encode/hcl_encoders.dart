/// HCL serializer.
library;

import '../ast/hcl.dart';
import 'escape.dart';

/// Serialize an [HclDocument] to HCL text.
String serializeHcl(HclDocument doc, {int indent = 2}) {
  final sb = StringBuffer();
  _serializeBody(sb, doc, indent, 0);
  return sb.toString();
}

void _serializeBody(
  StringBuffer sb,
  Map<String, HclValue> body,
  int indent,
  int depth,
) {
  final pad = ' ' * (indent * depth);
  for (final MapEntry(:key, :value) in body.entries) {
    switch (value) {
      case HclBlock(:final type, :final labels, body: final blockBody):
        final labelStr = labels.map((l) => '"$l"').join(' ');
        final sep = labelStr.isEmpty ? '' : ' $labelStr';
        sb.writeln('$pad$type$sep {');
        _serializeBody(sb, blockBody, indent, depth + 1);
        sb.writeln('$pad}');
      default:
        sb.writeln('$pad$key = ${_serializeValue(value)}');
    }
    if (depth == 0) sb.writeln();
  }
}

String _serializeValue(HclValue value) => switch (value) {
  HclString(:final value) => '"${escapeJson(value)}"',
  HclNumber(:final value) =>
    value == value.toInt() ? value.toInt().toString() : '$value',
  HclBool(:final value) => '$value',
  HclNull() => 'null',
  HclList(:final elements) => '[${elements.map(_serializeValue).join(', ')}]',
  HclObject(:final fields) =>
    '{ ${fields.entries.map((e) => '${e.key} = ${_serializeValue(e.value)}').join(', ')} }',
  HclBlock() => '/* nested block */',
  HclReference(:final path) => path,
};
