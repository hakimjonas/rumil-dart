/// Top-level combinator functions.
library;

import 'errors.dart';
import 'location.dart';
import 'parser.dart';

/// Try alternatives in order until one succeeds.
///
/// When every alternative starts with a known, distinct character (e.g.
/// `null` / `true` / `false` / `[` / `{` / `"` / digits in JSON), the
/// builder transparently fuses to a [FirstCharChoice] for O(1) dispatch
/// instead of the linear `Or`-chain scan. The fusion is conservative:
/// any alternative whose leading-char set is undecidable (`Defer`,
/// `FlatMap`, `Memo`, an opaque `Satisfy`, etc.), or any pair of
/// alternatives that share a leading char, disables it and falls
/// through to a regular [Choice]. Choices with fewer than 3
/// alternatives are also left unfused — a 2-way choice is already
/// efficiently handled by the existing `Or` FIRST-set optimization.
Parser<E, A> choice<E, A>(List<Parser<E, A>> alternatives) {
  if (alternatives.length < 3) return Choice<E, A>(alternatives);
  final fused = _tryFuseFirstChar<E, A>(alternatives);
  if (fused != null) return fused;
  return Choice<E, A>(alternatives);
}

/// Attempt to fuse [alternatives] into a [FirstCharChoice] when each has
/// statically decidable, mutually disjoint leading characters. Returns
/// null when fusion is unsafe (any alternative is undecidable or any
/// two share a leading char).
Parser<E, A>? _tryFuseFirstChar<E, A>(List<Parser<E, A>> alternatives) {
  final perAltSets = <Set<int>>[];
  for (final alt in alternatives) {
    final chars = _leadingChars(alt);
    if (chars == null) return null;
    // Internal duplicates within one alternative are fine (an Or-chain
    // may have several branches starting with the same char). Only
    // cross-alternative collisions disable fusion.
    perAltSets.add(chars.toSet());
  }
  final dispatch = <int, Parser<E, A>>{};
  final expectedBuf = StringBuffer();
  for (var i = 0; i < alternatives.length; i++) {
    for (final cu in perAltSets[i]) {
      if (dispatch.containsKey(cu)) {
        // Two alternatives share a leading char — bail out, the linear
        // Or scan is still required to disambiguate.
        return null;
      }
      dispatch[cu] = alternatives[i];
      expectedBuf.writeCharCode(cu);
    }
  }
  return FirstCharChoice<E, A>(dispatch, expectedBuf.toString());
}

/// Inspects [p] and returns the set of code units it can start with,
/// or null if undecidable.
///
/// Recognised shapes:
/// - `StringMatch(target)` → `{target.codeUnitAt(0)}`
/// - `StringChoice(targets)` → first code unit of each target
/// - `Satisfy` whose expected label is `'c'` (single-char) → `{c}`. This
///   matches the `char(c)` shape; arbitrary `Satisfy` predicates are
///   undecidable.
/// - `Mapped` / `Named` / `Expect` / `LookAhead` / `Memo` → recurse into
///   the inner parser (these wrappers don't change the leading char).
/// - `Or` / `Choice` → recurse into all branches; result is the union.
/// - `Zip(left, _)` / `Capture(inner)` → recurse on the leading
///   sub-parser; the leading char comes from the leftmost element.
///
/// Anything else (`FlatMap`, `Defer`, `Optional`, `Many`, etc.) returns
/// null — the leading char depends on a value not available at
/// construction time, or the parser may match empty input.
List<int>? _leadingChars(Parser<dynamic, dynamic> p) {
  // String literal of length 3 in the form 'c' (apostrophe + char +
  // apostrophe) is the convention used by `char(c)` for its expected
  // label. Recovering the char from this string lets us decide
  // single-char Satisfy parsers without inspecting the predicate.
  const apostrophe = 0x27;

  switch (p) {
    case StringMatch(:final target):
      if (target.isEmpty) return null;
      return [target.codeUnitAt(0)];

    case StringChoice(:final targets):
      final cus = <int>{};
      for (final t in targets) {
        if (t.isEmpty) return null;
        cus.add(t.codeUnitAt(0));
      }
      return cus.toList();

    case Satisfy(:final expected):
      if (expected.length == 3 &&
          expected.codeUnitAt(0) == apostrophe &&
          expected.codeUnitAt(2) == apostrophe) {
        return [expected.codeUnitAt(1)];
      }
      return null;

    case Mapped(:final source):
      return _leadingChars(source);

    case Named(:final parser):
      return _leadingChars(parser);

    case Expect(:final parser):
      return _leadingChars(parser);

    case LookAhead(:final parser):
      return _leadingChars(parser);

    case Memo(:final inner):
      return _leadingChars(inner);

    case Zip(:final left):
      return _leadingChars(left);

    case Capture(:final parser):
      return _leadingChars(parser);

    case Or(:final left, :final right):
      final l = _leadingChars(left);
      if (l == null) return null;
      final r = _leadingChars(right);
      if (r == null) return null;
      return [...l, ...r];

    case Choice(:final alternatives):
      final all = <int>[];
      for (final alt in alternatives) {
        final chars = _leadingChars(alt);
        if (chars == null) return null;
        all.addAll(chars);
      }
      return all;

    default:
      return null;
  }
}

