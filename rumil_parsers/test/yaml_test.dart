import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

YamlDocument doc_(Result<ParseError, YamlDocument> r) => switch (r) {
  Success<ParseError, YamlDocument>(:final value) => value,
  Partial<ParseError, YamlDocument>(:final value) => value,
  Failure() => throw StateError('Expected success, got ${r.errors}'),
};

void main() {
  group('YAML scalars', () {
    test('null', () {
      expect(doc_(parseYaml('null')), isA<YamlNull>());
    });

    test('null tilde', () {
      expect(doc_(parseYaml('~')), isA<YamlNull>());
    });

    test('boolean true', () {
      final v = doc_(parseYaml('true'));
      expect((v as YamlBool).value, true);
    });

    test('boolean false', () {
      final v = doc_(parseYaml('false'));
      expect((v as YamlBool).value, false);
    });

    test('boolean yes', () {
      final v = doc_(parseYaml('yes'));
      expect((v as YamlBool).value, true);
    });

    test('boolean no', () {
      final v = doc_(parseYaml('no'));
      expect((v as YamlBool).value, false);
    });

    test('integer', () {
      final v = doc_(parseYaml('42'));
      expect((v as YamlInteger).value, 42);
    });

    test('negative integer', () {
      final v = doc_(parseYaml('-17'));
      expect((v as YamlInteger).value, -17);
    });

    test('float', () {
      final v = doc_(parseYaml('3.14'));
      expect((v as YamlFloat).value, 3.14);
    });

    test('plain string', () {
      final v = doc_(parseYaml('hello'));
      expect((v as YamlString).value, 'hello');
    });

    test('double-quoted string', () {
      final v = doc_(parseYaml('"hello world"'));
      expect((v as YamlString).value, 'hello world');
    });

    test('single-quoted string', () {
      final v = doc_(parseYaml("'hello world'"));
      expect((v as YamlString).value, 'hello world');
    });
  });

  group('YAML flow collections', () {
    test('flow sequence', () {
      final v = doc_(parseYaml('[1, 2, 3]'));
      final elems = (v as YamlSequence).elements;
      expect(elems.length, 3);
      expect((elems[0] as YamlInteger).value, 1);
    });

    test('empty flow sequence', () {
      final v = doc_(parseYaml('[]'));
      expect((v as YamlSequence).elements, isEmpty);
    });

    test('flow mapping', () {
      final v = doc_(parseYaml('{name: Alice, age: 30}'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['name'] as YamlString).value, 'Alice');
      expect((pairs['age'] as YamlInteger).value, 30);
    });

    test('empty flow mapping', () {
      final v = doc_(parseYaml('{}'));
      expect((v as YamlMapping).pairs, isEmpty);
    });
  });

  group('YAML block collections', () {
    test('block sequence', () {
      final v = doc_(parseYaml('- item1\n- item2\n- item3\n'));
      final elems = (v as YamlSequence).elements;
      expect(elems.length, 3);
      expect((elems[0] as YamlString).value, 'item1');
    });

    test('block mapping', () {
      final v = doc_(parseYaml('name: Alice\nage: 30\ncity: NYC\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['name'] as YamlString).value, 'Alice');
      expect((pairs['age'] as YamlInteger).value, 30);
      expect((pairs['city'] as YamlString).value, 'NYC');
    });
  });

  group('YAML document', () {
    test('document markers', () {
      final v = doc_(parseYaml('---\nname: test\n...'));
      expect(v, isA<YamlMapping>());
    });

    test('with comments', () {
      final v = doc_(parseYaml('# This is a comment\nname: Alice\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['name'] as YamlString).value, 'Alice');
    });

    test('with inline comment', () {
      final v = doc_(parseYaml('name: Alice # inline\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['name'] as YamlString).value, 'Alice');
    });
  });

  group('YAML 1.2: hex integers', () {
    test('0xFF', () {
      final v = doc_(parseYaml('0xFF'));
      expect((v as YamlInteger).value, 255);
    });

    test('0x0', () {
      final v = doc_(parseYaml('0x0'));
      expect((v as YamlInteger).value, 0);
    });

    test('0xCAFE', () {
      final v = doc_(parseYaml('0xCAFE'));
      expect((v as YamlInteger).value, 51966);
    });

    test('hex in mapping', () {
      final v = doc_(parseYaml('color: 0xFF\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['color'] as YamlInteger).value, 255);
    });
  });

  group('YAML 1.2: octal integers', () {
    test('0o755', () {
      final v = doc_(parseYaml('0o755'));
      expect((v as YamlInteger).value, 493);
    });

    test('0o0', () {
      final v = doc_(parseYaml('0o0'));
      expect((v as YamlInteger).value, 0);
    });

    test('octal in mapping', () {
      final v = doc_(parseYaml('permissions: 0o755\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['permissions'] as YamlInteger).value, 493);
    });
  });

  group('YAML 1.2: special floats', () {
    test('.inf', () {
      final v = doc_(parseYaml('.inf'));
      expect((v as YamlFloat).value, double.infinity);
    });

    test('-.inf', () {
      final v = doc_(parseYaml('-.inf'));
      expect((v as YamlFloat).value, double.negativeInfinity);
    });

    test('.nan', () {
      final v = doc_(parseYaml('.nan'));
      expect((v as YamlFloat).value, isNaN);
    });

    test('special floats in mapping', () {
      final v = doc_(parseYaml('pos: .inf\nneg: -.inf\nnan: .nan\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['pos'] as YamlFloat).value, double.infinity);
      expect((pairs['neg'] as YamlFloat).value, double.negativeInfinity);
      expect((pairs['nan'] as YamlFloat).value, isNaN);
    });
  });

  group('YAML 1.2: plain string colon fix', () {
    test('URL with colon', () {
      final v = doc_(parseYaml('url: http://example.com\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['url'] as YamlString).value, 'http://example.com');
    });

    test('colon mid-word', () {
      final v = doc_(parseYaml('key: a:b\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['key'] as YamlString).value, 'a:b');
    });

    test('colon mid-value with non-ws after', () {
      // `:` followed by non-ws is a valid plain char per §7.3.3.
      final v = doc_(parseYaml('key: word:stuff\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['key'] as YamlString).value, 'word:stuff');
    });

    test('multiple colons in URL', () {
      final v = doc_(parseYaml('proxy: http://host:8080/path\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['proxy'] as YamlString).value, 'http://host:8080/path');
    });
  });

  group('YAML 1.2: plain string hash fix', () {
    test('hash mid-word', () {
      final v = doc_(parseYaml('tag: foo#bar\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['tag'] as YamlString).value, 'foo#bar');
    });

    test('hash with space before starts comment', () {
      final v = doc_(parseYaml('key: value #comment\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['key'] as YamlString).value, 'value');
    });

    test('multiple hashes no spaces', () {
      final v = doc_(parseYaml('tag: v1.0#beta#rc1\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['tag'] as YamlString).value, 'v1.0#beta#rc1');
    });
  });

  group('YAML 1.2: empty value = null', () {
    test('key with no value', () {
      final v = doc_(parseYaml('description:\nother: value\n'));
      final pairs = (v as YamlMapping).pairs;
      expect(pairs['description'], const YamlNull());
      expect((pairs['other'] as YamlString).value, 'value');
    });

    test('multiple empty values', () {
      final v = doc_(parseYaml('a:\nb:\nc: hello\n'));
      final pairs = (v as YamlMapping).pairs;
      expect(pairs['a'], const YamlNull());
      expect(pairs['b'], const YamlNull());
      expect((pairs['c'] as YamlString).value, 'hello');
    });

    test('empty value at end of document', () {
      final v = doc_(parseYaml('name: test\ndescription:\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['name'] as YamlString).value, 'test');
      expect(pairs['description'], const YamlNull());
    });
  });

  group('YAML 1.2: double-quoted escapes', () {
    test('null escape \\0', () {
      final v = doc_(parseYaml(r'val: "\0"'));
      expect((v as YamlMapping).pairs['val'], const YamlString('\x00'));
    });

    test('bell escape \\a', () {
      final v = doc_(parseYaml(r'val: "\a"'));
      expect((v as YamlMapping).pairs['val'], const YamlString('\x07'));
    });

    test('vertical tab \\v', () {
      final v = doc_(parseYaml(r'val: "\v"'));
      expect((v as YamlMapping).pairs['val'], const YamlString('\x0B'));
    });

    test('escape \\e', () {
      final v = doc_(parseYaml(r'val: "\e"'));
      expect((v as YamlMapping).pairs['val'], const YamlString('\x1B'));
    });

    test('next line \\N', () {
      final v = doc_(parseYaml(r'val: "\N"'));
      expect((v as YamlMapping).pairs['val'], const YamlString('\u0085'));
    });

    test('non-breaking space \\_', () {
      final v = doc_(parseYaml(r'val: "\_"'));
      expect((v as YamlMapping).pairs['val'], const YamlString('\u00A0'));
    });

    test('line separator \\L', () {
      final v = doc_(parseYaml(r'val: "\L"'));
      expect((v as YamlMapping).pairs['val'], const YamlString('\u2028'));
    });

    test('paragraph separator \\P', () {
      final v = doc_(parseYaml(r'val: "\P"'));
      expect((v as YamlMapping).pairs['val'], const YamlString('\u2029'));
    });

    test('hex escape \\xHH', () {
      final v = doc_(parseYaml(r'val: "\x41"'));
      expect((v as YamlMapping).pairs['val'], const YamlString('A'));
    });

    test('unicode escape \\uHHHH', () {
      final v = doc_(parseYaml(r'val: "\u0041"'));
      expect((v as YamlMapping).pairs['val'], const YamlString('A'));
    });

    test('unicode escape 32-bit \\UHHHHHHHH', () {
      final v = doc_(parseYaml(r'val: "\U00000041"'));
      expect((v as YamlMapping).pairs['val'], const YamlString('A'));
    });

    test('slash escape \\/', () {
      final v = doc_(parseYaml(r'val: "\/"'));
      expect((v as YamlMapping).pairs['val'], const YamlString('/'));
    });

    test('mixed escapes', () {
      final v = doc_(parseYaml(r'val: "hello\tworld\n"'));
      expect(
        (v as YamlMapping).pairs['val'],
        const YamlString('hello\tworld\n'),
      );
    });
  });

  group('YAML 1.2: single-quoted escaping', () {
    test("escaped single quote ''", () {
      final v = doc_(parseYaml("val: 'it''s a test'\n"));
      expect((v as YamlMapping).pairs['val'], const YamlString("it's a test"));
    });

    test('no backslash escapes in single quotes', () {
      final v = doc_(
        parseYaml(
          r"val: 'no \n here'"
          '\n',
        ),
      );
      expect((v as YamlMapping).pairs['val'], const YamlString(r'no \n here'));
    });

    test('empty single-quoted string', () {
      final v = doc_(parseYaml("val: ''\n"));
      expect((v as YamlMapping).pairs['val'], const YamlString(''));
    });
  });

  group('YAML 1.2: block scalars', () {
    test('literal basic', () {
      final v = doc_(parseYaml('literal: |\n  line 1\n  line 2\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['literal'] as YamlString).value, 'line 1\nline 2\n');
    });

    test('folded basic', () {
      final v = doc_(parseYaml('folded: >\n  long\n  description\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['folded'] as YamlString).value, 'long description\n');
    });

    test('literal strip', () {
      final v = doc_(parseYaml('stripped: |-\n  no trailing\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['stripped'] as YamlString).value, 'no trailing');
    });

    test('literal keep', () {
      final v = doc_(parseYaml('kept: |+\n  trailing\n\n\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['kept'] as YamlString).value, 'trailing\n\n\n');
    });

    test('folded with paragraph break', () {
      final v = doc_(
        parseYaml('text: >\n  para one\n  line two\n\n  para two\n'),
      );
      final pairs = (v as YamlMapping).pairs;
      expect(
        (pairs['text'] as YamlString).value,
        'para one line two\npara two\n',
      );
    });

    test('literal multiline', () {
      final v = doc_(parseYaml('script: |\n  echo hello\n  echo world\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['script'] as YamlString).value, 'echo hello\necho world\n');
    });

    test('block scalar followed by next key', () {
      final v = doc_(parseYaml('desc: |\n  hello\n  world\nname: test\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['desc'] as YamlString).value, 'hello\nworld\n');
      expect((pairs['name'] as YamlString).value, 'test');
    });

    test('block scalar as sequence item', () {
      final v = doc_(parseYaml('- |\n  line 1\n  line 2\n- plain\n'));
      final elems = (v as YamlSequence).elements;
      expect((elems[0] as YamlString).value, 'line 1\nline 2\n');
      expect((elems[1] as YamlString).value, 'plain');
    });

    test('literal with more-indented lines', () {
      final v = doc_(parseYaml('code: |\n  if x:\n    print(x)\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['code'] as YamlString).value, 'if x:\n  print(x)\n');
    });

    test('folded preserves more-indented lines', () {
      final v = doc_(parseYaml('text: >\n  normal\n    indented\n  normal\n'));
      final pairs = (v as YamlMapping).pairs;
      expect(
        (pairs['text'] as YamlString).value,
        'normal\n  indented\nnormal\n',
      );
    });

    test('explicit indent indicator', () {
      final v = doc_(parseYaml('data: |2\n    two extra\n    spaces\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['data'] as YamlString).value, '  two extra\n  spaces\n');
    });

    test('strip with trailing blank lines', () {
      final v = doc_(parseYaml('val: |-\n  content\n\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['val'] as YamlString).value, 'content');
    });
  });

  group('YAML 1.2: anchors and aliases', () {
    test('anchor on scalar', () {
      final v = doc_(parseYaml('name: &default Alice\n'));
      final pairs = (v as YamlMapping).pairs;
      final anchor = pairs['name'] as YamlAnchor;
      expect(anchor.name, 'default');
      expect((anchor.value as YamlString).value, 'Alice');
    });

    test('alias reference', () {
      final v = doc_(parseYaml('a: &val hello\nb: *val\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['a'] as YamlAnchor).name, 'val');
      expect((pairs['b'] as YamlAlias).name, 'val');
    });

    test('resolve simple anchor/alias', () {
      final v = doc_(parseYaml('a: &val hello\nb: *val\n'));
      final resolved = resolveAnchors(v);
      final pairs = (resolved as YamlMapping).pairs;
      expect((pairs['a'] as YamlString).value, 'hello');
      expect((pairs['b'] as YamlString).value, 'hello');
    });

    test('anchor on block mapping', () {
      final v = doc_(
        parseYaml('defaults: &defaults\n  host: localhost\n  port: 5432\n'),
      );
      final pairs = (v as YamlMapping).pairs;
      final anchor = pairs['defaults'] as YamlAnchor;
      expect(anchor.name, 'defaults');
      final inner = anchor.value as YamlMapping;
      expect((inner.pairs['host'] as YamlString).value, 'localhost');
    });

    test('merge key basic', () {
      const yaml =
          'defaults: &def\n'
          '  host: localhost\n'
          '  port: 5432\n'
          'prod:\n'
          '  <<: *def\n'
          '  database: prod_db\n';
      final resolved = resolveAnchors(doc_(parseYaml(yaml)));
      final prod = (resolved as YamlMapping).pairs['prod'] as YamlMapping;
      expect((prod.pairs['host'] as YamlString).value, 'localhost');
      expect((prod.pairs['port'] as YamlInteger).value, 5432);
      expect((prod.pairs['database'] as YamlString).value, 'prod_db');
    });

    test('merge key — local keys override merged', () {
      const yaml =
          'base: &base\n'
          '  host: default\n'
          'prod:\n'
          '  <<: *base\n'
          '  host: prod-server\n';
      final resolved = resolveAnchors(doc_(parseYaml(yaml)));
      final prod = (resolved as YamlMapping).pairs['prod'] as YamlMapping;
      expect((prod.pairs['host'] as YamlString).value, 'prod-server');
    });

    test('anchor on inline value', () {
      final v = doc_(parseYaml('x: &ref 42\ny: *ref\n'));
      final resolved = resolveAnchors(v);
      final pairs = (resolved as YamlMapping).pairs;
      expect((pairs['x'] as YamlInteger).value, 42);
      expect((pairs['y'] as YamlInteger).value, 42);
    });

    test('anchor on sequence', () {
      final v = doc_(parseYaml('tags: &tags\n  - web\n  - api\ncopy: *tags\n'));
      final resolved = resolveAnchors(v);
      final pairs = (resolved as YamlMapping).pairs;
      final tags = pairs['tags'] as YamlSequence;
      expect(tags.elements.length, 2);
      final copy = pairs['copy'] as YamlSequence;
      expect(copy.elements.length, 2);
    });

    test('undefined alias throws', () {
      final v = doc_(parseYaml('x: *missing\n'));
      expect(() => resolveAnchors(v), throwsStateError);
    });

    test('yamlToNative resolves transparently', () {
      final v = doc_(parseYaml('a: &val hello\nb: *val\n'));
      final native = yamlToNative(v) as Map;
      expect(native['a'], 'hello');
      expect(native['b'], 'hello');
    });
  });

  group('YAML 1.2: tab rejection', () {
    test('tab indent produces parse error', () {
      final r = parseYaml('key:\n\tvalue\n');
      expect(r, isA<Failure<ParseError, YamlDocument>>());
    });
  });

  group('YAML 1.2: strict12 config', () {
    const strict = YamlParseConfig(strict12: true);

    test('yes is string in strict mode', () {
      final v = doc_(parseYaml('val: yes\n', config: strict));
      expect((v as YamlMapping).pairs['val'], const YamlString('yes'));
    });

    test('no is string in strict mode', () {
      final v = doc_(parseYaml('val: no\n', config: strict));
      expect((v as YamlMapping).pairs['val'], const YamlString('no'));
    });

    test('on is string in strict mode', () {
      final v = doc_(parseYaml('val: on\n', config: strict));
      expect((v as YamlMapping).pairs['val'], const YamlString('on'));
    });

    test('off is string in strict mode', () {
      final v = doc_(parseYaml('val: off\n', config: strict));
      expect((v as YamlMapping).pairs['val'], const YamlString('off'));
    });

    test('true is still bool in strict mode', () {
      final v = doc_(parseYaml('val: true\n', config: strict));
      expect((v as YamlMapping).pairs['val'], const YamlBool(true));
    });

    test('false is still bool in strict mode', () {
      final v = doc_(parseYaml('val: false\n', config: strict));
      expect((v as YamlMapping).pairs['val'], const YamlBool(false));
    });
  });

  group('YAML 1.2: blank lines between entries', () {
    test('blank lines between mapping entries', () {
      final v = doc_(parseYaml('name: Alice\n\nage: 30\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['name'] as YamlString).value, 'Alice');
      expect((pairs['age'] as YamlInteger).value, 30);
    });

    test('multiple blank lines between entries', () {
      final v = doc_(parseYaml('a: 1\n\n\nb: 2\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['a'] as YamlInteger).value, 1);
      expect((pairs['b'] as YamlInteger).value, 2);
    });

    test('blank lines between sequence items', () {
      final v = doc_(parseYaml('- one\n\n- two\n\n- three\n'));
      final elems = (v as YamlSequence).elements;
      expect(elems.length, 3);
      expect((elems[0] as YamlString).value, 'one');
      expect((elems[2] as YamlString).value, 'three');
    });

    test('comment lines between entries', () {
      final v = doc_(parseYaml('name: Alice\n# a comment\nage: 30\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['name'] as YamlString).value, 'Alice');
      expect((pairs['age'] as YamlInteger).value, 30);
    });

    test('real-world: CI-style mapping with blank lines', () {
      final v = doc_(parseYaml('name: CI\n\njobs:\n  test: true\n'));
      final pairs = (v as YamlMapping).pairs;
      expect((pairs['name'] as YamlString).value, 'CI');
      final jobs = pairs['jobs'] as YamlMapping;
      expect((jobs.pairs['test'] as YamlBool).value, true);
    });
  });

  group('YAML 1.2: multi-document', () {
    test('two documents', () {
      final r = parseYamlMulti('---\nfirst\n---\nsecond\n');
      final docs = switch (r) {
        Success(:final value) => value,
        Partial(:final value) => value,
        Failure() => throw StateError('parse failed: ${r.errors}'),
      };
      expect(docs.length, 2);
      expect((docs[0] as YamlString).value, 'first');
      expect((docs[1] as YamlString).value, 'second');
    });

    test('document with end marker', () {
      final r = parseYamlMulti('---\nfirst\n...\n---\nsecond\n');
      final docs = switch (r) {
        Success(:final value) => value,
        Partial(:final value) => value,
        Failure() => throw StateError('parse failed: ${r.errors}'),
      };
      expect(docs.length, 2);
    });

    test('three documents', () {
      final r = parseYamlMulti('---\na: 1\n---\nb: 2\n---\nc: 3\n');
      final docs = switch (r) {
        Success(:final value) => value,
        Partial(:final value) => value,
        Failure() => throw StateError('parse failed: ${r.errors}'),
      };
      expect(docs.length, 3);
    });
  });

  group('Nested indentation', () {
    test('mapping with nested mapping', () {
      final v = doc_(parseYaml('metadata:\n  name: my-app\n  version: 1.0\n'));
      final meta = (v as YamlMapping).pairs['metadata'] as YamlMapping;
      expect((meta.pairs['name'] as YamlString).value, 'my-app');
    });

    test('mapping with nested sequence', () {
      final v = doc_(parseYaml('tags:\n  - admin\n  - user\n'));
      final tags = (v as YamlMapping).pairs['tags'] as YamlSequence;
      expect(tags.elements.length, 2);
      expect((tags.elements[0] as YamlString).value, 'admin');
    });

    test('deeply nested mapping', () {
      final v = doc_(parseYaml('a:\n  b:\n    c: deep\n'));
      final a = (v as YamlMapping).pairs['a'] as YamlMapping;
      final b = a.pairs['b'] as YamlMapping;
      expect((b.pairs['c'] as YamlString).value, 'deep');
    });

    test('sequence of mappings (compact notation)', () {
      final v = doc_(
        parseYaml(
          'users:\n  - name: Alice\n    age: 25\n  - name: Bob\n    age: 30\n',
        ),
      );
      final users = (v as YamlMapping).pairs['users'] as YamlSequence;
      expect(users.elements.length, 2);
      final alice = users.elements[0] as YamlMapping;
      expect((alice.pairs['name'] as YamlString).value, 'Alice');
      expect((alice.pairs['age'] as YamlInteger).value, 25);
    });

    test('mixed nesting', () {
      final v = doc_(
        parseYaml(
          'database:\n  host: localhost\n  ports:\n    - 5432\n    - 5433\n',
        ),
      );
      final db = (v as YamlMapping).pairs['database'] as YamlMapping;
      expect((db.pairs['host'] as YamlString).value, 'localhost');
      final ports = db.pairs['ports'] as YamlSequence;
      expect(ports.elements.length, 2);
    });

    test('real-world: k8s-like config', () {
      final v = doc_(
        parseYaml('''
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  labels:
    app: my-app
spec:
  replicas: 3
'''),
      );
      final root = v as YamlMapping;
      expect((root.pairs['apiVersion'] as YamlString).value, 'apps/v1');
      final metadata = root.pairs['metadata'] as YamlMapping;
      final labels = metadata.pairs['labels'] as YamlMapping;
      expect((labels.pairs['app'] as YamlString).value, 'my-app');
      expect(
        (root.pairs['spec'] as YamlMapping).pairs['replicas'],
        const YamlInteger(3),
      );
    });
  });
}
