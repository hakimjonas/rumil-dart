/// Top-level combinator functions.
library;

import 'errors.dart';
import 'location.dart';
import 'parser.dart';

/// Try alternatives in order until one succeeds.
Parser<E, A> choice<E, A>(List<Parser<E, A>> alternatives) =>
    Choice<E, A>(alternatives);

/// Left-associative binary operator chain.
///
/// Parses `p (op p)*` and folds left: `((a op b) op c) op d`.
Parser<E, A> chainl1<E, A>(Parser<E, A> p, Parser<E, A Function(A, A)> op) {
  Parser<E, A> rest(A acc) => Or<E, A>(
    FlatMap<E, A Function(A, A), A>(
      op,
      (A Function(A, A) f) =>
          FlatMap<E, A, A>(p, (A right) => rest(f(acc, right))),
    ),
    Succeed<E, A>(acc),
  );

  return FlatMap<E, A, A>(p, rest);
}

/// Exactly [n] occurrences of [p].
Parser<E, List<A>> count<E, A>(int n, Parser<E, A> p) {
  if (n <= 0) return Succeed<E, List<A>>(<A>[]);
  Parser<E, List<A>> loop(int remaining, List<A> acc) {
    if (remaining <= 0) return Succeed<E, List<A>>(acc);
    return FlatMap<E, A, List<A>>(p, (A v) => loop(remaining - 1, [...acc, v]));
  }

  return loop(n, []);
}

/// Right-associative binary operator chain.
///
/// Parses `p (op p)*` and folds right: `a op (b op (c op d))`.
Parser<E, A> chainr1<E, A>(Parser<E, A> p, Parser<E, A Function(A, A)> op) =>
    FlatMap<E, A, A>(
      p,
      (A left) => Or<E, A>(
        FlatMap<E, A Function(A, A), A>(
          op,
          (A Function(A, A) f) => Mapped<E, A, A>(
            chainr1<E, A>(p, op),
            (A right) => f(left, right),
          ),
        ),
        Succeed<E, A>(left),
      ),
    );

/// Operator description for the [pratt] combinator.
///
/// Each variant carries its own `symbol` parser (what input signals this
/// operator), a binding power, and a combining function. Binding powers drive
/// precedence and associativity:
///
/// - Higher bp binds tighter (`*` bp=20, `+` bp=10 → `1+2*3` parses as `1+(2*3)`)
/// - [InfixLeft] at `bp` gives `lbp=bp, rbp=bp` — left-associative
/// - [InfixRight] at `bp` gives `lbp=bp, rbp=bp-1` — right-associative
/// - [Prefix] applies before its operand at binding power `bp`
/// - [Postfix] applies to the accumulated LHS at binding power `bp`
sealed class Operator<A> {
  const Operator();
}

/// Left-associative infix: `a op b op c` → `(a op b) op c`.
final class InfixLeft<A> extends Operator<A> {
  /// The parser recognizing this operator's symbol.
  final Parser<ParseError, Object?> symbol;

  /// Binding power — higher means tighter.
  final int bp;

  /// Combines LHS and RHS into the result.
  final A Function(A, A) fn;

  /// Creates a left-associative infix operator descriptor.
  const InfixLeft(this.symbol, this.bp, this.fn);
}

/// Right-associative infix: `a op b op c` → `a op (b op c)`.
final class InfixRight<A> extends Operator<A> {
  /// The parser recognizing this operator's symbol.
  final Parser<ParseError, Object?> symbol;

  /// Binding power — higher means tighter.
  final int bp;

  /// Combines LHS and RHS into the result.
  final A Function(A, A) fn;

  /// Creates a right-associative infix operator descriptor.
  const InfixRight(this.symbol, this.bp, this.fn);
}

/// Prefix operator: applies before its operand (e.g. unary `-`).
final class Prefix<A> extends Operator<A> {
  /// The parser recognizing this operator's symbol.
  final Parser<ParseError, Object?> symbol;

  /// Binding power — higher means tighter.
  final int bp;

  /// Transforms the operand to produce the result.
  final A Function(A) fn;

  /// Creates a prefix operator descriptor.
  const Prefix(this.symbol, this.bp, this.fn);
}

/// Postfix operator: applies after its operand (e.g. `n!`).
final class Postfix<A> extends Operator<A> {
  /// The parser recognizing this operator's symbol.
  final Parser<ParseError, Object?> symbol;

  /// Binding power — higher means tighter.
  final int bp;

  /// Transforms the operand to produce the result.
  final A Function(A) fn;

  /// Creates a postfix operator descriptor.
  const Postfix(this.symbol, this.bp, this.fn);
}

