/// HOCON serializer.
///
/// Emits standard, valid JSON formatting — which is itself valid HOCON
/// — from a *resolved* [HoconValue]. For v1 this satisfies HOCON output
/// requirements: any JSON document is a HOCON document. Substitutions,
/// concatenations, and includes cannot be serialized meaningfully and
/// throw [HoconResolveException]; run [resolveHocon] first.
///
/// Iterative on the container axis (see `sink_walk.dart`): separators
/// and closing brackets are scheduled as their own steps between the
/// child-emission steps, so no step ever calls `emit` recursively and
/// arbitrarily deep values serialize without call-stack growth.
library;

import '../ast/hocon.dart';
import '../hocon_resolve.dart' show HoconResolveException;
import 'escape.dart' show escapeJson;
import 'sink_walk.dart';

/// Serialize a [HoconValue] to a HOCON (JSON-formatted) string.
String serializeHocon(HoconValue value) {
  final buffer = StringBuffer();
  serializeHoconTo(buffer, value);
  return buffer.toString();
}

/// Serialize a [HoconValue] into [sink].
void serializeHoconTo(StringSink sink, HoconValue value) {
  final walk = SinkWalk();

  late final void Function(HoconValue, int) emit;
  emit = (HoconValue node, int depth) {
    switch (node) {
      case HoconNull():
        sink.write('null');
      case HoconBool(:final value):
        sink.write(value);
      case HoconInt(:final value):
        sink.write(value);
      case HoconDouble(:final value):
        sink.write(value);
      case HoconString(:final value):
        sink
          ..write('"')
          ..write(escapeJson(value))
          ..write('"');
      case HoconArray(:final elements):
        if (elements.isEmpty) {
          sink.write('[]');
          return;
        }
        final pad = '  ' * depth;
        final inner = '  ' * (depth + 1);
        sink.write('[\n');
        final steps = <SinkStep>[];
        for (var i = 0; i < elements.length; i++) {
          final element = elements[i];
          if (i > 0) steps.add(() => sink.write(',\n'));
          steps.add(() => sink.write(inner));
          steps.add(() => emit(element, depth + 1));
        }
        steps.add(() => sink.write('\n$pad]'));
        walk.pushAll(steps);
      case HoconObject(:final entries):
        final assignments = <HoconAssignment>[];
        for (final e in entries) {
          switch (e) {
            case HoconAssignment():
              assignments.add(e);
            case HoconIncludeEntry():
              throw HoconResolveException(
                'Unresolved include — resolve before serializing',
              );
          }
        }
        if (assignments.isEmpty) {
          sink.write('{}');
          return;
        }
        final pad = '  ' * depth;
        final inner = '  ' * (depth + 1);
        sink.write('{\n');
        final steps = <SinkStep>[];
        for (var i = 0; i < assignments.length; i++) {
          final entry = assignments[i];
          if (i > 0) steps.add(() => sink.write(',\n'));
          steps.add(() => sink.write(inner));
          steps.add(() {
            sink
              ..write('"')
              ..write(escapeJson(entry.path.join('.')))
              ..write('": ');
          });
          steps.add(() => emit(entry.value, depth + 1));
        }
        steps.add(() => sink.write('\n$pad}'));
        walk.pushAll(steps);
      case HoconSubstitution() || HoconConcat() || HoconInclude():
        throw HoconResolveException(
          'Unresolved HOCON value (${node.runtimeType}) — '
          'call resolveHocon before serializeHocon',
        );
    }
  };

  emit(value, 0);
  walk.run();
}
