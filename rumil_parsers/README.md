# rumil_parsers

Format parsers built on [Rumil](https://pub.dev/packages/rumil): JSON, CSV, XML, TOML, YAML, and Proto3.

Includes typed AST decoders for converting parsed values into Dart types via the `ObjectAccessor` pattern.

## Usage

```dart
import 'package:rumil_parsers/rumil_parsers.dart';

// Parse formats
final json = parseJson('{"name": "Alice", "age": 30}');
final csv = parseCsv('a,b,c\n1,2,3');
final toml = parseToml('[server]\nhost = "localhost"\nport = 8080\n');

// Decode into typed values
final decoder = fromJsonObject((obj) => (
  name: obj.field('name', jsonString),
  age: obj.field('age', jsonInt),
));
```

See the [main README](https://github.com/hakimjonas/rumil-dart) for full documentation.
