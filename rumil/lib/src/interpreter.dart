/// The core interpreter — dispatches over the sealed Parser ADT.
///
/// Architecture: external pattern matching over a closed ADT (like Strongbow's
/// ExprInterpreter). Parser subtypes are pure data; interpretation is separate.
///
/// Type safety approach:
/// - **Generic subtypes** (Mapped, FlatMap, Zip): zero casts, existential types
///   preserved via `interpretWith` generic function callbacks
/// - **Fixed-type subtypes** (Satisfy, StringMatch, etc.): `as A` / `as E`
///   runtime-verified widenings, guaranteed safe by reified generics
/// - **Fully-generic subtypes** (Succeed, Fail, Or, etc.): zero casts
/// - **No `dynamic` anywhere**
library;

import 'dart:math' as math;

import 'errors.dart';
import 'memo.dart';
import 'parser.dart';
import 'result.dart';
import 'state.dart';

// ===========================================================================
// Public entry points
// ===========================================================================

/// Run a parser on [input], returning a [Result].
///
/// This is the standard entry point for executing parsers.
// TODO: add runTrampoline for stack-safe FlatMap chains
Result<E, A> run<E, A>(Parser<E, A> parser, String input) {
  final state = ParserState(input);
  return interpretI(parser, state);
}

// ===========================================================================
// Generic interpreter callback type
// ===========================================================================

/// The type of a generic interpreter function that can interpret any
/// `Parser<E, T>` for a fixed `E` and any `T`.
///
/// Used by [Mapped.interpretWith], [FlatMap.interpretWith], and
/// [Zip.interpretWith] to thread existential types without casts.
typedef Interpret<E> = Result<E, T> Function<T>(Parser<E, T> parser);

// ===========================================================================
// Recursive interpreter
// ===========================================================================

