/// Parse-scoped hash-consing cache for green nodes.
///
/// Interning structurally-equal greens through one cache returns a single
/// canonical instance, so identical subtrees (every `GreenToken(num, "5")`
/// across a parse, or every identical `GreenTree(expr, …)`) share one heap
/// object instead of each allocating afresh.
///
/// ## Why this shape (mutable, identity-returning)
///
/// rumil-scala's `GreenCache` is an immutable `Map` whose `intern` returns
/// `(updatedCache, canonical)` and is threaded through a `var` on
/// ParserState. That immutability is a deliberate authorial discipline, not
/// a language constraint — Scala has `mutable.Map`, and the same ParserState
/// uses it for the memo tables. The functional shape is cheap there because
/// Scala's immutable Map is a structure-sharing HAMT: O(log32 n) insert
/// sharing most of the prior version.
///
/// Dart has no structure-sharing persistent Map in the standard library, so
/// a literal translation would copy the whole map per intern — O(n) each,
/// O(n^2) per parse. A genuinely persistent map would mean a runtime
/// dependency, and rumil-dart ships with none. Meanwhile [ParserState] is
/// already the one mutable object in the pipeline and already holds its memo
/// tables as mutable Dart Maps. So a mutable cache whose [intern] updates in
/// place is both the idiomatic Dart shape and the only zero-dependency one —
/// and it is consistent with this library's own established discipline
/// rather than a compromise of the Scala version's.
///
/// Correctness is identical either way: interning is monotonic — a canonical
/// instance for a structural value is valid whether or not the branch that
/// produced it survives backtracking — so the cache never needs rollback,
/// exactly like memoization.
///
/// We return the canonical [GreenNode] directly rather than handing out an
/// integer id (the `TypeId`-style indirection a type checker would use):
/// greens are built once and then walked, not compared pairwise in a hot
/// loop, so there's no equality-speed win to justify forcing every consumer
/// to thread a cache around to resolve ids back to nodes. `identical` on the
/// returned reference is the O(1) comparison a future consumer could exploit
/// if one ever wanted it.
///
/// ## Equality and cost
///
/// Keys hash and compare by the green's own structural `==` / `hashCode`.
/// For tokens that's `kind == && text ==` (cheap). For trees it recurses
/// into children, so a tree intern costs O(subtree size) — worth it only
/// when structurally-equal subtrees actually recur in the workload. The
/// token vs tree split is surfaced to grammar authors as
/// `internToken` / `internTree` (see `resilient.dart`'s neighbours in the
/// combinator layer), which both feed this one cache; the naming is a cost
/// signal, not two mechanisms.
///
/// ## Lifecycle
///
/// One cache per `run(parser, input)`, living on [ParserState] for the
/// duration of that parse and discarded with it. Greens from different
/// documents never cross-contaminate.
///
/// ## Sibling-identity contract
///
/// Interning makes structurally-equal siblings `identical`. RedTree sibling
/// disambiguation therefore must not key on green reference identity — it
/// uses `childIndex`, assigned at construction, which survives interning.
/// Don't reintroduce an identity-based sibling lookup and expect it to hold.
library;

import 'green_node.dart';

/// A mutable, parse-scoped hash-cons cache over green nodes.
///
/// Not parameterised on a language's `(Tok, Syn)`: the cache stores greens
/// at `GreenNode<Object?, Object?>` and [intern] is a generic *method*.
/// Structural equality on a green doesn't depend on its type arguments
/// (`kind == && text ==`, or recursive children equality), so a green of any
/// `(Tok, Syn)` is a valid map key, and under the one-language-per-parse
/// invariant every green a single cache sees shares one `(Tok, Syn)` anyway.
///
/// Keeping the *class* non-generic is what lets [ParserState] hold one cache
/// field without being parameterised itself — Dart generics are invariant,
/// so a `GreenCache<Object?, Object?>` would not cast to
/// `GreenCache<Tok, Syn>`. A generic method on a non-generic class sidesteps
/// the cast entirely.
final class GreenCache {
  final Map<GreenNode<Object?, Object?>, GreenNode<Object?, Object?>> _table =
      {};

  /// Creates an empty cache. One is created per parse and discarded with it.
  GreenCache();

  /// Intern [node]: return the canonical instance for its structural
  /// equivalence class. The first occurrence stores [node] as its own
  /// canonical instance; later structurally-equal calls return that stored
  /// instance (`identical` to it).
  ///
  /// The cast back to `GreenNode<Tok, Syn>` is sound: the stored canonical is
  /// either [node] itself (same type) or a prior structurally-equal green,
  /// which under the one-language-per-parse invariant shares [node]'s
  /// `(Tok, Syn)`.
  GreenNode<Tok, Syn> intern<Tok, Syn>(GreenNode<Tok, Syn> node) =>
      (_table[node] ??= node) as GreenNode<Tok, Syn>;

  /// Number of distinct interned nodes. Diagnostic only.
  int get size => _table.length;
}
