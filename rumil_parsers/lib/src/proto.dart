/// Protocol Buffers .proto file parser (proto3).
library;

import 'package:rumil/rumil.dart';

import 'ast/proto.dart';

/// Parse a .proto file from [input].
Result<ParseError, ProtoFile> parseProto(String input) => _protoFile.run(input);

// ---- Whitespace & comments ----

final Parser<ParseError, void> _ws1 = satisfy(
  (c) => c == ' ' || c == '\t' || c == '\r' || c == '\n',
  'whitespace',
).as<void>(null);

final Parser<ParseError, void> _lineComment = string('//')
    .skipThen(satisfy((c) => c != '\n', 'comment char').many)
    .skipThen(char('\n').as<void>(null) | eof())
    .as<void>(null);

final Parser<ParseError, void> _blockComment = string('/*')
    .skipThen((string('*/').notFollowedBy.skipThen(anyChar())).many)
    .skipThen(string('*/'))
    .as<void>(null);

final Parser<ParseError, void> _skip = (_ws1 | _lineComment | _blockComment)
    .many
    .as<void>(null);

// ---- Identifiers ----

final Parser<ParseError, String> _protoIdentifier = (letter() | char('_'))
    .zip((alphaNum() | char('_')).many)
    .map((pair) => pair.$1 + pair.$2.join());

final Parser<ParseError, String> _fullIdentifier = _protoIdentifier
    .sepBy1(char('.'))
    .map((parts) => parts.join('.'));

// ---- Types ----

final Parser<ParseError, ProtoType> _scalarType = keywords<ProtoType>({
  'double': const ScalarType(ProtoScalar.double_),
  'float': const ScalarType(ProtoScalar.float_),
  'int32': const ScalarType(ProtoScalar.int32),
  'int64': const ScalarType(ProtoScalar.int64),
  'uint32': const ScalarType(ProtoScalar.uint32),
  'uint64': const ScalarType(ProtoScalar.uint64),
  'sint32': const ScalarType(ProtoScalar.sint32),
  'sint64': const ScalarType(ProtoScalar.sint64),
  'fixed32': const ScalarType(ProtoScalar.fixed32),
  'fixed64': const ScalarType(ProtoScalar.fixed64),
  'sfixed32': const ScalarType(ProtoScalar.sfixed32),
  'sfixed64': const ScalarType(ProtoScalar.sfixed64),
  'bool': const ScalarType(ProtoScalar.bool_),
  'string': const ScalarType(ProtoScalar.string_),
  'bytes': const ScalarType(ProtoScalar.bytes),
});

final Parser<ParseError, ProtoType> _namedType = _fullIdentifier.map<ProtoType>(
  NamedType.new,
);

final Parser<ParseError, ProtoType> _mapType = string('map')
    .skipThen(_skip)
    .skipThen(char('<'))
    .skipThen(_skip)
    .skipThen(_scalarType)
    .flatMap(
      (keyType) => _skip
          .skipThen(char(','))
          .skipThen(_skip)
          .skipThen(defer(() => _protoType))
          .flatMap(
            (valueType) => _skip
                .skipThen(char('>'))
                .map((_) => MapType(keyType, valueType) as ProtoType),
          ),
    );

final Parser<ParseError, ProtoType> _protoType =
    _mapType | _scalarType | _namedType;

// ---- Fields ----

final Parser<ParseError, ProtoField> _field = _skip
    .skipThen(string('repeated').optional)
    .flatMap(
      (repeated) => _skip
          .skipThen(
            repeated != null
                ? _protoType.map<ProtoType>(RepeatedType.new)
                : _protoType,
          )
          .flatMap(
            (fieldType) => _skip
                .skipThen(_protoIdentifier)
                .flatMap(
                  (name) => _skip
                      .skipThen(char('='))
                      .skipThen(_skip)
                      .skipThen(digit().many1.map((ds) => int.parse(ds.join())))
                      .flatMap(
                        (number) => _skip
                            .skipThen(char(';'))
                            .skipThen(_skip)
                            .map(
                              (_) => ProtoField(
                                repeated != null
                                    ? FieldRule.repeated
                                    : FieldRule.singular,
                                fieldType,
                                name,
                                number,
                              ),
                            ),
                      ),
                ),
          ),
    );

// ---- Messages ----

final Parser<ParseError, ProtoDefinition> _messageDef = _skip
    .skipThen(string('message'))
    .skipThen(_skip)
    .skipThen(_protoIdentifier)
    .flatMap(
      (name) => _skip
          .skipThen(char('{'))
          .skipThen(_skip)
          .skipThen(_field.many)
          .flatMap(
            (fields) => _skip
                .skipThen(char('}'))
                .skipThen(_skip)
                .map((_) => ProtoMessageDef(name, fields) as ProtoDefinition),
          ),
    );

// ---- Enums ----

