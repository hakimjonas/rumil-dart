/// Codec error types.
library;

/// An error encountered during binary decoding.
sealed class CodecException implements Exception {
  /// Base constructor.
  const CodecException();
}

/// Input ended before the expected data could be read.
final class UnexpectedEof extends CodecException {
  /// Byte offset where the read was attempted.
  final int offset;

  /// Creates an unexpected-EOF error at [offset].
  const UnexpectedEof(this.offset);

  @override
  String toString() => 'Unexpected end of input at offset $offset';
}

/// A varint exceeded the maximum 64-bit size.
final class VarintOverflow extends CodecException {
  /// Byte offset where the overflow occurred.
  final int offset;

  /// Creates a varint-overflow error at [offset].
  const VarintOverflow(this.offset);

  @override
  String toString() => 'Varint overflow at offset $offset';
}

/// A boolean byte was not 0x00 or 0x01.
final class InvalidBool extends CodecException {
  /// The invalid byte value.
  final int value;

  /// Byte offset of the invalid byte.
  final int offset;

  /// Creates an invalid-bool error.
  const InvalidBool(this.value, this.offset);

  @override
  String toString() =>
      'Invalid boolean byte 0x${value.toRadixString(16)} at offset $offset';
}

/// A nullable/option tag byte was not 0x00 or 0x01.
final class InvalidTag extends CodecException {
  /// The invalid tag value.
  final int tag;

  /// Byte offset of the invalid tag.
  final int offset;

  /// Creates an invalid-tag error.
  const InvalidTag(this.tag, this.offset);

  @override
  String toString() =>
      'Invalid tag byte 0x${tag.toRadixString(16)} at offset $offset';
}

/// A sum type ordinal was out of range.
final class InvalidOrdinal extends CodecException {
  /// The ordinal that was read.
  final int ordinal;

  /// The maximum valid ordinal.
  final int max;

  /// Byte offset where the ordinal was read.
  final int offset;

  /// Creates an invalid-ordinal error.
  const InvalidOrdinal(this.ordinal, this.max, this.offset);

  @override
  String toString() => 'Invalid ordinal $ordinal (max $max) at offset $offset';
}
