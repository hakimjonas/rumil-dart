/// Validation for grammar IRs, run before emission.
///
/// A grammar that passes [validate] satisfies the structural
/// guarantees the tree-sitter emitter relies on: every reference
/// resolves, externals are declared exactly once, hidden rules carry
/// the underscore prefix, and precedence levels are well formed.
library;

import 'ir.dart';

/// A grammar that failed validation.
final class GrammarValidationError implements Exception {
  /// The problems found, in discovery order.
  final List<String> problems;

  /// Creates a validation error.
  GrammarValidationError(this.problems);

  @override
  String toString() =>
      'GrammarValidationError:\n${problems.map((p) => '  - $p').join('\n')}';
}

/// Validates [grammar], throwing [GrammarValidationError] with every
/// problem found when the grammar is not well formed.
void validate(Grammar grammar) {
  final problems = <String>[];
  final ruleNames = grammar.rules.keys.toSet();

  if (_namePattern.hasMatch(grammar.name)) {
    // Valid.
  } else {
    problems.add('grammar name "${grammar.name}" is not an identifier');
  }

  switch (grammar.elem) {
    case CharElem():
      break;
    case TokenElem(:final tokenRule):
      problems.add(
        'token-stream grammars (element "$tokenRule") are not yet '
        'supported by any lowering; use a character-level grammar',
      );
  }

  for (final rule in grammar.rules.values) {
    if (!_namePattern.hasMatch(rule.name)) {
      problems.add('rule name "${rule.name}" is not an identifier');
    }
    switch (rule.kind) {
      case RuleKind.named || RuleKind.token:
        if (rule.name.startsWith('_')) {
          problems.add(
            'rule "${rule.name}" must not start with "_" '
            '(the underscore prefix is reserved for hidden rules)',
          );
        }
      case RuleKind.hidden:
        if (!rule.name.startsWith('_')) {
          problems.add('hidden rule "${rule.name}" must start with "_"');
        }
    }
    _validateExpr(rule.body, rule.name, ruleNames, grammar, problems);
  }

  final nameCounts = <String, int>{};
  for (final external in grammar.externals) {
    nameCounts[external] = (nameCounts[external] ?? 0) + 1;
    if (!_namePattern.hasMatch(external)) {
      problems.add('external token name "$external" is not an identifier');
    }
    if (external.startsWith('_')) {
      problems.add('external token name "$external" must not start with "_"');
    }
    if (ruleNames.contains(external)) {
      problems.add('external token "$external" collides with a declared rule');
    }
  }
  for (final entry in nameCounts.entries) {
    if (entry.value > 1) {
      problems.add(
        'external token "${entry.key}" is declared ${entry.value} times; '
        'each external must be declared exactly once',
      );
    }
  }

  final refTargets = <String>{...ruleNames, ...grammar.externals};
  for (final conflict in grammar.conflicts) {
    if (conflict.length < 2) {
      problems.add('conflict entry $conflict names fewer than two rules');
    }
    for (final name in conflict) {
      if (!ruleNames.contains(name)) {
        problems.add(
          'conflict entry references "$name", which is not a declared rule',
        );
      }
    }
  }

  final word = grammar.word;
  if (word != null && !refTargets.contains(word)) {
    problems.add('word token "$word" does not resolve to a declared rule');
  }

  if (problems.isEmpty) return;
  throw GrammarValidationError(problems);
}

final RegExp _namePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

void _validateExpr(
  Expr expr,
  String context,
  Set<String> ruleNames,
  Grammar grammar,
  List<String> problems,
) {
  switch (expr) {
    case Ref(:final name):
      if (!ruleNames.contains(name) && !grammar.externals.contains(name)) {
        problems.add(
          'rule "$context" references "$name", which is neither a declared '
          'rule nor an external token',
        );
      }
    case Lit() || Pattern():
      break;
    case Seq(:final elements):
      for (final element in elements) {
        _validateExpr(element, context, ruleNames, grammar, problems);
      }
    case Choice(:final members):
      for (final member in members) {
        _validateExpr(member, context, ruleNames, grammar, problems);
      }
    case ZeroOrMore(:final content):
    case OneOrMore(:final content):
    case Optional(:final content):
      _validateExpr(content, context, ruleNames, grammar, problems);
    case Prec(:final value, :final content):
      if (value < 0) {
        problems.add(
          'rule "$context" uses precedence $value; levels must be '
          'non-negative',
        );
      }
      _validateExpr(content, context, ruleNames, grammar, problems);
    case Field(:final name, :final content):
      if (!_namePattern.hasMatch(name)) {
        problems.add(
          'rule "$context" declares field "$name"; field names must be '
          'identifiers',
        );
      }
      _validateExpr(content, context, ruleNames, grammar, problems);
    case Alias(:final content, :final value, :final named):
      if (named && !_namePattern.hasMatch(value)) {
        problems.add(
          'rule "$context" aliases to "$value"; named aliases must be '
          'identifiers',
        );
      }
      _validateExpr(content, context, ruleNames, grammar, problems);
    case TokenWrap(:final content):
      _validateExpr(content, context, ruleNames, grammar, problems);
  }
}
