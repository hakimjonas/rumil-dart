/// Core interpreter for the Parser ADT.
library;

import 'dart:math' as math;

import 'errors.dart';
import 'memo.dart';
import 'parser.dart';
import 'radix.dart';
import 'result.dart';
import 'state.dart';

// ===========================================================================
// Public API
// ===========================================================================

/// Run a parser on [input], returning a [Result].
///
/// Stack-safe for arbitrarily deep FlatMap/Map/Zip chains.
Result<E, A> run<E, A>(Parser<E, A> parser, String input) {
  final state = ParserState(input);
  return interpretI(parser, state);
}

/// Run without the trampoline (direct recursion).
Result<E, A> runRecursive<E, A>(Parser<E, A> parser, String input) {
  final state = ParserState(input);
  return interpretI(parser, state);
}

// ===========================================================================
// Defunctionalized trampoline
// ===========================================================================

sealed class _Cont {
  const _Cont();
}

final class _ContEnd extends _Cont {
  const _ContEnd();
}

final class _ContFlatMap extends _Cont {
  final FlatMap<dynamic, dynamic, dynamic> node;
  final _Cont next;
  const _ContFlatMap(this.node, this.next);
}

final class _ContMap extends _Cont {
  final Mapped<dynamic, dynamic, dynamic> node;
  final _Cont next;
  const _ContMap(this.node, this.next);
}

final class _ContZipRight extends _Cont {
  final Parser<dynamic, dynamic> right;
  final _Cont next;
  _ContZipRight(this.right, this.next);
}

final class _ContZipCombine extends _Cont {
  final Object? leftValue;
  final int leftConsumed;
  final _Cont next;
  const _ContZipCombine(this.leftValue, this.leftConsumed, this.next);
}

final class _ContPartial extends _Cont {
  final List<Object?> Function() mkErrors;
  final _Cont next;
  const _ContPartial(this.mkErrors, this.next);
}

final class _ContPartialConsumed extends _Cont {
  final int extraConsumed;
  final _Cont next;
  const _ContPartialConsumed(this.extraConsumed, this.next);
}

