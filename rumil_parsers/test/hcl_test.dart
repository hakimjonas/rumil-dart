import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

HclDocument doc_(Result<ParseError, HclDocument> r) => switch (r) {
  Success<ParseError, HclDocument>(:final value) => value,
  Partial<ParseError, HclDocument>(:final value) => value,
  Failure() => throw StateError('Expected success, got ${r.errors}'),
};

void main() {
  group('HCL attributes', () {
    test('string', () {
      final d = doc_(parseHcl('name = "Alice"\n'));
      expect(d['name'], const HclString('Alice'));
    });

    test('number', () {
      final d = doc_(parseHcl('port = 8080\n'));
      expect(d['port'], const HclNumber(8080));
    });

    test('bool', () {
      final d = doc_(parseHcl('enabled = true\n'));
      expect(d['enabled'], const HclBool(true));
    });

    test('null', () {
      final d = doc_(parseHcl('value = null\n'));
      expect(d['value'], const HclNull());
    });

    test('list', () {
      final d = doc_(parseHcl('ports = [80, 443]\n'));
      final list = d['ports'] as HclList;
      expect(list.elements.length, 2);
    });

    test('object', () {
      final d = doc_(parseHcl('tags = { Name = "web" }\n'));
      final obj = d['tags'] as HclObject;
      expect(obj.fields['Name'], const HclString('web'));
    });

    test('reference', () {
      final d = doc_(parseHcl('value = aws_instance.web.id\n'));
      expect(d['value'], const HclReference('aws_instance.web.id'));
    });

    test('multiple attributes', () {
      final d = doc_(parseHcl('name = "test"\nport = 8080\n'));
      expect(d['name'], const HclString('test'));
      expect(d['port'], const HclNumber(8080));
    });
  });

  group('HCL blocks', () {
    test('simple block', () {
      final d = doc_(
        parseHcl('resource "aws_instance" "web" {\n  ami = "abc"\n}\n'),
      );
      final block = d['resource'] as HclBlock;
      expect(block.type, 'resource');
      expect(block.labels, ['aws_instance', 'web']);
      expect(block.body['ami'], const HclString('abc'));
    });

    test('block with no labels', () {
      final d = doc_(parseHcl('locals {\n  x = 1\n}\n'));
      final block = d['locals'] as HclBlock;
      expect(block.labels, isEmpty);
      expect(block.body['x'], const HclNumber(1));
    });

    test('nested blocks', () {
      final d = doc_(
        parseHcl(
          'terraform {\n  backend "s3" {\n    bucket = "state"\n  }\n}\n',
        ),
      );
      final tf = d['terraform'] as HclBlock;
      final backend = tf.body['backend'] as HclBlock;
      expect(backend.labels, ['s3']);
      expect(backend.body['bucket'], const HclString('state'));
    });
  });

  group('HCL comments', () {
    test('hash comment', () {
      final d = doc_(parseHcl('# comment\nname = "test"\n'));
      expect(d['name'], const HclString('test'));
    });

    test('slash comment', () {
      final d = doc_(parseHcl('// comment\nname = "test"\n'));
      expect(d['name'], const HclString('test'));
    });

    test('block comment', () {
      final d = doc_(parseHcl('/* comment */\nname = "test"\n'));
      expect(d['name'], const HclString('test'));
    });
  });

  group('HCL real-world', () {
    test('terraform variable', () {
      final d = doc_(
        parseHcl('''
variable "region" {
  type    = "string"
  default = "us-east-1"
}
'''),
      );
      final v = d['variable'] as HclBlock;
      expect(v.labels, ['region']);
      expect(v.body['default'], const HclString('us-east-1'));
    });

    test('terraform resource', () {
      final d = doc_(
        parseHcl('''
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
}
'''),
      );
      final r = d['resource'] as HclBlock;
      expect(r.labels, ['aws_instance', 'web']);
    });
  });

  group('HCL native decoder', () {
    test('attributes', () {
      final d = doc_(parseHcl('name = "test"\nport = 8080\n'));
      final native = <String, Object?>{
        for (final e in d.entries) e.key: hclToNative(e.value),
      };
      expect(native['name'], 'test');
      expect(native['port'], 8080);
    });

    test('blocks include _type and _labels', () {
      final d = doc_(
        parseHcl('resource "aws_instance" "web" {\n  ami = "abc"\n}\n'),
      );
      final native = hclToNative(d['resource']!) as Map;
      expect(native['_type'], 'resource');
      expect(native['_labels'], ['aws_instance', 'web']);
      expect(native['ami'], 'abc');
    });
  });

  group('HCL serializer', () {
    test('attributes', () {
      final doc = <String, HclValue>{
        'name': const HclString('test'),
        'port': const HclNumber(8080),
      };
      final s = serializeHcl(doc);
      expect(s, contains('name = "test"'));
      expect(s, contains('port = 8080'));
    });

    test('block', () {
      final doc = <String, HclValue>{
        'resource': HclBlock(
          'resource',
          ['aws_instance', 'web'],
          {'ami': const HclString('abc')},
        ),
      };
      final s = serializeHcl(doc);
      expect(s, contains('resource "aws_instance" "web" {'));
      expect(s, contains('ami = "abc"'));
    });
  });
}
