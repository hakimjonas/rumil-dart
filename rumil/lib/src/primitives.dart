/// Primitive parser constructors.
///
/// These are the leaf-level building blocks from which all parsers
/// are composed via combinators and the DSL extensions.
library;

import 'errors.dart';
import 'memo.dart';
import 'parser.dart';

/// Always succeeds with [value], consuming no input.
Parser<E, A> succeed<E, A>(A value) => Succeed<E, A>(value);

/// Always fails with [error], consuming no input.
Parser<E, A> fail<E, A>(E error) => Fail<E, A>(error);

/// Parses a specific single character.
///
/// ```dart
/// char('a').run('abc') // Success('a', consumed: 1)
/// char('a').run('xyz') // Failure
/// ```
Parser<ParseError, String> char(String c) =>
    Satisfy((ch) => ch == c, "'$c'");

/// Parses a character satisfying [pred].
///
/// [expected] is used in error messages (e.g. `"digit"`, `"letter"`).
///
/// ```dart
/// satisfy((c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0, 'digit')
/// ```
Parser<ParseError, String> satisfy(
  bool Function(String) pred,
  String expected,
) =>
    Satisfy(pred, expected);

/// Parses any single character. Fails only at end of input.
Parser<ParseError, String> anyChar() =>
    satisfy((_) => true, 'any character');

/// Parses a single digit (0-9).
Parser<ParseError, String> digit() => satisfy(
      (c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0,
      'digit',
    );

/// Parses a single letter (a-z, A-Z).
Parser<ParseError, String> letter() => satisfy(
      (c) =>
          (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
          (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0),
      'letter',
    );

/// Parses an exact string.
///
/// ```dart
/// string('hello').run('hello world') // Success('hello', consumed: 5)
/// ```
Parser<ParseError, String> string(String s) =>
    s.isEmpty ? const Succeed<ParseError, String>('') : StringMatch(s);

/// Matches end of input. Fails if any input remains.
Parser<ParseError, void> eof() => const Eof<ParseError>();

/// Creates a deferred parser for recursive grammars.
///
/// Required to prevent infinite initialization in recursive definitions.
///
/// ```dart
/// late final expr = defer(() => (expr << char('+')) & term() | term());
/// ```
Parser<E, A> defer<E, A>(Parser<E, A> Function() thunk) => Defer<E, A>(thunk);

/// Creates a left-recursion-enabled memoized parser (Warth seed-growth).
///
/// This is Rumil's signature feature. Left-recursive rules like
/// `expr -> expr '+' term | term` work without grammar transformation.
///
/// ```dart
/// final expr = rule(() => (expr << char('+')) & digit() | digit());
/// expr.run('1+2+3') // Success — parsed as (1+2)+3, left-associative
/// ```
Parser<E, A> rule<E, A>(Parser<E, A> Function() thunk) =>
    Memo<E, A>(Defer<E, A>(thunk), MemoKey<E, A>(), enableLR: true);
