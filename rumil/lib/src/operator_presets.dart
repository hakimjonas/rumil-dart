/// Operator presets for the [pratt] combinator.
///
/// These are convenience functions that return ready-made operator lists
/// for common precedence ladders. They are not part of rumil's core
/// architecture — the [pratt] combinator and [PrattOperator] subtypes are.
/// The presets exist to remove the duplicate operator/binding-power tables
/// that otherwise appear in every consumer that parses expressions.
library;

import 'combinators.dart';
import 'errors.dart';
import 'parser.dart';

/// C-family operator precedence: 15 operators across 7 levels.
///
/// Returns the standard left-associative arithmetic, comparison, and
/// boolean infix operators plus prefix unary `-` and `!`, with binding
/// powers matching the conventional C / Java / JavaScript / Dart ladder.
/// Multiplicative binds tighter than additive, additive than comparison,
/// comparison than equality, equality than `&&`, `&&` than `||`. Prefix
/// unary binds tighter than any infix.
///
/// Binding powers (low to high):
///
/// - `||`            10
/// - `&&`            20
/// - `==`, `!=`      30
/// - `<=`, `>=`, `<`, `>`  40
/// - `+`, `-`        50
/// - `*`, `/`, `%`   60
/// - prefix `-`, `!` 70
///
/// Use the result directly with [pratt]:
///
/// ```dart
/// final operators = cFamilyPrecedence<Expr>(
///   sym: (s) => string(s).thenSkip(spaces()),
///   binary: (op, a, b) => BinaryOp(op, a, b),
///   unary: (op, a) => UnaryOp(op, a),
/// );
/// final expr = pratt<Expr>(_atom, operators);
/// ```
///
/// To extend or override the preset, post-process or compose the result.
/// To override a single symbol (e.g. `/` needing a `notFollowedBy('/')`
/// guard against `//`), make [sym] dispatch on the input:
///
/// ```dart
/// sym: (s) => s == '/' ? _divSym : _defaultSym(s),
/// ```
///
/// To add new operators (e.g. keyword aliases like `and`, `or`, or a
/// `//` alternative), concatenate them onto the returned list:
///
/// ```dart
/// final operators = [
///   ...cFamilyPrecedence<LamExpr>(...),
///   InfixLeft(_kw('and'), 20, (a, b) => binary('&&', a, b)),
///   InfixLeft(_kw('or'), 10, (a, b) => binary('||', a, b)),
///   InfixRight(_sym('//'), 5, Alternative.new),
/// ];
/// ```
List<PrattOperator<A>> cFamilyPrecedence<A>({
  required Parser<ParseError, String> Function(String) sym,
  required A Function(String op, A left, A right) binary,
  required A Function(String op, A operand) unary,
}) => [
  // Logical OR (lowest precedence).
  InfixLeft(sym('||'), 10, (A a, A b) => binary('||', a, b)),
  // Logical AND.
  InfixLeft(sym('&&'), 20, (A a, A b) => binary('&&', a, b)),
  // Equality.
  InfixLeft(sym('=='), 30, (A a, A b) => binary('==', a, b)),
  InfixLeft(sym('!='), 30, (A a, A b) => binary('!=', a, b)),
  // Comparison. `<=` and `>=` first so `<` doesn't consume the `<` of `<=`.
  InfixLeft(sym('<='), 40, (A a, A b) => binary('<=', a, b)),
  InfixLeft(sym('>='), 40, (A a, A b) => binary('>=', a, b)),
  InfixLeft(sym('<'), 40, (A a, A b) => binary('<', a, b)),
  InfixLeft(sym('>'), 40, (A a, A b) => binary('>', a, b)),
  // Additive.
  InfixLeft(sym('+'), 50, (A a, A b) => binary('+', a, b)),
  InfixLeft(sym('-'), 50, (A a, A b) => binary('-', a, b)),
  // Multiplicative.
  InfixLeft(sym('*'), 60, (A a, A b) => binary('*', a, b)),
  InfixLeft(sym('/'), 60, (A a, A b) => binary('/', a, b)),
  InfixLeft(sym('%'), 60, (A a, A b) => binary('%', a, b)),
  // Prefix unary (highest precedence).
  Prefix(sym('-'), 70, (A a) => unary('-', a)),
  Prefix(sym('!'), 70, (A a) => unary('!', a)),
];
