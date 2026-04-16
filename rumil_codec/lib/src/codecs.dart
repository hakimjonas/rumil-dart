/// Primitive and composite codec instances.
///
/// **Wire compatibility note:** Product codecs encode fields in declaration
/// order. Changing field order breaks wire compatibility with previously
/// encoded data and with other language implementations (e.g. Scala Sarati).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'byte_reader.dart';
import 'byte_writer.dart';
import 'codec.dart';
import 'errors.dart';
import 'varint.dart';
import 'zigzag.dart';

// ---- Convenience extensions ----

/// Composite codec constructors as getters on [BinaryCodec].
extension BinaryCodecComposites<A> on BinaryCodec<A> {
  /// Codec for `List<A>` using this codec for elements.
  BinaryCodec<List<A>> get list => _ListCodec<A>(this);

  /// Codec for `A?` using this codec for the inner value.
  BinaryCodec<A?> get nullable => _NullableCodec<A>(this);
}

// ---- Primitive codecs ----

/// Signed 64-bit integer codec (ZigZag + LEB128 Varint).
const BinaryCodec<int> intCodec = _IntCodec();

/// 64-bit IEEE 754 double codec (big-endian).
const BinaryCodec<double> doubleCodec = _DoubleCodec();

/// Boolean codec (0x00 = false, 0x01 = true).
const BinaryCodec<bool> boolCodec = _BoolCodec();

/// UTF-8 string codec (Varint length prefix + UTF-8 bytes).
const BinaryCodec<String> stringCodec = _StringCodec();

/// Raw byte array codec (Varint length prefix + bytes).
const BinaryCodec<Uint8List> bytesCodec = _BytesCodec();

/// DateTime codec (microseconds since Unix epoch as ZigZag + Varint).
///
/// Preserves UTC/local distinction. Microsecond precision.
const BinaryCodec<DateTime> dateTimeCodec = _DateTimeCodec();

/// BigInt codec (sign byte + Varint length + big-endian magnitude bytes).
const BinaryCodec<BigInt> bigIntCodec = _BigIntCodec();

/// Codec for enum types. Maps each variant to a Varint ordinal.
///
/// ```dart
/// final colorCodec = enumCodec(Color.values);
/// colorCodec.encode(Color.red);   // [0x00]
/// colorCodec.encode(Color.green); // [0x02] (ZigZag-encoded 1)
/// ```
BinaryCodec<E> enumCodec<E extends Enum>(List<E> values) =>
    _EnumCodec<E>(values);

// ---- Composite constructors ----

/// Codec for `List<A>` (Varint count + elements).
BinaryCodec<List<A>> listOf<A>(BinaryCodec<A> element) =>
    _ListCodec<A>(element);

/// Codec for nullable `A?` (0x00 = null, 0x01 + value).
BinaryCodec<A?> nullableOf<A>(BinaryCodec<A> inner) => _NullableCodec<A>(inner);

/// Codec for `Map<K, V>` (Varint count + key/value pairs).
BinaryCodec<Map<K, V>> mapOf<K, V>(BinaryCodec<K> key, BinaryCodec<V> value) =>
    _MapCodec<K, V>(key, value);

/// Codec for `Set<A>` (Varint count + elements).
BinaryCodec<Set<A>> setOf<A>(BinaryCodec<A> element) => _SetCodec<A>(element);

// ---- Product codecs (Dart 3 records) ----

/// Codec for a 2-element product type.
BinaryCodec<(A, B)> product2<A, B>(BinaryCodec<A> a, BinaryCodec<B> b) =>
    _Product2Codec<A, B>(a, b);

/// Codec for a 3-element product type.
BinaryCodec<(A, B, C)> product3<A, B, C>(
  BinaryCodec<A> a,
  BinaryCodec<B> b,
  BinaryCodec<C> c,
) => _Product3Codec<A, B, C>(a, b, c);

/// Codec for a 4-element product type.
BinaryCodec<(A, B, C, D)> product4<A, B, C, D>(
  BinaryCodec<A> a,
  BinaryCodec<B> b,
  BinaryCodec<C> c,
  BinaryCodec<D> d,
) => _Product4Codec<A, B, C, D>(a, b, c, d);

/// Codec for a 5-element product type.
BinaryCodec<(A, B, C, D, E)> product5<A, B, C, D, E>(
  BinaryCodec<A> a,
  BinaryCodec<B> b,
  BinaryCodec<C> c,
  BinaryCodec<D> d,
  BinaryCodec<E> e,
) => _Product5Codec<A, B, C, D, E>(a, b, c, d, e);

/// Codec for a 6-element product type.
BinaryCodec<(A, B, C, D, E, F)> product6<A, B, C, D, E, F>(
  BinaryCodec<A> a,
  BinaryCodec<B> b,
  BinaryCodec<C> c,
  BinaryCodec<D> d,
  BinaryCodec<E> e,
  BinaryCodec<F> f,
) => _Product6Codec<A, B, C, D, E, F>(a, b, c, d, e, f);

// ---- Primitive implementations ----

final class _IntCodec implements BinaryCodec<int> {
  const _IntCodec();

