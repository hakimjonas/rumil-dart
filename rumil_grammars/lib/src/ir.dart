/// The grammar IR: plain data describing a context-free grammar.
///
/// The IR has two layers. [Grammar] is the whole-document object: its
/// name, element type, rule table, and the grammar-level declarations
/// tree-sitter needs (extras, externals, conflicts, word token).
/// [Expr] is the right-hand-side algebra: sequences, choices,
/// repetition, precedence annotations, fields, aliases, and terminals.
///
/// Both layers are immutable and constructor-valid: no method on any
/// IR class mutates state or executes input. The [validate] pass in
/// `validate.dart` checks cross-references before emission.
library;

// ---------------------------------------------------------------------------
// Element type
// ---------------------------------------------------------------------------

/// The element type a grammar consumes, one entry per input alphabet.
///
/// Mirrors the invariant-element discipline of the rumil core: a
/// grammar is defined against an abstract element type, and the
/// lowering decides what those elements are. [CharElem] is the only
/// kind a lowering supports today; [TokenElem] declares that the
/// grammar is written against a token stream and is accepted by the
/// IR (and rejected by the tree-sitter emitter) until the combinator
/// lowering lands.
sealed class Elem {
  /// Base constructor.
  const Elem();
}

/// Character-level input: terminals are literal strings and character
/// patterns over the source text.
final class CharElem extends Elem {
  /// The single character-level element.
  static const CharElem instance = CharElem();

  /// Creates the character element descriptor.
  const CharElem();

  @override
  bool operator ==(Object other) => other is CharElem;

  @override
  int get hashCode => 'CharElem'.hashCode;

  @override
  String toString() => 'CharElem()';
}

/// Token-stream input: terminals name tokens produced by a tokenizer,
/// not characters of the source text.
final class TokenElem extends Elem {
  /// The name of the rule that produces one token element.
  final String tokenRule;

  /// Creates a token-stream element descriptor.
  const TokenElem(this.tokenRule);

  @override
  bool operator ==(Object other) =>
      other is TokenElem && other.tokenRule == tokenRule;

  @override
  int get hashCode => Object.hash('TokenElem', tokenRule);

  @override
  String toString() => 'TokenElem($tokenRule)';
}

// ---------------------------------------------------------------------------
// Expressions (rule right-hand sides)
// ---------------------------------------------------------------------------

/// A rule right-hand side.
sealed class Expr {
  /// Base constructor.
  const Expr();
}

/// A reference to a named rule or an external token.
final class Ref extends Expr {
  /// The referenced name.
  final String name;

  /// Creates a reference.
  const Ref(this.name);

  @override
  bool operator ==(Object other) => other is Ref && other.name == name;

  @override
  int get hashCode => Object.hash('Ref', name);

  @override
  String toString() => 'Ref($name)';
}

/// A literal string terminal, matched exactly.
final class Lit extends Expr {
  /// The literal text.
  final String value;

  /// Creates a literal terminal.
  const Lit(this.value);

  @override
  bool operator ==(Object other) => other is Lit && other.value == value;

  @override
  int get hashCode => Object.hash('Lit', value);

  @override
  String toString() => 'Lit(${jsonEscape(value)})';

  /// Minimal JSON-style escaping for readable toString output.
  static String jsonEscape(String value) => value
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\t', r'\t');
}

/// A character-pattern terminal, a single-element regular expression
/// over the grammar's elements.
final class Pattern extends Expr {
  /// The pattern text, in the syntax the target lowering accepts.
  final String value;

  /// Per-character flags (tree-sitter accepts `i` for case
  /// insensitivity), or null.
  final String? flags;

  /// Creates a pattern terminal.
  const Pattern(this.value, {this.flags});

  @override
  bool operator ==(Object other) =>
      other is Pattern && other.value == value && other.flags == flags;

  @override
  int get hashCode => Object.hash('Pattern', value, flags);

  @override
  String toString() => 'Pattern(${Lit.jsonEscape(value)})';
}

/// An ordered sequence.
final class Seq extends Expr {
  /// The elements, matched in order.
  final List<Expr> elements;

