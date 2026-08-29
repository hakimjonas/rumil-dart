# Changelog

## 0.1.0

First release. A declarative grammar IR for the rumil family and a
tree-sitter code generator:

- Plain-data IR (`Grammar`, `Rule`, `Expr`) with an abstract element
  type: character-level input today, token-stream input declared but
  not yet lowered.
- Tree-sitter lowering (`emitGrammarJson`) emitting deterministic,
  commit-friendly `grammar.json` documents.
- Validation pass (`validate`) covering reference resolution, external
  declarations, hidden-rule naming, and precedence levels.
- Generator CLI reading IR JSON and writing `grammar.json`.

The combinator lowering (IR to a rumil parser pipeline) is deferred.