Result<E, A> _runTrampoline<E, A>(Parser<E, A> parser, ParserState state) {
  Parser<dynamic, dynamic> currentParser = parser;
  _Cont cont = const _ContEnd();

  outer:
  while (true) {
    while (currentParser is FlatMap<dynamic, dynamic, dynamic>) {
      cont = _ContFlatMap(currentParser, cont);
      currentParser = currentParser.source;
    }
    while (currentParser is Mapped<dynamic, dynamic, dynamic>) {
      cont = _ContMap(currentParser, cont);
      currentParser = currentParser.source;
    }
    if (currentParser is Zip<dynamic, dynamic, dynamic>) {
      cont = _ContZipRight(currentParser.right, cont);
      currentParser = currentParser.left;
      continue outer;
    }

    var result = interpretI<E, dynamic>(currentParser as Parser<E, dynamic>, state) as Result<E, Object?>;

    while (true) {
      switch (cont) {
        case _ContEnd():
          return switch (result) {
            Success<E, Object?>(:final value, :final consumed) => Success<E, A>(
              value as A,
              consumed,
            ),
            Partial<E, Object?>(
              :final value,
              :final errorThunk,
              :final consumed,
            ) =>
              Partial<E, A>(value as A, errorThunk, consumed),
            Failure<E, Object?>(:final errorThunk, :final furthest) =>
              Failure<E, A>(errorThunk, furthest),
          };

        case _ContFlatMap(:final node, :final next):
          if (result case Success<E, Object?>(:final value, :final consumed)) {
            currentParser = node.applyF(value);
            cont = consumed > 0 ? _ContPartialConsumed(consumed, next) : next;
            continue outer;
          }
          if (result case Partial<E, Object?>(
            :final value,
            :final errorThunk,
            :final consumed,
          )) {
            currentParser = node.applyF(value);
            cont = _ContPartial(
              errorThunk,
              consumed > 0 ? _ContPartialConsumed(consumed, next) : next,
            );
            continue outer;
          }
          cont = next;
          continue;

        case _ContMap(:final node, :final next):
          if (result case Success<E, Object?>(:final value, :final consumed)) {
            result = Success<E, Object?>(node.applyF(value), consumed);
          } else if (result case Partial<E, Object?>(
            :final value,
            :final errorThunk,
            :final consumed,
          )) {
            result = Partial<E, Object?>(
              node.applyF(value),
              errorThunk,
              consumed,
            );
          }
          cont = next;
          continue;

        case _ContZipRight(:final right, :final next):
          if (result case Success<E, Object?>(:final value, :final consumed)) {
            cont = _ContZipCombine(value, consumed, next);
            currentParser = right;
            continue outer;
          }
          if (result case Partial<E, Object?>(
            :final value,
            :final errorThunk,
            :final consumed,
          )) {
            cont = _ContPartial(errorThunk, _ContZipCombine(value, consumed, next));
            currentParser = right;
            continue outer;
          }
          cont = next;
          continue;

        case _ContZipCombine(
          :final leftValue,
          :final leftConsumed,
          :final next,
        ):
          if (result case Success<E, Object?>(:final value, :final consumed)) {
            result = Success<E, Object?>((
              leftValue,
              value,
            ), leftConsumed + consumed);
          } else if (result case Partial<E, Object?>(
            :final value,
            :final errorThunk,
            :final consumed,
          )) {
            result = Partial<E, Object?>(
              (leftValue, value),
              errorThunk,
              leftConsumed + consumed,
            );
          }
          cont = next;
          continue;

        case _ContPartial(:final mkErrors, :final next):
          List<E> typedMkErrors() => mkErrors().cast<E>();
          if (result case Success<E, Object?>(:final value, :final consumed)) {
            result = Partial<E, Object?>(value, typedMkErrors, consumed);
          } else if (result case Partial<E, Object?>(
            :final value,
            :final errorThunk,
            :final consumed,
          )) {
            result = Partial<E, Object?>(
              value,
              () => [...typedMkErrors(), ...errorThunk()],
              consumed,
            );
          } else if (result case Failure<E, Object?>(
            :final errorThunk,
            :final furthest,
          )) {
            result = Failure<E, Object?>(
              () => [...typedMkErrors(), ...errorThunk()],
              furthest,
            );
          }
          cont = next;
          continue;

        case _ContPartialConsumed(:final extraConsumed, :final next):
          if (result case Success<E, Object?>(:final value, :final consumed)) {
            result = Success<E, Object?>(value, extraConsumed + consumed);
          } else if (result case Partial<E, Object?>(
            :final value,
            :final errorThunk,
            :final consumed,
          )) {
            result = Partial<E, Object?>(
              value,
              errorThunk,
              extraConsumed + consumed,
            );
          }
          cont = next;
          continue;
      }
    }
  }
}


// ===========================================================================
// Recursive interpreter
// ===========================================================================

