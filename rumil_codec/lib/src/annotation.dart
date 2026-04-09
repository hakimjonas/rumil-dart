/// Annotation for automatic BinaryCodec generation.
library;

/// Marks a class or sealed class for BinaryCodec code generation.
///
/// For classes, generates a codec that encodes fields in declaration order.
/// For sealed classes, generates ordinal-dispatched codecs over subtypes.
///
/// Requires `rumil_codec_builder` as a dev dependency and `build_runner`
/// to generate the `.codec.g.dart` file.
class BinarySerializable {
  const BinarySerializable();
}

/// Shorthand annotation for [BinarySerializable].
const binarySerializable = BinarySerializable();
