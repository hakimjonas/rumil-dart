/// Protocol Buffers .proto schema AST types.
library;

/// Scalar field types.
enum ProtoScalar {
  double_,
  float_,
  int32,
  int64,
  uint32,
  uint64,
  sint32,
  sint64,
  fixed32,
  fixed64,
  sfixed32,
  sfixed64,
  bool_,
  string_,
  bytes,
}

/// A field type.
sealed class ProtoType {
  const ProtoType();
}

final class ScalarType extends ProtoType {
  final ProtoScalar scalar;
  const ScalarType(this.scalar);
}

final class NamedType extends ProtoType {
  final String name;
  const NamedType(this.name);
}

final class MapType extends ProtoType {
  final ProtoType keyType;
  final ProtoType valueType;
  const MapType(this.keyType, this.valueType);
}

final class RepeatedType extends ProtoType {
  final ProtoType elementType;
  const RepeatedType(this.elementType);
}

/// Field rule in proto3.
enum FieldRule { singular, repeated, optional }

/// A field definition.
class ProtoField {
  final FieldRule rule;
  final ProtoType type;
  final String name;
  final int number;

  const ProtoField(this.rule, this.type, this.name, this.number);
}

/// An enum value definition.
class ProtoEnumValue {
  final String name;
  final int number;

  const ProtoEnumValue(this.name, this.number);
}

/// An RPC method definition.
class ProtoMethod {
  final String name;
  final String inputType;
  final String outputType;
  final bool inputStreaming;
  final bool outputStreaming;

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
  const ProtoDefinition();
}

final class ProtoMessageDef extends ProtoDefinition {
  final String name;
  final List<ProtoField> fields;
  final List<ProtoDefinition> nested;
  const ProtoMessageDef(this.name, this.fields, [this.nested = const []]);
}

final class ProtoEnumDef extends ProtoDefinition {
  final String name;
  final List<ProtoEnumValue> values;
  const ProtoEnumDef(this.name, this.values);
}

final class ProtoServiceDef extends ProtoDefinition {
  final String name;
  final List<ProtoMethod> methods;
  const ProtoServiceDef(this.name, this.methods);
}

final class ProtoImport extends ProtoDefinition {
  final String path;
  final bool isPublic;
  const ProtoImport(this.path, {this.isPublic = false});
}

final class ProtoPackage extends ProtoDefinition {
  final String name;
  const ProtoPackage(this.name);
}

/// A parsed .proto file.
class ProtoFile {
  final String syntax;
  final List<ProtoDefinition> definitions;
  const ProtoFile(this.syntax, this.definitions);
}