/// Internal recursive interpreter. Dispatches over all 26 Parser cases.
///
/// Returns [Result] with lazy errors in [Partial] and [Failure].
///
/// Type safety:
/// - ~18 generic cases: zero casts, types flow naturally
/// - ~3 existential cases (Mapped, FlatMap, Zip): zero casts via interpretWith
/// - ~8 fixed-type cases: `as A`/`as E` runtime-verified widenings
Result<E, A> interpretI<E, A>(Parser<E, A> parser, ParserState state) {
  var p = parser;

  // Outer while loop enables tail-call optimization for Defer
  while (true) {
    switch (p) {
      // ---- Terminals (fully generic — zero casts) ----

      case Succeed<E, A>(:final value):
        return Success<E, A>(value, 0);

      case Fail<E, A>(:final error):
        final loc = state.location;
        return Failure<E, A>(() => [error], loc);

      // ---- Terminals (fixed types — runtime-verified widenings) ----

      case Satisfy(:final pred, :final expected):
        // E is ParseError, A is String (reified generics guarantee)
        if (state.hasChar) {
          final c = state.currentChar;
          if (pred(c)) {
            state.advance();
            return Success<E, A>(c as A, 1);
          } else {
            final loc = state.location;
            return Failure<E, A>(
              () => [Unexpected(c, {expected}, loc) as E],
              loc,
            );
          }
        } else {
          final loc = state.location;
          return Failure<E, A>(
            () => [EndOfInput(expected, loc) as E],
            loc,
          );
        }

      case StringMatch(:final target):
        // E is ParseError, A is String (reified generics guarantee)
        final len = target.length;
        if (state.offset + len > state.input.length) {
          final loc = state.location;
          return Failure<E, A>(
            () => [EndOfInput('"$target"', loc) as E],
            loc,
          );
        }
        if (state.input.substring(state.offset, state.offset + len) == target) {
          state.advanceByString(target);
          return Success<E, A>(target as A, len);
        }
        final loc = state.location;
        final endOff = math.min(state.offset + len, state.input.length);
        final found = state.input.substring(state.offset, endOff);
        return Failure<E, A>(
          () => [Unexpected(found, {'"$target"'}, loc) as E],
          loc,
        );

      case StringChoice(:final targets):
        // E is ParseError, A is String (reified generics guarantee)
        // Linear scan fallback — RadixNode optimization added later
        return _interpretStringChoiceLinear<E, A>(targets, state);

      case Eof():
        // A is void (reified generics guarantee)
        if (state.atEnd) {
          return Success<E, A>(null as A, 0);
        }
        final loc = state.location;
        return Failure<E, A>(
          () => [CustomError('Expected end of input', loc) as E],
          loc,
        );

      // ---- Composition (existential types — zero casts via interpretWith) ----

      case final Mapped<E, dynamic, A> m:
        return m.interpretWith(
          <T>(Parser<E, T> inner) => interpretI<E, T>(inner, state),
        );

      case final FlatMap<E, dynamic, A> fm:
        return fm.interpretWith(
          <T>(Parser<E, T> inner) => interpretI<E, T>(inner, state),
        );

      case final Zip<E, dynamic, dynamic> z:
        return z.interpretWith(
          <T>(Parser<E, T> inner) => interpretI<E, T>(inner, state),
        ) as Result<E, A>;

      // ---- Alternation (fully generic — zero casts) ----

      case Or<E, A>(:final left, :final right):
        final snapshot = state.save();
        final r1 = interpretI<E, A>(left, state);
        if (r1 is! Failure<E, A>) return r1;
        state.restore(snapshot);
        final r2 = interpretI<E, A>(right, state);
        if (r2 is! Failure<E, A>) return r2;
        if (r1.furthest.offset > r2.furthest.offset) return r1;
        if (r2.furthest.offset > r1.furthest.offset) return r2;
        return Failure<E, A>(
          () => [...r1.errorThunk(), ...r2.errorThunk()],
          r1.furthest,
        );

      case Choice<E, A>(:final alternatives):
        return _interpretChoice<E, A>(alternatives, state);

      // ---- Repetition (generic — zero casts, delegated to helpers) ----

      case final Many<E, dynamic> m:
        return m.interpretWith(
          <T>(Parser<E, T> inner) => _interpretMany<E, T>(inner, state),
        ) as Result<E, A>;

      case final Many1<E, dynamic> m1:
        return m1.interpretWith(
          <T>(Parser<E, T> inner) => _interpretMany1<E, T>(inner, state),
        ) as Result<E, A>;

      case final SkipMany<E, dynamic> sm:
        return sm.interpretWith(
          <T>(Parser<E, T> inner) => _interpretSkipMany<E, T>(inner, state),
        ) as Result<E, A>;

      case final Capture<E, dynamic> cap:
        return cap.interpretWith((inner) {
          final startOff = state.offset;
          final r = interpretI(inner, state);
          return switch (r) {
            Success(:final consumed) =>
              Success<E, String>(state.slice(startOff, startOff + consumed), consumed),
            Partial(:final consumed, :final errorThunk) =>
              Partial<E, String>(state.slice(startOff, startOff + consumed), errorThunk, consumed),
            Failure(:final errorThunk, :final furthest) =>
              Failure<E, String>(errorThunk, furthest),
          };
        }) as Result<E, A>;

      // ---- Optional / Lookahead / Negation ----

      case final Optional<E, dynamic> opt:
        return opt.interpretWith(<T>(Parser<E, T> inner) {
          final snapshot = state.save();
          final r = interpretI<E, T>(inner, state);
          if (r case Success<E, T>(:final value, :final consumed)) {
            return Success<E, T?>(value, consumed);
          }
          if (r case Partial<E, T>(:final value, :final errorThunk, :final consumed)) {
            return Partial<E, T?>(value, errorThunk, consumed);
          }
          state.restore(snapshot);
          return Success<E, T?>(null, 0);
        }) as Result<E, A>;

      case final Attempt<dynamic, dynamic> att:
        return att.interpretWith((inner) {
          final snapshot = state.save();
          final r = interpretI(inner, state);
          return switch (r) {
            Success(:final value, :final consumed) =>
              Success<Never, Result<dynamic, dynamic>>(
                Success(value, consumed), 0),
            Partial(:final value, :final errorThunk, :final consumed) =>
              Success<Never, Result<dynamic, dynamic>>(
                Partial.eager(value, errorThunk(), consumed), 0),
            Failure(:final errorThunk, :final furthest) => () {
                state.restore(snapshot);
                return Success<Never, Result<dynamic, dynamic>>(
                  Failure.eager(errorThunk(), furthest), 0);
              }(),
          };
        }) as Result<E, A>;

      case LookAhead<E, A>(:final parser):
        final snapshot = state.save();
        final r = interpretI<E, A>(parser, state);
        state.restore(snapshot);
        return switch (r) {
          Success(:final value) => Success<E, A>(value, 0),
          Partial(:final value, :final errorThunk) =>
            Partial<E, A>(value, errorThunk, 0),
          Failure() => r,
        };

      case NotFollowedBy(:final parser):
        // E is ParseError, A is void
        final snapshot = state.save();
        final r = interpretI(parser, state);
        state.restore(snapshot);
        if (r is! Failure) {
          final loc = state.location;
          return Failure<E, A>(
            () => [CustomError('Unexpected success', loc) as E],
            loc,
          );
        }
        return Success<E, A>(null as A, 0);

      // ---- Error handling / Recovery ----

      case RecoverWith<E, A>(:final parser, :final recovery):
        final snapshot = state.save();
        final r = interpretI<E, A>(parser, state);
        if (r is! Failure<E, A>) return r;
        state.restore(snapshot);
        final r2 = interpretI<E, A>(recovery, state);
        return switch (r2) {
          Success<E, A>(:final value, :final consumed) =>
            Partial<E, A>(value, r.errorThunk, consumed),
          Partial<E, A>(:final value, :final errorThunk, :final consumed) =>
            Partial<E, A>(value, () => [...r.errorThunk(), ...errorThunk()], consumed),
          Failure<E, A>(:final errorThunk, :final furthest) =>
            Failure<E, A>(
              () => [...r.errorThunk(), ...errorThunk()],
              r.furthest.offset > furthest.offset ? r.furthest : furthest,
            ),
        };

      case Expect(:final parser, :final message):
        // E is ParseError, A matches parser's A
        final r = interpretI(parser, state);
        if (r case final Failure<ParseError, dynamic> f) {
          return Failure<E, A>(
            () => [CustomError(message, f.furthest) as E],
            f.furthest,
          );
        }
        return r as Result<E, A>;

      case Named(:final parser, :final name):
        // E is ParseError
        final r = interpretI(parser, state);
        if (r case final Failure<ParseError, dynamic> f) {
          return Failure<E, A>(
            () => f.errorThunk().map((ParseError e) {
                  if (e is Unexpected) {
                    return Unexpected(e.found, {...e.expected, name}, e.location) as E;
                  }
                  return e as E;
                }).toList(),
            f.furthest,
          );
        }
        return r as Result<E, A>;

      // ---- Debugging ----

      case Trace<E, A>(:final parser, :final label):
        // ignore: avoid_print
        print('[TRACE] $label: trying at offset ${state.offset}');
        final r = interpretI<E, A>(parser, state);
        switch (r) {
          case Success(:final consumed):
            print('[TRACE] $label: success, consumed $consumed chars');
          case Partial(:final consumed):
            print('[TRACE] $label: partial, consumed $consumed chars');
          case Failure():
            print('[TRACE] $label: failed');
        }
        return r;

      case Debug<E, A>(:final parser, :final label):
        // ignore: avoid_print
        print('[DEBUG] $label: trying at offset ${state.offset}');
        final r = interpretI<E, A>(parser, state);
        switch (r) {
          case Success(:final value):
            print('[DEBUG] $label: success, parsed $value');
          case Partial(:final value, :final errors):
            print('[DEBUG] $label: partial, $value with ${errors.length} errors');
          case Failure(:final errors):
            print('[DEBUG] $label: failed with ${errors.firstOrNull ?? "unknown"}');
        }
        return r;

      // ---- Laziness / Memoization / Left Recursion ----

      case Defer<E, A>(:final thunk):
        // Tail-call optimization: loop instead of recurse
        p = thunk();
        continue;

      case Memo<E, A>(:final inner, :final key, :final enableLR):
        if (enableLR) {
          return _interpretMemo<E, A>(inner, key, state);
        }
        return _interpretSimpleMemo<E, A>(inner, key, state);

      // Dart's exhaustiveness checker cannot prove coverage when sealed
      // subtypes have varying type parameters. All 26 cases ARE covered.
      default:
        throw StateError('Unreachable: unhandled ${p.runtimeType}');
    }
  }
}

