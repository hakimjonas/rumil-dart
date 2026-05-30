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
final class PrattOpInfix<A> extends PrattOp<A> {
  /// Left binding power (threshold for the Pratt loop to adopt this operator).
  final int lbp;

  /// Right binding power (minBp for the RHS subparse).
  final int rbp;

  /// Combines the left and right values into the operator's result.
  final A Function(A, A) combine;

  /// Creates an infix operator descriptor.
  const PrattOpInfix(this.lbp, this.rbp, this.combine);

  /// Combine the left and right values at the erased-driver boundary.
  ///
  /// The interpreter drives Pratt at `A = dynamic`, so it holds the operands as
  /// `Object?`. This operator *applies itself*: the `as A` casts live here,
  /// where [A] is statically in scope and reified from this instance's runtime
  /// type, so they are self-evidently sound. Reading [combine] out and widening
  /// it to `dynamic Function(dynamic, dynamic)` instead would fail — a typed
  /// combiner like `int Function(int, int)` is not assignable under parameter
  /// contravariance. This is the same boundary shape as `FlatMap.applyF`.
  Object? combineWith(Object? l, Object? r) => combine(l as A, r as A);
}

/// Postfix operator: binds to the accumulated LHS, no RHS needed.
final class PrattOpPostfix<A> extends PrattOp<A> {
  /// Binding power (threshold for the Pratt loop to adopt this operator).
  final int bp;

  /// Transforms the LHS to produce the result.
  final A Function(A) apply;

  /// Creates a postfix operator descriptor.
  const PrattOpPostfix(this.bp, this.apply);

  /// Apply this postfix operator to the accumulated LHS at the erased-driver
  /// boundary. The `as A` cast is confined here; see [PrattOpInfix.combineWith].
  Object? applyTo(Object? x) => apply(x as A);
}

/// Post-prefix guard applied before committing to an operator match.
///
/// After the literal prefix characters match at the current offset, the guard
/// decides whether the match is really an operator or whether it is the start
/// of something longer (or a larger identifier). On failure, the Pratt loop
/// continues down the bucket to try the next shorter prefix; if every entry
/// fails, the loop exits without consuming input.
sealed class TokenGuard {
  const TokenGuard();

  /// No post-match check — the prefix alone is the operator.
  static const TokenGuard none = TokenGuardNone._();

  /// Require a word boundary: the character immediately after the prefix must
  /// not be `[A-Za-z0-9_]`. Used for keyword operators like `and` / `or` where
  /// `.andy` must not be split as `and` + `y`.
  static const TokenGuard wordBoundary = TokenGuardWordBoundary._();

  /// Require the character immediately after the prefix not to equal the given
  /// code unit. Used to disambiguate `/` from `//` where `//` is a longer op
  /// at a different precedence.
  const factory TokenGuard.notFollowedByChar(int codeUnit) =
      TokenGuardNotFollowedByChar._;
}

/// The "no guard" variant.
final class TokenGuardNone extends TokenGuard {
  const TokenGuardNone._();
}

/// Guard requiring the next char to be a non-identifier boundary.
final class TokenGuardWordBoundary extends TokenGuard {
  const TokenGuardWordBoundary._();
}

/// Guard requiring the next char not to equal [codeUnit].
final class TokenGuardNotFollowedByChar extends TokenGuard {
  /// The code unit that must NOT follow the matched prefix.
  final int codeUnit;

  const TokenGuardNotFollowedByChar._(this.codeUnit);
}

/// A single operator entry in a [PrattOpTable] bucket.
///
/// Carries the literal prefix to match at the current offset, the operator
/// descriptor to apply on a successful match, and a post-prefix guard for
/// disambiguation with longer operators or identifiers.
final class PrattOpEntry<A> {
  /// The literal characters that begin this operator.
  final String prefix;

  /// The operator descriptor applied once the prefix + guard match.
  final PrattOp<A> op;

  /// Post-prefix guard; [TokenGuard.none] if the prefix alone suffices.
  final TokenGuard guard;

  /// Creates a table entry for [prefix] producing [op].
  const PrattOpEntry(this.prefix, this.op, {this.guard = TokenGuard.none});
}

/// Pre-compiled operator dispatch table indexed by the first code unit of
/// each operator's prefix.
///
/// Each bucket holds the entries whose prefix begins with that code unit,
/// pre-sorted longest-prefix-first so `<=` is tried before `<`, `==` before
/// `=`-led alternatives, and so on. On a hit the Pratt loop compares the
/// literal prefix against the input, runs the guard, then advances and
/// optionally consumes trailing whitespace — all without entering the
/// interpreter recursion used by the general `getOp` fallback path.
final class PrattOpTable<A> {
  /// Entries grouped by first code unit; null means "no operator starts here".
  final List<List<PrattOpEntry<A>>?> slots;

  /// Whether the loop should skip ASCII whitespace
  /// (space/tab/CR/LF) after advancing past the matched prefix.
  final bool consumesTrailingWs;

  /// Creates a table from a pre-populated slot list.
  const PrattOpTable(this.slots, {this.consumesTrailingWs = false});

  /// Returns the bucket of entries starting at [codeUnit], or null on miss.
  List<PrattOpEntry<A>>? entriesAt(int codeUnit) {
    if (codeUnit < 0 || codeUnit >= slots.length) return null;
    return slots[codeUnit];
  }

  /// Builds a single-char table from (code unit, op) pairs without guards or
  /// trailing-whitespace skipping. Kept for callers that want a minimal
  /// one-char dispatch like arithmetic `+-*/`.
  static PrattOpTable<A> fromPairs<A>(List<(int, PrattOp<A>)> pairs) {
    if (pairs.isEmpty) return PrattOpTable<A>(const []);
    final entries = [
      for (final p in pairs)
        (p.$1, PrattOpEntry<A>(String.fromCharCode(p.$1), p.$2)),
    ];
    return fromEntries(entries);
  }

  /// Builds a table from (first code unit, entry) pairs. Within each bucket,
  /// entries are sorted longest-prefix-first so `<=` is tried before `<`.
  static PrattOpTable<A> fromEntries<A>(
    List<(int, PrattOpEntry<A>)> pairs, {
    bool consumesTrailingWs = false,
  }) {
    if (pairs.isEmpty) {
      return PrattOpTable<A>(const [], consumesTrailingWs: consumesTrailingWs);
    }
    final max = pairs.map((p) => p.$1).reduce((a, b) => a > b ? a : b);
    final slots = List<List<PrattOpEntry<A>>?>.filled(max + 1, null);
    for (final pair in pairs) {
      (slots[pair.$1] ??= <PrattOpEntry<A>>[]).add(pair.$2);
    }
    for (final bucket in slots) {
      if (bucket != null && bucket.length > 1) {
        bucket.sort((a, b) => b.prefix.length - a.prefix.length);
      }
    }
    return PrattOpTable<A>(slots, consumesTrailingWs: consumesTrailingWs);
  }
}

/// True if [codeUnit] is an ASCII identifier continuation character.
///
/// Shared with [TokenGuard.wordBoundary] and kept here so the interpreter
/// doesn't need to duplicate the class definition.
bool isIdentChar(int codeUnit) =>
    (codeUnit >= 0x30 && codeUnit <= 0x39) || // 0-9
    (codeUnit >= 0x41 && codeUnit <= 0x5A) || // A-Z
    (codeUnit >= 0x61 && codeUnit <= 0x7A) || // a-z
    codeUnit == 0x5F; // _