  /// Creates a sequence.
  const Seq(this.elements);

  @override
  bool operator ==(Object other) =>
      other is Seq && _listEquals(other.elements, elements);

  @override
  int get hashCode => Object.hash('Seq', Object.hashAll(elements));

  @override
  String toString() => 'Seq($elements)';
}

/// A choice among alternatives.
final class Choice extends Expr {
  /// The alternatives, tried in order.
  final List<Expr> members;

  /// Creates a choice.
  const Choice(this.members);

  @override
  bool operator ==(Object other) =>
      other is Choice && _listEquals(other.members, members);

  @override
  int get hashCode => Object.hash('Choice', Object.hashAll(members));

  @override
  String toString() => 'Choice($members)';
}

/// Zero or more repetitions.
final class ZeroOrMore extends Expr {
  /// The repeated expression.
  final Expr content;

  /// Creates a repetition.
  const ZeroOrMore(this.content);

  @override
  bool operator ==(Object other) =>
      other is ZeroOrMore && other.content == content;

  @override
  int get hashCode => Object.hash('ZeroOrMore', content);

  @override
  String toString() => 'ZeroOrMore($content)';
}

/// One or more repetitions.
final class OneOrMore extends Expr {
  /// The repeated expression.
  final Expr content;

  /// Creates a repetition.
  const OneOrMore(this.content);

  @override
  bool operator ==(Object other) =>
      other is OneOrMore && other.content == content;

  @override
  int get hashCode => Object.hash('OneOrMore', content);

  @override
  String toString() => 'OneOrMore($content)';
}

/// An optional element.
final class Optional extends Expr {
  /// The optional expression.
  final Expr content;

  /// Creates an optional.
  const Optional(this.content);

  @override
  bool operator ==(Object other) =>
      other is Optional && other.content == content;

  @override
  int get hashCode => Object.hash('Optional', content);

  @override
  String toString() => 'Optional($content)';
}

/// A precedence annotation wrapping [content].
///
/// [kind] selects the tree-sitter lowering: [PrecKind.prec] for a
/// static precedence on an expression or rule, [PrecKind.precLeft] and
/// [PrecKind.precRight] for left- and right-associative rules, and
/// [PrecKind.precDynamic] for run-time precedence resolution under GLR.
final class Prec extends Expr {
  /// The precedence level; non-negative.
  final int value;

  /// The annotated expression.
  final Expr content;

  /// The annotation kind.
  final PrecKind kind;

  /// Creates a precedence annotation of [kind].
  const Prec._(this.kind, this.value, this.content);

  /// Static `prec`.
  const Prec(int value, Expr content) : this._(PrecKind.prec, value, content);

  /// Left-associative `prec.left`.
  const Prec.left(int value, Expr content)
    : this._(PrecKind.precLeft, value, content);

  /// Right-associative `prec.right`.
  const Prec.right(int value, Expr content)
    : this._(PrecKind.precRight, value, content);

  /// Dynamic `prec.dynamic`.
  const Prec.dynamic_(int value, Expr content)
    : this._(PrecKind.precDynamic, value, content);

  @override
  bool operator ==(Object other) =>
      other is Prec &&
      other.kind == kind &&
      other.value == value &&
      other.content == content;

  @override
  int get hashCode => Object.hash('Prec', kind, value, content);

  @override
  String toString() => 'Prec($kind, $value, $content)';
}

/// The precedence annotation kinds.
enum PrecKind {
  /// Static precedence.
  prec,

  /// Left-associative rule precedence.
  precLeft,

  /// Right-associative rule precedence.
  precRight,

  /// Dynamic (run-time) precedence.
  precDynamic,
}

/// A named field wrapping [content].
final class Field extends Expr {
  /// The field name.
  final String name;

  /// The field's expression.
  final Expr content;

  /// Creates a field.
  const Field(this.name, this.content);

  @override
  bool operator ==(Object other) =>
      other is Field && other.name == name && other.content == content;

  @override
  int get hashCode => Object.hash('Field', name, content);

  @override
  String toString() => 'Field($name, $content)';
}

