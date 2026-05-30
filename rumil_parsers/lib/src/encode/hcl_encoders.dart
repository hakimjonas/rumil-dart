/// HCL serializer.
library;

import '../ast/hcl.dart';
import 'escape.dart';
import 'sink_walk.dart';

/// Serialize an [HclDocument] to HCL text.
///
/// Thin wrapper over [serializeHclTo]; output is byte-for-byte identical.
String serializeHcl(HclDocument doc, {int indent = 2}) {
  final buffer = StringBuffer();
  serializeHclTo(buffer, doc, indent: indent);
  return buffer.toString();
}

/// Serialize an [HclDocument] into [sink].
///
/// The value/expression axis ([serializeHclValueTo]) is fully iterative, so
/// arbitrarily-deep lists, objects, and expression trees serialize without
/// overflowing the Dart call stack. The *block-nesting* axis (a `HclBlock`
/// whose body contains another `HclBlock`) is still a recursive descent: HCL
/// block nesting is shallow and statically bounded by the source's brace
/// structure in practice — the same disposition as the proto serializer's
/// nested-message recursion — and it is not reachable from a value tree, only
/// from hand-built or parsed block documents. Block-body indentation is
/// single-level by design (matching the prior output), so flattening it would
/// change bytes; the recursion is preserved deliberately.
void serializeHclTo(StringSink sink, HclDocument doc, {int indent = 2}) {
  for (final (key, value) in doc) {
    switch (value) {
      case HclBlock(:final type, :final labels, body: final blockBody):
        final labelStr = labels.map((l) => '"$l"').join(' ');
        final sep = labelStr.isEmpty ? '' : ' $labelStr';
        sink.writeln('$type$sep {');
        for (final MapEntry(:key, :value) in blockBody.entries) {
          final pad = ' ' * indent;
          switch (value) {
            case HclBlock():
              sink.write(pad);
              serializeHclTo(sink, [(key, value)], indent: indent);
            default:
              sink.write('$pad$key = ');
              serializeHclValueTo(sink, value);
              sink.write('\n');
          }
        }
        sink.writeln('}');
      default:
        sink.write('$key = ');
        serializeHclValueTo(sink, value);
        sink.write('\n');
    }
    sink.writeln();
  }
}

/// Serialize a single [HclValue] to HCL text.
///
/// Thin wrapper over [serializeHclValueTo]; output is byte-for-byte identical.
String serializeHclValue(HclValue value) {
  final buffer = StringBuffer();
  serializeHclValueTo(buffer, value);
  return buffer.toString();
}