// ===========================================================================
// Warth seed-growth left-recursion algorithm
// ===========================================================================

/// Memoized parser with full left-recursion support.
Result<E, A> _interpretMemo<E, A>(
  Parser<E, A> inner,
  MemoKey<E, A> key,
  ParserState state,
) {
  final pos = state.offset;
  final startSnapshot = state.save();

  // Check if we're inside a growing cycle
  final head = state.heads[pos];
  if (head != null) {
    if (head.evalSet.contains(key.id)) {
      // In eval set — re-evaluate fresh
      head.evalSet.remove(key.id);
      final result = interpretI<E, A>(inner, state);
      state.memo.put(key, pos, result, state.offset);
      return result;
    }
    if (identical(head.rule, key.id)) {
      // This IS the head — return seed from memo
      final slot = state.memo.getRaw(key, pos);
      if (slot case MemoSlotLR(:final lr)) {
        return lr.seed as Result<E, A>;
      }
      if (slot case MemoSlotEntry(:final entry)) {
        state.restoreTo(entry.endPos, state.line, state.column);
        return state.memo.getResult(key, pos)!;
      }
    }
    if (head.involvedSet.contains(key.id)) {
      // Involved in cycle but not head
      final slot = state.memo.getRaw(key, pos);
      if (slot case MemoSlotLR(:final lr)) {
        return lr.seed as Result<E, A>;
      }
      if (slot case MemoSlotEntry(:final entry)) {
        state.restoreTo(entry.endPos, state.line, state.column);
        return state.memo.getResult(key, pos)!;
      }
    }
  }

  return _evaluateMemo<E, A>(inner, key, pos, startSnapshot, state);
}