final Parser<ParseError, ProtoEnumValue> _enumValue = _skip
    .skipThen(_protoIdentifier)
    .flatMap(
      (name) => _skip
          .skipThen(char('='))
          .skipThen(_skip)
          .skipThen(digit().many1.map((ds) => int.parse(ds.join())))
          .flatMap(
            (number) => _skip
                .skipThen(char(';'))
                .skipThen(_skip)
                .map((_) => ProtoEnumValue(name, number)),
          ),
    );

final Parser<ParseError, ProtoDefinition> _enumDef = _skip
    .skipThen(string('enum'))
    .skipThen(_skip)
    .skipThen(_protoIdentifier)
    .flatMap(
      (name) => _skip
          .skipThen(char('{'))
          .skipThen(_skip)
          .skipThen(_enumValue.many)
          .flatMap(
            (values) => _skip
                .skipThen(char('}'))
                .skipThen(_skip)
                .map((_) => ProtoEnumDef(name, values) as ProtoDefinition),
          ),
    );

// ---- Services ----

final Parser<ParseError, ProtoMethod> _rpcMethod = _skip
    .skipThen(string('rpc'))
    .skipThen(_skip)
    .skipThen(_protoIdentifier)
    .flatMap(
      (name) => _skip
          .skipThen(char('('))
          .skipThen(_skip)
          .skipThen(string('stream').optional)
          .flatMap(
            (inStream) => _skip
                .skipThen(_fullIdentifier)
                .flatMap(
                  (inputType) => _skip
                      .skipThen(char(')'))
                      .skipThen(_skip)
                      .skipThen(string('returns'))
                      .skipThen(_skip)
                      .skipThen(char('('))
                      .skipThen(_skip)
                      .skipThen(string('stream').optional)
                      .flatMap(
                        (outStream) => _skip
                            .skipThen(_fullIdentifier)
                            .flatMap(
                              (outputType) => _skip
                                  .skipThen(char(')'))
                                  .skipThen(_skip)
                                  .skipThen(
                                    (char('{')
                                                .skipThen(_skip)
                                                .skipThen(char('}')) |
                                            char(';'))
                                        .as<void>(null),
                                  )
                                  .skipThen(_skip)
                                  .map(
                                    (_) => ProtoMethod(
                                      name,
                                      inputType,
                                      outputType,
                                      inputStreaming: inStream != null,
                                      outputStreaming: outStream != null,
                                    ),
                                  ),
                            ),
                      ),
                ),
          ),
    );

final Parser<ParseError, ProtoDefinition> _serviceDef = _skip
    .skipThen(string('service'))
    .skipThen(_skip)
    .skipThen(_protoIdentifier)
    .flatMap(
      (name) => _skip
          .skipThen(char('{'))
          .skipThen(_skip)
          .skipThen(_rpcMethod.many)
          .flatMap(
            (methods) => _skip
                .skipThen(char('}'))
                .skipThen(_skip)
                .map((_) => ProtoServiceDef(name, methods) as ProtoDefinition),
          ),
    );

// ---- Top-level statements ----

final Parser<ParseError, String> _syntaxStatement = _skip
    .skipThen(string('syntax'))
    .skipThen(_skip)
    .skipThen(char('='))
    .skipThen(_skip)
    .skipThen(char('"'))
    .skipThen(string('proto3') | string('proto2'))
    .flatMap(
      (version) => char(
        '"',
      ).skipThen(_skip).skipThen(char(';')).skipThen(_skip).map((_) => version),
    );

final Parser<ParseError, ProtoDefinition> _packageStatement = _skip
    .skipThen(string('package'))
    .skipThen(_skip)
    .skipThen(_fullIdentifier)
    .flatMap(
      (name) => _skip
          .skipThen(char(';'))
          .skipThen(_skip)
          .map((_) => ProtoPackage(name) as ProtoDefinition),
    );

final Parser<ParseError, ProtoDefinition> _importStatement = _skip
    .skipThen(string('import'))
    .skipThen(_skip)
    .skipThen(string('public').optional)
    .flatMap(
      (pub) => _skip
          .skipThen(char('"'))
          .skipThen(
            satisfy((c) => c != '"', 'path char').many.map((cs) => cs.join()),
          )
          .flatMap(
            (path) => char('"')
                .skipThen(_skip)
                .skipThen(char(';'))
                .skipThen(_skip)
                .map(
                  (_) =>
                      ProtoImport(path, isPublic: pub != null)
                          as ProtoDefinition,
                ),
          ),
    );

// ---- File ----

final Parser<ParseError, ProtoDefinition> _definition =
    _packageStatement | _importStatement | _messageDef | _enumDef | _serviceDef;

final Parser<ParseError, ProtoFile> _protoFile = _skip
    .skipThen(_syntaxStatement.optional)
    .flatMap(
      (syntax) => _skip
          .skipThen(_definition.sepBy(_skip))
          .flatMap(
            (defs) => _skip
                .skipThen(eof())
                .map((_) => ProtoFile(syntax ?? 'proto3', defs)),
          ),
    );