/// Top-Down Operator Precedence (Pratt) expression combinator.
///
/// Builds a parser for expressions formed from an atom parser and a list of
/// operators. Each operator specifies its binding power and combining
/// function; the parser handles precedence, associativity, and mixing of
/// infix/prefix/postfix forms.
///
/// Example:
/// ```dart
/// final num = digit.map(int.parse);
/// final expr = pratt(
///   num,
///   [
///     InfixLeft(char('+'), 10, (int a, int b) => a + b),
///     InfixLeft(char('-'), 10, (int a, int b) => a - b),
///     InfixLeft(char('*'), 20, (int a, int b) => a * b),
///     InfixRight(char('^'), 30, (int a, int b) => math.pow(a, b).toInt()),
///     Prefix(char('-'), 40, (int a) => -a),
///   ],
/// );
/// ```
Parser<ParseError, A> pratt<A>(
  Parser<ParseError, A> atom,
  List<Operator<A>> operators,
) {
  final prefixOps = operators.whereType<Prefix<A>>().toList();
  final infixAndPostfix = <Operator<A>>[
    for (final o in operators)
      if (o is! Prefix<A>) o,
  ];
  final getOp = _compileGetOp<A>(infixAndPostfix);
  final opTable = _compileOpTable<A>(infixAndPostfix);

  final Parser<ParseError, A> nud = prefixOps.isEmpty
      ? atom
      : Choice<ParseError, A>([
          for (final pre in prefixOps)
            FlatMap<ParseError, Object?, A>(
              pre.symbol,
              (_) => Mapped<ParseError, A, A>(
                Pratt<ParseError, A>(atom, getOp, pre.bp, opTable),
                pre.fn,
              ),
            ),
          atom,
        ]);

  return Pratt<ParseError, A>(nud, getOp, 0, opTable);
}

Parser<ParseError, PrattOp<A>> _compileGetOp<A>(List<Operator<A>> ops) {
  if (ops.isEmpty) {
    return Fail<ParseError, PrattOp<A>>(
      CustomError('pratt: no operators', Location.zero),
    );
  }
  final branches = <Parser<ParseError, PrattOp<A>>>[];
  for (final op in ops) {
    switch (op) {
      case InfixLeft<A>(:final symbol, :final bp, :final fn):
        branches.add(
          Mapped<ParseError, Object?, PrattOp<A>>(
            symbol,
            (_) => PrattOpInfix.of<A>(bp, bp, fn),
          ),
        );
      case InfixRight<A>(:final symbol, :final bp, :final fn):
        branches.add(
          Mapped<ParseError, Object?, PrattOp<A>>(
            symbol,
            (_) => PrattOpInfix.of<A>(bp, bp - 1, fn),
          ),
        );
      case Postfix<A>(:final symbol, :final bp, :final fn):
        branches.add(
          Mapped<ParseError, Object?, PrattOp<A>>(
            symbol,
            (_) => PrattOpPostfix.of<A>(bp, fn),
          ),
        );
      case Prefix<A>():
        throw StateError('unreachable: Prefix compiled into nud, not getOp');
    }
  }
  return branches.length == 1 ? branches.single : Choice(branches);
}

/// When every operator's symbol is a `char(c)` parser (detected by the
/// `Satisfy(_, "'c'")` shape produced by the `char` primitive), build a
/// direct code-unit dispatch table. Otherwise returns null; the interpreter
/// falls back to running `getOp`.
PrattOpTable<A>? _compileOpTable<A>(List<Operator<A>> ops) {
  int? charOf(Parser<ParseError, Object?> p) {
    if (p is Satisfy) {
      final expected = p.expected;
      if (expected.length == 3 &&
          expected.codeUnitAt(0) == 0x27 && // '
          expected.codeUnitAt(2) == 0x27) {
        return expected.codeUnitAt(1);
      }
    }
    return null;
  }

  final pairs = <(int, PrattOp<A>)>[];
  for (final op in ops) {
    switch (op) {
      case InfixLeft<A>(:final symbol, :final bp, :final fn):
        final c = charOf(symbol);
        if (c == null) return null;
        pairs.add((c, PrattOpInfix.of<A>(bp, bp, fn)));
      case InfixRight<A>(:final symbol, :final bp, :final fn):
        final c = charOf(symbol);
        if (c == null) return null;
        pairs.add((c, PrattOpInfix.of<A>(bp, bp - 1, fn)));
      case Postfix<A>(:final symbol, :final bp, :final fn):
        final c = charOf(symbol);
        if (c == null) return null;
        pairs.add((c, PrattOpPostfix.of<A>(bp, fn)));
      case Prefix<A>():
        return null;
    }
  }
  return pairs.isEmpty ? null : PrattOpTable.fromPairs<A>(pairs);
}