/// Dispatches over all 26 Parser cases.
Result<E, A> interpretI<E, A>(Parser<E, A> parser, ParserState state) {
  var p = parser;

  while (true) {
    switch (p) {
      case Succeed<E, A>(:final value):
        return Success<E, A>(value, 0);

      case Fail<E, A>(:final error):
        final loc = state.location;
        return Failure<E, A>(() => [error], loc);

      case Satisfy(:final pred, :final expected):
        if (state.hasChar) {
          final c = state.currentChar;
          if (pred(c)) {
            state.advance();
            return Success<E, A>(c as A, 1);
          } else {
            final loc = state.location;
            return Failure<E, A>(
              () => [
                Unexpected(c, {expected}, loc) as E,
              ],
              loc,
            );
          }
        } else {
          final loc = state.location;
          return Failure<E, A>(() => [EndOfInput(expected, loc) as E], loc);
        }

      case StringMatch(:final target):
        final len = target.length;
        if (state.offset + len > state.input.length) {
          final loc = state.location;
          return Failure<E, A>(() => [EndOfInput('"$target"', loc) as E], loc);
        }
        if (_regionMatches(state.input, state.offset, target)) {
          state.advanceByString(target);
          return Success<E, A>(target as A, len);
        }
        final loc = state.location;
        final endOff = math.min(state.offset + len, state.input.length);
        final found = state.input.substring(state.offset, endOff);
        return Failure<E, A>(
          () => [
            Unexpected(found, {'"$target"'}, loc) as E,
          ],
          loc,
        );

      case StringChoice(:final radix, :final targets):
        return _interpretStringChoice<E, A>(radix, targets, state);

      case Eof():
        if (state.atEnd) return Success<E, A>(null as A, 0);
        final loc = state.location;
        return Failure<E, A>(
          () => [CustomError('Expected end of input', loc) as E],
          loc,
        );

      case Mapped<E, dynamic, A>():
        return _runTrampoline<E, A>(p, state);

      case FlatMap<E, dynamic, A>():
        return _runTrampoline<E, A>(p, state);

      case Zip<E, dynamic, dynamic>():
        return _runTrampoline<E, A>(p, state);

      case Or<E, A>(:final left, :final right):
        final simple = left.isSimple;
        final snapshot = simple ? 0 : state.save();
        final r1 = interpretI<E, A>(left, state);
        if (r1 is! Failure<E, A>) return r1;
        if (!simple) state.restore(snapshot);
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

      case Capture<E, dynamic>(
        parser: Many<E, dynamic>(parser: final Satisfy s),
      ):
        return _scanMany<E, A>(s.pred, s.expected, state, required: false);

      case Capture<E, dynamic>(
        parser: Many1<E, dynamic>(parser: final Satisfy s),
      ):
        return _scanMany<E, A>(s.pred, s.expected, state, required: true);

      case Many<E, dynamic>(parser: final Satisfy s):
        return _collectMany<E, A>(s.pred, state);

      case Many1<E, dynamic>(parser: final Satisfy s):
        return _collectMany1<E, A>(s.pred, s.expected, state);

      case final Many<E, dynamic> m:
        return m.interpretWith(
              <T>(Parser<E, T> inner) => _interpretMany<E, T>(inner, state),
            )
            as Result<E, A>;

      case final Many1<E, dynamic> m1:
        return m1.interpretWith(
              <T>(Parser<E, T> inner) => _interpretMany1<E, T>(inner, state),
            )
            as Result<E, A>;

      case final SkipMany<E, dynamic> sm:
        return sm.interpretWith(
              <T>(Parser<E, T> inner) => _interpretSkipMany<E, T>(inner, state),
            )
            as Result<E, A>;

      case Capture<E, dynamic>(parser: Many<E, dynamic>(:final parser)):
        return _interpretCaptureMany<E, dynamic>(
          parser, state, required: false,
        ) as Result<E, A>;

      case Capture<E, dynamic>(parser: Many1<E, dynamic>(:final parser)):
        return _interpretCaptureMany<E, dynamic>(
          parser, state, required: true,
        ) as Result<E, A>;

      case final Capture<E, dynamic> cap:
        return cap.interpretWith((inner) {
              final startOff = state.offset;
              final r = interpretI(inner, state);
              return switch (r) {
                Success(:final consumed) => Success<E, String>(
                  state.slice(startOff, startOff + consumed),
                  consumed,
                ),
                Partial(:final consumed, :final errorThunk) =>
                  Partial<E, String>(
                    state.slice(startOff, startOff + consumed),
                    errorThunk,
                    consumed,
                  ),
                Failure(:final errorThunk, :final furthest) =>
                  Failure<E, String>(errorThunk, furthest),
              };
            })
            as Result<E, A>;

      case final Optional<E, dynamic> opt:
        return opt.interpretWith(<T>(Parser<E, T> inner) {
              final simple = inner.isSimple;
              final snapshot = simple ? 0 : state.save();
              final r = interpretI<E, T>(inner, state);
              if (r case Success<E, T>(:final value, :final consumed)) {
                return Success<E, T?>(value, consumed);
              }
              if (r case Partial<E, T>(
                :final value,
                :final errorThunk,
                :final consumed,
              )) {
                return Partial<E, T?>(value, errorThunk, consumed);
              }
              if (!simple) state.restore(snapshot);
              return Success<E, T?>(null, 0);
            })
            as Result<E, A>;

      case final Attempt<dynamic, dynamic> att:
        return att.interpretWith((inner) {
              final snapshot = state.save();
              final r = interpretI(inner, state);
              return switch (r) {
                Success(:final value, :final consumed) =>
                  Success<Never, Result<dynamic, dynamic>>(
                    Success(value, consumed),
                    0,
                  ),
                Partial(:final value, :final errorThunk, :final consumed) =>
                  Success<Never, Result<dynamic, dynamic>>(
                    Partial.eager(value, errorThunk(), consumed),
                    0,
                  ),
                Failure(:final errorThunk, :final furthest) => () {
                  state.restore(snapshot);
                  return Success<Never, Result<dynamic, dynamic>>(
                    Failure.eager(errorThunk(), furthest),
                    0,
                  );
                }(),
              };
            })
            as Result<E, A>;

      case LookAhead<E, A>(:final parser):
        final snapshot = state.save();
        final r = interpretI<E, A>(parser, state);
        state.restore(snapshot);
        return switch (r) {
          Success(:final value) => Success<E, A>(value, 0),
          Partial(:final value, :final errorThunk) => Partial<E, A>(
            value,
            errorThunk,
            0,
          ),
          Failure() => r,
        };

      case NotFollowedBy(:final parser):
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

      case RecoverWith<E, A>(:final parser, :final recovery):
        final snapshot = state.save();
        final r = interpretI<E, A>(parser, state);
        if (r is! Failure<E, A>) return r;
        state.restore(snapshot);
        // Eagerly evaluate the original failure's errors now, before further
        // parsing mutates state. Lazy thunks may close over ParserState and
        // read stale offsets if evaluated later (see _satisfyMany).
        final originalErrors = r.errorThunk();
        final r2 = interpretI<E, A>(recovery, state);
        return switch (r2) {
          Success<E, A>(:final value, :final consumed) => Partial<E, A>.eager(
            value,
            originalErrors,
            consumed,
          ),
          Partial<E, A>(:final value, :final errorThunk, :final consumed) =>
            Partial<E, A>(
              value,
              () => [...originalErrors, ...errorThunk()],
              consumed,
            ),
          Failure<E, A>(:final errorThunk, :final furthest) => Failure<E, A>(
            () => [...originalErrors, ...errorThunk()],
            r.furthest.offset > furthest.offset ? r.furthest : furthest,
          ),
        };

      case Expect(:final parser, :final message):
        final r = interpretI(parser, state);
        if (r case final Failure<ParseError, dynamic> f) {
          return Failure<E, A>(
            () => [CustomError(message, f.furthest) as E],
            f.furthest,
          );
        }
        return r as Result<E, A>;

      case Named(:final parser, :final name):
        final r = interpretI(parser, state);
        if (r case final Failure<ParseError, dynamic> f) {
          return Failure<E, A>(
            () =>
                f.errorThunk().map((ParseError e) {
                  if (e is Unexpected) {
                    return Unexpected(e.found, {
                          ...e.expected,
                          name,
                        }, e.location)
                        as E;
                  }
                  return e as E;
                }).toList(),
            f.furthest,
          );
        }
        return r as Result<E, A>;

      case Trace<E, A>(:final parser, :final label):
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
        print('[DEBUG] $label: trying at offset ${state.offset}');
        final r = interpretI<E, A>(parser, state);
        switch (r) {
          case Success(:final value):
            print('[DEBUG] $label: success, parsed $value');
          case Partial(:final value, :final errors):
            print(
              '[DEBUG] $label: partial, $value with ${errors.length} errors',
            );
          case Failure(:final errors):
            print(
              '[DEBUG] $label: failed with ${errors.firstOrNull ?? "unknown"}',
            );
        }
        return r;

      case Defer<E, A>(:final thunk):
        p = thunk();
        continue;

      case Memo<E, A>(:final inner, :final key, :final enableLR):
        if (enableLR) return _interpretMemo<E, A>(inner, key, state);
        return _interpretSimpleMemo<E, A>(inner, key, state);

      default:
        throw StateError('Unreachable: unhandled ${p.runtimeType}');
    }
  }
}

