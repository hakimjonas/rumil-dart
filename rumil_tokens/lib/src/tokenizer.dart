/// Lossless tokenizer built on Rumil combinators.
library;

import 'package:rumil/rumil.dart';

import 'grammar.dart';
import 'spanned.dart';
import 'token.dart';

/// Tokenize [source] according to [grammar].
///
/// Returns a lossless token stream: concatenating every token's [Token.text]
/// reproduces [source] exactly.
///
/// Equivalent to `tokenizeSpans(source, grammar).map((s) => s.token).toList()`.
/// Callers that need byte offsets should use [tokenizeSpans] directly.
List<Token> tokenize(String source, LangGrammar grammar) =>
    tokenizeSpans(source, grammar).map((s) => s.token).toList();

/// Tokenize [source] into [Spanned] tokens carrying byte offsets.
///
/// The returned list satisfies:
///
/// - Lossless: `spans.map((s) => s.token.text).join() == source`.
/// - Anchored: `spans.first.start == 0` and `spans.last.end == source.length`
///   unless [source] is empty, in which case the list is empty.
/// - Contiguous: `spans[i].end == spans[i+1].start` for every adjacent pair.
/// - Text matches span: `source.substring(s.start, s.end) == s.token.text`.
///
/// On parser failure the whole source is returned as a single `Spanned<Plain>`
/// covering `[0, source.length)`.
List<Spanned<Token>> tokenizeSpans(String source, LangGrammar grammar) {
  if (source.isEmpty) return const [];
  final parser = _buildSpannedTokenizer(grammar);
  final result = parser.run(source);
  final spans = switch (result) {
    Success<ParseError, List<Spanned<Token>>>(:final value) => value,
    Partial<ParseError, List<Spanned<Token>>>(:final value) => value,
    Failure<ParseError, List<Spanned<Token>>>() => <Spanned<Token>>[
      Spanned<Token>.of(Plain(source), 0, source.length),
    ],
  };
  return _mergePlainSpans(spans);
}

Parser<ParseError, List<Spanned<Token>>> _buildSpannedTokenizer(
  LangGrammar grammar,
) {
  final choice = Choice<ParseError, Token>(_alternatives(grammar));
  final spanned = position<ParseError>()
      .zip(choice)
      .zip(position<ParseError>())
      .map<Spanned<Token>>((nested) {
        final ((start, token), end) = nested;
        return Spanned<Token>.of(token, start, end);
      });
  return spanned.many.thenSkip(eof());
}

List<Parser<ParseError, Token>> _alternatives(LangGrammar grammar) {
  final alternatives = <Parser<ParseError, Token>>[];

  if (grammar.blockComment case (final open, final close)) {
    alternatives.add(_blockComment(open, close));
  }
  if (grammar.lineComment case final prefix?) {
    alternatives.add(_lineComment(prefix));
  }

  if (grammar.rawStringPrefix case final prefix?) {
    for (final delim in grammar.multiLineStringDelimiters) {
      alternatives.add(_rawMultiLineString(prefix, delim));
    }
    for (final delim in grammar.stringDelimiters) {
      alternatives.add(_rawStringLiteral(prefix, delim));
    }
  }

  if (grammar.identifierStringPrefix) {
    for (final delim in grammar.multiLineStringDelimiters) {
      alternatives.add(_prefixedMultiLineString(delim));
    }
    for (final delim in grammar.stringDelimiters) {
      alternatives.add(_prefixedStringLiteral(delim));
    }
  }

  for (final delim in grammar.multiLineStringDelimiters) {
    alternatives.add(_multiLineString(delim));
  }
  for (final delim in grammar.stringDelimiters) {
    alternatives.add(_stringLiteral(delim));
  }

  alternatives.add(_number(grammar.operatorChars));

  if (grammar.annotationPrefix case final prefix?) {
    alternatives.add(_annotation(prefix, grammar.identifiersAllowDollar));
  }

  if (grammar.backtickIdentifiers) {
    alternatives.add(_backtickIdentifier());
  }

  if (grammar.heredocs) {
    alternatives.add(_heredoc());
  }

  if (grammar.shellVariables) {
    alternatives.add(_shellVariableBraced());
    alternatives.add(_shellVariableBare());
  }

  if (grammar.backtickCommandSubstitution) {
    alternatives.add(char('`').map((c) => Punctuation(c) as Token));
  }

  alternatives.add(
    _identifierOrKeyword(
      grammar.keywords,
      grammar.types,
      grammar.identifiersAllowDollar,
    ),
  );

  if (grammar.multiCharOperators.isNotEmpty) {
    alternatives.add(_multiCharOperator(grammar.multiCharOperators));
  }

  if (grammar.operatorChars.isNotEmpty) {
    alternatives.add(_operator(grammar.operatorChars));
  }

  if (grammar.punctuationChars.isNotEmpty) {
    alternatives.add(_punctuation(grammar.punctuationChars));
  }

  alternatives.add(_whitespace());
  alternatives.add(anyChar().map(Plain.new));

  return alternatives;
}

