/// HCL serializer.
library;

import '../ast/hcl.dart';
import 'escape.dart';

/// Serialize an [HclDocument] to HCL text.
String serializeHcl(HclDocument doc, {int indent = 2}) {
  final sb = StringBuffer();
  for (final (key, value) in doc) {
    switch (value) {
      case HclBlock(:final type, :final labels, body: final blockBody):
        final labelStr = labels.map((l) => '"$l"').join(' ');
        final sep = labelStr.isEmpty ? '' : ' $labelStr';
        sb.writeln('$type$sep {');
        for (final MapEntry(:key, :value) in blockBody.entries) {
          final pad = ' ' * indent;
          switch (value) {
            case HclBlock():
              sb.write(pad);
              sb.write(serializeHcl([(key, value)], indent: indent));
            default:
              sb.writeln('$pad$key = ${_serializeValue(value)}');
          }
        }
        sb.writeln('}');
      default:
        sb.writeln('$key = ${_serializeValue(value)}');
    }
    sb.writeln();
  }
  return sb.toString();
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