// ===========================================================================
// Left-recursion (Warth seed-growth)
// ===========================================================================

Result<E, A> _interpretMemo<E, A>(
  Parser<E, A> inner,
  MemoKey<E, A> key,
  ParserState state,
) {
  final pos = state.offset;
  final startSnapshot = state.save();

  final head = state.heads[pos];
  if (head != null) {
    if (head.evalSet.contains(key.id)) {
      head.evalSet.remove(key.id);
      final result = interpretI<E, A>(inner, state);
      state.memo.put(key, pos, result, state.offset);
      return result;
    }
    if (identical(head.rule, key.id)) {
      final slot = state.memo.getRaw(key, pos);
      if (slot case MemoSlotLR(:final lr)) return lr.seed as Result<E, A>;
      if (slot case MemoSlotEntry(:final entry)) {
        state.restoreTo(entry.endPos);
        return state.memo.getResult(key, pos)!;
      }
    }
    if (head.involvedSet.contains(key.id)) {
      final slot = state.memo.getRaw(key, pos);
      if (slot case MemoSlotLR(:final lr)) return lr.seed as Result<E, A>;
      if (slot case MemoSlotEntry(:final entry)) {
        state.restoreTo(entry.endPos);
        return state.memo.getResult(key, pos)!;
      }
    }
  }

  return _evaluateMemo<E, A>(inner, key, pos, startSnapshot, state);
}