/// Core memoization: first-visit logic with LR detection.
Result<E, A> _evaluateMemo<E, A>(
  Parser<E, A> inner,
  MemoKey<E, A> key,
  int pos,
  Snapshot startSnapshot,
  ParserState state,
) {
  final slot = state.memo.getRaw(key, pos);

  // Cached LR marker — cycle detected
  if (slot case MemoSlotLR(:final lr)) {
    _setupLR(key.id, lr, state);
    return lr.seed as Result<E, A>;
  }

  // Cached result — return it
  if (slot case MemoSlotEntry(:final entry)) {
    state.restoreTo(entry.endPos, state.line, state.column);
    return entry.result as Result<E, A>;
  }

  // First visit: plant LR marker, parse, maybe grow
  final lr = LR(
    seed: Failure<E, A>.eager([], state.location),
    rule: key.id,
  );
  state.lrStack.add(lr);
  state.memo.putLR(key, pos, lr);

  final result = interpretI<E, A>(inner, state);
  final endPos = state.offset;

  state.lrStack.removeLast();

  // If no cycle detected, or we're not the head — just cache
  if (lr.head == null || !identical(lr.head!.rule, key.id)) {
    state.memo.put(key, pos, result, endPos);
    return result;
  }

  // We're the head of a left-recursive cycle
  if (result is Failure<E, A>) {
    state.memo.put(key, pos, result, endPos);
    return result;
  }

  // Seed growth
  lr.seed = result;
  return _growLR<E, A>(inner, key, startSnapshot, lr, endPos, state);
}

