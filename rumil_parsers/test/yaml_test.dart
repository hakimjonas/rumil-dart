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
}
