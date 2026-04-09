# rumil_codec_builder

Code generator for [rumil_codec](https://pub.dev/packages/rumil_codec): derives `BinaryCodec` implementations for annotated classes and sealed class hierarchies.

## Setup

Add to `pubspec.yaml`:
```yaml
dependencies:
  rumil_codec: ^0.1.0

dev_dependencies:
  rumil_codec_builder: ^0.1.0
  build_runner: ^2.4.0
```

## Usage

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

Sealed class hierarchies generate ordinal-dispatched codecs with exhaustive `switch`:

```dart
@binarySerializable
sealed class Shape {}
final class Circle extends Shape { final double radius; ... }
final class Rectangle extends Shape { final double width, height; ... }

// Generates: const shapeCodec = _$ShapeCodec();
// Circle = ordinal 0, Rectangle = ordinal 1
```

Run with: `dart run build_runner build`

See the [main README](https://github.com/hakimjonas/rumil-dart) for full documentation.