/// Set up left-recursion head when a cycle is detected.
void _setupLR(Object key, LR lr, ParserState state) {
  final existingHead = state.lrStack
      .where((slr) => slr.head != null)
      .map((slr) => slr.head!)
      .firstOrNull;

  final LRHead actualHead;
  if (existingHead != null) {
    lr.head = existingHead;
    if (!identical(key, existingHead.rule)) {
      existingHead.involvedSet.add(key);
    }
    actualHead = existingHead;
  } else {
    lr.head ??= LRHead(key, {}, {});
    actualHead = lr.head!;
  }

  for (final stackLr in state.lrStack.reversed) {
    if (identical(stackLr.rule, key) ||
        identical(stackLr.rule, actualHead.rule)) {
      continue;
    }
    stackLr.head = actualHead;
    actualHead.involvedSet.add(stackLr.rule);
  }
}

/// Grow the seed until no more progress is made.
Result<E, A> _growLR<E, A>(
  Parser<E, A> inner,
  MemoKey<E, A> key,
  Snapshot startSnapshot,
  LR lr,
  int seedEndPos,
  ParserState state,
) {
  final pos = startSnapshot.offset;
  state.heads[pos] = lr.head!;

  var lastResult = lr.seed as Result<E, A>;
  var lastPos = seedEndPos;
  var lastLine = state.line;
  var lastColumn = state.column;

  while (true) {
    state.restore(startSnapshot);
    state.memo.put(key, pos, lastResult, lastPos);
    lr.head!.evalSet = {...lr.head!.involvedSet};

    final result = interpretI<E, A>(inner, state);
    final resultPos = state.offset;

    if (result is Failure || resultPos <= lastPos) {
      break;
    }

    lastResult = result;
    lastPos = resultPos;
    lastLine = state.line;
    lastColumn = state.column;
    lr.seed = result;
  }

  state.heads.remove(pos);
  state.restoreTo(lastPos, lastLine, lastColumn);
  state.memo.put(key, pos, lastResult, lastPos);
  return lastResult;
}

// ===========================================================================
// Simple memoization (no LR support, ~50% faster)
// ===========================================================================

Result<E, A> _interpretSimpleMemo<E, A>(
  Parser<E, A> inner,
  MemoKey<E, A> key,
  ParserState state,
) {
  final pos = state.offset;
  final entry = state.simpleCache.getEntry(key, pos);

  if (entry != null) {
    state.restoreTo(entry.endPos, state.line, state.column);
    return entry.result as Result<E, A>;
  }

  final result = interpretI<E, A>(inner, state);
  state.simpleCache.put(key, pos, result, state.offset);
  return result;
}

// ===========================================================================
// Specialized helpers: Many, Many1, SkipMany, Choice, StringChoice
// ===========================================================================

/// Whether a parser never modifies state on failure (skip save/restore).
bool _isSimple(Parser<dynamic, dynamic> p) =>
    p is Satisfy || p is StringMatch;

Result<E, List<A>> _interpretMany<E, A>(
  Parser<E, A> p,
  ParserState state,
) {
  final acc = <A>[];
  final errThunks = <List<E> Function()>[];
  var totalConsumed = 0;
  final simple = _isSimple(p);

  while (true) {
    final snapshot = simple ? null : state.save();
    final result = interpretI<E, A>(p, state);
    switch (result) {
      case Success<E, A>(:final value, :final consumed):
        acc.add(value);
        totalConsumed += consumed;
      case Partial<E, A>(:final value, :final errorThunk, :final consumed):
        acc.add(value);
        errThunks.add(errorThunk);
        totalConsumed += consumed;
      case Failure<E, A>():
        if (snapshot != null) state.restore(snapshot);
        if (errThunks.isEmpty) {
          return Success<E, List<A>>(acc, totalConsumed);
        }
        return Partial<E, List<A>>(
          acc,
          () => errThunks.expand((t) => t()).toList(),
          totalConsumed,
        );
    }
  }
}

