# rumil_codec_builder

Code generator for [rumil_codec](https://pub.dev/packages/rumil_codec): derives `BinaryCodec` and `AstEncoder` implementations for annotated classes and sealed class hierarchies.

## Setup

Add to `pubspec.yaml`:
```yaml
dependencies:
  rumil_codec: ^0.3.0

dev_dependencies:
  rumil_codec_builder: ^0.3.0
  build_runner: ^2.4.0
```

## Binary codec generation

```dart
import 'package:rumil_codec/rumil_codec.dart';

part 'person.codec.g.dart';

@binarySerializable
class Person {
  final String name;
  final int age;
  const Person(this.name, this.age);
}

// Generates: const personCodec = _$PersonCodec();
```

Sealed class hierarchies generate ordinal-dispatched codecs with exhaustive `switch`.

## AST encoder generation

```dart
import 'package:rumil_codec/rumil_codec.dart';
import 'package:rumil_parsers/rumil_parsers.dart';

part 'person.ast.g.dart';

@astSerializable
class Person {
  final String name;
  final int age;
  const Person(this.name, this.age);
}

// Generates: const personJsonEncoder = _$PersonJsonEncoder();
// Encodes Person to JsonObject with field-by-field encoding.
```

Run with: `dart run build_runner build`

See the [main README](https://github.com/hakimjonas/rumil-dart) for full documentation.
