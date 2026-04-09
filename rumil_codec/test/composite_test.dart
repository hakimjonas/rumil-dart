import 'dart:typed_data';

import 'package:rumil_codec/rumil_codec.dart';
import 'package:test/test.dart';

void _roundTrip<A>(BinaryCodec<A> codec, A value) {
  final bytes = codec.encode(value);
  final decoded = codec.decode(bytes);
  expect(decoded, value);
}

void main() {
  group('listOf', () {
    test('empty list', () => _roundTrip(listOf(intCodec), <int>[]));
    test('int list', () => _roundTrip(listOf(intCodec), [1, 2, 3]));
    test(
      'string list',
      () => _roundTrip(listOf(stringCodec), ['a', 'bb', 'ccc']),
    );
    test('nested list', () {
      final codec = listOf(listOf(intCodec));
      _roundTrip(codec, [
        [1, 2],
        [3, 4, 5],
      ]);
    });
  });

  group('nullableOf', () {
    test('null value', () {
      final codec = nullableOf(intCodec);
      final bytes = codec.encode(null);
      expect(bytes, [0x00]);
      expect(codec.decode(bytes), null);
    });

    test('present value', () {
      final codec = nullableOf(intCodec);
      final bytes = codec.encode(42);
      expect(bytes[0], 0x01); // tag
      expect(codec.decode(bytes), 42);
    });

    test('nullable string', () {
      final codec = nullableOf(stringCodec);
      _roundTrip(codec, null);
      _roundTrip(codec, 'hello');
    });

    test('invalid tag throws', () {
      final codec = nullableOf(intCodec);
      expect(
        () => codec.decode(Uint8List.fromList([0x02])),
        throwsA(isA<InvalidTag>()),
      );
    });
  });

  group('mapOf', () {
    test('empty map', () {
      final codec = mapOf(stringCodec, intCodec);
      _roundTrip(codec, <String, int>{});
    });

    test('string-int map', () {
      final codec = mapOf(stringCodec, intCodec);
      _roundTrip(codec, {'a': 1, 'b': 2, 'c': 3});
    });
  });

  group('setOf', () {
    test('empty set', () => _roundTrip(setOf(intCodec), <int>{}));
    test('int set', () => _roundTrip(setOf(intCodec), {1, 2, 3}));
  });

  group('.list extension', () {
    test('works like listOf', () {
      _roundTrip(intCodec.list, [10, 20, 30]);
    });
  });

  group('.nullable extension', () {
    test('works like nullableOf', () {
      final codec = stringCodec.nullable;
      _roundTrip(codec, null);
      _roundTrip(codec, 'hello');
    });
  });

  group('xmap', () {
    test('transforms types', () {
      final codec = intCodec.xmap<String>((n) => n.toString(), int.parse);
      final bytes = codec.encode('42');
      expect(codec.decode(bytes), '42');
      // Wire format is still int
      expect(intCodec.decode(bytes), 42);
    });
  });

  group('product2', () {
    test('round-trips', () {
      final codec = product2(stringCodec, intCodec);
      _roundTrip(codec, ('Alice', 30));
    });

    test('xmap to domain type', () {
      final codec = product2(
        stringCodec,
        intCodec,
      ).xmap((r) => (name: r.$1, age: r.$2), (p) => (p.name, p.age));
      final bytes = codec.encode((name: 'Alice', age: 30));
      final decoded = codec.decode(bytes);
      expect(decoded.name, 'Alice');
      expect(decoded.age, 30);
    });
  });

  group('product3', () {
    test('round-trips', () {
      final codec = product3(stringCodec, intCodec, boolCodec);
      _roundTrip(codec, ('test', 42, true));
    });
  });

  group('product4', () {
    test('round-trips', () {
      final codec = product4(stringCodec, intCodec, doubleCodec, boolCodec);
      _roundTrip(codec, ('x', 1, 3.14, false));
    });
  });

  group('nested composites', () {
    test('list of nullable ints', () {
      final codec = listOf(nullableOf(intCodec));
      _roundTrip(codec, [1, null, 3, null, 5]);
    });

    test('product with list field', () {
      final codec = product2(stringCodec, listOf(intCodec));
      final bytes = codec.encode(('tags', [1, 2, 3]));
      final decoded = codec.decode(bytes);
      expect(decoded.$1, 'tags');
      expect(decoded.$2, [1, 2, 3]);
    });

    test('map of string to list', () {
      final codec = mapOf(stringCodec, listOf(intCodec));
      final bytes = codec.encode({
        'a': [1, 2],
        'b': [3, 4, 5],
      });
      final decoded = codec.decode(bytes);
      expect(decoded['a'], [1, 2]);
      expect(decoded['b'], [3, 4, 5]);
    });
  });
}