Result<E, List<A>> _interpretMany1<E, A>(
  Parser<E, A> p,
  ParserState state,
) {
  final first = interpretI<E, A>(p, state);
  return switch (first) {
    Success<E, A>(:final value, :final consumed) => () {
        final rest = _interpretMany<E, A>(p, state);
        return switch (rest) {
          Success<E, List<A>>(value: final tail, consumed: final c2) =>
            Success<E, List<A>>([value, ...tail], consumed + c2),
          Partial<E, List<A>>(value: final tail, :final errorThunk, consumed: final c2) =>
            Partial<E, List<A>>([value, ...tail], errorThunk, consumed + c2),
          Failure<E, List<A>>() => rest,
        };
      }(),
    Partial<E, A>(:final value, errorThunk: final mk1, :final consumed) => () {
        final rest = _interpretMany<E, A>(p, state);
        return switch (rest) {
          Success<E, List<A>>(value: final tail, consumed: final c2) =>
            Partial<E, List<A>>([value, ...tail], mk1, consumed + c2),
          Partial<E, List<A>>(value: final tail, errorThunk: final mk2, consumed: final c2) =>
            Partial<E, List<A>>([value, ...tail], () => [...mk1(), ...mk2()], consumed + c2),
          Failure<E, List<A>>(errorThunk: final mk2, :final furthest) =>
            Failure<E, List<A>>(() => [...mk1(), ...mk2()], furthest),
        };
      }(),
    Failure<E, A>(:final errorThunk, :final furthest) =>
      Failure<E, List<A>>(errorThunk, furthest),
  };
}

Result<E, void> _interpretSkipMany<E, A>(
  Parser<E, A> p,
  ParserState state,
) {
  final errThunks = <List<E> Function()>[];
  var totalConsumed = 0;
  final simple = _isSimple(p);

  while (true) {
    final snapshot = simple ? null : state.save();
    final result = interpretI<E, A>(p, state);
    switch (result) {
      case Success<E, A>(:final consumed):
        totalConsumed += consumed;
      case Partial<E, A>(:final errorThunk, :final consumed):
        errThunks.add(errorThunk);
        totalConsumed += consumed;
      case Failure<E, A>():
        if (snapshot != null) state.restore(snapshot);
        if (errThunks.isEmpty) {
          return Success<E, void>(null, totalConsumed);
        }
        return Partial<E, void>(
          null,
          () => errThunks.expand((t) => t()).toList(),
          totalConsumed,
        );
    }
  }
}

Result<E, A> _interpretChoice<E, A>(
  List<Parser<E, A>> alternatives,
  ParserState state,
) {
  final snapshot = state.save();
  List<E> Function() accMkErrors = () => [];
  var furthest = state.location;

  for (final alt in alternatives) {
    final result = interpretI<E, A>(alt, state);
    if (result is! Failure<E, A>) return result;
    state.restore(snapshot);

    if (result.furthest.offset > furthest.offset) {
      accMkErrors = result.errorThunk;
      furthest = result.furthest;
    } else if (result.furthest.offset == furthest.offset) {
      final prev = accMkErrors;
      final curr = result.errorThunk;
      accMkErrors = () => [...prev(), ...curr()];
    }
  }

  return Failure<E, A>(accMkErrors, furthest);
}

/// Linear scan fallback for StringChoice. RadixNode optimization added later.
Result<E, A> _interpretStringChoiceLinear<E, A>(
  List<String> targets,
  ParserState state,
) {
  final input = state.input;
  final offset = state.offset;

  for (final target in targets) {
    final len = target.length;
    if (offset + len <= input.length &&
        input.substring(offset, offset + len) == target) {
      state.advanceByString(target);
      return Success<E, A>(target as A, len);
    }
  }

  final loc = state.location;
  final maxLen = targets.fold(0, (m, t) => math.max(m, t.length));
  final found = input.substring(offset, math.min(offset + maxLen, input.length));
  final expected = targets.map((s) => '"$s"').toSet();
  return Failure<E, A>(
    () => [Unexpected(found, expected, loc) as E],
    loc,
  );
}
