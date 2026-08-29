import 'package:rumil_grammars/rumil_grammars.dart';
import 'package:test/test.dart';

Grammar _grammar({
  Elem elem = const CharElem(),
  Map<String, Rule> rules = const {},
  String? word,
  List<Expr> extras = const [],
  List<String> externals = const [],
  List<List<String>> conflicts = const [],
}) => Grammar(
  name: 'test',
  elem: elem,
  rules: rules,
  word: word,
  extras: extras,
  externals: externals,
  conflicts: conflicts,
);

void main() {
  group('validate', () {
    test('accepts a well-formed grammar', () {
      final grammar = _grammar(
        rules: {
          'source': const Rule(
            'source',
            ZeroOrMore(Choice([Ref('identifier'), Ref('_comment')])),
          ),
          'identifier': const Rule.token(
            'identifier',
            Pattern(r'[a-zA-Z_]\w*'),
          ),
          '_comment': const Rule.hidden(
            '_comment',
            Seq([Lit('#'), Lit('note')]),
          ),
        },
        word: 'identifier',
        extras: [const Pattern(r'\s')],
        externals: ['block_comment'],
        conflicts: const [
          ['source', 'identifier'],
        ],
      );
      expect(() => validate(grammar), returnsNormally);
    });

    test('rejects unresolved references', () {
      final grammar = _grammar(
        rules: {'source': const Rule('source', Ref('missing'))},
      );
      expect(
        () => validate(grammar),
        throwsA(
          isA<GrammarValidationError>().having(
            (e) => e.problems.join('\n'),
            'problems',
            contains('"missing"'),
          ),
        ),
      );
    });

    test('resolves references to external tokens', () {
      final grammar = _grammar(
        rules: {'source': const Rule('source', Ref('eof'))},
        externals: ['eof'],
      );
      expect(() => validate(grammar), returnsNormally);
    });

    test('rejects duplicate external declarations', () {
      final grammar = _grammar(
        rules: {'source': const Rule('source', Ref('eof'))},
        externals: ['eof', 'eof'],
      );
      expect(
        () => validate(grammar),
        throwsA(
          isA<GrammarValidationError>().having(
            (e) => e.problems.join('\n'),
            'problems',
            contains('declared 2 times'),
          ),
        ),
      );
    });

    test('rejects negative precedence levels', () {
      final grammar = _grammar(
        rules: {'expr': const Rule('expr', Prec(-1, Lit('a')))},
      );
      expect(() => validate(grammar), throwsA(isA<GrammarValidationError>()));
    });

    test('requires hidden rules to start with an underscore', () {
      final grammar = _grammar(
        rules: {
          'source': const Rule('source', Ref('_helper')),
          '_helper': const Rule.hidden('_helper', Lit('a')),
        },
      );
      expect(() => validate(grammar), returnsNormally);

      const misnamed = Grammar(
        name: 'test',
        rules: {
          'source': Rule('source', Ref('helper')),
          'helper': Rule.hidden('helper', Lit('a')),
        },
      );
      expect(
        () => validate(misnamed),
        throwsA(
          isA<GrammarValidationError>().having(
            (e) => e.problems.join('\n'),
            'problems',
            contains('hidden rule "helper" must start with "_"'),
          ),
        ),
      );
    });

    test('rejects token-stream element types', () {
      final grammar = _grammar(
        elem: const TokenElem('_token'),
        rules: {'source': const Rule('source', Lit('a'))},
      );
      expect(
        () => validate(grammar),
        throwsA(
          isA<GrammarValidationError>().having(
            (e) => e.problems.join('\n'),
            'problems',
            contains('token-stream'),
          ),
        ),
      );
    });

    test('rejects a word token that does not resolve', () {
      final grammar = _grammar(
        rules: {'source': const Rule('source', Lit('a'))},
        word: 'identifier',
      );
      expect(
        () => validate(grammar),
        throwsA(
          isA<GrammarValidationError>().having(
            (e) => e.problems.join('\n'),
            'problems',
            contains('word token "identifier"'),
          ),
        ),
      );
    });

    test('rejects conflicts that reference undeclared rules', () {
      final grammar = _grammar(
        rules: {'source': const Rule('source', Lit('a'))},
        conflicts: const [
          ['source', 'expr'],
        ],
      );
      expect(
        () => validate(grammar),
        throwsA(
          isA<GrammarValidationError>().having(
            (e) => e.problems.join('\n'),
            'problems',
            contains('"expr", which is not a declared rule'),
          ),
        ),
      );
    });
  });

  group('equality', () {
    test('structural equality holds across identical IRs', () {
      const a = Seq([Lit('a'), Optional(Ref('b'))]);
      const b = Seq([Lit('a'), Optional(Ref('b'))]);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });
}
