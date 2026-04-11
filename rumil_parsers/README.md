# rumil_parsers

Format parsers and serializers built on [Rumil](https://pub.dev/packages/rumil): JSON, CSV, XML, TOML, YAML, Proto3, and HCL.

Bidirectional: parse strings into typed ASTs, serialize ASTs back to strings. Includes AST decoders, encoders, native converters, and structural equality on all AST types.

## Usage

```dart
import 'package:rumil_parsers/rumil_parsers.dart';

// Parse
final json = parseJson('{"name": "Alice", "age": 30}');
final yaml = parseYaml('name: Alice\ntags:\n  - admin\n');
final hcl = parseHcl('resource "aws_instance" "web" { ami = "abc" }\n');

// Serialize
final s = serializeJson(json, config: JsonFormatConfig.pretty);

// Decode AST into typed Dart values
final decoder = fromJsonObject((obj) => (
  name: obj.field('name', jsonString),
  age: obj.field('age', jsonInt),
));

// Encode Dart values into AST
final encoder = toJsonObject<Person>((b, p) {
  b.field('name', p.name, jsonStringEncoder);
  b.field('age', p.age, jsonIntEncoder);
});
```

See the [main README](https://github.com/hakimjonas/rumil-dart) for full documentation.
