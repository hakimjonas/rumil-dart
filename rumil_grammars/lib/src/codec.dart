/// IR serialization: grammar IR to and from JSON.
///
/// The JSON form is the interchange format for the generator CLI: a
/// tool (or a checked-in file) produces IR JSON, and
/// `grammarFromJson` reconstructs the IR for validation and emission.
/// The format is distinct from tree-sitter's `grammar.json`, which is
/// an output format produced by [emitGrammarJson].
library;

import 'ir.dart';

/// Serialises [grammar] to an IR JSON map with a stable key order.
Map<String, Object?> grammarToJson(Grammar grammar) => <String, Object?>{
  'name': grammar.name,
  'elem': switch (grammar.elem) {
    CharElem() => 'char',
    TokenElem(:final tokenRule) => <String, Object?>{
      'kind': 'token',
      'tokenRule': tokenRule,
    },
  },
  'rules': <String, Object?>{
    for (final rule in grammar.rules.values) rule.name: _ruleToJson(rule),
  },
  if (grammar.word != null) 'word': grammar.word,
  'extras': [for (final extra in grammar.extras) _exprToJson(extra)],
  'externals': [...grammar.externals],
  'conflicts': [
    for (final conflict in grammar.conflicts) [...conflict],
  ],
};

Map<String, Object?> _ruleToJson(Rule rule) => <String, Object?>{
  'body': _exprToJson(rule.body),
  'kind': switch (rule.kind) {
    RuleKind.named => 'named',
    RuleKind.hidden => 'hidden',
    RuleKind.token => 'token',
  },
};

Map<String, Object?> _exprToJson(Expr expr) => switch (expr) {
  Ref(:final name) => <String, Object?>{'kind': 'ref', 'name': name},
  Lit(:final value) => <String, Object?>{'kind': 'lit', 'value': value},
  Pattern(:final value, :final flags) => <String, Object?>{
    'kind': 'pattern',
    'value': value,
    if (flags != null) 'flags': flags,
  },
  Seq(:final elements) => <String, Object?>{
    'kind': 'seq',
    'elements': [for (final element in elements) _exprToJson(element)],
  },
  Choice(:final members) => <String, Object?>{
    'kind': 'choice',
    'members': [for (final member in members) _exprToJson(member)],
  },
  ZeroOrMore(:final content) => <String, Object?>{
    'kind': 'zeroOrMore',
    'content': _exprToJson(content),
  },
  OneOrMore(:final content) => <String, Object?>{
    'kind': 'oneOrMore',
    'content': _exprToJson(content),
  },
  Optional(:final content) => <String, Object?>{
    'kind': 'optional',
    'content': _exprToJson(content),
  },
  Prec() => <String, Object?>{
    'kind': switch (expr.kind) {
      PrecKind.prec => 'prec',
      PrecKind.precLeft => 'precLeft',
      PrecKind.precRight => 'precRight',
      PrecKind.precDynamic => 'precDynamic',
    },
    'value': expr.value,
    'content': _exprToJson(expr.content),
  },
  Field(:final name, :final content) => <String, Object?>{
    'kind': 'field',
    'name': name,
    'content': _exprToJson(content),
  },
  Alias(:final content, :final value, :final named) => <String, Object?>{
    'kind': 'alias',
    'content': _exprToJson(content),
    'value': value,
    'named': named,
  },
  TokenWrap(:final content) => <String, Object?>{
    'kind': 'token',
    'content': _exprToJson(content),
  },
};

/// Reconstructs a grammar from an IR JSON map produced by
/// [grammarToJson]. Throws [FormatException] on a malformed document.
Grammar grammarFromJson(Map<String, Object?> json) {
  final name = _string(json, 'name');
  final elemJson = json['elem'];
  final Elem elem = switch (elemJson) {
    'char' => const CharElem(),
    {'kind': 'token', 'tokenRule': final String tokenRule} => TokenElem(
      tokenRule,
    ),
    _ =>
      throw FormatException(
        'invalid "elem": expected "char" or a token descriptor, '
        'got $elemJson',
      ),
  };
  final rulesJson = _map(json, 'rules');
  final rules = <String, Rule>{};
  for (final entry in rulesJson.entries) {
    rules[entry.key] = _ruleFromJson(entry.key, _asMap(entry.value));
  }
  final word = json['word'] as String?;
  final extras = [
    for (final extra in _list(json, 'extras')) _exprFromJson(_asMap(extra)),
  ];
  final externals = [
    for (final external in _list(json, 'externals')) external as String,
  ];
  final conflicts = [
    for (final conflict in _list(json, 'conflicts'))
      [for (final name in _asList(conflict)) name as String],
  ];
  return Grammar(
    name: name,
    elem: elem,
    rules: rules,
    word: word,
    extras: extras,
    externals: externals,
    conflicts: conflicts,
  );
}

