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
              sb.writeln('$pad$key = ${serializeHclValue(value)}');
          }
        }
        sb.writeln('}');
      default:
        sb.writeln('$key = ${serializeHclValue(value)}');
    }
    sb.writeln();
  }
  return sb.toString();
}

/// Serialize a single [HclValue] to HCL text.
String serializeHclValue(HclValue value) => switch (value) {
  HclString(:final value) => '"${escapeHcl(value)}"',
  HclNumber(:final value) =>
    value == value.toInt() ? value.toInt().toString() : '$value',
  HclBool(:final value) => '$value',
  HclNull() => 'null',
  HclList(:final elements) => '[${elements.map(serializeHclValue).join(', ')}]',
  HclObject(:final fields) =>
    '{ ${fields.entries.map((e) => '${e.key} = ${serializeHclValue(e.value)}').join(', ')} }',
  HclBlock() => '/* nested block */',
  HclReference(:final path) => path,
  HclUnaryOp(:final op, :final operand) => '($op${serializeHclValue(operand)})',
  HclBinaryOp(:final op, :final left, :final right) =>
    '(${serializeHclValue(left)} $op ${serializeHclValue(right)})',
  HclConditional(:final condition, :final then_, :final else_) =>
    '${serializeHclValue(condition)} ? ${serializeHclValue(then_)} : ${serializeHclValue(else_)}',
  HclFunctionCall(:final name, :final args, :final expandFinal) => () {
    final argStr = args.map(serializeHclValue).join(', ');
    final expand = expandFinal ? '...' : '';
    return '$name($argStr$expand)';
  }(),
  HclIndex(:final collection, :final index) =>
    '${serializeHclValue(collection)}[${serializeHclValue(index)}]',
  HclGetAttr(:final object, :final name) =>
    '${serializeHclValue(object)}.$name',
  HclAttrSplat(:final object, :final attrs) =>
    '${serializeHclValue(object)}.*${attrs.map((a) => '.$a').join()}',
  HclFullSplat(:final object, :final accessors) =>
    '${serializeHclValue(object)}[*]${accessors.map(_serializePostfix).join()}',
  HclForTuple(
    :final keyVar,
    :final valueVar,
    :final collection,
    :final body,
    :final condition,
  ) =>
    () {
      final vars = keyVar != null ? '$keyVar, $valueVar' : valueVar;
      final cond =
          condition != null ? ' if ${serializeHclValue(condition)}' : '';
      return '[for $vars in ${serializeHclValue(collection)} : ${serializeHclValue(body)}$cond]';
    }(),
  HclForObject(
    :final keyVar,
    :final valueVar,
    :final collection,
    :final keyExpr,
    :final valueExpr,
    :final grouping,
    :final condition,
  ) =>
    () {
      final vars = keyVar != null ? '$keyVar, $valueVar' : valueVar;
      final group = grouping ? '...' : '';
      final cond =
          condition != null ? ' if ${serializeHclValue(condition)}' : '';
      return '{for $vars in ${serializeHclValue(collection)} : ${serializeHclValue(keyExpr)} => ${serializeHclValue(valueExpr)}$group$cond}';
    }(),
  HclParenExpr(:final inner) => '(${serializeHclValue(inner)})',
  HclTemplate(:final parts) => '"${parts.map(_serializeTemplatePart).join()}"',
  HclHeredoc(:final marker, :final indented, :final parts) => () {
    final op = indented ? '<<-' : '<<';
    final body = parts.map(_serializeTemplatePart).join();
    return '$op$marker\n$body\n$marker';
  }(),
};

String _serializePostfix(HclPostfixOp op) => switch (op) {
  HclPostfixGetAttr(:final name) => '.$name',
  HclPostfixIndex(:final index) => '[${serializeHclValue(index)}]',
};

String _serializeTemplatePart(HclTemplatePart part) => switch (part) {
  HclTemplateLiteral(:final value) => escapeHcl(value),
  HclTemplateInterpolation(
    :final expr,
    :final stripBefore,
    :final stripAfter,
  ) =>
    () {
      final before = stripBefore ? '~ ' : '';
      final after = stripAfter ? ' ~' : '';
      return '\${$before${serializeHclValue(expr)}$after}';
    }(),
  HclTemplateIf(:final condition, :final thenBranch, :final elseBranch) => () {
    final thenStr = thenBranch.map(_serializeTemplatePart).join();
    final elseStr =
        elseBranch != null
            ? '%{else}${elseBranch.map(_serializeTemplatePart).join()}'
            : '';
    return '%{if ${serializeHclValue(condition)}}$thenStr$elseStr%{endif}';
  }(),
  HclTemplateFor(
    :final keyVar,
    :final valueVar,
    :final collection,
    :final body,
  ) =>
    () {
      final vars = keyVar != null ? '$keyVar, $valueVar' : valueVar;
      final bodyStr = body.map(_serializeTemplatePart).join();
      return '%{for $vars in ${serializeHclValue(collection)}}$bodyStr%{endfor}';
    }(),
};