Result<E, A> _evaluateMemo<E, A>(
  Parser<E, A> inner,
  MemoKey<E, A> key,
  int pos,
  int startSnapshot,
  ParserState state,
) {
  final slot = state.memo.getRaw(key, pos);

  if (slot case MemoSlotLR(:final lr)) {
    _setupLR(key.id, lr, state);
    return lr.seed as Result<E, A>;
  }

  if (slot case MemoSlotEntry(:final entry)) {
    state.restoreTo(entry.endPos);
    return entry.result as Result<E, A>;
  }

  final lr = LR(seed: Failure<E, A>.eager([], state.location), rule: key.id);
  state.lrStack.add(lr);
  state.memo.putLR(key, pos, lr);

  final result = interpretI<E, A>(inner, state);
  final endPos = state.offset;
  state.lrStack.removeLast();

  if (lr.head == null || !identical(lr.head!.rule, key.id)) {
    state.memo.put(key, pos, result, endPos);
    return result;
  }

  if (result is Failure<E, A>) {
    state.memo.put(key, pos, result, endPos);
    return result;
  }

  lr.seed = result;
  return _growLR<E, A>(inner, key, startSnapshot, lr, endPos, state);
}

void _setupLR(Object key, LR lr, ParserState state) {
  final existingHead =
      state.lrStack
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

Result<E, A> _growLR<E, A>(
  Parser<E, A> inner,
  MemoKey<E, A> key,
  int startSnapshot,
  LR lr,
  int seedEndPos,
  ParserState state,
) {
  final pos = startSnapshot;
  state.heads[pos] = lr.head!;

  var lastResult = lr.seed as Result<E, A>;
  var lastPos = seedEndPos;

  while (true) {
    state.restore(startSnapshot);
    state.memo.put(key, pos, lastResult, lastPos);
    lr.head!.evalSet = {...lr.head!.involvedSet};

    final result = interpretI<E, A>(inner, state);
    final resultPos = state.offset;

    if (result is Failure || resultPos <= lastPos) break;

    lastResult = result;
    lastPos = resultPos;
    lr.seed = result;
  }

  state.heads.remove(pos);
  state.restoreTo(lastPos);
  state.memo.put(key, pos, lastResult, lastPos);
  return lastResult;
}

// ===========================================================================
// Simple memoization
// ===========================================================================

Result<E, A> _interpretSimpleMemo<E, A>(
  Parser<E, A> inner,
  MemoKey<E, A> key,
  ParserState state,
) {
  final pos = state.offset;
  final entry = state.simpleCache.getEntry(key, pos);

  if (entry != null) {
    state.restoreTo(entry.endPos);
    return entry.result as Result<E, A>;
  }

  final result = interpretI<E, A>(inner, state);
  state.simpleCache.put(key, pos, result, state.offset);
  return result;
}

// ===========================================================================
// Specialized helpers
// ===========================================================================

Result<E, List<A>> _interpretMany<E, A>(Parser<E, A> p, ParserState state) {
  final acc = <A>[];
  final errThunks = <List<E> Function()>[];
  var totalConsumed = 0;
  final simple = p.isSimple;

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
        if (errThunks.isEmpty) return Success<E, List<A>>(acc, totalConsumed);
        return Partial<E, List<A>>(
          acc,
          () => errThunks.expand((t) => t()).toList(),
          totalConsumed,
        );
    }
  }
}

