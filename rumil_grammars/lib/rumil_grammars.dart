/// A declarative grammar IR for the rumil family.
///
/// Grammars are plain data, extending the `rumil_tokens` principle
/// ("grammars are plain data; the tokenizer reads a grammar and builds
/// the pipeline") to the parse layer. Nothing in this package executes
/// a grammar. Lowerings read the data and emit their own formats:
///
///  * `emitGrammarJson` produces a tree-sitter `grammar.json`, which
///    the `tree-sitter generate` CLI turns into a structural parser
///    for editors (highlighting, folding, outline). The generated
///    parser never checks, elaborates, or formats; it is a structural
///    backend only.
///  * The combinator lowering (IR to a rumil parser pipeline) is
///    reserved for a later release; `Grammar.elem` records the element
///    type that lowering will consume.
library;

export 'src/codec.dart';
export 'src/emit.dart';
export 'src/ir.dart';
export 'src/validate.dart';