  @override
  void write(ByteWriter writer, int value) =>
      Varint.write(writer, ZigZag.encode(value));

  @override
  int read(ByteReader reader) => ZigZag.decode(Varint.read(reader));
}

final class _DoubleCodec implements BinaryCodec<double> {
  const _DoubleCodec();

  @override
  void write(ByteWriter writer, double value) => writer.writeFloat64(value);

  @override
  double read(ByteReader reader) => reader.readFloat64();
}

final class _BoolCodec implements BinaryCodec<bool> {
  const _BoolCodec();

  @override
  void write(ByteWriter writer, bool value) => writer.writeByte(value ? 1 : 0);

  @override
  bool read(ByteReader reader) {
    final offset = reader.offset;
    final byte = reader.readByte();
    if (byte != 0 && byte != 1) throw InvalidBool(byte, offset);
    return byte == 1;
  }
}

final class _StringCodec implements BinaryCodec<String> {
  const _StringCodec();

  @override
  void write(ByteWriter writer, String value) {
    final bytes = utf8.encode(value);
    Varint.write(writer, bytes.length);
    writer.writeBytes(Uint8List.fromList(bytes));
  }

  @override
  String read(ByteReader reader) {
    final length = Varint.read(reader);
    final bytes = reader.readBytes(length);
    return utf8.decode(bytes);
  }
}

final class _BytesCodec implements BinaryCodec<Uint8List> {
  const _BytesCodec();

  @override
  void write(ByteWriter writer, Uint8List value) {
    Varint.write(writer, value.length);
    writer.writeBytes(value);
  }

  @override
  Uint8List read(ByteReader reader) {
    final length = Varint.read(reader);
    return reader.readBytes(length);
  }
}

final class _DateTimeCodec implements BinaryCodec<DateTime> {
  const _DateTimeCodec();

  @override
  void write(ByteWriter writer, DateTime value) {
    writer.writeByte(value.isUtc ? 1 : 0);
    Varint.write(writer, ZigZag.encode(value.microsecondsSinceEpoch));
  }

  @override
  DateTime read(ByteReader reader) {
    final offset = reader.offset;
    final utcFlag = reader.readByte();
    if (utcFlag != 0 && utcFlag != 1) throw InvalidTag(utcFlag, offset);
    final us = ZigZag.decode(Varint.read(reader));
    return utcFlag == 1
        ? DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true)
        : DateTime.fromMicrosecondsSinceEpoch(us);
  }
}

final class _BigIntCodec implements BinaryCodec<BigInt> {
  const _BigIntCodec();

  @override
  void write(ByteWriter writer, BigInt value) {
    if (value == BigInt.zero) {
      writer.writeByte(0);
      Varint.write(writer, 0);
      return;
    }
    writer.writeByte(value.isNegative ? 1 : 0);
    final mag = value.isNegative ? -value : value;
    final hex = mag.toRadixString(16);
    final padded = hex.length.isOdd ? '0$hex' : hex;
    final bytes = Uint8List(padded.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(padded.substring(i * 2, i * 2 + 2), radix: 16);
    }
    Varint.write(writer, bytes.length);
    writer.writeBytes(bytes);
  }

  @override
  BigInt read(ByteReader reader) {
    final offset = reader.offset;
    final sign = reader.readByte();
    if (sign != 0 && sign != 1) throw InvalidTag(sign, offset);
    final length = Varint.read(reader);
    if (length == 0) return BigInt.zero;
    final bytes = reader.readBytes(length);
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return sign == 1 ? -result : result;
  }
}

final class _EnumCodec<E extends Enum> implements BinaryCodec<E> {
  final List<E> _values;
  const _EnumCodec(this._values);

  @override
  void write(ByteWriter writer, E value) =>
      Varint.write(writer, ZigZag.encode(value.index));

  @override
  E read(ByteReader reader) {
    final offset = reader.offset;
    final index = ZigZag.decode(Varint.read(reader));
    if (index < 0 || index >= _values.length) {
      throw InvalidOrdinal(index, _values.length - 1, offset);
    }
    return _values[index];
  }
}

// ---- Composite implementations ----

final class _ListCodec<A> implements BinaryCodec<List<A>> {
  final BinaryCodec<A> _element;
  const _ListCodec(this._element);

  @override
  void write(ByteWriter writer, List<A> value) {
    Varint.write(writer, value.length);
    for (final item in value) {
      _element.write(writer, item);
    }
  }

  @override
  List<A> read(ByteReader reader) {
    final count = Varint.read(reader);
    return List<A>.generate(count, (_) => _element.read(reader));
  }
}

final class _NullableCodec<A> implements BinaryCodec<A?> {
  final BinaryCodec<A> _inner;
  const _NullableCodec(this._inner);

  @override
  void write(ByteWriter writer, A? value) {
    if (value == null) {
      writer.writeByte(0);
    } else {
      writer.writeByte(1);
      _inner.write(writer, value);
    }
  }

  @override
  A? read(ByteReader reader) {
    final offset = reader.offset;
    final tag = reader.readByte();
    return switch (tag) {
      0 => null,
      1 => _inner.read(reader),
      _ => throw InvalidTag(tag, offset),
    };
  }
}

