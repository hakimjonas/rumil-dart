/// Tree-sitter lowering: IR to `grammar.json`.
///
/// The emitter is total and deterministic: the same grammar always
/// produces byte-identical JSON. Rule bodies are emitted in the
/// grammar's declaration order; object keys follow the fixed order
/// below, so generated files can be committed and diffed.
///
/// Reference for the target format: the tree-sitter `grammar.json`
/// schema (see the tree-sitter "creating parsers" docs). The
/// `tree-sitter generate` CLI consumes the emitted file and produces
/// `parser.c`.
library;

import 'dart:convert';

import 'ir.dart';

/// Emits [grammar] as a `grammar.json` string (two-space indented,
/// trailing newline).
String emitGrammarJson(Grammar grammar) {
  final doc = <String, Object?>{};
  doc['name'] = grammar.name;
  if (grammar.word != null) {
    doc['word'] = grammar.word;
  }
  doc['rules'] = <String, Object?>{
    for (final rule in grammar.rules.values) rule.name: _ruleBody(rule),
  };
  doc['extras'] = [for (final extra in grammar.extras) _expr(extra)];
  if (grammar.externals.isNotEmpty) {
    doc['externals'] = [
      for (final external in grammar.externals) _symbol(external),
    ];
  }
  if (grammar.conflicts.isNotEmpty) {
    doc['conflicts'] = [
      for (final conflict in grammar.conflicts) [...conflict],
    ];
  }
  return '${_pretty(doc)}\n';
}

Object? _ruleBody(Rule rule) {
  if (rule.kind == RuleKind.token) {
    return <String, Object?>{'type': 'TOKEN', 'content': _expr(rule.body)};
  }
  return _expr(rule.body);
}

Map<String, Object?> _symbol(String name) => <String, Object?>{
  'type': 'SYMBOL',
  'name': name,
};

Map<String, Object?> _expr(Expr expr) => switch (expr) {
  Ref(:final name) => _symbol(name),
  Lit(:final value) => <String, Object?>{'type': 'STRING', 'value': value},
  Pattern(:final value, :final flags) => <String, Object?>{
    'type': 'PATTERN',
    'value': value,
    if (flags != null) 'flags': flags,
  },
  Seq(:final elements) => <String, Object?>{
    'type': 'SEQ',
    'members': [for (final element in elements) _expr(element)],
  },
  Choice(:final members) => <String, Object?>{
    'type': 'CHOICE',
    'members': [for (final member in members) _expr(member)],
  },
  ZeroOrMore(:final content) => <String, Object?>{
    'type': 'REPEAT',
    'content': _expr(content),
  },
  OneOrMore(:final content) => <String, Object?>{
    'type': 'REPEAT1',
    'content': _expr(content),
  },
  Optional(:final content) => <String, Object?>{
    // The grammar.json schema has no OPTIONAL variant: an optional is
    // a choice between the content and a BLANK.
    'type': 'CHOICE',
    'members': [
      _expr(content),
      const <String, Object?>{'type': 'BLANK'},
    ],
  },
  Prec() => <String, Object?>{
    'type': switch (expr.kind) {
      PrecKind.prec => 'PREC',
      PrecKind.precLeft => 'PREC_LEFT',
      PrecKind.precRight => 'PREC_RIGHT',
      PrecKind.precDynamic => 'PREC_DYNAMIC',
    },
    'value': expr.value,
    'content': _expr(expr.content),
  },
  Field(:final name, :final content) => <String, Object?>{
    'type': 'FIELD',
    'name': name,
    'content': _expr(content),
  },
  Alias(:final content, :final value, :final named) => <String, Object?>{
    'type': 'ALIAS',
    'content': _expr(content),
    'value': value,
    'named': named,
  },
  TokenWrap(:final content) => <String, Object?>{
    'type': 'TOKEN',
    'content': _expr(content),
  },
};

/// Renders [value] with two-space indentation. Key order is insertion
/// order; the emitter controls insertion, so output is stable.
String _pretty(Object? value) {
  final buffer = StringBuffer();
  _write(value, buffer, 0);
  return buffer.toString();
}

void _write(Object? value, StringBuffer buffer, int indent) {
  switch (value) {
    case Map<String, Object?>(:final isEmpty):
      if (isEmpty) {
        buffer.write('{}');
        return;
      }
      buffer.write('{\n');
      var first = true;
      for (final entry in value.entries) {
        if (!first) buffer.write(',\n');
        first = false;
        buffer.write('  ' * (indent + 1));
        buffer.write(jsonEncode(entry.key));
        buffer.write(': ');
        _write(entry.value, buffer, indent + 1);
      }
      buffer.write('\n');
      buffer.write('  ' * indent);
      buffer.write('}');
    case List<Object?>(:final isEmpty):
      if (isEmpty) {
        buffer.write('[]');
        return;
      }
      buffer.write('[\n');
      var first = true;
      for (final element in value) {
        if (!first) buffer.write(',\n');
        first = false;
        buffer.write('  ' * (indent + 1));
        _write(element, buffer, indent + 1);
      }
      buffer.write('\n');
      buffer.write('  ' * indent);
      buffer.write(']');
    case String():
      buffer.write(jsonEncode(value));
    case bool():
      buffer.write(value ? 'true' : 'false');
    case num():
      buffer.write(value.toString());
    case null:
      buffer.write('null');
    default:
      throw ArgumentError.value(value, 'value', 'unsupported JSON value');
  }
}
