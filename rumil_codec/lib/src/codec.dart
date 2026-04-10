/// BinaryCodec interfaces and extensions.
library;

import 'dart:typed_data';

import 'byte_reader.dart';
import 'byte_writer.dart';

/// Encodes values of type [A] to bytes.
abstract interface class Encoder<A> {
  /// Write [value] to [writer].
  void write(ByteWriter writer, A value);
}

/// Decodes values of type [A] from bytes.
abstract interface class Decoder<A> {
  /// Read a value from [reader].
  A read(ByteReader reader);
}

/// Bidirectional binary codec for type [A].
abstract interface class BinaryCodec<A> implements Encoder<A>, Decoder<A> {}

/// Convenience methods on [BinaryCodec].
extension BinaryCodecExt<A> on BinaryCodec<A> {
  /// Encode [value] to a byte array.
  Uint8List encode(A value) {
    final writer = ByteWriter();
    write(writer, value);
    return writer.toBytes();
  }

  /// Decode a value from [bytes].
  A decode(Uint8List bytes) {
    final reader = ByteReader(bytes);
    return read(reader);
  }

  /// Transform the encoded type via an isomorphism.
  BinaryCodec<B> xmap<B>(B Function(A) from, A Function(B) to) =>
      _XmapCodec<A, B>(this, from, to);
}

/// Functor map on [Decoder].
extension DecoderMap<A> on Decoder<A> {
  /// Transform the decoded value.
  Decoder<B> map<B>(B Function(A) f) => _MappedDecoder<A, B>(this, f);
}

/// Contravariant map on [Encoder].
extension EncoderContramap<A> on Encoder<A> {
  /// Adapt the encoder to accept a different input type.
  Encoder<B> contramap<B>(A Function(B) f) =>
      _ContramappedEncoder<A, B>(this, f);
}

// ---- Internal implementations ----

final class _XmapCodec<A, B> implements BinaryCodec<B> {
  final BinaryCodec<A> _inner;
  final B Function(A) _from;
  final A Function(B) _to;

  const _XmapCodec(this._inner, this._from, this._to);

  @override
  void write(ByteWriter writer, B value) => _inner.write(writer, _to(value));

  @override
  B read(ByteReader reader) => _from(_inner.read(reader));
}

final class _MappedDecoder<A, B> implements Decoder<B> {
  final Decoder<A> _inner;
  final B Function(A) _f;

  const _MappedDecoder(this._inner, this._f);

  @override
  B read(ByteReader reader) => _f(_inner.read(reader));
}

final class _ContramappedEncoder<A, B> implements Encoder<B> {
  final Encoder<A> _inner;
  final A Function(B) _f;

  const _ContramappedEncoder(this._inner, this._f);

  @override
  void write(ByteWriter writer, B value) => _inner.write(writer, _f(value));
}