Parser<ParseError, Token> _lineComment(String prefix) => string(prefix)
    .skipThen(satisfy((c) => c != '\n', 'comment char').many.capture)
    .map((body) => Comment('$prefix$body') as Token);

Parser<ParseError, Token> _blockComment(String open, String close) {
  final closeFirst = close[0];
  final body = (string(close).notFollowedBy.skipThen(anyChar())).many.capture;
  return string(open)
      .skipThen(body)
      .thenSkip(string(close))
      .map((body) => Comment('$open$body$close') as Token)
      .or(
        string(open)
            .skipThen(satisfy((c) => c != closeFirst, 'any char').many.capture)
            .map((body) => Comment('$open$body') as Token),
      );
}

Parser<ParseError, Token> _multiLineString(String delim) {
  final body = (string(delim).notFollowedBy.skipThen(anyChar())).many.capture;
  return string(delim)
      .skipThen(body)
      .thenSkip(string(delim))
      .map((body) => StringLit('$delim$body$delim') as Token)
      .or(
        string(delim)
            .skipThen(anyChar().many.capture)
            .map((body) => StringLit('$delim$body') as Token),
      );
}

Parser<ParseError, Token> _stringLiteral(String delim) {
  final escaped = string('\\').skipThen(anyChar()).capture;
  final normal = satisfy((c) => c != delim && c != '\\' && c != '\n', 'char');
  final body = (escaped | normal.capture).many.map((parts) => parts.join());
  return char(delim).skipThen(body).zip(char(delim).capture.optional).map((
    pair,
  ) {
    final (body, close) = pair;
    return StringLit('$delim$body${close ?? ''}') as Token;
  });
}

/// Raw string literal (`r'no\escape'`). Escapes are captured verbatim;
/// the body runs until the matching delimiter or end-of-line.
Parser<ParseError, Token> _rawStringLiteral(String prefix, String delim) {
  final normal = satisfy((c) => c != delim && c != '\n', 'raw-string char');
  final body = normal.many.capture;
  return string(prefix)
      .skipThen(char(delim))
      .skipThen(body)
      .zip(char(delim).capture.optional)
      .map((pair) {
        final (body, close) = pair;
        return StringLit('$prefix$delim$body${close ?? ''}') as Token;
      });
}

/// Raw multi-line string literal (`r'''no\escape'''`). Body runs until
/// the matching triple delimiter; a missing close is tolerated.
Parser<ParseError, Token> _rawMultiLineString(String prefix, String delim) {
  final body = (string(delim).notFollowedBy.skipThen(anyChar())).many.capture;
  return string(prefix)
      .skipThen(string(delim))
      .skipThen(body)
      .thenSkip(string(delim))
      .map((body) => StringLit('$prefix$delim$body$delim') as Token)
      .or(
        string(prefix)
            .skipThen(string(delim))
            .skipThen(anyChar().many.capture)
            .map((body) => StringLit('$prefix$delim$body') as Token),
      );
}

