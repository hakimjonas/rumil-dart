# rumil_grammars

A declarative grammar IR for the rumil family, plus a tree-sitter code
generator. Grammars are plain data: nothing in this package parses
input or executes parser combinators. Lowerings read the data and emit
their own formats.

The tree-sitter lowering produces `grammar.json`, which the
`tree-sitter generate` CLI turns into a structural parser. That parser
is an editor backend (syntax highlighting, folding, outline) for Zed,
Neovim, Helix, and similar consumers. It never checks, elaborates, or
formats source code, and it does not replace a language's authoritative
parser.

## The IR

`Grammar` holds the whole-document shape: the grammar's name, its
element type (`Elem`: character input today, token streams reserved
for the future combinator lowering), the rule table, and the
grammar-level declarations tree-sitter needs (`word`, `extras`,
`externals`, `conflicts`).

`Expr` is the right-hand-side algebra: `Ref`, `Lit`, `Pattern`, `Seq`,
`Choice`, `ZeroOrMore`, `OneOrMore`, `Optional`, `Prec` (with the
`prec.left`, `prec.right`, and `prec.dynamic` kinds), `Field`, `Alias`,
and `TokenWrap`. `Rule` carries a `RuleKind` (`named`, `hidden`, or
`token`) that decides how the rule appears in the concrete syntax
tree; hidden rules must start with `_`.

```dart
final grammar = Grammar(
  name: 'mini',
  rules: {
    'source_file': Rule('source_file', ZeroOrMore(Ref('declaration'))),
    'declaration': Rule(
      'declaration',
      Seq([Field('name', Ref('identifier')), Lit('=')]),
    ),
    'identifier': Rule.token('identifier', Pattern(r'[a-zA-Z_]\w*')),
  },
  extras: [Pattern(r'\s')],
);
validate(grammar);
print(emitGrammarJson(grammar));
```

## The generator CLI

The CLI reads an IR document (JSON produced by `grammarToJson`) and
writes `grammar.json` into a target directory. The grammar is
validated before emission; a failing grammar exits non-zero and lists
every problem.

```sh
dart run bin/rumil_grammars.dart --input tool/grammar/mini.ir.json --out tree-sitter-mini/
```

## Validation

`validate` checks, before emission:

- every `Ref` resolves to a declared rule or an external token,
- external tokens are declared exactly once and do not collide with
  rules,
- hidden rules carry the `_` prefix and precedence levels are
  non-negative,
- conflict entries name at least two declared rules, and the `word`
  declaration resolves,
- the element type is one a lowering supports.

## Status

Version 0.1.0. The package is independent until its API stabilises.
The combinator lowering (IR to a rumil parser pipeline) is not
implemented; token-stream grammars are accepted by the IR and rejected
by the emitter until it lands.