Result<E, List<A>> _interpretMany1<E, A>(Parser<E, A> p, ParserState state) {
  final first = interpretI<E, A>(p, state);
  return switch (first) {
    Success<E, A>(:final value, :final consumed) => () {
      final rest = _interpretMany<E, A>(p, state);
      return switch (rest) {
        Success<E, List<A>>(value: final tail, consumed: final c2) =>
          Success<E, List<A>>([value, ...tail], consumed + c2),
        Partial<E, List<A>>(
          value: final tail,
          :final errorThunk,
          consumed: final c2,
        ) =>
          Partial<E, List<A>>([value, ...tail], errorThunk, consumed + c2),
        Failure<E, List<A>>() => rest,
      };
    }(),
    Partial<E, A>(:final value, errorThunk: final mk1, :final consumed) => () {
      final rest = _interpretMany<E, A>(p, state);
      return switch (rest) {
        Success<E, List<A>>(value: final tail, consumed: final c2) =>
          Partial<E, List<A>>([value, ...tail], mk1, consumed + c2),
        Partial<E, List<A>>(
          value: final tail,
          errorThunk: final mk2,
          consumed: final c2,
        ) =>
          Partial<E, List<A>>(
            [value, ...tail],
            () => [...mk1(), ...mk2()],
            consumed + c2,
          ),
        Failure<E, List<A>>(errorThunk: final mk2, :final furthest) =>
          Failure<E, List<A>>(() => [...mk1(), ...mk2()], furthest),
      };
    }(),
    Failure<E, A>(:final errorThunk, :final furthest) => Failure<E, List<A>>(
      errorThunk,
      furthest,
    ),
  };
}