/// Reconstructs one rule from its JSON form.
///
/// Two shapes are accepted. The canonical (emitted) form wraps the
/// body: `{"body": <expr>, "kind": "named"|"hidden"|"token"}`. The
/// hand-authoring form is a bare expression object, whose `kind` key
/// is the expression kind; the rule kind is then inferred from the
/// name (the `_` prefix means hidden, the tree-sitter convention).
Rule _ruleFromJson(String name, Map<String, Object?> json) {
  final kindValue = json['kind'];
  final isWrapped =
      json.containsKey('body') &&
      switch (kindValue) {
        'named' || 'hidden' || 'token' => true,
        _ => false,
      };
  if (isWrapped) {
    final kind = switch (kindValue) {
      'named' => RuleKind.named,
      'hidden' => RuleKind.hidden,
      _ => RuleKind.token,
    };
    return Rule(name, _exprFromJson(_map(json, 'body')), kind: kind);
  }
  return Rule(
    name,
    _exprFromJson(json),
    kind: name.startsWith('_') ? RuleKind.hidden : RuleKind.named,
  );
}

Expr _exprFromJson(Map<String, Object?> json) {
  final kind = _string(json, 'kind');
  switch (kind) {
    case 'ref':
      return Ref(_string(json, 'name'));
    case 'lit':
      return Lit(_string(json, 'value'));
    case 'pattern':
      return Pattern(_string(json, 'value'), flags: json['flags'] as String?);
    case 'seq':
      return Seq([
        for (final element in _list(json, 'elements'))
          _exprFromJson(_asMap(element)),
      ]);
    case 'choice':
      return Choice([
        for (final member in _list(json, 'members'))
          _exprFromJson(_asMap(member)),
      ]);
    case 'zeroOrMore' || 'repeat':
      return ZeroOrMore(_exprFromJson(_map(json, 'content')));
    case 'oneOrMore' || 'repeat1':
      return OneOrMore(_exprFromJson(_map(json, 'content')));
    case 'optional':
      return Optional(_exprFromJson(_map(json, 'content')));
    case 'prec' ||
        'precLeft' ||
        'precRight' ||
        'precDynamic' ||
        'prec_left' ||
        'prec_right' ||
        'prec_dynamic':
      final value = json['value'];
      if (value is! int) {
        throw FormatException('invalid precedence value: $value');
      }
      final content = _exprFromJson(_map(json, 'content'));
      return switch (kind) {
        'prec' => Prec(value, content),
        'precLeft' || 'prec_left' => Prec.left(value, content),
        'precRight' || 'prec_right' => Prec.right(value, content),
        _ => Prec.dynamic_(value, content),
      };
    case 'field':
      return Field(_string(json, 'name'), _exprFromJson(_map(json, 'content')));
    case 'alias':
      return Alias(
        _exprFromJson(_map(json, 'content')),
        _string(json, 'value'),
        named: json['named'] as bool? ?? true,
      );
    case 'token':
      return TokenWrap(_exprFromJson(_map(json, 'content')));
    default:
      throw FormatException('invalid expression kind "$kind"');
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map<dynamic, dynamic>) {
    return value.map((key, item) => MapEntry(key as String, item));
  }
  throw FormatException('expected an object, got $value');
}

List<Object?> _asList(Object? value) {
  if (value is List<Object?>) return value;
  if (value is List<dynamic>) return [...value];
  throw FormatException('expected an array, got $value');
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('expected "$key" to be a string, got $value');
}

Map<String, Object?> _map(Map<String, Object?> json, String key) =>
    _asMap(json[key]);

List<Object?> _list(Map<String, Object?> json, String key) =>
    _asList(json[key]);