/// Dispatch to one of several parsers based on the leading character at
/// the current position.
///
/// [dispatch] keys are strings of one or more characters; a single key
/// like `'-0123456789'` binds the same parser to all 11 leading chars
/// (useful for number literals). Each key character maps to that key's
/// parser in the dispatch table. Duplicate characters across keys throw
/// [ArgumentError] at construction.
///
/// On no leading-char match, runs [fallback] if provided, else fails
/// with an error listing the expected characters. The chosen parser is
/// invoked at the same position; it sees the leading char as input.
///
/// O(1) dispatch vs `choice([...])` / `p1 | p2 | ...`'s linear scan.
/// Use when the alternatives have disjoint leading characters — typical
/// for value parsers in structured formats.
///
/// ```dart
/// final jsonValue = firstCharChoice<ParseError, JsonValue>({
///   'n': jsonNull,
///   'tf': jsonBool,
///   '-0123456789': jsonNumber,
///   '"': jsonString,
///   '[': jsonArray,
///   '{': jsonObject,
/// });
/// ```
Parser<ParseError, A> firstCharChoice<A>(
  Map<String, Parser<ParseError, A>> dispatch, {
  Parser<ParseError, A>? fallback,
}) {
  final table = <int, Parser<ParseError, A>>{};
  final expectedBuf = StringBuffer();
  for (final entry in dispatch.entries) {
    if (entry.key.isEmpty) {
      throw ArgumentError(
        'firstCharChoice: dispatch keys must be non-empty strings',
      );
    }
    for (var i = 0; i < entry.key.length; i++) {
      final cu = entry.key.codeUnitAt(i);
      if (table.containsKey(cu)) {
        throw ArgumentError(
          'firstCharChoice: duplicate leading char '
          '"${entry.key[i]}" across dispatch keys',
        );
      }
      table[cu] = entry.value;
      expectedBuf.write(entry.key[i]);
    }
  }
  return FirstCharChoice<ParseError, A>(
    table,
    expectedBuf.toString(),
    fallback: fallback,
  );
}

/// Left-associative binary operator chain.
///
/// Parses `p (op p)*` and folds left: `((a op b) op c) op d`. Iterative
/// in the interpreter — chain depth does not grow the Dart call stack.
Parser<E, A> chainl1<E, A>(Parser<E, A> p, Parser<E, A Function(A, A)> op) =>
    Chainl1<E, A>(p, op);

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
/// Parses `p (op p)*` and folds right: `a op (b op (c op d))`. Iterative
/// in the interpreter — chain depth does not grow the Dart call stack.
Parser<E, A> chainr1<E, A>(Parser<E, A> p, Parser<E, A Function(A, A)> op) =>
    Chainr1<E, A>(p, op);

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
sealed class PrattOperator<A> {
  const PrattOperator();
}