/// Identifier-prefixed string literal (`s"hi $x"`). Escapes are respected
/// like a regular string literal.
Parser<ParseError, Token> _prefixedStringLiteral(String delim) {
  final prefix = satisfy((c) => _isAlpha(c) || c == '_', 'interpolator prefix')
      .zip(
        satisfy(
          (c) => _isAlpha(c) || _isDigit(c) || c == '_',
          'ident char',
        ).many,
      )
      .map((pair) => pair.$1 + pair.$2.join());
  final escaped = string('\\').skipThen(anyChar()).capture;
  final normal = satisfy((c) => c != delim && c != '\\' && c != '\n', 'char');
  final body = (escaped | normal.capture).many.map((parts) => parts.join());
  return prefix
      .zip(char(delim))
      .zip(body)
      .zip(char(delim).capture.optional)
      .map((nested) {
        final (((p, d), b), close) = nested;
        return StringLit('$p$d$b${close ?? ''}') as Token;
      });
}

/// Identifier-prefixed multi-line string literal (`s"""hi $x"""`).
Parser<ParseError, Token> _prefixedMultiLineString(String delim) {
  final prefix = satisfy((c) => _isAlpha(c) || c == '_', 'interpolator prefix')
      .zip(
        satisfy(
          (c) => _isAlpha(c) || _isDigit(c) || c == '_',
          'ident char',
        ).many,
      )
      .map((pair) => pair.$1 + pair.$2.join());
  final body = (string(delim).notFollowedBy.skipThen(anyChar())).many.capture;
  return prefix
      .zip(string(delim))
      .zip(body)
      .thenSkip(string(delim))
      .map((nested) {
        final ((p, d), b) = nested;
        return StringLit('$p$d$b$d') as Token;
      })
      .or(
        prefix.zip(string(delim)).zip(anyChar().many.capture).map((nested) {
          final ((p, d), b) = nested;
          return StringLit('$p$d$b') as Token;
        }),
      );
}

/// Backtick-delimited identifier (`` `type` ``). Keywords inside
/// backticks are identifiers. Body runs until the matching backtick.
Parser<ParseError, Token> _backtickIdentifier() {
  final normal = satisfy((c) => c != '`' && c != '\n', 'backtick-ident char');
  final body = normal.many.capture;
  return char('`').skipThen(body).zip(char('`').capture.optional).map((pair) {
    final (body, close) = pair;
    return Identifier('`$body${close ?? ''}') as Token;
  });
}

/// Bare shell variable (`$NAME`, `$1`, `$@`, `$#`, `$?`, `$$`, `$!`).
///
/// Matches `$` followed by an identifier name, a single digit, or a
/// special positional parameter character. A lone `$` emits `$` as
/// [Variable] so the follower tokenizes normally.
Parser<ParseError, Token> _shellVariableBare() {
  final name = satisfy((c) => _isAlpha(c) || c == '_', 'variable name start')
      .zip(
        satisfy(
          (c) => _isAlpha(c) || _isDigit(c) || c == '_',
          'ident char',
        ).many,
      )
      .map((pair) => pair.$1 + pair.$2.join());
  final special = satisfy(
    (c) =>
        _isDigit(c) ||
        c == '@' ||
        c == '#' ||
        c == '?' ||
        c == r'$' ||
        c == '!' ||
        c == '*' ||
        c == '-',
    'special parameter',
  );
  final body = name | special.capture | succeed<ParseError, String>('');
  return char(
    r'$',
  ).skipThen(body).map((name) => Variable(r'$' + name) as Token);
}

