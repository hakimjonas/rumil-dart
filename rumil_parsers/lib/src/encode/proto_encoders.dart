/// Serializer for writing Proto3 AST back to .proto text format.
library;

import '../ast/proto.dart';

/// Serialize a [ProtoFile] to .proto text.
String serializeProto(ProtoFile file) {
  final sb = StringBuffer();
  sb.writeln('syntax = "${file.syntax}";');
  for (final def in file.definitions) {
    sb.writeln('');
    _serializeDefinition(sb, def, 0);
  }
  return sb.toString();
}

void _serializeDefinition(StringBuffer sb, ProtoDefinition def, int depth) {
  final pad = '  ' * depth;
  switch (def) {
    case ProtoPackage(:final name):
      sb.writeln('${pad}package $name;');
    case ProtoImport(:final path, :final isPublic):
      sb.writeln('${pad}import ${isPublic ? 'public ' : ''}"$path";');
    case ProtoMessageDef(:final name, :final fields, :final nested):
      sb.writeln('${pad}message $name {');
      for (final field in fields) {
        _serializeField(sb, field, depth + 1);
      }
      for (final n in nested) {
        sb.writeln('');
        _serializeDefinition(sb, n, depth + 1);
      }
      sb.writeln('$pad}');
    case ProtoEnumDef(:final name, :final values):
      sb.writeln('${pad}enum $name {');
      for (final v in values) {
        sb.writeln('$pad  ${v.name} = ${v.number};');
      }
      sb.writeln('$pad}');
    case ProtoServiceDef(:final name, :final methods):
      sb.writeln('${pad}service $name {');
      for (final m in methods) {
        _serializeMethod(sb, m, depth + 1);
      }
      sb.writeln('$pad}');
  }
}

void _serializeField(StringBuffer sb, ProtoField field, int depth) {
  final pad = '  ' * depth;
  final prefix = switch (field.rule) {
    FieldRule.repeated => 'repeated ',
    FieldRule.optional => 'optional ',
    FieldRule.singular => '',
  };
  final type =
      field.rule == FieldRule.repeated
          ? _serializeType((field.type as RepeatedType).elementType)
          : _serializeType(field.type);
  sb.writeln('$pad$prefix$type ${field.name} = ${field.number};');
}

String _serializeType(ProtoType type) => switch (type) {
  ScalarType(:final scalar) => switch (scalar) {
    ProtoScalar.double_ => 'double',
    ProtoScalar.float_ => 'float',
    ProtoScalar.int32 => 'int32',
    ProtoScalar.int64 => 'int64',
    ProtoScalar.uint32 => 'uint32',
    ProtoScalar.uint64 => 'uint64',
    ProtoScalar.sint32 => 'sint32',
    ProtoScalar.sint64 => 'sint64',
    ProtoScalar.fixed32 => 'fixed32',
    ProtoScalar.fixed64 => 'fixed64',
    ProtoScalar.sfixed32 => 'sfixed32',
    ProtoScalar.sfixed64 => 'sfixed64',
    ProtoScalar.bool_ => 'bool',
    ProtoScalar.string_ => 'string',
    ProtoScalar.bytes => 'bytes',
  },
  NamedType(:final name) => name,
  MapType(:final keyType, :final valueType) =>
    'map<${_serializeType(keyType)}, ${_serializeType(valueType)}>',
  RepeatedType(:final elementType) => _serializeType(elementType),
};

void _serializeMethod(StringBuffer sb, ProtoMethod method, int depth) {
  final pad = '  ' * depth;
  final inStream = method.inputStreaming ? 'stream ' : '';
  final outStream = method.outputStreaming ? 'stream ' : '';
  sb.writeln(
    '${pad}rpc ${method.name} ($inStream${method.inputType}) '
    'returns ($outStream${method.outputType});',
  );
}
