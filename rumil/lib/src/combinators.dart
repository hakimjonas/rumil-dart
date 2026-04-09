/// Top-level combinator functions.
library;

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
