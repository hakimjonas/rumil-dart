# rumil_codec

Binary codec library for Dart with ZigZag/Varint encoding, composable `BinaryCodec` instances, and product type composition via Dart 3 records.

## Usage

```dart
import 'package:rumil_codec/rumil_codec.dart';

// Primitive codecs
final bytes = intCodec.encode(42);     // ZigZag + LEB128 varint
final value = intCodec.decode(bytes);  // 42

// Compose for domain types
final personCodec = product2(stringCodec, intCodec).xmap(
  (r) => Person(r.$1, r.$2),
  (p) => (p.name, p.age),
);

// Composites
final listCodec = intCodec.list;          // BinaryCodec<List<int>>
final optCodec = stringCodec.nullable;    // BinaryCodec<String?>
```

For automatic derivation via `build_runner`, see [rumil_codec_builder](https://pub.dev/packages/rumil_codec_builder).

See the [main README](https://github.com/hakimjonas/rumil-dart) for full documentation.