final class _MapCodec<K, V> implements BinaryCodec<Map<K, V>> {
  final BinaryCodec<K> _key;
  final BinaryCodec<V> _value;
  const _MapCodec(this._key, this._value);

  @override
  void write(ByteWriter writer, Map<K, V> value) {
    Varint.write(writer, value.length);
    for (final MapEntry(:key, :value) in value.entries) {
      _key.write(writer, key);
      _value.write(writer, value);
    }
  }

  @override
  Map<K, V> read(ByteReader reader) {
    final count = Varint.read(reader);
    return Map<K, V>.fromEntries(
      List.generate(
        count,
        (_) => MapEntry(_key.read(reader), _value.read(reader)),
      ),
    );
  }
}

final class _SetCodec<A> implements BinaryCodec<Set<A>> {
  final BinaryCodec<A> _element;
  const _SetCodec(this._element);

  @override
  void write(ByteWriter writer, Set<A> value) {
    Varint.write(writer, value.length);
    for (final item in value) {
      _element.write(writer, item);
    }
  }

  @override
  Set<A> read(ByteReader reader) {
    final count = Varint.read(reader);
    return Set<A>.of(List.generate(count, (_) => _element.read(reader)));
  }
}

// ---- Product implementations ----

final class _Product2Codec<A, B> implements BinaryCodec<(A, B)> {
  final BinaryCodec<A> _a;
  final BinaryCodec<B> _b;
  const _Product2Codec(this._a, this._b);

  @override
  void write(ByteWriter writer, (A, B) value) {
    _a.write(writer, value.$1);
    _b.write(writer, value.$2);
  }

  @override
  (A, B) read(ByteReader reader) => (_a.read(reader), _b.read(reader));
}

final class _Product3Codec<A, B, C> implements BinaryCodec<(A, B, C)> {
  final BinaryCodec<A> _a;
  final BinaryCodec<B> _b;
  final BinaryCodec<C> _c;
  const _Product3Codec(this._a, this._b, this._c);

  @override
  void write(ByteWriter writer, (A, B, C) value) {
    _a.write(writer, value.$1);
    _b.write(writer, value.$2);
    _c.write(writer, value.$3);
  }

  @override
  (A, B, C) read(ByteReader reader) => (
    _a.read(reader),
    _b.read(reader),
    _c.read(reader),
  );
}

final class _Product4Codec<A, B, C, D> implements BinaryCodec<(A, B, C, D)> {
  final BinaryCodec<A> _a;
  final BinaryCodec<B> _b;
  final BinaryCodec<C> _c;
  final BinaryCodec<D> _d;
  const _Product4Codec(this._a, this._b, this._c, this._d);

  @override
  void write(ByteWriter writer, (A, B, C, D) value) {
    _a.write(writer, value.$1);
    _b.write(writer, value.$2);
    _c.write(writer, value.$3);
    _d.write(writer, value.$4);
  }

  @override
  (A, B, C, D) read(ByteReader reader) => (
    _a.read(reader),
    _b.read(reader),
    _c.read(reader),
    _d.read(reader),
  );
}

final class _Product5Codec<A, B, C, D, E>
    implements BinaryCodec<(A, B, C, D, E)> {
  final BinaryCodec<A> _a;
  final BinaryCodec<B> _b;
  final BinaryCodec<C> _c;
  final BinaryCodec<D> _d;
  final BinaryCodec<E> _e;
  const _Product5Codec(this._a, this._b, this._c, this._d, this._e);

  @override
  void write(ByteWriter writer, (A, B, C, D, E) value) {
    _a.write(writer, value.$1);
    _b.write(writer, value.$2);
    _c.write(writer, value.$3);
    _d.write(writer, value.$4);
    _e.write(writer, value.$5);
  }

  @override
  (A, B, C, D, E) read(ByteReader reader) => (
    _a.read(reader),
    _b.read(reader),
    _c.read(reader),
    _d.read(reader),
    _e.read(reader),
  );
}

final class _Product6Codec<A, B, C, D, E, F>
    implements BinaryCodec<(A, B, C, D, E, F)> {
  final BinaryCodec<A> _a;
  final BinaryCodec<B> _b;
  final BinaryCodec<C> _c;
  final BinaryCodec<D> _d;
  final BinaryCodec<E> _e;
  final BinaryCodec<F> _f;
  const _Product6Codec(this._a, this._b, this._c, this._d, this._e, this._f);

  @override
  void write(ByteWriter writer, (A, B, C, D, E, F) value) {
    _a.write(writer, value.$1);
    _b.write(writer, value.$2);
    _c.write(writer, value.$3);
    _d.write(writer, value.$4);
    _e.write(writer, value.$5);
    _f.write(writer, value.$6);
  }

  @override
  (A, B, C, D, E, F) read(ByteReader reader) => (
    _a.read(reader),
    _b.read(reader),
    _c.read(reader),
    _d.read(reader),
    _e.read(reader),
    _f.read(reader),
  );
}
