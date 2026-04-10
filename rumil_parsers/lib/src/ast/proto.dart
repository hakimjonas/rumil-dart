/// Protocol Buffers .proto schema AST types.
library;

/// Scalar field types.
enum ProtoScalar {
  /// 64-bit float.
  double_,

  /// 32-bit float.
  float_,

  /// Signed 32-bit integer.
  int32,

  /// Signed 64-bit integer.
  int64,

  /// Unsigned 32-bit integer.
  uint32,

  /// Unsigned 64-bit integer.
  uint64,

  /// ZigZag-encoded signed 32-bit integer.
  sint32,

  /// ZigZag-encoded signed 64-bit integer.
  sint64,

  /// Fixed-width 32-bit integer.
  fixed32,

  /// Fixed-width 64-bit integer.
  fixed64,

  /// Fixed-width signed 32-bit integer.
  sfixed32,

  /// Fixed-width signed 64-bit integer.
  sfixed64,

  /// Boolean.
  bool_,

  /// UTF-8 string.
  string_,

  /// Raw bytes.
  bytes,
}

/// A field type.
sealed class ProtoType {
  /// Base constructor.
  const ProtoType();
}

/// A scalar type (int32, string, bool, etc.).
final class ScalarType extends ProtoType {
  /// Which scalar type.
  final ProtoScalar scalar;

  /// Creates a scalar type.
  const ScalarType(this.scalar);
}

/// A reference to a message or enum type by name.
final class NamedType extends ProtoType {
  /// The fully qualified type name.
  final String name;

  /// Creates a named type reference.
  const NamedType(this.name);
}

/// A map field type.
final class MapType extends ProtoType {
  /// The key type (must be scalar).
  final ProtoType keyType;

  /// The value type.
  final ProtoType valueType;

  /// Creates a map type.
  const MapType(this.keyType, this.valueType);
}

/// A repeated (list) field type.
final class RepeatedType extends ProtoType {
  /// The element type.
  final ProtoType elementType;

  /// Creates a repeated type.
  const RepeatedType(this.elementType);
}

/// Field rule in proto3.
enum FieldRule {
  /// Default field (implicit presence).
  singular,

  /// Repeated (list) field.
  repeated,

  /// Explicitly optional field.
  optional,
}

/// A field definition.
class ProtoField {
  /// The field rule.
  final FieldRule rule;

  /// The field type.
  final ProtoType type;

  /// The field name.
  final String name;

  /// The field number (tag).
  final int number;

  /// Creates a field definition.
  const ProtoField(this.rule, this.type, this.name, this.number);
}

/// An enum value definition.
class ProtoEnumValue {
  /// The value name.
  final String name;

  /// The value number.
  final int number;

  /// Creates an enum value.
  const ProtoEnumValue(this.name, this.number);
}

/// An RPC method definition.
class ProtoMethod {
  /// The method name.
  final String name;

  /// The request message type.
  final String inputType;

  /// The response message type.
  final String outputType;

  /// Whether the request is a stream.
  final bool inputStreaming;

  /// Whether the response is a stream.
  final bool outputStreaming;

  /// Creates a method definition.
  const ProtoMethod(
    this.name,
    this.inputType,
    this.outputType, {
    this.inputStreaming = false,
    this.outputStreaming = false,
  });
}

/// A top-level .proto definition.
sealed class ProtoDefinition {
  /// Base constructor.
  const ProtoDefinition();
}

/// A message definition.
final class ProtoMessageDef extends ProtoDefinition {
  /// The message name.
  final String name;

  /// The message fields.
  final List<ProtoField> fields;

  /// Nested definitions (messages, enums).
  final List<ProtoDefinition> nested;

  /// Creates a message definition.
  const ProtoMessageDef(this.name, this.fields, [this.nested = const []]);
}

/// An enum definition.
final class ProtoEnumDef extends ProtoDefinition {
  /// The enum name.
  final String name;

  /// The enum values.
  final List<ProtoEnumValue> values;

  /// Creates an enum definition.
  const ProtoEnumDef(this.name, this.values);
}

/// A service definition.
final class ProtoServiceDef extends ProtoDefinition {
  /// The service name.
  final String name;

  /// The RPC methods.
  final List<ProtoMethod> methods;

  /// Creates a service definition.
  const ProtoServiceDef(this.name, this.methods);
}

/// An import statement.
final class ProtoImport extends ProtoDefinition {
  /// The imported file path.
  final String path;

  /// Whether this is a public import.
  final bool isPublic;

  /// Creates an import.
  const ProtoImport(this.path, {this.isPublic = false});
}

/// A package declaration.
final class ProtoPackage extends ProtoDefinition {
  /// The package name.
  final String name;

  /// Creates a package declaration.
  const ProtoPackage(this.name);
}

/// A parsed .proto file.
class ProtoFile {
  /// The syntax version (`proto2` or `proto3`).
  final String syntax;

  /// The top-level definitions.
  final List<ProtoDefinition> definitions;

  /// Creates a proto file.
  const ProtoFile(this.syntax, this.definitions);
}
