import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

void main() {
  // ---- JSON decoders ----

  group('JSON primitive decoders', () {
    test('int', () => expect(jsonInt.decode(const JsonNumber(42)), 42));
    test(
      'double',
      () => expect(jsonDouble.decode(const JsonNumber(3.14)), 3.14),
    );
    test(
      'string',
      () => expect(jsonString.decode(const JsonString('hello')), 'hello'),
    );
    test(
      'bool true',
      () => expect(jsonBool.decode(const JsonBool(true)), true),
    );
    test(
      'bool false',
      () => expect(jsonBool.decode(const JsonBool(false)), false),
    );
    test(
      'type mismatch throws',
      () => expect(
        () => jsonInt.decode(const JsonString('x')),
        throwsA(isA<DecodeException>()),
      ),
    );
  });

  group('JSON composite decoders', () {
    test('list of int', () {
      final decoder = jsonListOf(jsonInt);
      const value = JsonArray([JsonNumber(1), JsonNumber(2), JsonNumber(3)]);
      expect(decoder.decode(value), [1, 2, 3]);
    });

    test('nullable present', () {
      final decoder = jsonNullableOf(jsonInt);
      expect(decoder.decode(const JsonNumber(42)), 42);
    });

    test('nullable absent', () {
      final decoder = jsonNullableOf(jsonInt);
      expect(decoder.decode(const JsonNull()), null);
    });

    test('map of string to int', () {
      final decoder = jsonMapOf(jsonInt);
      const value = JsonObject({'a': JsonNumber(1), 'b': JsonNumber(2)});
      expect(decoder.decode(value), {'a': 1, 'b': 2});
    });
  });

  group('JSON object decoder', () {
    test('decode fields', () {
      final decoder = fromJsonObject(
        (obj) => (
          name: obj.field('name', jsonString),
          age: obj.field('age', jsonInt),
        ),
      );

      const value = JsonObject({
        'name': JsonString('Alice'),
        'age': JsonNumber(30),
      });

      final result = decoder.decode(value);
      expect(result.name, 'Alice');
      expect(result.age, 30);
    });

    test('optional field present', () {
      final decoder = fromJsonObject(
        (obj) => (
          name: obj.field('name', jsonString),
          email: obj.optionalField('email', jsonString),
        ),
      );

      const value = JsonObject({
        'name': JsonString('Alice'),
        'email': JsonString('alice@example.com'),
      });

      expect(decoder.decode(value).email, 'alice@example.com');
    });

    test('optional field absent', () {
      final decoder = fromJsonObject(
        (obj) => (
          name: obj.field('name', jsonString),
          email: obj.optionalField('email', jsonString),
        ),
      );

      const value = JsonObject({'name': JsonString('Alice')});
      expect(decoder.decode(value).email, null);
    });

    test('missing required field throws', () {
      final decoder = fromJsonObject((obj) => obj.field('name', jsonString));
      expect(
        () => decoder.decode(const JsonObject({})),
        throwsA(isA<DecodeException>()),
      );
    });

    test('nested object', () {
      final addressDecoder = fromJsonObject(
        (obj) => (
          city: obj.field('city', jsonString),
          zip: obj.field('zip', jsonString),
        ),
      );

      final personDecoder = fromJsonObject(
        (obj) => (
          name: obj.field('name', jsonString),
          address: obj.field('address', addressDecoder),
        ),
      );

      const value = JsonObject({
        'name': JsonString('Alice'),
        'address': JsonObject({
          'city': JsonString('NYC'),
          'zip': JsonString('10001'),
        }),
      });

      final result = personDecoder.decode(value);
      expect(result.name, 'Alice');
      expect(result.address.city, 'NYC');
    });
  });

  group('JSON decoder map', () {
    test('map transforms result', () {
      final decoder = jsonInt.map((n) => n * 2);
      expect(decoder.decode(const JsonNumber(21)), 42);
    });
  });

  // ---- TOML decoders ----

  group('TOML decoders', () {
    test('int', () => expect(tomlInt.decode(const TomlInteger(42)), 42));
    test(
      'double',
      () => expect(tomlDouble.decode(const TomlFloat(3.14)), 3.14),
    );
    test(
      'double from int',
      () => expect(tomlDouble.decode(const TomlInteger(5)), 5.0),
    );
    test(
      'string',
      () => expect(tomlString.decode(const TomlString('hello')), 'hello'),
    );
    test('bool', () => expect(tomlBool.decode(const TomlBool(true)), true));

    test('datetime', () {
      final dt = DateTime.utc(2024, 1, 15, 10, 30);
      expect(tomlDateTime.decode(TomlDateTime(dt)), dt);
    });

    test('list', () {
      final decoder = tomlListOf(tomlInt);
      const value = TomlArray([TomlInteger(1), TomlInteger(2)]);
      expect(decoder.decode(value), [1, 2]);
    });

    test('table decoder', () {
      final decoder = fromTomlTable(
        (obj) => (
          host: obj.field('host', tomlString),
          port: obj.field('port', tomlInt),
        ),
      );

      const value = TomlTable({
        'host': TomlString('localhost'),
        'port': TomlInteger(8080),
      });

      final result = decoder.decode(value);
      expect(result.host, 'localhost');
      expect(result.port, 8080);
    });
  });

  // ---- YAML decoders ----

  group('YAML decoders', () {
    test('int', () => expect(yamlInt.decode(const YamlInteger(42)), 42));
    test(
      'double',
      () => expect(yamlDouble.decode(const YamlFloat(3.14)), 3.14),
    );
    test(
      'double from int',
      () => expect(yamlDouble.decode(const YamlInteger(5)), 5.0),
    );
    test(
      'string',
      () => expect(yamlString.decode(const YamlString('hello')), 'hello'),
    );
    test('bool', () => expect(yamlBool.decode(const YamlBool(true)), true));

    test('nullable null', () {
      expect(yamlNullableOf(yamlInt).decode(const YamlNull()), null);
    });

    test('nullable present', () {
      expect(yamlNullableOf(yamlInt).decode(const YamlInteger(42)), 42);
    });

    test('list', () {
      final decoder = yamlListOf(yamlString);
      const value = YamlSequence([YamlString('a'), YamlString('b')]);
      expect(decoder.decode(value), ['a', 'b']);
    });

    test('map', () {
      final decoder = yamlMapOf(yamlInt);
      const value = YamlMapping({'x': YamlInteger(1), 'y': YamlInteger(2)});
      expect(decoder.decode(value), {'x': 1, 'y': 2});
    });

    test('mapping decoder', () {
      final decoder = fromYamlMapping(
        (obj) => (
          name: obj.field('name', yamlString),
          age: obj.field('age', yamlInt),
        ),
      );

      const value = YamlMapping({
        'name': YamlString('Alice'),
        'age': YamlInteger(30),
      });

      final result = decoder.decode(value);
      expect(result.name, 'Alice');
      expect(result.age, 30);
    });
  });
}
