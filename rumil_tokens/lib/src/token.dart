/// Token types produced by the tokenizer.
library;

/// A classified span of source text.
///
/// Tokens are lossless: concatenating [text] from a token stream
/// reconstructs the original source exactly.
sealed class Token {
  /// The source text this token covers.
  final String text;

  /// Creates a token covering [text].
  const Token(this.text);
}

/// A language keyword (`if`, `class`, `val`, etc.).
final class Keyword extends Token {
  /// Creates a keyword token.
  const Keyword(super.text);

  @override
  String toString() => 'Keyword($text)';
}

/// A built-in or well-known type name (`int`, `String`, `List`, etc.).
final class TypeName extends Token {
  /// Creates a type-name token.
  const TypeName(super.text);

  @override
  String toString() => 'TypeName($text)';
}

/// A string literal, including delimiters.
final class StringLit extends Token {
  /// Creates a string-literal token.
  const StringLit(super.text);

  @override
  String toString() => 'StringLit($text)';
}

/// A numeric literal (integer, float, hex, etc.).
final class NumberLit extends Token {
  /// Creates a number-literal token.
  const NumberLit(super.text);

  @override
  String toString() => 'NumberLit($text)';
}

/// A comment (line or block), including delimiters.
final class Comment extends Token {
  /// Creates a comment token.
  const Comment(super.text);

  @override
  String toString() => 'Comment($text)';
}

/// Structural punctuation: `(`, `)`, `{`, `}`, `[`, `]`, `,`, `;`, `:`, `.`.
///
/// Delimits, separates, or groups. Distinct from [Operator], which is
/// reserved for value-computing operators.
final class Punctuation extends Token {
  /// Creates a punctuation token.
  const Punctuation(super.text);

  @override
  String toString() => 'Punctuation($text)';
}

/// A value-computing operator: `+`, `*`, `==`, `&&`, `=>`, `->`.
///
/// Distinct from [Punctuation].
final class Operator extends Token {
  /// Creates an operator token.
  const Operator(super.text);

  @override
  String toString() => 'Operator($text)';
}

/// A variable reference: shell `$HOME`, `${PATH}`.
///
/// The token text includes the leading `$` and braces if present.
final class Variable extends Token {
  /// Creates a variable token.
  const Variable(super.text);

  @override
  String toString() => 'Variable($text)';
}

/// An identifier that is not a keyword or type name.
final class Identifier extends Token {
  /// Creates an identifier token.
  const Identifier(super.text);

  @override
  String toString() => 'Identifier($text)';
}

/// An annotation or decorator (`@override`, `#[derive]`, etc.).
final class Annotation extends Token {
  /// Creates an annotation token.
  const Annotation(super.text);

  @override
  String toString() => 'Annotation($text)';
}

/// Whitespace (spaces, tabs, newlines).
final class Whitespace extends Token {
  /// Creates a whitespace token.
  const Whitespace(super.text);

  @override
  String toString() => 'Whitespace(${text.length})';
}

/// Any text not matched by a language-specific rule.
final class Plain extends Token {
  /// Creates a plain-text token.
  const Plain(super.text);

  @override
  String toString() => 'Plain($text)';
}