/// Shell heredoc (`<<EOF\nbody\nEOF`, `<<-EOF\nbody\n\tEOF`,
/// `<<'EOF'\nbody\nEOF`).
///
/// The entire construct is emitted as one [StringLit] token.
///
/// Limitations:
/// - Only `<<` and `<<-` (tab-strip) are recognized. `<<~` and `<<<` are not.
/// - Marker may be bare, single-quoted, or double-quoted. The body is
///   an opaque string regardless; variable expansion is not tokenized.
/// - If the terminator is never found, the body runs to end-of-input.
Parser<ParseError, Token> _heredoc() {
  final introducer = string('<<-') | string('<<');
  final quotedMarker = char("'")
      .skipThen(
        satisfy((c) => c != "'" && c != '\n', 'marker char').many.capture,
      )
      .thenSkip(char("'"))
      .map((m) => ("'$m'", m));
  final dquotedMarker = char('"')
      .skipThen(
        satisfy((c) => c != '"' && c != '\n', 'marker char').many.capture,
      )
      .thenSkip(char('"'))
      .map((m) => ('"$m"', m));
  final bareMarker = satisfy((c) => _isAlpha(c) || c == '_', 'marker start')
      .zip(
        satisfy(
          (c) => _isAlpha(c) || _isDigit(c) || c == '_',
          'marker char',
        ).many,
      )
      .map((p) => (p.$1 + p.$2.join(), p.$1 + p.$2.join()));
  final marker = quotedMarker | dquotedMarker | bareMarker;

  return introducer.zip(marker).flatMap((pair) {
    final (intro, markerPair) = pair;
    final (markerText, markerName) = markerPair;
    final restOfLine = satisfy((c) => c != '\n', 'heredoc rest').many.capture;
    final newline = char('\n');
    final tabs = satisfy((c) => c == '\t', 'tab').many.capture;
    final eolOrEof = newline.capture | succeed<ParseError, String>('');
    final stripLeadingTabs = intro == '<<-';
    // Word-boundary lookahead: `EOF` terminates, `EOFISH` does not.
    final markerEnd =
        satisfy(
          (c) => c != '\n' && (_isAlpha(c) || _isDigit(c) || c == '_'),
          'ident continuation',
        ).notFollowedBy;
    final terminatorLine = (stripLeadingTabs
            ? tabs
            : succeed<ParseError, String>(''))
        .zip(string(markerName))
        .thenSkip(markerEnd)
        .zip(eolOrEof)
        .map((nested) {
          final ((leading, mark), trailing) = nested;
          return '$leading$mark$trailing';
        });
    final bodyChar = terminatorLine.notFollowedBy.skipThen(anyChar());
    final body = bodyChar.many.capture;
    final full = restOfLine.thenSkip(newline).zip(body).zip(terminatorLine).map(
      (nested) {
        final ((rest, bodyText), term) = nested;
        return StringLit('$intro$markerText$rest\n$bodyText$term') as Token;
      },
    );
    final untilEof = restOfLine
        .thenSkip(newline.optional)
        .zip(anyChar().many.capture)
        .map((pair) {
          final (rest, bodyText) = pair;
          return StringLit('$intro$markerText$rest\n$bodyText') as Token;
        });
    return full | untilEof;
  });
}

/// Braced shell variable (`${NAME}`, `${#NAME}`, `${NAME:-default}`,
/// `${NAME//pat/repl}`). Body runs until the matching close brace.
///
/// Nested braces are not balanced: the first `}` at the top level
/// closes the expansion.
Parser<ParseError, Token> _shellVariableBraced() {
  final body =
      satisfy((c) => c != '}' && c != '\n', 'expansion body').many.capture;
  return string(r'${').skipThen(body).zip(char('}').capture.optional).map((
    pair,
  ) {
    final (body, close) = pair;
    return Variable('\${$body${close ?? ''}') as Token;
  });
}

