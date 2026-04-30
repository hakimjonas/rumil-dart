import 'package:rumil_tokens/rumil_tokens.dart';
import 'package:test/test.dart';

void _expectLossless(String source, LangGrammar grammar) {
  final tokens = tokenize(source, grammar);
  final reconstructed = tokens.map((t) => t.text).join();
  expect(reconstructed, source, reason: 'lossless round-trip');
}

List<T> _ofType<T extends Token>(List<Token> tokens) =>
    tokens.whereType<T>().toList();

List<String> _textsOf<T extends Token>(List<Token> tokens) =>
    _ofType<T>(tokens).map((t) => t.text).toList();

void main() {
  // ---------------------------------------------------------------------------
  // Lossless round-trip.
  // ---------------------------------------------------------------------------

  group('lossless round-trip', () {
    test('empty input', () {
      expect(tokenize('', dart), isEmpty);
    });

    test('single character', () {
      _expectLossless('x', dart);
    });

    test('only whitespace', () {
      _expectLossless('   \t\n  \r\n', dart);
    });

    test('Dart function', () {
      const source = '''
void main() {
  final x = 42;
  // comment
  print('hello \$x');
}
''';
      _expectLossless(source, dart);
    });

    test('Dart class with annotations', () {
      const source = '''
@immutable
class Point {
  final int x;
  final int y;
  const Point(this.x, this.y);

  @override
  String toString() => 'Point(\$x, \$y)';
}
''';
      _expectLossless(source, dart);
    });

    test('Dart multi-line strings', () {
      _expectLossless("var a = '''multi\nline''';\n", dart);
      _expectLossless('var b = """another\nmulti""";\n', dart);
    });

    test('Dart string interpolation with escapes', () {
      const source = r'''var s = "line1\nline2\t\"quoted\"\\end";''';
      _expectLossless(source, dart);
    });

    test('Dart hex and binary literals', () {
      _expectLossless('var a = 0xFF; var b = 0b1010;', dart);
    });

    test('Dart floating point', () {
      _expectLossless('var x = 3.14; var y = 1e10; var z = 2.5e-3;', dart);
    });

    test('Dart block comment', () {
      _expectLossless('x /* block\ncomment */ y', dart);
    });

    test('unterminated string', () {
      _expectLossless('var s = "unterminated', dart);
    });

    test('unterminated multi-line string', () {
      _expectLossless("var s = '''unterminated", dart);
    });

    test('unterminated block comment', () {
      _expectLossless('/* unterminated', dart);
    });

    test('Scala snippet', () {
      const source = '''
object Main:
  def run(args: List[String]): Unit =
    val x: Int = 42
    /* block comment */
    println(s"hello \$x")
''';
      _expectLossless(source, scala);
    });

    test('Scala triple-quoted string', () {
      _expectLossless('val s = """raw\nstring"""', scala);
    });

    test('YAML document', () {
      const source = '''
name: rumil
version: 0.5.0
# comment
dependencies:
  rumil: ^0.5.0
  flag: true
list:
  - one
  - two
''';
      _expectLossless(source, yaml);
    });

    test('JSON document', () {
      const source = '''
{
  "name": "rumil",
  "version": 42,
  "active": true,
  "data": null,
  "items": [1, 2, 3]
}
''';
      _expectLossless(source, json);
    });

    test('shell script', () {
      const source = '''
#!/bin/bash
# deploy script
export PORT=8080
for f in *.dart; do
  echo "building \$f"
  if [ -f "\$f" ]; then
    dart compile exe "\$f"
  fi
done
''';
      _expectLossless(source, shell);
    });

    test('consecutive comments', () {
      _expectLossless('// one\n// two\n// three\n', dart);
    });

    test('adjacent strings', () {
      _expectLossless('"a""b""c"', dart);
    });

    test('mixed content', () {
      const source = 'if (x > 0) { return "yes"; } // done';
      _expectLossless(source, dart);
    });

    test('only punctuation', () {
      _expectLossless('(){}[]<>;:,.', dart);
    });

    test('only numbers', () {
      _expectLossless('42', dart);
    });

    test('only a string', () {
      _expectLossless('"hello world"', dart);
    });

    test('only a comment', () {
      _expectLossless('// just a comment', dart);
    });

    test('unicode identifiers', () {
      _expectLossless(r'var $dollar = _under;', dart);
    });
  });

  // ---------------------------------------------------------------------------
  // Token classification.
  // ---------------------------------------------------------------------------

  group('keywords', () {
    test('Dart keywords', () {
      final tokens = tokenize('if else class final var void return', dart);
      expect(_textsOf<Keyword>(tokens), [
        'if',
        'else',
        'class',
        'final',
        'var',
        'void',
        'return',
      ]);
    });

    test('Scala keywords', () {
      final tokens = tokenize('def val object trait sealed match', scala);
      expect(_textsOf<Keyword>(tokens), [
        'def',
        'val',
        'object',
        'trait',
        'sealed',
        'match',
      ]);
    });

    test('YAML keywords', () {
      final tokens = tokenize('true false null', yaml);
      expect(_textsOf<Keyword>(tokens), ['true', 'false', 'null']);
    });

    test('JSON keywords', () {
      final tokens = tokenize('true false null', json);
      expect(_textsOf<Keyword>(tokens), ['true', 'false', 'null']);
    });

    test('shell keywords', () {
      final tokens = tokenize('if then else fi for do done', shell);
      expect(_textsOf<Keyword>(tokens), [
        'if',
        'then',
        'else',
        'fi',
        'for',
        'do',
        'done',
      ]);
    });

    test('keyword not matched inside identifier', () {
      final tokens = tokenize('classify iffy', dart);
      expect(_textsOf<Identifier>(tokens), ['classify', 'iffy']);
      expect(_ofType<Keyword>(tokens), isEmpty);
    });

    test('keyword not matched as prefix of identifier', () {
      final tokens = tokenize('ifTrue forEachItem', dart);
      expect(_textsOf<Identifier>(tokens), ['ifTrue', 'forEachItem']);
      expect(_ofType<Keyword>(tokens), isEmpty);
    });

    test('keyword followed by punctuation', () {
      final tokens = tokenize('if(x)', dart);
      expect(_textsOf<Keyword>(tokens), ['if']);
      expect(_textsOf<Identifier>(tokens), ['x']);
    });
  });

  group('type names', () {
    test('Dart types', () {
      final tokens = tokenize('int String List Map Future', dart);
      expect(_textsOf<TypeName>(tokens), [
        'int',
        'String',
        'List',
        'Map',
        'Future',
      ]);
    });

    test('Scala types', () {
      final tokens = tokenize('Int Boolean Option Either Unit', scala);
      expect(_textsOf<TypeName>(tokens), [
        'Int',
        'Boolean',
        'Option',
        'Either',
        'Unit',
      ]);
    });

    test('type not matched inside identifier', () {
      final tokens = tokenize('integer Stringify', dart);
      expect(_textsOf<Identifier>(tokens), ['integer', 'Stringify']);
      expect(_ofType<TypeName>(tokens), isEmpty);
    });
  });

  group('identifiers', () {
    test('simple identifiers', () {
      final tokens = tokenize('foo bar baz', dart);
      expect(_textsOf<Identifier>(tokens), ['foo', 'bar', 'baz']);
    });

    test('underscore identifiers', () {
      final tokens = tokenize('_private __dunder _a1', dart);
      expect(_textsOf<Identifier>(tokens), ['_private', '__dunder', '_a1']);
    });

    test('dollar identifiers', () {
      final tokens = tokenize(r'$ref $$double', dart);
      expect(_textsOf<Identifier>(tokens), [r'$ref', r'$$double']);
    });

    test('alphanumeric identifiers', () {
      final tokens = tokenize('item1 item2 a123b', dart);
      expect(_textsOf<Identifier>(tokens), ['item1', 'item2', 'a123b']);
    });
  });

  group('string literals', () {
    test('double-quoted string', () {
      final tokens = tokenize('"hello"', dart);
      expect(_textsOf<StringLit>(tokens), ['"hello"']);
    });

    test('single-quoted string', () {
      final tokens = tokenize("'world'", dart);
      expect(_textsOf<StringLit>(tokens), ["'world'"]);
    });

    test('empty string', () {
      final tokens = tokenize('""', dart);
      expect(_textsOf<StringLit>(tokens), ['""']);
    });

    test('string with escapes', () {
      final tokens = tokenize(r'"hello\nworld"', dart);
      expect(_textsOf<StringLit>(tokens), [r'"hello\nworld"']);
    });

    test('string with escaped quote', () {
      final tokens = tokenize(r'"say \"hi\""', dart);
      expect(_textsOf<StringLit>(tokens), [r'"say \"hi\""']);
    });

    test('string with escaped backslash', () {
      final tokens = tokenize(r'"path\\file"', dart);
      expect(_textsOf<StringLit>(tokens), [r'"path\\file"']);
    });

    test('multi-line string (triple single)', () {
      final tokens = tokenize("'''multi\nline'''", dart);
      expect(_textsOf<StringLit>(tokens), ["'''multi\nline'''"]);
    });

    test('multi-line string (triple double)', () {
      final tokens = tokenize('"""multi\nline"""', dart);
      expect(_textsOf<StringLit>(tokens), ['"""multi\nline"""']);
    });

    test('unterminated string stops at newline', () {
      final tokens = tokenize('"unterminated\nnext', dart);
      final strings = _textsOf<StringLit>(tokens);
      expect(strings.length, 1);
      expect(strings.first, '"unterminated');
    });

    test('adjacent strings', () {
      final tokens = tokenize('"a""b"', dart);
      expect(_textsOf<StringLit>(tokens), ['"a"', '"b"']);
    });

    test('JSON only has double-quoted strings', () {
      final tokens = tokenize('"value"', json);
      expect(_textsOf<StringLit>(tokens), ['"value"']);
    });
  });

  group('number literals', () {
    test('integer', () {
      final tokens = tokenize('42', dart);
      expect(_textsOf<NumberLit>(tokens), ['42']);
    });

    test('float', () {
      final tokens = tokenize('3.14', dart);
      expect(_textsOf<NumberLit>(tokens), ['3.14']);
    });

    test('hex literal', () {
      final tokens = tokenize('0xFF', dart);
      expect(_textsOf<NumberLit>(tokens), ['0xFF']);
    });

    test('hex lowercase', () {
      final tokens = tokenize('0xdeadbeef', dart);
      expect(_textsOf<NumberLit>(tokens), ['0xdeadbeef']);
    });

    test('binary literal', () {
      final tokens = tokenize('0b1010', dart);
      expect(_textsOf<NumberLit>(tokens), ['0b1010']);
    });

    test('scientific notation', () {
      final tokens = tokenize('1e10', dart);
      expect(_textsOf<NumberLit>(tokens), ['1e10']);
    });

    test('scientific with decimal', () {
      final tokens = tokenize('2.5e-3', dart);
      expect(_textsOf<NumberLit>(tokens), ['2.5e-3']);
    });

    test('multiple numbers', () {
      final tokens = tokenize('1 2 3', dart);
      expect(_textsOf<NumberLit>(tokens), ['1', '2', '3']);
    });

    test('number followed by punctuation', () {
      final tokens = tokenize('42;', dart);
      expect(_textsOf<NumberLit>(tokens), ['42']);
      expect(_textsOf<Punctuation>(tokens), [';']);
    });

    test('number inside expression', () {
      final tokens = tokenize('x+42', dart);
      expect(_textsOf<NumberLit>(tokens), ['42']);
    });
  });

  group('comments', () {
    test('line comment', () {
      final tokens = tokenize('x // comment\ny', dart);
      expect(_textsOf<Comment>(tokens), ['// comment']);
    });

    test('line comment at start', () {
      final tokens = tokenize('// first line', dart);
      expect(_textsOf<Comment>(tokens), ['// first line']);
    });

    test('line comment with no space', () {
      final tokens = tokenize('//compact', dart);
      expect(_textsOf<Comment>(tokens), ['//compact']);
    });

    test('empty line comment', () {
      final tokens = tokenize('//\nx', dart);
      expect(_textsOf<Comment>(tokens), ['//']);
    });

    test('block comment single line', () {
      final tokens = tokenize('/* block */', dart);
      expect(_textsOf<Comment>(tokens), ['/* block */']);
    });

    test('block comment multi-line', () {
      final tokens = tokenize('/* line1\nline2 */', dart);
      expect(_textsOf<Comment>(tokens), ['/* line1\nline2 */']);
    });

    test('block comment with stars', () {
      final tokens = tokenize('/** doc comment */', dart);
      expect(_textsOf<Comment>(tokens), ['/** doc comment */']);
    });

    test('unterminated block comment', () {
      final tokens = tokenize('/* unterminated', dart);
      expect(_textsOf<Comment>(tokens), ['/* unterminated']);
    });

    test('consecutive line comments', () {
      final tokens = tokenize('// one\n// two\n// three', dart);
      expect(_textsOf<Comment>(tokens), ['// one', '// two', '// three']);
    });

    test('hash comment (YAML)', () {
      final tokens = tokenize('key: value # comment', yaml);
      expect(_textsOf<Comment>(tokens), ['# comment']);
    });

    test('hash comment (shell)', () {
      final tokens = tokenize('echo hi # comment', shell);
      expect(_textsOf<Comment>(tokens), ['# comment']);
    });

    test('JSON has no comments', () {
      final tokens = tokenize('// not a comment', json);
      expect(_ofType<Comment>(tokens), isEmpty);
    });
  });

  group('annotations', () {
    test('Dart annotation', () {
      final tokens = tokenize('@override', dart);
      expect(_textsOf<Annotation>(tokens), ['@override']);
    });

    test('Dart annotation before declaration', () {
      final tokens = tokenize('@deprecated void f() {}', dart);
      expect(_textsOf<Annotation>(tokens), ['@deprecated']);
    });

    test('multiple annotations', () {
      final tokens = tokenize('@immutable @sealed class X {}', dart);
      expect(_textsOf<Annotation>(tokens), ['@immutable', '@sealed']);
    });

    test('Scala annotation', () {
      final tokens = tokenize('@tailrec def f(): Unit = ???', scala);
      expect(_textsOf<Annotation>(tokens), ['@tailrec']);
    });

    test('no annotations in YAML', () {
      final tokens = tokenize('@value', yaml);
      expect(_ofType<Annotation>(tokens), isEmpty);
    });

    test('no annotations in JSON', () {
      final tokens = tokenize('@value', json);
      expect(_ofType<Annotation>(tokens), isEmpty);
    });
  });

  group('punctuation', () {
    test('parentheses', () {
      final tokens = tokenize('()', dart);
      expect(_textsOf<Punctuation>(tokens), ['(', ')']);
    });

    test('braces', () {
      final tokens = tokenize('{}', dart);
      expect(_textsOf<Punctuation>(tokens), ['{', '}']);
    });

    test('brackets', () {
      final tokens = tokenize('[]', dart);
      expect(_textsOf<Punctuation>(tokens), ['[', ']']);
    });

    test('mixed punctuation', () {
      final tokens = tokenize('f(x, y);', dart);
      expect(_textsOf<Punctuation>(tokens), ['(', ',', ')', ';']);
    });

    test('operators are Operator, not Punctuation', () {
      final tokens = tokenize('a + b * c', dart);
      expect(_textsOf<Punctuation>(tokens), isEmpty);
      expect(_textsOf<Operator>(tokens), ['+', '*']);
    });

    test('JSON punctuation', () {
      final tokens = tokenize('{[]:,}', json);
      expect(_textsOf<Punctuation>(tokens), ['{', '[', ']', ':', ',', '}']);
    });

    test('YAML colon', () {
      final tokens = tokenize('key: value', yaml);
      expect(_textsOf<Punctuation>(tokens), [':']);
    });
  });

  group('whitespace', () {
    test('spaces', () {
      final tokens = tokenize('a  b', dart);
      expect(tokens[1], isA<Whitespace>());
      expect(tokens[1].text, '  ');
    });

    test('tabs', () {
      final tokens = tokenize('a\tb', dart);
      expect(tokens[1], isA<Whitespace>());
      expect(tokens[1].text, '\t');
    });

    test('newlines', () {
      final tokens = tokenize('a\nb', dart);
      expect(tokens[1], isA<Whitespace>());
      expect(tokens[1].text, '\n');
    });

    test('mixed whitespace collapsed', () {
      final tokens = tokenize('a \t\n b', dart);
      expect(tokens[1], isA<Whitespace>());
      expect(tokens[1].text, ' \t\n ');
    });

    test('only whitespace', () {
      final tokens = tokenize('   ', dart);
      expect(tokens.length, 1);
      expect(tokens.first, isA<Whitespace>());
    });
  });

  // ---------------------------------------------------------------------------
  // Language-specific integration tests
  // ---------------------------------------------------------------------------

  group('Dart integration', () {
    test('full function', () {
      const source = '''
Future<int> compute(List<String> args) async {
  final result = await fetch("url");
  if (result == null) return -1;
  // process
  return result.length;
}
''';
      _expectLossless(source, dart);
      final tokens = tokenize(source, dart);
      expect(_textsOf<Keyword>(tokens), contains('async'));
      expect(_textsOf<Keyword>(tokens), contains('await'));
      expect(_textsOf<Keyword>(tokens), contains('if'));
      expect(_textsOf<Keyword>(tokens), contains('return'));
      expect(_textsOf<TypeName>(tokens), contains('Future'));
      expect(_textsOf<TypeName>(tokens), contains('int'));
      expect(_textsOf<TypeName>(tokens), contains('List'));
      expect(_textsOf<TypeName>(tokens), contains('String'));
      expect(_textsOf<StringLit>(tokens), ['"url"']);
      expect(_textsOf<NumberLit>(tokens), ['1']);
      expect(_textsOf<Comment>(tokens), ['// process']);
    });

    test('sealed class with pattern matching', () {
      const source = '''
sealed class Shape {}
final class Circle extends Shape {
  final double radius;
  const Circle(this.radius);
}
''';
      _expectLossless(source, dart);
      final tokens = tokenize(source, dart);
      expect(_textsOf<Keyword>(tokens), contains('sealed'));
      expect(_textsOf<Keyword>(tokens), contains('extends'));
      expect(_textsOf<TypeName>(tokens), contains('double'));
    });
  });

  group('Scala integration', () {
    test('case class and match', () {
      const source = '''
case class Point(x: Int, y: Int)

val p = Point(1, 2)
val desc = p match
  case Point(0, 0) => "origin"
  case Point(x, y) => s"(\$x, \$y)"
''';
      _expectLossless(source, scala);
      final tokens = tokenize(source, scala);
      expect(_textsOf<Keyword>(tokens), contains('case'));
      expect(_textsOf<Keyword>(tokens), contains('class'));
      expect(_textsOf<Keyword>(tokens), contains('val'));
      expect(_textsOf<Keyword>(tokens), contains('match'));
      expect(_textsOf<TypeName>(tokens), contains('Int'));
    });
  });

  group('YAML integration', () {
    test('nested structure', () {
      const source = '''
server:
  host: "localhost"
  port: 8080
  debug: true
  tags:
    - web
    - api
''';
      _expectLossless(source, yaml);
      final tokens = tokenize(source, yaml);
      expect(_textsOf<StringLit>(tokens), ['"localhost"']);
      expect(_textsOf<NumberLit>(tokens), ['8080']);
      expect(_textsOf<Keyword>(tokens), contains('true'));
    });
  });

  group('JSON integration', () {
    test('nested object', () {
      const source = '{"a": 1, "b": [true, false, null], "c": "text"}';
      _expectLossless(source, json);
      final tokens = tokenize(source, json);
      expect(_textsOf<Keyword>(tokens), ['true', 'false', 'null']);
      expect(_textsOf<NumberLit>(tokens), ['1']);
      expect(_textsOf<StringLit>(tokens), ['"a"', '"b"', '"c"', '"text"']);
    });
  });

  group('shell integration', () {
    test('script with conditionals and loops', () {
      const source = '''
if [ -d "build" ]; then
  for f in build/*; do
    echo "removing \$f"
  done
fi
''';
      _expectLossless(source, shell);
      final tokens = tokenize(source, shell);
      expect(_textsOf<Keyword>(tokens), contains('if'));
      expect(_textsOf<Keyword>(tokens), contains('then'));
      expect(_textsOf<Keyword>(tokens), contains('for'));
      expect(_textsOf<Keyword>(tokens), contains('do'));
      expect(_textsOf<Keyword>(tokens), contains('done'));
      expect(_textsOf<Keyword>(tokens), contains('fi'));
    });
  });

  // ---------------------------------------------------------------------------
  // Custom grammars
  // ---------------------------------------------------------------------------

  group('custom grammar', () {
    test('minimal grammar', () {
      const minimal = LangGrammar(name: 'minimal');
      const source = 'hello 42 "world"';
      _expectLossless(source, minimal);
    });

    test('custom keywords', () {
      const custom = LangGrammar(
        name: 'custom',
        keywords: ['fn', 'let'],
        types: ['u32'],
      );
      final tokens = tokenize('fn main() { let x: u32 = 1; }', custom);
      expect(_textsOf<Keyword>(tokens), ['fn', 'let']);
      expect(_textsOf<TypeName>(tokens), ['u32']);
    });

    test('custom comment syntax', () {
      const custom = LangGrammar(
        name: 'custom',
        lineComment: '--',
        blockComment: ('{-', '-}'),
      );
      final tokens = tokenize('x -- line comment\ny {- block -} z', custom);
      expect(_textsOf<Comment>(tokens), ['-- line comment', '{- block -}']);
    });
  });

  // ---------------------------------------------------------------------------
  // grammarFor lookup
  // ---------------------------------------------------------------------------

  group('grammarFor', () {
    test('dart', () {
      expect(grammarFor('dart')?.name, 'dart');
    });

    test('scala', () {
      expect(grammarFor('scala')?.name, 'scala');
    });

    test('yaml aliases', () {
      expect(grammarFor('yaml')?.name, 'yaml');
      expect(grammarFor('yml')?.name, 'yaml');
    });

    test('json', () {
      expect(grammarFor('json')?.name, 'json');
    });

    test('shell aliases', () {
      expect(grammarFor('sh')?.name, 'shell');
      expect(grammarFor('bash')?.name, 'shell');
      expect(grammarFor('shell')?.name, 'shell');
      expect(grammarFor('zsh')?.name, 'shell');
    });

    test('unknown returns null', () {
      expect(grammarFor('brainfuck'), isNull);
      expect(grammarFor(''), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Edge cases
  // ---------------------------------------------------------------------------

  group('edge cases', () {
    test('empty input returns empty list', () {
      expect(tokenize('', dart), isEmpty);
    });

    test('single keyword', () {
      final tokens = tokenize('if', dart);
      expect(tokens.length, 1);
      expect(tokens.first, isA<Keyword>());
    });

    test('single number', () {
      final tokens = tokenize('42', dart);
      expect(tokens.length, 1);
      expect(tokens.first, isA<NumberLit>());
    });

    test('single string', () {
      final tokens = tokenize('"x"', dart);
      expect(tokens.length, 1);
      expect(tokens.first, isA<StringLit>());
    });

    test('single comment', () {
      final tokens = tokenize('// comment', dart);
      expect(tokens.length, 1);
      expect(tokens.first, isA<Comment>());
    });

    test('number then dot then identifier is not float', () {
      final tokens = tokenize('x.length', dart);
      expect(_textsOf<Identifier>(tokens), ['x', 'length']);
      expect(_textsOf<Punctuation>(tokens), ['.']);
    });

    test('annotation without following identifier is Plain', () {
      // `@` is only valid as an annotation prefix in Dart. On its own
      // It falls through to Plain.
      final tokens = tokenize('@ ', dart);
      expect(_ofType<Annotation>(tokens), isEmpty);
      expect(_textsOf<Plain>(tokens), ['@']);
    });

    test('special characters merged into single Plain token', () {
      final tokens = tokenize('\u00e9\u00e8\u00ea', dart);
      expect(tokens.length, 1);
      expect(tokens.first, isA<Plain>());
      expect(tokens.first.text, '\u00e9\u00e8\u00ea');
    });

    test('very long input', () {
      final source = 'var x = ${List.filled(1000, '42').join(' + ')};';
      _expectLossless(source, dart);
    });
  });

  // ---------------------------------------------------------------------------
  // tokenizeSpans: byte offsets into source.
  // ---------------------------------------------------------------------------

  void expectSpanInvariants(String source, LangGrammar grammar) {
    final spans = tokenizeSpans(source, grammar);
    if (source.isEmpty) {
      expect(spans, isEmpty);
      return;
    }
    // Anchored.
    expect(spans.first.start, 0, reason: 'first span starts at 0');
    expect(
      spans.last.end,
      source.length,
      reason: 'last span ends at source.length',
    );
    // Contiguous.
    for (var i = 0; i + 1 < spans.length; i++) {
      expect(
        spans[i].end,
        spans[i + 1].start,
        reason: 'spans[$i].end == spans[${i + 1}].start',
      );
    }
    // Text matches substring.
    for (final s in spans) {
      expect(
        source.substring(s.start, s.end),
        s.token.text,
        reason: 'substring matches token text at [${s.start}, ${s.end})',
      );
      expect(s.length, s.end - s.start, reason: 'length == end - start');
    }
    // Lossless (already covered by substring-matches + contiguous, but
    // explicit for readability).
    expect(
      spans.map((s) => s.token.text).join(),
      source,
      reason: 'lossless join',
    );
  }

  group('tokenizeSpans invariants', () {
    test('empty source returns empty list', () {
      expect(tokenizeSpans('', dart), isEmpty);
    });

    test('single-character source', () {
      expectSpanInvariants('x', dart);
    });

    test('Dart snippet', () {
      const source = '''
void main() {
  final x = 42;
  // greeting
  print("hello \$x");
}
''';
      expectSpanInvariants(source, dart);
    });

    test('Scala snippet', () {
      const source = '''
object Main:
  def run(args: List[String]): Unit =
    val x: Int = 42
''';
      expectSpanInvariants(source, scala);
    });

    test('YAML snippet', () {
      const source = '''
name: rumil_tokens
version: 0.6.0
# comment
''';
      expectSpanInvariants(source, yaml);
    });

    test('JSON snippet', () {
      expectSpanInvariants('{"a": 1, "b": true, "c": null}', json);
    });

    test('shell snippet', () {
      const source = '''
# deploy
for f in *.dart; do
  echo "\$f"
done
''';
      expectSpanInvariants(source, shell);
    });

    test('unterminated string preserves end-of-source anchor', () {
      expectSpanInvariants('var s = "unterminated', dart);
    });

    test('unterminated block comment preserves end-of-source anchor', () {
      expectSpanInvariants('/* unterminated', dart);
    });

    test('only whitespace', () {
      expectSpanInvariants('   \t\n  ', dart);
    });

    test('only punctuation', () {
      expectSpanInvariants('(){}[]<>;:,.', dart);
    });
  });

  group('tokenizeSpans parity with tokenize', () {
    // Token has no == / hashCode so we compare by (runtimeType, text).
    (Type, String) key(Token t) => (t.runtimeType, t.text);
    void expectParity(String source, LangGrammar grammar) {
      final tokens = tokenize(source, grammar);
      final spans = tokenizeSpans(source, grammar);
      expect(
        spans.map((s) => key(s.token)).toList(),
        tokens.map(key).toList(),
        reason: 'tokenizeSpans token sequence matches tokenize',
      );
    }

    test('Dart', () {
      expectParity('void f() { return 42; }', dart);
    });

    test('Scala', () {
      expectParity('val x: Int = 42', scala);
    });

    test('YAML', () {
      expectParity('key: "value" # c\n', yaml);
    });

    test('JSON', () {
      expectParity('[1, 2, 3]', json);
    });

    test('shell', () {
      expectParity('if [ -f "x" ]; then echo hi; fi', shell);
    });
  });

  group('tokenizeSpans span boundaries', () {
    test('keyword span covers exact characters', () {
      final spans = tokenizeSpans('if x', dart);
      expect(spans[0].token, isA<Keyword>());
      expect(spans[0].start, 0);
      expect(spans[0].end, 2);
    });

    test('whitespace span covers exact characters', () {
      final spans = tokenizeSpans('a  b', dart);
      expect(spans[1].token, isA<Whitespace>());
      expect(spans[1].start, 1);
      expect(spans[1].end, 3);
    });

    test('number span covers exact characters', () {
      final spans = tokenizeSpans('x = 42', dart);
      final number = spans.firstWhere((s) => s.token is NumberLit);
      expect(number.start, 4);
      expect(number.end, 6);
    });

    test('string span includes delimiters', () {
      final spans = tokenizeSpans('"hi"', dart);
      expect(spans.single.token, isA<StringLit>());
      expect(spans.single.start, 0);
      expect(spans.single.end, 4);
    });

    test('line comment span runs to end of line (exclusive of newline)', () {
      final spans = tokenizeSpans('// note\nx', dart);
      final comment = spans.firstWhere((s) => s.token is Comment);
      expect(comment.start, 0);
      expect(comment.end, 7);
      // Newline is a separate Whitespace token.
      expect(spans[1].token, isA<Whitespace>());
      expect(spans[1].start, 7);
    });

    test('merged Plain spans cover the full run', () {
      // Unicode chars the tokenizer doesn't classify → Plain tokens that
      // get merged. The merged span must cover the whole run.
      const source = 'éèê';
      final spans = tokenizeSpans(source, dart);
      expect(spans, hasLength(1));
      expect(spans.single.token, isA<Plain>());
      expect(spans.single.start, 0);
      expect(spans.single.end, source.length);
      expect(spans.single.token.text, source);
    });

    test('annotation span includes prefix', () {
      final spans = tokenizeSpans('@override', dart);
      expect(spans.single.token, isA<Annotation>());
      expect(spans.single.start, 0);
      expect(spans.single.end, 9);
    });
  });

  group('Spanned generics', () {
    test('Spanned<Token> exposes record fields through getters', () {
      const s = Spanned<Token>.of(Keyword('if'), 3, 5);
      expect(s.token.text, 'if');
      expect(s.start, 3);
      expect(s.end, 5);
      expect(s.length, 2);
    });

    test('narrow type parameter upcasts to Spanned<Token>', () {
      const kw = Spanned<Keyword>.of(Keyword('if'), 0, 2);
      // Covariance through the record type parameter.
      const Spanned<Token> wide = kw;
      expect(wide.token, isA<Keyword>());
      expect(wide.start, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Grammar correctness (0.6.0 Path C fixes)
  // ---------------------------------------------------------------------------

  group('Dart raw strings', () {
    test("r'...' is one StringLit including the r prefix", () {
      final tokens = tokenize("r'no\\escape'", dart);
      expect(_textsOf<StringLit>(tokens), ["r'no\\escape'"]);
      expect(_ofType<Identifier>(tokens), isEmpty);
    });

    test('r"..." is one StringLit including the r prefix', () {
      final tokens = tokenize('r"no\\escape"', dart);
      expect(_textsOf<StringLit>(tokens), ['r"no\\escape"']);
    });

    test("r'''...''' (triple-single) is one StringLit", () {
      final tokens = tokenize("r'''no\\escape'''", dart);
      expect(_textsOf<StringLit>(tokens), ["r'''no\\escape'''"]);
    });

    test('r"""..." (triple-double) is one StringLit', () {
      final tokens = tokenize('r"""no\\escape"""', dart);
      expect(_textsOf<StringLit>(tokens), ['r"""no\\escape"""']);
    });

    test('non-raw identifier r followed by space is Identifier', () {
      final tokens = tokenize("r 'x'", dart);
      expect(_textsOf<Identifier>(tokens), ['r']);
      expect(_textsOf<StringLit>(tokens), ["'x'"]);
    });
  });

  group('Scala backtick identifiers', () {
    test('`type` is one Identifier even though `type` is a keyword', () {
      final tokens = tokenize('val `type` = 1', scala);
      expect(_textsOf<Identifier>(tokens), ['`type`']);
      // `type` inside backticks must NOT appear as a separate keyword.
      expect(_textsOf<Keyword>(tokens), ['val']);
    });

    test('unterminated backtick identifier is tolerated', () {
      final tokens = tokenize('val `noclose', scala);
      expect(_textsOf<Identifier>(tokens), ['`noclose']);
    });

    test('backtick identifier with spaces', () {
      final tokens = tokenize('val `hello world` = 1', scala);
      expect(_textsOf<Identifier>(tokens), ['`hello world`']);
    });
  });

  group('Scala string interpolator prefix', () {
    test('s"..." is one StringLit including the s prefix', () {
      final tokens = tokenize(r'val s = s"hi $name"', scala);
      expect(_textsOf<StringLit>(tokens), ['s"hi \$name"']);
      // Only `s` as in `val s = ...` should be an Identifier, not the
      // interpolator prefix.
      expect(_textsOf<Identifier>(tokens), ['s']);
    });

    test('f"..." is one StringLit including the f prefix', () {
      final tokens = tokenize(r'val x = f"$v%.2f"', scala);
      expect(_textsOf<StringLit>(tokens).last, 'f"\$v%.2f"');
    });

    test('arbitrary identifier prefix (my_interp"..."):', () {
      final tokens = tokenize('val x = my_interp"body"', scala);
      expect(_textsOf<StringLit>(tokens), ['my_interp"body"']);
    });

    test('triple-quoted with prefix (raw"""...""")', () {
      final tokens = tokenize('val x = raw"""body"""', scala);
      expect(_textsOf<StringLit>(tokens), ['raw"""body"""']);
    });

    test('no prefix still works (plain "...")', () {
      final tokens = tokenize('val x = "body"', scala);
      expect(_textsOf<StringLit>(tokens), ['"body"']);
    });
  });

  group('JSON negative numbers', () {
    test('-1 is one NumberLit', () {
      final tokens = tokenize('{"n": -1}', json);
      expect(_textsOf<NumberLit>(tokens), ['-1']);
      // No separate `-` token anywhere.
      expect(_ofType<Operator>(tokens), isEmpty);
      expect(_textsOf<Plain>(tokens), isEmpty);
    });

    test('-3.14 is one NumberLit', () {
      final tokens = tokenize('{"n": -3.14}', json);
      expect(_textsOf<NumberLit>(tokens), ['-3.14']);
    });

    test('-1e10 is one NumberLit', () {
      final tokens = tokenize('{"n": -1e10}', json);
      expect(_textsOf<NumberLit>(tokens), ['-1e10']);
    });

    test('positive numbers still work', () {
      final tokens = tokenize('{"n": 42}', json);
      expect(_textsOf<NumberLit>(tokens), ['42']);
    });
  });

  group('YAML flow collections', () {
    test('flow sequence [1, 2, 3] classifies as punctuation', () {
      final tokens = tokenize('[1, 2, 3]', yaml);
      expect(_textsOf<Punctuation>(tokens), ['[', ',', ',', ']']);
      expect(_textsOf<NumberLit>(tokens), ['1', '2', '3']);
    });

    test('flow map {a: 1} classifies as punctuation', () {
      final tokens = tokenize('{a: 1}', yaml);
      expect(_textsOf<Punctuation>(tokens), ['{', ':', '}']);
    });

    test('YAML 1.1 keywords removed: yes/no/on/off are identifiers', () {
      final tokens = tokenize('a: yes\nb: no\nc: on\nd: off', yaml);
      // In YAML 1.2 these are strings (we treat as identifiers for highlighting).
      expect(_textsOf<Keyword>(tokens), isEmpty);
      expect(_textsOf<Identifier>(tokens), [
        'a',
        'yes',
        'b',
        'no',
        'c',
        'on',
        'd',
        'off',
      ]);
    });

    test('YAML 1.2 booleans still classified as Keyword', () {
      final tokens = tokenize('a: true\nb: false\nc: null', yaml);
      expect(_textsOf<Keyword>(tokens), ['true', 'false', 'null']);
    });
  });

  group('Operator vs Punctuation classification', () {
    test('Dart: + and * are Operator, not Punctuation', () {
      final tokens = tokenize('a + b * c', dart);
      expect(_textsOf<Operator>(tokens), ['+', '*']);
      expect(_ofType<Punctuation>(tokens), isEmpty);
    });

    test('Dart: parens and comma are Punctuation', () {
      final tokens = tokenize('f(1, 2)', dart);
      expect(_textsOf<Punctuation>(tokens), ['(', ',', ')']);
      expect(_ofType<Operator>(tokens), isEmpty);
    });

    test('Dart: multi-char operators coalesce into one token', () {
      final tokens = tokenize('a == b && c', dart);
      expect(_textsOf<Operator>(tokens), ['==', '&&']);
    });

    test('Dart: arrow => is one Operator', () {
      final tokens = tokenize('(x) => x', dart);
      expect(_textsOf<Operator>(tokens), ['=>']);
    });

    test('Scala: <- is one Operator (for-comprehensions)', () {
      final tokens = tokenize('for { x <- xs }', scala);
      expect(_textsOf<Operator>(tokens), ['<-']);
    });

    test('JSON: no operators (no operator classification happens)', () {
      final tokens = tokenize('{"n": 1}', json);
      expect(_ofType<Operator>(tokens), isEmpty);
    });
  });

  group('Shell variables', () {
    test('bare \$NAME is one Variable', () {
      final tokens = tokenize(r'echo $HOME', shell);
      expect(_textsOf<Variable>(tokens), [r'$HOME']);
      // $ must not leak out as a separate Plain token.
      expect(_textsOf<Plain>(tokens), isEmpty);
    });

    test(r'${NAME} (braced) is one Variable', () {
      final tokens = tokenize(r'echo ${HOME}', shell);
      expect(_textsOf<Variable>(tokens), [r'${HOME}']);
    });

    test(r'${NAME:-default} captures full expansion', () {
      final tokens = tokenize(r'echo ${X:-hi}', shell);
      expect(_textsOf<Variable>(tokens), [r'${X:-hi}']);
    });

    test(r'${#NAME} (string length) captures full expansion', () {
      final tokens = tokenize(r'echo ${#PATH}', shell);
      expect(_textsOf<Variable>(tokens), [r'${#PATH}']);
    });

    test('special parameters: \$1, \$@, \$?, \$\$', () {
      final tokens = tokenize(r'echo $1 $@ $? $$', shell);
      expect(_textsOf<Variable>(tokens), [r'$1', r'$@', r'$?', r'$$']);
    });

    test(r'lone $ before ( (for $(...)) emits $ as Variable', () {
      final tokens = tokenize(r'echo $(ls)', shell);
      final vars = _textsOf<Variable>(tokens);
      expect(vars, [r'$']);
      expect(_textsOf<Punctuation>(tokens), ['(', ')']);
      expect(_textsOf<Identifier>(tokens), ['echo', 'ls']);
    });

    test('unterminated \${ is tolerated', () {
      final tokens = tokenize(r'echo ${foo', shell);
      expect(_textsOf<Variable>(tokens), [r'${foo']);
    });

    test('Dart: \$ in identifier does NOT produce Variable', () {
      final tokens = tokenize(r'var $x = 1;', dart);
      // Dart allows $ in idents; no Variable classification.
      expect(_ofType<Variable>(tokens), isEmpty);
      expect(_textsOf<Identifier>(tokens), [r'$x']);
    });
  });

  group('Shell backtick command substitution', () {
    test('backticks classified as Punctuation', () {
      final tokens = tokenize('echo `ls`', shell);
      expect(_textsOf<Punctuation>(tokens), ['`', '`']);
      expect(_textsOf<Identifier>(tokens), ['echo', 'ls']);
    });

    test('non-shell grammars do not recognize backticks as punctuation', () {
      final tokens = tokenize('x `y`', json);
      // backtick falls through to Plain in JSON.
      expect(_textsOf<Plain>(tokens), contains('`'));
    });
  });

  group('Shell heredocs', () {
    test('<<EOF ... EOF captures the full construct as StringLit', () {
      const source = 'cat <<EOF\nhello\nEOF\n';
      final tokens = tokenize(source, shell);
      // The heredoc is one StringLit covering `<<EOF\nhello\nEOF\n`.
      final heredoc = tokens.whereType<StringLit>().single;
      expect(heredoc.text, startsWith('<<EOF'));
      expect(heredoc.text, contains('hello'));
      expect(heredoc.text, endsWith('EOF\n'));
    });

    test('<<-EOF tab-stripped terminator', () {
      const source = 'cat <<-EOF\n\tbody\n\tEOF\n';
      final tokens = tokenize(source, shell);
      final heredoc = tokens.whereType<StringLit>().single;
      expect(heredoc.text, startsWith('<<-EOF'));
      expect(heredoc.text, contains('\tbody'));
    });

    test("<<'EOF' single-quoted marker", () {
      const source = "cat <<'EOF'\nbody\nEOF\n";
      final tokens = tokenize(source, shell);
      final heredoc = tokens.whereType<StringLit>().single;
      expect(heredoc.text, startsWith("<<'EOF'"));
      expect(heredoc.text, contains('body'));
    });

    test('unterminated heredoc consumes to end-of-source', () {
      const source = 'cat <<EOF\nbody line\nanother line\n';
      final tokens = tokenize(source, shell);
      final heredoc = tokens.whereType<StringLit>().single;
      expect(heredoc.text, startsWith('<<EOF'));
      expect(heredoc.text, contains('another line'));
    });

    test('body containing EOF-ish lines that are not the terminator', () {
      const source = 'cat <<EOF\nEOFISH\nEOF\n';
      final tokens = tokenize(source, shell);
      final heredoc = tokens.whereType<StringLit>().single;
      expect(heredoc.text, contains('EOFISH'));
      expect(heredoc.text, endsWith('EOF\n'));
    });
  });

  group('Multi-char operators and generics (0.6.0 polish)', () {
    test('Dart: Map<String, int>: < and > are Punctuation (generics)', () {
      final tokens = tokenize('Map<String, int>', dart);
      expect(_textsOf<Punctuation>(tokens), ['<', ',', '>']);
      expect(_ofType<Operator>(tokens), isEmpty);
    });

    test('Dart: a <= b is one Operator', () {
      final tokens = tokenize('a <= b', dart);
      expect(_textsOf<Operator>(tokens), ['<=']);
      expect(_ofType<Punctuation>(tokens), isEmpty);
    });

    test('Dart: a >= b is one Operator', () {
      final tokens = tokenize('a >= b', dart);
      expect(_textsOf<Operator>(tokens), ['>=']);
    });

    test('Dart: a ?? b is one Operator', () {
      final tokens = tokenize('a ?? b', dart);
      expect(_textsOf<Operator>(tokens), ['??']);
    });

    test('Dart: a?.b is one Operator', () {
      final tokens = tokenize('a?.b', dart);
      expect(_textsOf<Operator>(tokens), ['?.']);
    });

    test('Dart: nullable type String?: ? is Punctuation', () {
      final tokens = tokenize('String? x', dart);
      expect(_textsOf<Punctuation>(tokens), ['?']);
    });

    test('Dart: arrow => is one Operator, not < plus =', () {
      final tokens = tokenize('(x) => x', dart);
      expect(_textsOf<Operator>(tokens), ['=>']);
    });

    test('Dart: compound assign += -= *= etc', () {
      final tokens = tokenize('x += 1; y -= 2; z *= 3;', dart);
      expect(_textsOf<Operator>(tokens), ['+=', '-=', '*=']);
    });

    test('Dart: ??= compound assign', () {
      final tokens = tokenize('x ??= 1', dart);
      expect(_textsOf<Operator>(tokens), ['??=']);
    });

    test('Dart: x=-1 tokenizes as three tokens', () {
      final tokens = tokenize('x=-1', dart);
      expect(_textsOf<Operator>(tokens), ['=', '-']);
      expect(_textsOf<NumberLit>(tokens), ['1']);
    });

    test('Scala: <- is one Operator', () {
      final tokens = tokenize('for { x <- xs }', scala);
      expect(_textsOf<Operator>(tokens), ['<-']);
    });

    test('Scala: -> is one Operator', () {
      final tokens = tokenize('val m = Map(1 -> "a")', scala);
      expect(_textsOf<Operator>(tokens), contains('->'));
    });

    test('Scala: :: is one Operator', () {
      final tokens = tokenize('1 :: Nil', scala);
      expect(_textsOf<Operator>(tokens), ['::']);
    });

    test('Shell: && is one Operator', () {
      final tokens = tokenize('a && b', shell);
      expect(_textsOf<Operator>(tokens), ['&&']);
    });

    test('Shell: || is one Operator', () {
      final tokens = tokenize('a || b', shell);
      expect(_textsOf<Operator>(tokens), ['||']);
    });
  });

  group('lossless roundtrip under new grammar rules', () {
    // Every grammar-fix input must still round-trip losslessly.
    test('Dart raw strings round-trip', () {
      _expectLossless("r'no\\escape' + r\"also\" + r'''triple'''", dart);
    });

    test('Scala interpolators round-trip', () {
      _expectLossless(r'val s = s"hi $name"; val f = f"$x%.2f"', scala);
    });

    test('Scala backtick idents round-trip', () {
      _expectLossless('val `type` = 1; val `hello world` = 2', scala);
    });

    test('JSON negatives round-trip', () {
      _expectLossless('{"a": -1, "b": -3.14, "c": -1e10}', json);
    });

    test('YAML flow collections round-trip', () {
      _expectLossless('a: [1, 2, 3]\nb: {x: 1, y: 2}\n', yaml);
    });

    test('shell variables round-trip', () {
      _expectLossless(r'echo $HOME ${PATH:-/bin} $(ls) `pwd`', shell);
    });

    test('shell heredocs round-trip', () {
      _expectLossless('cat <<EOF\nhello\nworld\nEOF\n', shell);
      _expectLossless('cat <<-EOF\n\tindented\n\tEOF\n', shell);
      _expectLossless("cat <<'EOF'\nno expansion\nEOF\n", shell);
    });
  });
}
