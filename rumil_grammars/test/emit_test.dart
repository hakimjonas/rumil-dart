import 'dart:convert';

import 'package:rumil_grammars/rumil_grammars.dart';
import 'package:test/test.dart';

/// A small hand-checked grammar covering every IR construct.
Grammar _fullGrammar() => const Grammar(
  name: 'sample',
  word: 'identifier',
  rules: {
    'source_file': Rule('source_file', ZeroOrMore(Ref('declaration'))),
    'declaration': Rule(
      'declaration',
      Prec.left(
        1,
        Seq([
          Field('name', Ref('identifier')),
          Optional(Field('value', Ref('expression'))),
        ]),
      ),
    ),
    'expression': Rule(
      'expression',
      Choice([
        Ref('identifier'),
        Alias(Lit('+'), 'plus', named: false),
        TokenWrap(Pattern(r'0x[0-9a-f]+')),
        OneOrMore(Ref('digit')),
        Ref('_punct'),
      ]),
    ),
    'identifier': Rule.token('identifier', Pattern(r'[a-zA-Z_]\w*')),
    'digit': Rule('digit', Pattern(r'\d')),
    '_punct': Rule.hidden('_punct', Choice([Lit(','), Lit(';')])),
  },
  extras: [Pattern(r'\s')],
  externals: ['block_comment'],
  conflicts: [
    ['declaration', 'expression'],
  ],
);

void main() {
  group('emitGrammarJson', () {
    test('emits the expected document for the full grammar', () {
      final output = emitGrammarJson(_fullGrammar());
      expect(output, equals(_expectedFullGrammarJson));
    });

    test('is deterministic', () {
      expect(emitGrammarJson(_fullGrammar()), emitGrammarJson(_fullGrammar()));
    });

    test('emits valid JSON that round-trips through jsonDecode', () {
      final decoded = jsonDecode(emitGrammarJson(_fullGrammar()));
      expect(decoded, isA<Map<String, dynamic>>());
    });

    test('omits optional declarations when absent', () {
      const grammar = Grammar(
        name: 'minimal',
        rules: {'start': Rule('start', Lit('x'))},
      );
      final output = emitGrammarJson(grammar);
      expect(output, isNot(contains('"word"')));
      expect(output, isNot(contains('"externals"')));
      expect(output, isNot(contains('"conflicts"')));
      // An explicit empty extras list means no trivia at all; it is
      // emitted verbatim because tree-sitter's default (when extras is
      // omitted) is whitespace, which is not what an empty declaration
      // asks for.
      expect(output, contains('"extras": []'));
    });

    test('wraps token rules in TOKEN', () {
      const grammar = Grammar(
        name: 'tokened',
        rules: {
          'start': Rule('start', Ref('word')),
          'word': Rule.token('word', Lit('hello')),
        },
      );
      final output = emitGrammarJson(grammar);
      expect(output, contains('"TOKEN"'));
    });
  });
}

const String _expectedFullGrammarJson = '''
{
  "name": "sample",
  "word": "identifier",
  "rules": {
    "source_file": {
      "type": "REPEAT",
      "content": {
        "type": "SYMBOL",
        "name": "declaration"
      }
    },
    "declaration": {
      "type": "PREC_LEFT",
      "value": 1,
      "content": {
        "type": "SEQ",
        "members": [
          {
            "type": "FIELD",
            "name": "name",
            "content": {
              "type": "SYMBOL",
              "name": "identifier"
            }
          },
          {
            "type": "CHOICE",
            "members": [
              {
                "type": "FIELD",
                "name": "value",
                "content": {
                  "type": "SYMBOL",
                  "name": "expression"
                }
              },
              {
                "type": "BLANK"
              }
            ]
          }
        ]
      }
    },
    "expression": {
      "type": "CHOICE",
      "members": [
        {
          "type": "SYMBOL",
          "name": "identifier"
        },
        {
          "type": "ALIAS",
          "content": {
            "type": "STRING",
            "value": "+"
          },
          "value": "plus",
          "named": false
        },
        {
          "type": "TOKEN",
          "content": {
            "type": "PATTERN",
            "value": "0x[0-9a-f]+"
          }
        },
        {
          "type": "REPEAT1",
          "content": {
            "type": "SYMBOL",
            "name": "digit"
          }
        },
        {
          "type": "SYMBOL",
          "name": "_punct"
        }
      ]
    },
    "identifier": {
      "type": "TOKEN",
      "content": {
        "type": "PATTERN",
        "value": "[a-zA-Z_]\\\\w*"
      }
    },
    "digit": {
      "type": "PATTERN",
      "value": "\\\\d"
    },
    "_punct": {
      "type": "CHOICE",
      "members": [
        {
          "type": "STRING",
          "value": ","
        },
        {
          "type": "STRING",
          "value": ";"
        }
      ]
    }
  },
  "extras": [
    {
      "type": "PATTERN",
      "value": "\\\\s"
    }
  ],
  "externals": [
    {
      "type": "SYMBOL",
      "name": "block_comment"
    }
  ],
  "conflicts": [
    [
      "declaration",
      "expression"
    ]
  ]
}
''';
