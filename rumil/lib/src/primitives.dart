/// Primitive parser constructors.
library;

import 'errors.dart';
import 'memo.dart';
import 'parser.dart';
import 'radix.dart';

/// Always succeeds with [value], consuming no input.
Parser<E, A> succeed<E, A>(A value) => Succeed<E, A>(value);

/// Always fails with [error], consuming no input.
Parser<E, A> failure<E, A>(E error) => Fail<E, A>(error);

/// Parses a specific single character.
Parser<ParseError, String> char(String c) => Satisfy((ch) => ch == c, "'$c'");

/// Parses a character satisfying [pred].
Parser<ParseError, String> satisfy(
  bool Function(String) pred,
  String expected,
) => Satisfy(pred, expected);

/// Parses any single character.
Parser<ParseError, String> anyChar() => satisfy((_) => true, 'any character');

/// Parses any character from [chars].
Parser<ParseError, String> oneOf(String chars) =>
    satisfy((c) => chars.contains(c), "one of '$chars'");

/// Parses any character NOT in [chars].
Parser<ParseError, String> noneOf(String chars) =>
    satisfy((c) => !chars.contains(c), "none of '$chars'");

/// Parses a single digit (0-9).
Parser<ParseError, String> digit() =>
    satisfy((c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0, 'digit');

/// Parses a single letter (a-z, A-Z).
Parser<ParseError, String> letter() => satisfy(
  (c) =>
      (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
      (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0),
  'letter',
);

/// Parses a single alphanumeric character.
Parser<ParseError, String> alphaNum() => satisfy(
  (c) =>
      (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
      (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
      (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0),
  'alphanumeric',
);

/// Parses a single whitespace character.
Parser<ParseError, String> whitespace() => satisfy(
  (c) => c == ' ' || c == '\t' || c == '\n' || c == '\r',
  'whitespace',
);

/// Parses zero or more whitespace characters.
Parser<ParseError, List<String>> spaces() =>
    Many<ParseError, String>(whitespace());

/// Parses one or more whitespace characters.
Parser<ParseError, List<String>> spaces1() =>
    Many1<ParseError, String>(whitespace());

/// Parses an exact string.
Parser<ParseError, String> string(String s) =>
    s.isEmpty ? const Succeed<ParseError, String>('') : StringMatch(s);

/// Parses one of several strings using O(m) radix tree matching.
Parser<ParseError, String> stringIn(List<String> strings) {
  if (strings.isEmpty) {
    throw ArgumentError('stringIn requires at least one string');
  }
  if (strings.length == 1) return StringMatch(strings.first);
  final radix = RadixNode.fromStrings(strings);
  return StringChoice(radix, strings);
}

/// Parses a keyword and maps it to a value using O(m) radix tree matching.
Parser<ParseError, A> keywords<A>(Map<String, A> mappings) {
  if (mappings.isEmpty) {
    throw ArgumentError('keywords requires at least one mapping');
  }
  final targets = mappings.keys.toList();
  final radix = RadixNode.fromStrings(targets);
  return Mapped<ParseError, String, A>(
    StringChoice(radix, targets),
    (matched) => mappings[matched] as A,
  );
}

/// Wraps [parser] to consume trailing whitespace.
///
/// Every atom in a grammar should consume its own trailing whitespace
/// (either via [lexeme] or a manual whitespace parser). If an atom
/// doesn't, downstream combinators like `chainl1` will fail to match
/// the operator between terms.
Parser<ParseError, A> lexeme<A>(Parser<ParseError, A> parser) =>
    Mapped<ParseError, (A, List<String>), A>(
      Zip<ParseError, A, List<String>>(parser, spaces()),
      ((A, List<String>) pair) => pair.$1,
    );

/// Parses [s] then consumes trailing whitespace.
Parser<ParseError, String> symbol(String s) => lexeme(string(s));

/// Matches end of input.
Parser<ParseError, void> eof() => const Eof<ParseError>();

/// Succeeds without consuming input, yielding the current byte offset.
///
/// Combines with [Zip] to capture spans around a parser:
///
/// ```dart
/// final spanned = position<E>().zip(myParser).zip(position<E>());
/// // produces (((int startOffset, A value), int endOffset))
/// ```
///
/// The offset is 0-indexed. Use [Location] (via `Location(input, offset)`)
/// when converting to line/column.
Parser<E, int> position<E>() => GetPosition<E>();

/// Defers parser construction for recursive grammars.
Parser<E, A> defer<E, A>(Parser<E, A> Function() thunk) => Defer<E, A>(thunk);

/// Creates a left-recursion-enabled memoized parser (Warth seed-growth).
///
/// Left-recursive rules like `expr -> expr '+' term | term` work
/// without grammar transformation.
///
/// Place `rule()` at the level where left recursion occurs (e.g.
/// chained postfix operations). For binary operator precedence, use
/// `chainl1` instead and make the rule the operand of the lowest
/// `chainl1` layer.
Parser<E, A> rule<E, A>(Parser<E, A> Function() thunk) =>
    Memo<E, A>(Defer<E, A>(thunk), MemoKey<E, A>(), enableLR: true);
