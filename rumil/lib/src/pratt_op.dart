/// Operator descriptions for the Pratt (Top-Down Operator Precedence) parsing path.
library;

/// Operator produced by a `getOp` parser and consumed by the Pratt loop.
///
/// Binding powers drive precedence and associativity:
/// - Left-associative infix at precedence `n`: `lbp = n, rbp = n` (RHS must
///   exceed `bp` to continue, yielding left nesting).
/// - Right-associative infix at precedence `n`: `lbp = n, rbp = n - 1` (RHS
///   accepts equal `bp`, yielding right nesting).
/// - Postfix: single `bp`; applies in-place to the accumulated LHS.
///
/// Prefix operators are not a `PrattOp` variant — they are compiled into the
/// `nud` parser directly.
sealed class PrattOp<A> {
  const PrattOp();
}

/// Infix operator: binds `lhs op rhs` into a combined value.
///
/// The `combine` function is stored as `Function` (type-erased) to avoid
/// Dart's function-contravariance cast failures when an interpreter routes
/// through a type-erased trampoline. The public factory [infix] accepts the
/// precise `A Function(A, A)` signature and stores it as `Function`; the
/// interpreter invokes it via `Function.apply`.
final class PrattOpInfix<A> extends PrattOp<A> {
  /// Left binding power (threshold for the Pratt loop to adopt this operator).
  final int lbp;

  /// Right binding power (minBp for the RHS subparse).
  final int rbp;

  /// Combines the left and right values (type-erased to avoid Dart's
  /// function-contravariance cast failures when routed through a trampoline
  /// typed at `dynamic`).
  final Function combine;

  /// Creates an infix operator descriptor from a precise typed combiner.
  static PrattOpInfix<A> of<A>(int lbp, int rbp, A Function(A, A) combine) =>
      PrattOpInfix<A>._(lbp, rbp, combine);

  const PrattOpInfix._(this.lbp, this.rbp, this.combine);
}

/// Postfix operator: binds to the accumulated LHS, no RHS needed.
final class PrattOpPostfix<A> extends PrattOp<A> {
  /// Binding power (threshold for the Pratt loop to adopt this operator).
  final int bp;

  /// Transforms the LHS to produce the result (type-erased; see [PrattOpInfix.combine]).
  final Function apply;

  /// Creates a postfix operator descriptor from a precise typed transformer.
  static PrattOpPostfix<A> of<A>(int bp, A Function(A) apply) =>
      PrattOpPostfix<A>._(bp, apply);

  const PrattOpPostfix._(this.bp, this.apply);
}

/// Pre-compiled character-indexed operator dispatch table.
///
/// When all operators in a Pratt grammar have single-character symbols, the
/// public builder auto-compiles them into this table so the loop can dispatch
/// by peeking the next input character instead of running the `getOp` parser.
/// This avoids per-operator allocation of Failure, Location, and
/// PrattOpInfix/Postfix instances — the table holds pre-built Op instances
/// reused across every parse.
///
/// The table is indexed by the code unit of the character; a `null` slot means
/// the character is not an operator. Callers must only consume the input
/// character when they have confirmed a match and want to apply the operator.
final class PrattOpTable<A> {
  /// Slots indexed by Char.code; null means "no operator here".
  final List<PrattOp<A>?> slots;

  /// Creates a table from a pre-populated slots list.
  const PrattOpTable(this.slots);

  /// Looks up the operator for a given code unit. Returns null on miss.
  PrattOp<A>? opAt(int codeUnit) {
    if (codeUnit < 0 || codeUnit >= slots.length) return null;
    return slots[codeUnit];
  }

  /// Builds a table from (code unit, op) pairs. Last wins on duplicate keys.
  static PrattOpTable<A> fromPairs<A>(List<(int, PrattOp<A>)> pairs) {
    if (pairs.isEmpty) return PrattOpTable<A>(const []);
    final max = pairs.map((p) => p.$1).reduce((a, b) => a > b ? a : b);
    final slots = List<PrattOp<A>?>.filled(max + 1, null);
    for (final pair in pairs) {
      slots[pair.$1] = pair.$2;
    }
    return PrattOpTable<A>(slots);
  }
}