/// Left-associative infix: `a op b op c` → `(a op b) op c`.
final class InfixLeft<A> extends PrattOperator<A> {
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
final class InfixRight<A> extends PrattOperator<A> {
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
final class Prefix<A> extends PrattOperator<A> {
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
final class Postfix<A> extends PrattOperator<A> {
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
  List<PrattOperator<A>> operators,
) {
  final infixAndPostfix = <PrattOperator<A>>[
    for (final o in operators)
      if (o is! Prefix<A>) o,
  ];
  final getOp = _compileGetOp<A>(infixAndPostfix);
  final opTable = _compileOpTable<A>(infixAndPostfix);
  final prefixes = <PrattPrefix<ParseError, A>>[
    for (final o in operators)
      if (o is Prefix<A>) PrattPrefix<ParseError, A>(o.symbol, o.bp, o.fn),
  ];

  return Pratt<ParseError, A>(atom, prefixes, getOp, 0, opTable);
}

Parser<ParseError, PrattOp<A>> _compileGetOp<A>(List<PrattOperator<A>> ops) {
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
            (_) => PrattOpInfix<A>(bp, bp, fn),
          ),
        );
      case InfixRight<A>(:final symbol, :final bp, :final fn):
        branches.add(
          Mapped<ParseError, Object?, PrattOp<A>>(
            symbol,
            (_) => PrattOpInfix<A>(bp, bp - 1, fn),
          ),
        );
      case Postfix<A>(:final symbol, :final bp, :final fn):
        branches.add(
          Mapped<ParseError, Object?, PrattOp<A>>(
            symbol,
            (_) => PrattOpPostfix<A>(bp, fn),
          ),
        );
      case Prefix<A>():
        throw StateError('unreachable: Prefix compiled into nud, not getOp');
    }
  }
  return branches.length == 1 ? branches.single : Choice(branches);
}

/// Descriptor of an operator symbol's literal prefix plus a post-match guard.
typedef _SymShape = ({String prefix, TokenGuard guard});

/// When every operator's symbol can be reduced to a literal prefix (plus an
/// optional word-boundary / not-followed-by guard), build a direct dispatch
/// table keyed on the first code unit. Otherwise returns null; the
/// interpreter falls back to running `getOp`.
///
/// Recognised shapes (in addition to `char(c)`):
/// - `string(s)` / single-char `Satisfy` from `char(c)`
/// - `_lex(string(s))` / `symbol(s)` — trailing ASCII whitespace
/// - `_kw(kw)` — trailing word boundary
/// - `_lex(string(s).thenSkip(char(x).notFollowedBy))` — ambiguity guard
///
/// Ops whose parsers drop into [Mapped]/[FlatMap]/[Defer] early return null,
/// so downstream consumers only pay the table cost when it actually applies.
PrattOpTable<A>? _compileOpTable<A>(List<PrattOperator<A>> ops) {
  var anyTrailingWs = false;

  final pairs = <(int, PrattOpEntry<A>)>[];
  for (final op in ops) {
    _SymShape? shape;
    PrattOp<A>? desc;
    switch (op) {
      case InfixLeft<A>(:final symbol, :final bp, :final fn):
        shape = _symbolShape(symbol);
        desc = PrattOpInfix<A>(bp, bp, fn);
      case InfixRight<A>(:final symbol, :final bp, :final fn):
        shape = _symbolShape(symbol);
        desc = PrattOpInfix<A>(bp, bp - 1, fn);
      case Postfix<A>(:final symbol, :final bp, :final fn):
        shape = _symbolShape(symbol);
        desc = PrattOpPostfix<A>(bp, fn);
      case Prefix<A>():
        return null;
    }
    if (shape == null) return null;
    if (_isLexed(switch (op) {
      InfixLeft<A>(:final symbol) => symbol,
      InfixRight<A>(:final symbol) => symbol,
      Postfix<A>(:final symbol) => symbol,
      Prefix<A>() => throw StateError('unreachable'),
    })) {
      anyTrailingWs = true;
    }
    pairs.add((
      shape.prefix.codeUnitAt(0),
      PrattOpEntry<A>(shape.prefix, desc, guard: shape.guard),
    ));
  }
  return pairs.isEmpty
      ? null
      : PrattOpTable.fromEntries<A>(pairs, consumesTrailingWs: anyTrailingWs);
}