/// An alias renaming [content] in the concrete syntax tree.
final class Alias extends Expr {
  /// The aliased expression.
  final Expr content;

  /// The alias value.
  final String value;

  /// Whether the alias is a named node (true) or an anonymous token
  /// (false).
  final bool named;

  /// Creates an alias.
  const Alias(this.content, this.value, {this.named = true});

  @override
  bool operator ==(Object other) =>
      other is Alias &&
      other.content == content &&
      other.value == value &&
      other.named == named;

  @override
  int get hashCode => Object.hash('Alias', content, value, named);

  @override
  String toString() => 'Alias($content, $value, named: $named)';
}

/// A `token(...)` wrapping: the content is lexed as one terminal.
final class TokenWrap extends Expr {
  /// The token's expression.
  final Expr content;

  /// Creates a token wrapping.
  const TokenWrap(this.content);

  @override
  bool operator ==(Object other) =>
      other is TokenWrap && other.content == content;

  @override
  int get hashCode => Object.hash('TokenWrap', content);

  @override
  String toString() => 'TokenWrap($content)';
}

// ---------------------------------------------------------------------------
// Rules and grammar
// ---------------------------------------------------------------------------

/// How a rule appears in the concrete syntax tree.
enum RuleKind {
  /// A named node (tree-sitter: a plain rule, visible in the CST).
  named,

  /// A hidden node (tree-sitter: an underscore rule, spliced out of
  /// the CST). The rule name must start with `_`.
  hidden,

  /// A terminal defined by a rule body (tree-sitter: a rule used only
  /// through `token(...)` wrapping at its use sites, or declared as an
  /// external). Rendered as its own rule entry with TOKEN wrapping
  /// when [Rule.isTokenRule] is set at definition time.
  token,
}

/// A named rule: [name] mapped to a body [Expr].
final class Rule {
  /// The rule name.
  final String name;

  /// The rule body.
  final Expr body;

  /// The rule kind (named, hidden, or token).
  final RuleKind kind;

  /// Creates a rule of [kind].
  const Rule(this.name, this.body, {this.kind = RuleKind.named});

  /// Creates a hidden rule; [name] must start with `_`.
  const Rule.hidden(this.name, this.body) : kind = RuleKind.hidden;

  /// Creates a token rule: the body lexes as one terminal.
  const Rule.token(this.name, this.body) : kind = RuleKind.token;

  @override
  bool operator ==(Object other) =>
      other is Rule &&
      other.name == name &&
      other.body == body &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash('Rule', name, body, kind);

  @override
  String toString() => 'Rule($name, $kind)';
}

/// A declarative grammar: the whole-document IR object.
///
/// [elem] is the grammar's element type ([CharElem] today, [TokenElem]
/// declared for the future combinator lowering). The maps and lists
/// are caller-owned; pass unmodifiable collections if the grammar must
/// be frozen.
final class Grammar {
  /// The grammar name (e.g. `'doxa'`), used as the parser name.
  final String name;

  /// The element type the grammar consumes.
  final Elem elem;

  /// The rules, in declaration order. The first rule is the start
  /// rule, matching tree-sitter's convention.
  final Map<String, Rule> rules;

  /// The `word` token declaration: the rule tree-sitter uses to
  /// identify keyword boundaries during error recovery, or null.
  final String? word;

  /// Trivia accepted between any two tokens (whitespace, comments).
  final List<Expr> extras;

  /// External tokens produced by a scanner callback, referenced by
  /// name in rule bodies. Order matters: tree-sitter indexes externals
  /// by position.
  final List<String> externals;

  /// GLR ambiguity declarations. Each entry names two or more rules
  /// that may parse the same input; tree-sitter explores all parses
  /// and prunes by precedence.
  final List<List<String>> conflicts;

  /// Creates a grammar.
  const Grammar({
    required this.name,
    this.elem = CharElem.instance,
    required this.rules,
    this.word,
    this.extras = const [],
    this.externals = const [],
    this.conflicts = const [],
  });
}

bool _listEquals(List<Expr> a, List<Expr> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