Parser<ParseError, Token> _number(String operatorChars) {
  final hexLit =
      string('0x').skipThen(satisfy(_isHexDigit, 'hex digit').many1).capture;
  final binLit = string('0b').skipThen(oneOf('01').many1).capture;

  final digits = satisfy(_isDigit, 'digit').many1.capture;
  // Digit-lookahead gate so `x.length` doesn't read `.l` as a decimal.
  final decimalPart =
      char(
        '.',
      ).thenSkip(satisfy(_isDigit, 'digit').lookAhead).skipThen(digits).capture;
  final exponent =
      oneOf('eE').skipThen(oneOf('+-').optional).zip(digits).capture;
  final suffix = oneOf('lLfFdD').capture.optional;

  final decLit =
      digits
          .zip(decimalPart.optional)
          .zip(exponent.optional)
          .zip(suffix)
          .capture;

  // When `-` is an operator character the operator parser handles it;
  // otherwise (JSON) we accept an optional leading `-` as part of the number.
  final signed =
      operatorChars.contains('-')
          ? (hexLit | binLit | decLit)
          : char('-').capture.optional
              .zip(hexLit | binLit | decLit)
              .map((pair) => (pair.$1 ?? '') + pair.$2);

  return signed.map(NumberLit.new as Token Function(String));
}

Parser<ParseError, Token> _annotation(String prefix, bool allowDollar) =>
    string(prefix)
        .skipThen(_identRaw(allowDollar))
        .map((id) => Annotation('$prefix$id') as Token);

Parser<ParseError, Token> _identifierOrKeyword(
  List<String> keywords,
  List<String> types,
  bool allowDollar,
) {
  final keywordSet = {...keywords};
  final typeSet = {...types};
  return _identRaw(allowDollar).map((id) {
    if (keywordSet.contains(id)) return Keyword(id) as Token;
    if (typeSet.contains(id)) return TypeName(id) as Token;
    return Identifier(id) as Token;
  });
}

Parser<ParseError, String> _identRaw(bool allowDollar) {
  bool isStart(String c) =>
      _isAlpha(c) || c == '_' || (allowDollar && c == r'$');
  bool isCont(String c) => isStart(c) || _isDigit(c);
  return satisfy(isStart, 'identifier start')
      .zip(satisfy(isCont, 'identifier char').many)
      .map((pair) => pair.$1 + pair.$2.join());
}

Parser<ParseError, Token> _punctuation(String chars) => satisfy(
  (c) => chars.contains(c),
  'punctuation',
).map((c) => Punctuation(c) as Token);

/// Single-character operator parser. Emits one character per token.
/// Multi-character operators must be declared in
/// [LangGrammar.multiCharOperators].
Parser<ParseError, Token> _operator(String chars) => satisfy(
  (c) => chars.contains(c),
  'operator',
).map((c) => Operator(c) as Token);

/// Multi-character operator parser. Matches candidates longest-first.
Parser<ParseError, Token> _multiCharOperator(List<String> ops) {
  final sorted = [...ops]..sort((a, b) => b.length.compareTo(a.length));
  var parser = string(sorted.first);
  for (final op in sorted.skip(1)) {
    parser = parser.or(string(op));
  }
  return parser.map((s) => Operator(s) as Token);
}

Parser<ParseError, Token> _whitespace() =>
    satisfy(_isWhitespace, 'whitespace').many1.capture.map(Whitespace.new);

/// Merges consecutive [Plain]-spanned entries. The merged span inherits
/// the first entry's `start` and the last entry's `end`.
List<Spanned<Token>> _mergePlainSpans(List<Spanned<Token>> spans) {
  if (spans.length < 2) return spans;
  final out = <Spanned<Token>>[];
  for (final cur in spans) {
    if (cur.token is Plain && out.isNotEmpty && out.last.token is Plain) {
      final prev = out.last;
      final merged = Plain(prev.token.text + cur.token.text);
      out[out.length - 1] = Spanned<Token>.of(merged, prev.start, cur.end);
    } else {
      out.add(cur);
    }
  }
  return out;
}

bool _isDigit(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;

bool _isHexDigit(String c) =>
    _isDigit(c) ||
    (c.compareTo('a') >= 0 && c.compareTo('f') <= 0) ||
    (c.compareTo('A') >= 0 && c.compareTo('F') <= 0);

bool _isAlpha(String c) =>
    (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
    (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0);

bool _isWhitespace(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';
