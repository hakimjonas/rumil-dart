/// Codec error types.
library;

/// An error encountered during binary decoding.
sealed class CodecException implements Exception {
  const CodecException();
}

final class UnexpectedEof extends CodecException {
  final int offset;
  const UnexpectedEof(this.offset);
  @override
  String toString() => 'Unexpected end of input at offset $offset';
}

final class VarintOverflow extends CodecException {
  final int offset;
  const VarintOverflow(this.offset);
  @override
  String toString() => 'Varint overflow at offset $offset';
}

final class InvalidBool extends CodecException {
  final int value;
  final int offset;
  const InvalidBool(this.value, this.offset);
  @override
  String toString() =>
      'Invalid boolean byte 0x${value.toRadixString(16)} at offset $offset';
}

final class InvalidTag extends CodecException {
  final int tag;
  final int offset;
  const InvalidTag(this.tag, this.offset);
  @override
  String toString() =>
      'Invalid tag byte 0x${tag.toRadixString(16)} at offset $offset';
}

final class InvalidOrdinal extends CodecException {
  final int ordinal;
  final int max;
  final int offset;
  const InvalidOrdinal(this.ordinal, this.max, this.offset);
  @override
  String toString() => 'Invalid ordinal $ordinal (max $max) at offset $offset';
}
