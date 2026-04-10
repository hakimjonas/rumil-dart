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

/// Target AST format for [AstSerializable].
enum AstFormat {
  /// Generate `AstEncoder<T, JsonValue>`.
  json,
  /// Generate `AstEncoder<T, YamlValue>`.
  yaml,
  /// Generate `AstEncoder<T, TomlValue>`.
  toml,
  /// Generate `AstEncoder<T, XmlNode>`.
  xml,
}

/// Marks a class for AST encoder code generation.
///
/// Generates typed `AstEncoder` implementations for the specified [formats].
/// Requires `rumil_codec_builder` as a dev dependency and `build_runner`
/// to generate the `.ast.g.dart` file.
class AstSerializable {
  /// Which AST formats to generate encoders for.
  final List<AstFormat> formats;

  /// Creates an AST serializable annotation.
  const AstSerializable({this.formats = const [AstFormat.json]});
}

/// Shorthand annotation for [AstSerializable] (JSON only).
const astSerializable = AstSerializable();
