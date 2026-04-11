import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

JsonValue _json(String input) {
  final r = parseJson(input);
  return switch (r) {
    Success<ParseError, JsonValue>(:final value) => value,
    Partial<ParseError, JsonValue>(:final value) => value,
    Failure() => throw StateError('Parse failed: ${r.errors}'),
  };
}

void main() {
  group('JSON round-trip', () {
    test('compact', () {
      const input = '{"name":"Alice","age":30,"active":true}';
      final ast = _json(input);
      final serialized = serializeJson(ast);
      expect(_json(serialized), ast);
    });

    test('pretty', () {
      final ast = _json('{"a":1,"b":[2,3]}');
      final pretty = serializeJson(ast, config: JsonFormatConfig.pretty);
      expect(pretty, contains('\n'));
      expect(_json(pretty), ast);
    });

    test('sortKeys', () {
      final ast = _json('{"c":3,"a":1,"b":2}');
      final sorted = serializeJson(
        ast,
        config: const JsonFormatConfig(sortKeys: true),
      );
      expect(sorted, '{"a":1,"b":2,"c":3}');
    });

    test('empty object and array', () {
      expect(serializeJson(const JsonObject({})), '{}');
      expect(serializeJson(const JsonArray([])), '[]');
    });

    test('nested', () {
      const input = '{"users":[{"name":"Alice","tags":["admin","user"]}]}';
      final ast = _json(input);
      expect(_json(serializeJson(ast)), ast);
    });

    test('string escaping', () {
      const ast = JsonString('line1\nline2\ttab "quote" \\slash');
      final s = serializeJson(ast);
      expect(s, r'"line1\nline2\ttab \"quote\" \\slash"');
    });

    test('control char escaping', () {
      const ast = JsonString('bell\x07form\x0C');
      final s = serializeJson(ast);
      expect(s, contains(r'\u0007'));
      expect(s, contains(r'\f'));
    });

    test('numbers', () {
      expect(serializeJson(const JsonNumber(42)), '42');
      expect(serializeJson(const JsonNumber(3.14)), '3.14');
      expect(serializeJson(const JsonNumber(-0.5)), '-0.5');
      expect(serializeJson(const JsonNumber(0)), '0');
    });

    test('null and booleans', () {
      expect(serializeJson(const JsonNull()), 'null');
      expect(serializeJson(const JsonBool(true)), 'true');
      expect(serializeJson(const JsonBool(false)), 'false');
    });
  });

  group('YAML serializer', () {
    test('scalars', () {
      expect(serializeYaml(const YamlNull()), 'null');
      expect(serializeYaml(const YamlBool(true)), 'true');
      expect(serializeYaml(const YamlInteger(42)), '42');
      expect(serializeYaml(const YamlFloat(3.14)), '3.14');
      expect(serializeYaml(const YamlString('hello')), 'hello');
    });

    test('float special values', () {
      expect(serializeYaml(const YamlFloat(double.nan)), '.nan');
      expect(serializeYaml(const YamlFloat(double.infinity)), '.inf');
      expect(serializeYaml(const YamlFloat(double.negativeInfinity)), '-.inf');
    });

    test('string quoting', () {
      expect(serializeYaml(const YamlString('true')), '"true"');
      expect(serializeYaml(const YamlString('null')), '"null"');
      expect(serializeYaml(const YamlString('')), '""');
      expect(serializeYaml(const YamlString('a:b')), '"a:b"');
    });

    test('block sequence', () {
      final yaml = serializeYaml(
        const YamlSequence([YamlInteger(1), YamlInteger(2), YamlInteger(3)]),
      );
      expect(yaml, '- 1\n- 2\n- 3');
    });

    test('block mapping', () {
      final yaml = serializeYaml(
        const YamlMapping({
          'name': YamlString('Alice'),
          'age': YamlInteger(30),
        }),
      );
      expect(yaml, 'name: Alice\nage: 30');
    });

    test('nested mapping + sequence', () {
      final yaml = serializeYaml(
        const YamlMapping({
          'users': YamlSequence([
            YamlMapping({'name': YamlString('Alice')}),
          ]),
        }),
      );
      expect(yaml, contains('users:\n'));
      expect(yaml, contains('- name: Alice'));
    });

    test('document markers', () {
      final doc = serializeYamlDocument(const YamlString('hello'));
      expect(doc, startsWith('---\n'));
    });

    test('empty collections', () {
      expect(serializeYaml(const YamlSequence([])), '[]');
      expect(serializeYaml(const YamlMapping({})), '{}');
    });
  });

  group('TOML round-trip', () {
    test('simple pairs', () {
      const input = 'name = "Alice"\nage = 30\n';
      final doc = _tomlDoc(input);
      final serialized = serializeToml(doc);
      expect(serializeToml(_tomlDoc(serialized)), serializeToml(doc));
    });

    test('nested tables', () {
      const input =
          'title = "Test"\n\n[server]\nhost = "localhost"\nport = 8080\n';
      final doc = _tomlDoc(input);
      final serialized = serializeToml(doc);
      expect(serialized, contains('[server]'));
      expect(serialized, contains('host = "localhost"'));
    });

    test('string escaping', () {
      final doc = {'msg': const TomlString('line1\nline2')};
      final s = serializeToml(doc);
      expect(s, contains(r'\n'));
    });

    test('float special values', () {
      expect(
        serializeToml({'x': const TomlFloat(double.nan)}),
        contains('nan'),
      );
      expect(
        serializeToml({'x': const TomlFloat(double.infinity)}),
        contains('inf'),
      );
    });
  });

  group('XML serializer', () {
    test('simple element', () {
      final xml = serializeXml(
        const XmlElement(QName('root'), [], [XmlText('hello')]),
      );
      expect(xml, '<root>hello</root>');
    });

    test('attributes', () {
      final xml = serializeXml(
        const XmlElement(QName('div'), [
          (name: QName('class'), value: 'main'),
        ], []),
      );
      expect(xml, '<div class="main"/>');
    });

    test('nested elements', () {
      final xml = serializeXml(
        const XmlElement(QName('root'), [], [
          XmlElement(QName('child'), [], [XmlText('a')]),
          XmlElement(QName('child'), [], [XmlText('b')]),
        ]),
      );
      expect(xml, contains('<child>a</child>'));
      expect(xml, contains('<child>b</child>'));
    });

    test('self-closing', () {
      final xml = serializeXml(const XmlElement(QName('br'), [], []));
      expect(xml, '<br/>');
    });

    test('text escaping', () {
      final xml = serializeXml(
        const XmlElement(QName('p'), [], [XmlText('a < b & c > d')]),
      );
      expect(xml, contains('a &lt; b &amp; c &gt; d'));
    });

    test('attribute escaping', () {
      final xml = serializeXml(
        const XmlElement(QName('a'), [
          (name: QName('href'), value: 'x"y'),
        ], []),
      );
      expect(xml, contains('&quot;'));
    });

    test('CDATA', () {
      expect(
        serializeXml(const XmlCData('raw <content>')),
        '<![CDATA[raw <content>]]>',
      );
    });

    test('comment', () {
      expect(serializeXml(const XmlComment(' note ')), '<!-- note -->');
    });

    test('processing instruction', () {
      expect(
        serializeXml(const XmlPI('xml-stylesheet', 'type="text/xsl"')),
        '<?xml-stylesheet type="text/xsl"?>',
      );
    });

    test('document with declaration', () {
      final doc = serializeXmlDocument(const XmlElement(QName('root'), [], []));
      expect(doc, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    });

    test('namespaced element', () {
      final xml = serializeXml(
        const XmlElement(QName('element', prefix: 'ns'), [], [XmlText('val')]),
      );
      expect(xml, '<ns:element>val</ns:element>');
    });
  });

  group('CSV round-trip', () {
    test('simple', () {
      final records = [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ];
      final csv = serializeCsv(records);
      expect(csv, 'a,b,c\r\n1,2,3');
    });

    test('quoted fields', () {
      final csv = serializeCsv([
        ['has,comma', 'has"quote', 'normal'],
      ]);
      expect(csv, '"has,comma","has""quote",normal');
    });

    test('with headers', () {
      final csv = serializeCsvWithHeaders(
        ['name', 'age'],
        [
          ['Alice', '30'],
        ],
      );
      expect(csv, 'name,age\r\nAlice,30');
    });

    test('newline in field', () {
      final csv = serializeCsv([
        ['line1\nline2'],
      ]);
      expect(csv, '"line1\nline2"');
    });
  });

  group('Proto round-trip', () {
    test('message with fields', () {
      const input = '''
syntax = "proto3";

message Person {
  string name = 1;
  int32 age = 2;
}
''';
      final file = _protoFile(input);
      final serialized = serializeProto(file);
      expect(serialized, contains('message Person'));
      expect(serialized, contains('string name = 1;'));
    });

    test('optional field', () {
      const file = ProtoFile('proto3', [
        ProtoMessageDef('Msg', [
          ProtoField(
            FieldRule.optional,
            ScalarType(ProtoScalar.string_),
            'label',
            1,
          ),
        ]),
      ]);
      final s = serializeProto(file);
      expect(s, contains('optional string label = 1;'));
    });

    test('service with streaming', () {
      const file = ProtoFile('proto3', [
        ProtoServiceDef('Svc', [
          ProtoMethod('List', 'Req', 'Resp', outputStreaming: true),
        ]),
      ]);
      final s = serializeProto(file);
      expect(s, contains('returns (stream Resp)'));
    });
  });

  group('Native decoders', () {
    test('jsonToNative preserves int', () {
      expect(jsonToNative(const JsonNumber(42)), 42);
      expect(jsonToNative(const JsonNumber(42)), isA<int>());
    });

    test('jsonToNative preserves double', () {
      expect(jsonToNative(const JsonNumber(3.14)), 3.14);
    });

    test('jsonToNative null', () {
      expect(jsonToNative(const JsonNull()), null);
    });

    test('jsonToNative nested', () {
      final result = jsonToNative(
        const JsonObject({
          'a': JsonArray([JsonNumber(1), JsonString('two')]),
        }),
      );
      expect(result, {
        'a': [1, 'two'],
      });
    });

    test('yamlToNative', () {
      expect(yamlToNative(const YamlNull()), null);
      expect(yamlToNative(const YamlInteger(42)), 42);
      expect(yamlToNative(const YamlString('hi')), 'hi');
    });

    test('tomlToNative', () {
      expect(tomlToNative(const TomlInteger(42)), 42);
      expect(tomlToNative(const TomlString('hi')), 'hi');
      expect(tomlToNative(const TomlBool(true)), true);
    });

    test('tomlDocToNative', () {
      final doc = <String, TomlValue>{
        'name': const TomlString('test'),
        'port': const TomlInteger(8080),
      };
      final native = tomlDocToNative(doc);
      expect(native, {'name': 'test', 'port': 8080});
    });
  });

  group('AstBuilder', () {
    test('nativeToAst JSON', () {
      final ast = nativeToAst({'name': 'Alice', 'age': 30}, jsonBuilder);
      expect(ast, isA<JsonObject>());
    });

    test('nativeToAst YAML', () {
      final ast = nativeToAst([1, 'two', true], yamlBuilder);
      expect(ast, isA<YamlSequence>());
    });

    test('nativeToAst primitives', () {
      expect(nativeToAst(null, jsonBuilder), isA<JsonNull>());
      expect(nativeToAst(true, jsonBuilder), isA<JsonBool>());
      expect(nativeToAst(42, jsonBuilder), isA<JsonNumber>());
      expect(nativeToAst(3.14, jsonBuilder), isA<JsonNumber>());
      expect(nativeToAst('hi', jsonBuilder), isA<JsonString>());
    });
  });

  group('Encoder round-trip (encode → serialize → parse)', () {
    test('JSON object encoder', () {
      final encoder = toJsonObject<({String name, int age})>((b, v) {
        b.field('name', v.name, jsonStringEncoder);
        b.field('age', v.age, jsonIntEncoder);
      });
      final ast = encoder.encode((name: 'Alice', age: 30));
      final json = serializeJson(ast);
      expect(json, '{"name":"Alice","age":30}');
      expect(_json(json), ast);
    });

    test('TOML table encoder', () {
      final encoder = toTomlTable<({String host, int port})>((b, v) {
        b.field('host', v.host, tomlStringEncoder);
        b.field('port', v.port, tomlIntEncoder);
      });
      final ast = encoder.encode((host: 'localhost', port: 8080));
      expect(ast, isA<TomlTable>());
    });
  });

  // Item 4: YAML round-trip tests
  group('YAML round-trip', () {
    test('flat mapping', () {
      const ast = YamlMapping({
        'name': YamlString('Alice'),
        'age': YamlInteger(30),
      });
      final s = serializeYaml(ast);
      final reparsed = _yamlDoc('$s\n');
      expect(reparsed, ast);
    });

    test('block sequence', () {
      const ast = YamlSequence([
        YamlString('a'),
        YamlString('b'),
        YamlString('c'),
      ]);
      final s = serializeYaml(ast);
      final reparsed = _yamlDoc('$s\n');
      expect(reparsed, ast);
    });

    test('nested mapping round-trip', () {
      const ast = YamlMapping({
        'database': YamlMapping({
          'host': YamlString('localhost'),
          'port': YamlInteger(5432),
        }),
      });
      final s = serializeYaml(ast);
      final reparsed = _yamlDoc('$s\n');
      expect(reparsed, ast);
    });

    test('sequence of mappings round-trip', () {
      const ast = YamlMapping({
        'users': YamlSequence([
          YamlMapping({'name': YamlString('Alice'), 'age': YamlInteger(25)}),
          YamlMapping({'name': YamlString('Bob'), 'age': YamlInteger(30)}),
        ]),
      });
      final s = serializeYaml(ast);
      final reparsed = _yamlDoc('$s\n');
      expect(reparsed, ast);
    });

    test('deeply nested round-trip', () {
      const ast = YamlMapping({
        'a': YamlMapping({
          'b': YamlMapping({
            'c': YamlString('deep'),
          }),
        }),
      });
      final s = serializeYaml(ast);
      final reparsed = _yamlDoc('$s\n');
      expect(reparsed, ast);
    });

    test('mixed nesting round-trip', () {
      const ast = YamlMapping({
        'database': YamlMapping({
          'host': YamlString('localhost'),
          'ports': YamlSequence([YamlInteger(5432), YamlInteger(5433)]),
        }),
      });
      final s = serializeYaml(ast);
      final reparsed = _yamlDoc('$s\n');
      expect(reparsed, ast);
    });
  });

  // Item 5: Proto structural round-trip
  group('Proto structural round-trip', () {
    test('message', () {
      const ast = ProtoFile('proto3', [
        ProtoMessageDef('Person', [
          ProtoField(
            FieldRule.singular,
            ScalarType(ProtoScalar.string_),
            'name',
            1,
          ),
          ProtoField(
            FieldRule.singular,
            ScalarType(ProtoScalar.int32),
            'age',
            2,
          ),
        ]),
      ]);
      final serialized = serializeProto(ast);
      final reparsed = _protoFile(serialized);
      expect(reparsed, ast);
    });

    test('enum', () {
      const ast = ProtoFile('proto3', [
        ProtoEnumDef('Color', [
          ProtoEnumValue('RED', 0),
          ProtoEnumValue('GREEN', 1),
        ]),
      ]);
      final serialized = serializeProto(ast);
      final reparsed = _protoFile(serialized);
      expect(reparsed, ast);
    });
  });

  // Item 2: Expanded AstBuilder tests
  group('AstBuilder expanded', () {
    test('nested structure', () {
      final data = <String, Object?>{
        'users': <Object?>[
          <String, Object?>{'name': 'Alice', 'age': 30},
        ],
      };
      final ast = nativeToAst(data, jsonBuilder);
      final json = serializeJson(ast);
      final reparsed = _json(json);
      expect(reparsed, ast);
    });

    test('empty collections', () {
      expect(
        nativeToAst(<String, Object?>{}, jsonBuilder),
        const JsonObject({}),
      );
      expect(nativeToAst(<Object?>[], jsonBuilder), const JsonArray([]));
    });

    test('TOML builder null produces empty string', () {
      expect(nativeToAst(null, tomlBuilder), const TomlString(''));
    });

    test('unsupported type throws', () {
      expect(
        () => nativeToAst(DateTime.now(), jsonBuilder),
        throwsArgumentError,
      );
    });

    test('JSON native round-trip', () {
      final data = <String, Object?>{
        'a': 1,
        'b': <Object?>[true, null, 'hello'],
        'c': <String, Object?>{'d': 3.14},
      };
      final ast = nativeToAst(data, jsonBuilder);
      final native = jsonToNative(ast);
      expect(native, data);
    });

    test('YAML native round-trip', () {
      final data = <String, Object?>{
        'x': 42,
        'y': <Object?>[1, 2, 3],
      };
      final ast = nativeToAst(data, yamlBuilder);
      final native = yamlToNative(ast);
      expect(native, data);
    });
  });
}

YamlValue _yamlDoc(String input) {
  final r = parseYaml(input);
  return switch (r) {
    Success<ParseError, YamlDocument>(:final value) => value,
    Partial<ParseError, YamlDocument>(:final value) => value,
    Failure() => throw StateError('Parse failed: ${r.errors}'),
  };
}

Map<String, TomlValue> _tomlDoc(String input) {
  final r = parseToml(input);
  return switch (r) {
    Success<ParseError, TomlDocument>(:final value) => value,
    Partial<ParseError, TomlDocument>(:final value) => value,
    Failure() => throw StateError('Parse failed: ${r.errors}'),
  };
}

ProtoFile _protoFile(String input) {
  final r = parseProto(input);
  return switch (r) {
    Success<ParseError, ProtoFile>(:final value) => value,
    Partial<ParseError, ProtoFile>(:final value) => value,
    Failure() => throw StateError('Parse failed: ${r.errors}'),
  };
}