/// Serialize a single [HclValue] into [sink].
///
/// Iterative (see `sink_walk.dart`): an explicit worklist replaces the
/// recursive descent across every value, expression, template-part, and
/// splat-postfix shape, so a deeply-nested list, conditional chain, or
/// interpolation tree serializes without overflowing the Dart call stack.
/// Every form's exact byte output is preserved.
void serializeHclValueTo(StringSink sink, HclValue root) {
  final walk = SinkWalk();

  // All three emitters are mutually recursive *in scheduling* only — each
  // writes its node's literals and schedules child steps; none calls another
  // directly. Template parts and splat postfixes embed nested [HclValue]s, so
  // they schedule back into [emit] through the same worklist.
  late final void Function(HclValue) emit;
  late final void Function(HclTemplatePart) emitPart;
  late final void Function(HclPostfixOp) emitPostfix;

  emitPostfix = (HclPostfixOp op) {
    switch (op) {
      case HclPostfixGetAttr(:final name):
        sink.write('.$name');
      case HclPostfixIndex(:final index):
        walk.pushAll([
          () => sink.write('['),
          () => emit(index),
          () => sink.write(']'),
        ]);
    }
  };

  emitPart = (HclTemplatePart part) {
    switch (part) {
      case HclTemplateLiteral(:final value):
        sink.write(escapeHcl(value));
      case HclTemplateInterpolation(
        :final expr,
        :final stripBefore,
        :final stripAfter,
      ):
        final before = stripBefore ? '~ ' : '';
        final after = stripAfter ? ' ~' : '';
        walk.pushAll([
          () => sink.write('\${$before'),
          () => emit(expr),
          () => sink.write('$after}'),
        ]);
      case HclTemplateIf(
        :final condition,
        :final thenBranch,
        :final elseBranch,
      ):
        final steps = <SinkStep>[
          () => sink.write('%{if '),
          () => emit(condition),
          () => sink.write('}'),
          for (final p in thenBranch) () => emitPart(p),
        ];
        if (elseBranch != null) {
          steps.add(() => sink.write('%{else}'));
          for (final p in elseBranch) {
            steps.add(() => emitPart(p));
          }
        }
        steps.add(() => sink.write('%{endif}'));
        walk.pushAll(steps);
      case HclTemplateFor(
        :final keyVar,
        :final valueVar,
        :final collection,
        :final body,
      ):
        final vars = keyVar != null ? '$keyVar, $valueVar' : valueVar;
        walk.pushAll([
          () => sink.write('%{for $vars in '),
          () => emit(collection),
          () => sink.write('}'),
          for (final p in body) () => emitPart(p),
          () => sink.write('%{endfor}'),
        ]);
    }
  };

  emit = (HclValue value) {
    switch (value) {
      case HclString(:final value):
        sink.write('"${escapeHcl(value)}"');
      case HclInt(:final value):
        sink.write('$value');
      case HclDouble(:final value):
        sink.write(_hclDoubleString(value));
      case HclBool(:final value):
        sink.write('$value');
      case HclNull():
        sink.write('null');
      case HclList(:final elements):
        sink.write('[');
        final steps = <SinkStep>[];
        for (var i = 0; i < elements.length; i++) {
          final e = elements[i];
          if (i > 0) steps.add(() => sink.write(', '));
          steps.add(() => emit(e));
        }
        steps.add(() => sink.write(']'));
        walk.pushAll(steps);
      case HclObject(:final fields):
        sink.write('{ ');
        final entries = fields.entries.toList();
        final steps = <SinkStep>[];
        for (var i = 0; i < entries.length; i++) {
          final entry = entries[i];
          if (i > 0) steps.add(() => sink.write(', '));
          steps.add(() => sink.write('${entry.key} = '));
          steps.add(() => emit(entry.value));
        }
        steps.add(() => sink.write(' }'));
        walk.pushAll(steps);
      case HclBlock():
        sink.write('/* nested block */');
      case HclReference(:final path):
        sink.write(path);
      case HclUnaryOp(:final op, :final operand):
        walk.pushAll([
          () => sink.write('($op'),
          () => emit(operand),
          () => sink.write(')'),
        ]);
      case HclBinaryOp(:final op, :final left, :final right):
        walk.pushAll([
          () => sink.write('('),
          () => emit(left),
          () => sink.write(' $op '),
          () => emit(right),
          () => sink.write(')'),
        ]);
      case HclConditional(:final condition, :final then_, :final else_):
        walk.pushAll([
          () => emit(condition),
          () => sink.write(' ? '),
          () => emit(then_),
          () => sink.write(' : '),
          () => emit(else_),
        ]);
      case HclFunctionCall(:final name, :final args, :final expandFinal):
        final expand = expandFinal ? '...' : '';
        sink.write('$name(');
        final steps = <SinkStep>[];
        for (var i = 0; i < args.length; i++) {
          final a = args[i];
          if (i > 0) steps.add(() => sink.write(', '));
          steps.add(() => emit(a));
        }
        steps.add(() => sink.write('$expand)'));
        walk.pushAll(steps);
      case HclIndex(:final collection, :final index):
        walk.pushAll([
          () => emit(collection),
          () => sink.write('['),
          () => emit(index),
          () => sink.write(']'),
        ]);
      case HclGetAttr(:final object, :final name):
        walk.pushAll([() => emit(object), () => sink.write('.$name')]);
      case HclAttrSplat(:final object, :final attrs):
        walk.pushAll([
          () => emit(object),
          () => sink.write('.*${attrs.map((a) => '.$a').join()}'),
        ]);
      case HclFullSplat(:final object, :final accessors):
        walk.pushAll([
          () => emit(object),
          () => sink.write('[*]'),
          for (final a in accessors) () => emitPostfix(a),
        ]);
      case HclForTuple(
        :final keyVar,
        :final valueVar,
        :final collection,
        :final body,
        :final condition,
      ):
        final vars = keyVar != null ? '$keyVar, $valueVar' : valueVar;
        final steps = <SinkStep>[
          () => sink.write('[for $vars in '),
          () => emit(collection),
          () => sink.write(' : '),
          () => emit(body),
        ];
        if (condition != null) {
          steps.add(() => sink.write(' if '));
          steps.add(() => emit(condition));
        }
        steps.add(() => sink.write(']'));
        walk.pushAll(steps);
      case HclForObject(
        :final keyVar,
        :final valueVar,
        :final collection,
        :final keyExpr,
        :final valueExpr,
        :final grouping,
        :final condition,
      ):
        final vars = keyVar != null ? '$keyVar, $valueVar' : valueVar;
        final group = grouping ? '...' : '';
        final steps = <SinkStep>[
          () => sink.write('{for $vars in '),
          () => emit(collection),
          () => sink.write(' : '),
          () => emit(keyExpr),
          () => sink.write(' => '),
          () => emit(valueExpr),
          () => sink.write(group),
        ];
        if (condition != null) {
          steps.add(() => sink.write(' if '));
          steps.add(() => emit(condition));
        }
        steps.add(() => sink.write('}'));
        walk.pushAll(steps);
      case HclParenExpr(:final inner):
        walk.pushAll([
          () => sink.write('('),
          () => emit(inner),
          () => sink.write(')'),
        ]);
      case HclTemplate(:final parts):
        walk.pushAll([
          () => sink.write('"'),
          for (final p in parts) () => emitPart(p),
          () => sink.write('"'),
        ]);
      case HclHeredoc(:final marker, :final indented, :final parts):
        final op = indented ? '<<-' : '<<';
        walk.pushAll([
          () => sink.write('$op$marker\n'),
          for (final p in parts) () => emitPart(p),
          () => sink.write('\n$marker'),
        ]);
    }
  };

  emit(root);
  walk.run();
}

/// Render an [HclDouble] value in source-shape-preserving form. An
/// integer-valued [double] (e.g. parsed from `1.0`) renders with a
/// trailing `.0` so it round-trips as [HclDouble], not [HclInt].
String _hclDoubleString(double value) =>
    value.isFinite && value == value.truncateToDouble()
        ? '${value.toInt()}.0'
        : '$value';
