/// Variable and function binding for expression evaluation.
library;

import 'dart:math' as math;

/// Evaluation environment with variables and functions.
///
/// Variables are `Object` values (double, String, bool).
/// Functions take a list of `Object` arguments and return `Object`.
class Environment {
  /// Named values available to expressions.
  final Map<String, Object> variables;

  /// Named functions callable from expressions.
  final Map<String, Object Function(List<Object>)> functions;

  /// Creates an environment with the given [variables] and [functions].
  const Environment({this.variables = const {}, this.functions = const {}});

  /// Creates an environment with built-in math and string functions.
  factory Environment.standard({
    Map<String, Object> variables = const {},
    Map<String, Object Function(List<Object>)> functions = const {},
  }) => Environment(
    variables: variables,
    functions: {...builtinFunctions, ...functions},
  );
}

double _asNum(Object v, String ctx) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  throw EvalException('$ctx: expected number, got ${v.runtimeType}');
}

/// Built-in functions available via [Environment.standard].
///
/// Includes: abs, ceil, floor, round, sqrt, min, max, length,
/// uppercase, lowercase.
final Map<String, Object Function(List<Object>)> builtinFunctions = {
  'abs': (args) => _asNum(args[0], 'abs').abs(),
  'ceil': (args) => _asNum(args[0], 'ceil').ceilToDouble(),
  'floor': (args) => _asNum(args[0], 'floor').floorToDouble(),
  'round': (args) => _asNum(args[0], 'round').roundToDouble(),
  'sqrt': (args) => math.sqrt(_asNum(args[0], 'sqrt')),
  'min': (args) => math.min(_asNum(args[0], 'min'), _asNum(args[1], 'min')),
  'max': (args) => math.max(_asNum(args[0], 'max'), _asNum(args[1], 'max')),
  'length': (args) {
    final v = args[0];
    if (v is String) return v.length.toDouble();
    throw EvalException('length: expected string, got ${v.runtimeType}');
  },
  'uppercase': (args) {
    final v = args[0];
    if (v is String) return v.toUpperCase();
    throw EvalException('uppercase: expected string, got ${v.runtimeType}');
  },
  'lowercase': (args) {
    final v = args[0];
    if (v is String) return v.toLowerCase();
    throw EvalException('lowercase: expected string, got ${v.runtimeType}');
  },
};

/// Error thrown during expression evaluation.
class EvalException implements Exception {
  /// The error message.
  final String message;

  /// Creates an [EvalException] with [message].
  const EvalException(this.message);

  @override
  String toString() => 'EvalException: $message';
}
