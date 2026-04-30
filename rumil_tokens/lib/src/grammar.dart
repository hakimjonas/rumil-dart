/// Language grammar definitions for the tokenizer.
library;

/// Describes a language's lexical structure.
///
/// Grammars are plain data. The tokenizer reads a grammar and builds
/// the combinator pipeline.
class LangGrammar {
  /// Language identifier (e.g. `'dart'`, `'scala'`).
  final String name;

  /// Reserved keywords (e.g. `['if', 'else', 'class']`).
  final List<String> keywords;

  /// Built-in or well-known type names (e.g. `['int', 'String']`).
  final List<String> types;

  /// Line comment prefix (e.g. `'//'`), or `null` if unsupported.
  final String? lineComment;

  /// Block comment delimiters `(open, close)`, or `null`.
  final (String, String)? blockComment;

  /// String delimiters to recognize (e.g. `['"', "'"]`).
  final List<String> stringDelimiters;

  /// Multi-line string delimiters (e.g. `['"""', "'''"]`).
  final List<String> multiLineStringDelimiters;

  /// Annotation prefix (e.g. `'@'` for Dart/Java), or `null`.
  final String? annotationPrefix;

  /// Structural punctuation: delimiters, separators, grouping characters.
  ///
  /// Typical contents: `()`, `{}`, `[]`, `,`, `;`, `:`, `.`. Distinct from
  /// [operatorChars], which is reserved for value-computing operators
  /// (`+`, `*`, `==`).
  final String punctuationChars;

  /// Multi-character operator vocabulary, matched before single-char
  /// operators or punctuation.
  ///
  /// Order within the list is irrelevant; the tokenizer matches in
  /// longest-first order. Each entry is matched as a literal string.
  ///
  /// Dart example: `['=>', '<=', '>=', '==', '!=', '&&', '||', '??',
  /// '?.', '<<', '>>', '~/']`. Scala adds `'<-'`, `'->'`, `'::'`.
  ///
  /// Matched operators emit one [Operator] token including the full
  /// multi-char text.
  final List<String> multiCharOperators;

  /// Single-character operator alphabet.
  ///
  /// Typical contents: `+`, `-`, `*`, `/`, `%`, `=`, `&`, `|`, `^`, `~`,
  /// `!`. Characters here emit one [Operator] token each; runs do not
  /// coalesce. Multi-character operators must be listed explicitly in
  /// [multiCharOperators].
  ///
  /// When empty (e.g. JSON), no operator classification happens.
  /// Overlaps with [punctuationChars] are resolved in favor of operators.
  final String operatorChars;

  /// Whether identifiers may contain `$`.
  ///
  /// Dart allows `$` in identifiers; most other languages do not. When
  /// `false`, `$` is free to carry language-specific meaning such as a
  /// shell variable prefix.
  final bool identifiersAllowDollar;

  /// Raw-string prefix (Dart's `'r'` for `r'no\escape'`), or `null`.
  ///
  /// When set, the tokenizer recognizes the single-character prefix
  /// immediately followed by any [stringDelimiters] or
  /// [multiLineStringDelimiters] as one [StringLit] whose text includes
  /// the prefix. Escape sequences inside raw strings are not processed;
  /// the body is captured verbatim up to the matching delimiter.
  final String? rawStringPrefix;

  /// Whether an identifier immediately followed by a string delimiter
  /// forms a string with that identifier as a prefix.
  ///
  /// Scala's string interpolators (`s"hi $x"`, `f"$x%.2f"`, any
  /// user-defined `foo"..."`) follow this pattern. When `true`, the
  /// tokenizer treats `<ident>"..."` as one [StringLit] whose text
  /// includes the identifier prefix.
  final bool identifierStringPrefix;

  /// Whether backtick-delimited identifiers are allowed (`` `type` ``).
  ///
  /// Scala uses this to escape keywords. When `true`, the tokenizer
  /// recognizes `` `...` `` as one [Identifier] even when the bracketed
  /// content would otherwise be a keyword.
  final bool backtickIdentifiers;

  /// Whether `$` introduces a variable reference (shell-style).
  ///
  /// When `true`, the tokenizer recognizes:
  /// - `$NAME`: one [Variable] token including the `$`.
  /// - `${NAME}` and `${...}` expansions: one [Variable] token, including
  ///   braces and body up to the matching close brace.
  /// - Bare `$` not followed by a name or `{` falls through.
  final bool shellVariables;

  /// Whether backtick-delimited command substitution is recognized
  /// (`` `cmd` ``).
  ///
  /// When `true`, the tokenizer emits [Punctuation] for each backtick;
  /// the body between them is tokenized as ordinary source.
  final bool backtickCommandSubstitution;

  /// Whether `<<` followed by a marker introduces a heredoc.
  ///
  /// Shell heredocs (`<<EOF`, `<<-EOF`, `<<'EOF'`) capture their body
  /// up to a line equal to the marker. The body is emitted as one
  /// [StringLit] token.
  final bool heredocs;

  /// Creates a language grammar.
  const LangGrammar({
    required this.name,
    this.keywords = const [],
    this.types = const [],
    this.lineComment,
    this.blockComment,
    this.stringDelimiters = const ['"', "'"],
    this.multiLineStringDelimiters = const [],
    this.annotationPrefix,
    this.punctuationChars = '(){}[];:,.',
    this.operatorChars = '',
    this.multiCharOperators = const [],
    this.identifiersAllowDollar = false,
    this.rawStringPrefix,
    this.identifierStringPrefix = false,
    this.backtickIdentifiers = false,
    this.shellVariables = false,
    this.backtickCommandSubstitution = false,
    this.heredocs = false,
  });
}