/// Extracts the literal prefix + post-match guard for a known operator
/// symbol parser shape. Returns null if the shape is opaque.
///
/// Recognised shapes:
/// - `char(c)` / `Satisfy` with an "'c'" expected string → 1-char prefix
/// - `string(s)` / `StringMatch` → multi-char prefix, no guard
/// - `p.thenSkip(q)` (Mapped(Zip(p, q))) — strip any `q` and recurse on `p`,
///   composing guards from `q`:
///     - `q` is trailing whitespace (`Many`/`Mapped(Many)`) → no guard
///     - `q` is `char(x).notFollowedBy` → not-followed-by-x guard
///     - `q` is `ident.notFollowedBy` → word-boundary guard
///
/// Opaque shapes (`FlatMap`, `Defer`, `Memo`, choice, etc.) return null.
_SymShape? _symbolShape(Parser<ParseError, Object?> p) {
  const apostrophe = 0x27;
  if (p is Satisfy &&
      p.expected.length == 3 &&
      p.expected.codeUnitAt(0) == apostrophe &&
      p.expected.codeUnitAt(2) == apostrophe) {
    return (prefix: p.expected.substring(1, 2), guard: TokenGuard.none);
  }
  if (p is StringMatch) {
    return (prefix: p.target, guard: TokenGuard.none);
  }

  // thenSkip(q) → Mapped(Zip(p, q)).
  if (p is! Mapped<ParseError, dynamic, dynamic>) return null;
  final inner = p.source;
  if (inner is! Zip<ParseError, dynamic, dynamic>) return null;
  final innerGuard = _skipGuard(inner.right);
  if (innerGuard == null) return null;
  final leftShape = _symbolShape(inner.left);
  if (leftShape == null) return null;
  final combined = _combineGuards(leftShape.guard, innerGuard);
  if (combined == null) return null;
  return (prefix: leftShape.prefix, guard: combined);
}

/// Decodes the `q` in `p.thenSkip(q)` into a guard contribution. Returns null
/// when `q` is opaque so the caller can bail out.
TokenGuard? _skipGuard(Parser<ParseError, Object?> q) {
  // Trailing ASCII whitespace: Many(whitespace) or Mapped(Many(...)).
  var candidate = q;
  if (candidate is Mapped<ParseError, dynamic, dynamic>) {
    candidate = candidate.source;
  }
  if (candidate is Many<ParseError, dynamic>) return TokenGuard.none;

  if (q is NotFollowedBy) {
    final guarded = q.parser;
    const apostrophe = 0x27;
    if (guarded is Satisfy &&
        guarded.expected.length == 3 &&
        guarded.expected.codeUnitAt(0) == apostrophe &&
        guarded.expected.codeUnitAt(2) == apostrophe) {
      return TokenGuard.notFollowedByChar(guarded.expected.codeUnitAt(1));
    }
    // An `Or` / `Choice` whose branches are all `Satisfy` is the idiomatic
    // identifier-continuation check (`alphaNum | char('_')`). Treat it as a
    // word-boundary guard. Any other shape is opaque — fall back.
    if (_isIdentLikeClass(guarded)) return TokenGuard.wordBoundary;
    return null;
  }
  return null;
}

/// True if [p] recognises a single ident-like character — either a direct
/// [Satisfy] or an [Or]/[Choice] whose branches are all ident-like.
bool _isIdentLikeClass(Parser<dynamic, dynamic> p) {
  if (p is Satisfy) return true;
  if (p is Or<dynamic, dynamic>) {
    return _isIdentLikeClass(p.left) && _isIdentLikeClass(p.right);
  }
  if (p is Choice<dynamic, dynamic>) {
    return p.alternatives.every(_isIdentLikeClass);
  }
  return false;
}

/// Combines two guards at the same match site. We only need a small lattice:
/// - none + g → g
/// - g + none → g
/// - same guard twice → that guard
/// Anything else (two distinct non-none guards on one op) is an unusual shape
/// we don't try to encode; fall back to the slow path.
TokenGuard? _combineGuards(TokenGuard a, TokenGuard b) {
  if (a is TokenGuardNone) return b;
  if (b is TokenGuardNone) return a;
  if (a.runtimeType == b.runtimeType) {
    if (a is TokenGuardNotFollowedByChar && b is TokenGuardNotFollowedByChar) {
      if (a.codeUnit == b.codeUnit) return a;
      return null;
    }
    return a;
  }
  return null;
}

/// True if [p] ends in a trailing-whitespace consumer, meaning the table
/// should skip ASCII whitespace after the prefix match to keep the state
/// aligned with what the (bypassed) parser would have done.
///
/// Recognises `p.thenSkip(Many(...))` and `p.thenSkip(Mapped(Many(...)))`.
bool _isLexed(Parser<ParseError, Object?> p) {
  if (p is! Mapped<ParseError, dynamic, dynamic>) return false;
  final inner = p.source;
  if (inner is! Zip<ParseError, dynamic, dynamic>) return false;
  var right = inner.right;
  if (right is Mapped<ParseError, dynamic, dynamic>) {
    right = right.source;
  }
  if (right is Many<ParseError, dynamic>) return true;
  // thenSkip nested once more (e.g. string.thenSkip(nfb).thenSkip(ws)).
  final left = inner.left;
  return _isLexed(left);
}