Result<E, void> _interpretSkipMany<E, A>(Parser<E, A> p, ParserState state) {
  final errThunks = <List<E> Function()>[];
  var totalConsumed = 0;
  final simple = p.isSimple;

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
        if (errThunks.isEmpty) return Success<E, void>(null, totalConsumed);
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

Result<E, A> _interpretStringChoice<E, A>(
  RadixNode radix,
  List<String> targets,
  ParserState state,
) {
  final input = state.input;
  final offset = state.offset;
  final matched = radix.matchAtOrNull(input, offset);

  if (matched != null) {
    state.advanceByString(matched);
    return Success<E, A>(matched as A, matched.length);
  }

  final loc = state.location;
  final maxLen = targets.fold(0, (m, t) => math.max(m, t.length));
  final found = input.substring(
    offset,
    math.min(offset + maxLen, input.length),
  );
  final expected = targets.map((s) => '"$s"').toSet();
  return Failure<E, A>(() => [Unexpected(found, expected, loc) as E], loc);
}

// ===========================================================================
// Fused Capture(Many) / Capture(Many1) — skip list allocation
// ===========================================================================

Result<E, String> _interpretCaptureMany<E, A>(
  Parser<E, A> p,
  ParserState state, {
  required bool required,
}) {
  final startOff = state.offset;
  final errThunks = <List<E> Function()>[];
  var totalConsumed = 0;
  final simple = p.isSimple;

  while (true) {
    final snapshot = simple ? 0 : state.save();
    final result = interpretI<E, A>(p, state);
    switch (result) {
      case Success<E, A>(:final consumed):
        totalConsumed += consumed;
      case Partial<E, A>(:final errorThunk, :final consumed):
        errThunks.add(errorThunk);
        totalConsumed += consumed;
      case Failure<E, A>():
        if (!simple) state.restore(snapshot);
        if (required && totalConsumed == 0) {
          return Failure<E, String>(result.errorThunk, result.furthest);
        }
        final captured = state.slice(startOff, startOff + totalConsumed);
        if (errThunks.isEmpty) {
          return Success<E, String>(captured, totalConsumed);
        }
        return Partial<E, String>(
          captured,
          () => errThunks.expand((t) => t()).toList(),
          totalConsumed,
        );
    }
  }
}

// ===========================================================================
// Fused Satisfy scan fast paths
// ===========================================================================

/// Capture(Many(Satisfy)) / Capture(Many1(Satisfy)) → direct string scan.
Result<E, A> _scanMany<E, A>(
  bool Function(String) pred,
  String expected,
  ParserState state, {
  required bool required,
}) {
  final start = state.offset;
  while (state.hasChar && pred(state.currentChar)) {
    state.advance();
  }
  final consumed = state.offset - start;
  if (required && consumed == 0) {
    final loc = state.location;
    if (state.hasChar) {
      final actual = state.currentChar;
      return Failure<E, A>(
        () => [
          Unexpected(actual, {expected}, loc) as E,
        ],
        loc,
      );
    }
    return Failure<E, A>(() => [EndOfInput(expected, loc) as E], loc);
  }
  return Success<E, A>(state.slice(start, state.offset) as A, consumed);
}

/// Many(Satisfy) → collect chars without per-character interpretI dispatch.
Result<E, A> _collectMany<E, A>(bool Function(String) pred, ParserState state) {
  final acc = <String>[];
  var totalConsumed = 0;
  while (state.hasChar && pred(state.currentChar)) {
    acc.add(state.currentChar);
    state.advance();
    totalConsumed++;
  }
  return Success<E, A>(acc as A, totalConsumed);
}

/// Many1(Satisfy) → collect chars, require at least one.
Result<E, A> _collectMany1<E, A>(
  bool Function(String) pred,
  String expected,
  ParserState state,
) {
  if (!state.hasChar || !pred(state.currentChar)) {
    final loc = state.location;
    if (state.hasChar) {
      final actual = state.currentChar;
      return Failure<E, A>(
        () => [
          Unexpected(actual, {expected}, loc) as E,
        ],
        loc,
      );
    }
    return Failure<E, A>(() => [EndOfInput(expected, loc) as E], loc);
  }
  final acc = <String>[state.currentChar];
  state.advance();
  var totalConsumed = 1;
  while (state.hasChar && pred(state.currentChar)) {
    acc.add(state.currentChar);
    state.advance();
    totalConsumed++;
  }
  return Success<E, A>(acc as A, totalConsumed);
}

/// In-place string comparison without substring allocation.
bool _regionMatches(String input, int offset, String target) {
  for (var i = 0; i < target.length; i++) {
    if (input.codeUnitAt(offset + i) != target.codeUnitAt(i)) return false;
  }
  return true;
}
