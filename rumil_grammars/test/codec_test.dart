import 'package:rumil_grammars/rumil_grammars.dart';
import 'package:test/test.dart';

Grammar _grammar() => const Grammar(
  name: 'roundtrip',
  word: 'identifier',
  rules: {
    'source_file': Rule('source_file', ZeroOrMore(Ref('declaration'))),
    'declaration': Rule(
      'declaration',
      Prec.dynamic_(
        2,
        Seq([
          Field('head', Ref('identifier')),
          Prec.right(1, Choice([Lit('a'), Optional(Lit('b'))])),
          Alias(Ref('identifier'), 'ref', named: true),
          TokenWrap(Seq([Lit('0x'), Ref('digit')])),
          OneOrMore(Ref('digit')),
          Ref('_ws'),
          Ref('block_comment'),
        ]),
      ),
    ),
    'identifier': Rule.token('identifier', Pattern(r'[a-zA-Z_]\w*')),
    'digit': Rule('digit', Pattern(r'\d')),
    '_ws': Rule.hidden('_ws', Pattern(r'\s+')),
  },
  extras: [Pattern(r'\s'), Ref('_ws')],
  externals: ['block_comment'],
  conflicts: [
    ['source_file', 'declaration'],
  ],
);

void main() {
  test('IR to JSON to IR preserves the grammar', () {
    final original = _grammar();
    final restored = grammarFromJson(grammarToJson(original));
    expect(restored.name, original.name);
    expect(restored.elem, isA<CharElem>());
    expect(restored.word, original.word);
    expect(restored.externals, original.externals);
    expect(restored.conflicts, original.conflicts);
    expect(restored.extras, original.extras);
    expect(restored.rules.keys, original.rules.keys);
    for (final name in original.rules.keys) {
      expect(restored.rules[name], original.rules[name], reason: name);
    }
  });

  test('the restored grammar emits identical tree-sitter JSON', () {
    final original = _grammar();
    final restored = grammarFromJson(grammarToJson(original));
    expect(emitGrammarJson(restored), emitGrammarJson(original));
  });

  test('the token element descriptor survives the round-trip', () {
    const original = Grammar(
      name: 'tokenized',
      elem: TokenElem('_token'),
      rules: {'source_file': Rule('source_file', Lit('x'))},
    );
    final restored = grammarFromJson(grammarToJson(original));
    expect(restored.elem, const TokenElem('_token'));
  });

  test('rejects a malformed IR document', () {
    expect(
      () => grammarFromJson(const {
        'name': 'x',
        'elem': 'char',
        'rules': {
          'start': {
            'body': {'kind': 'wat'},
            'kind': 'named',
          },
        },
        'extras': [],
        'externals': [],
        'conflicts': [],
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
