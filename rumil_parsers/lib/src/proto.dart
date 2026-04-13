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

final Parser<ParseError, String> _fullIdentifier = char('.').optional.flatMap(
  (dot) => _protoIdentifier
      .sepBy1(char('.'))
      .map((parts) => '${dot ?? ""}${parts.join(".")}'),
);

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
    .skipThen(
      string('repeated').as<FieldRule>(FieldRule.repeated) |
          string('optional').as<FieldRule>(FieldRule.optional) |
          string('required').as<FieldRule>(FieldRule.singular) |
          succeed<ParseError, FieldRule>(FieldRule.singular),
    )
    .flatMap(
      (rule) => _skip
          .skipThen(
            rule == FieldRule.repeated
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
                            .skipThen(
                              _balancedBrackets.optional,
                            ) // field options
                            .skipThen(_skip)
                            .skipThen(char(';'))
                            .skipThen(_skip)
                            .map(
                              (_) => ProtoField(rule, fieldType, name, number),
                            ),
                      ),
                ),
          ),
    );

// ---- Oneof ----

final Parser<ParseError, List<ProtoField>> _oneofDef = _skip
    .skipThen(string('oneof'))
    .skipThen(_skip)
    .skipThen(_protoIdentifier) // oneof name
    .skipThen(_skip)
    .skipThen(char('{'))
    .skipThen(_skip)
    .skipThen(
      (_field.map<ProtoField?>((f) => f) |
              _optionStatement.as<ProtoField?>(null))
          .many,
    ) // oneof fields + options
    .flatMap(
      (items) => _skip
          .skipThen(char('}'))
          .skipThen(_skip)
          .map((_) => items.whereType<ProtoField>().toList()),
    );

// ---- Extend blocks (consumed and discarded) ----

final Parser<ParseError, void> _extendDef = _skip
    .skipThen(string('extend'))
    .skipThen(_skip)
    .skipThen(_fullIdentifier)
    .skipThen(_skip)
    .skipThen(_balancedBraces)
    .skipThen(_skip)
    .as<void>(null);

// ---- Messages ----

/// Proto2 group: `repeated group Name = N { fields... }`
/// A group combines a field declaration with an inline message definition.
/// Parsed as a field whose type is a NamedType with the group's name.
final Parser<ParseError, ProtoField> _groupDef = _skip
    .skipThen(
      string('repeated').as<FieldRule>(FieldRule.repeated) |
          string('optional').as<FieldRule>(FieldRule.optional) |
          string('required').as<FieldRule>(FieldRule.singular) |
          succeed<ParseError, FieldRule>(FieldRule.singular),
    )
    .flatMap(
      (rule) => _skip
          .skipThen(string('group'))
          .skipThen(_skip)
          .skipThen(_protoIdentifier)
          .flatMap(
            (name) => _skip
                .skipThen(char('='))
                .skipThen(_skip)
                .skipThen(_protoInt)
                .flatMap(
                  (number) => _skip
                      .skipThen(_balancedBrackets.optional) // field options
                      .skipThen(_skip)
                      .skipThen(_balancedBraces) // group body (skip contents)
                      .skipThen(_skip)
                      .map(
                        (_) => ProtoField(
                          rule,
                          NamedType(name),
                          name.substring(0, 1).toLowerCase() +
                              name.substring(1),
                          number,
                        ),
                      ),
                ),
          ),
    );

/// A message body item: field, nested message, nested enum, oneof,
/// option, reserved, extensions, extend, group, or map entry.
Parser<ParseError, List<ProtoField>> _messageBodyItem() =>
    // Proto2 group (must be before _field — both start with repeated/optional)
    _groupDef.map((f) => [f]) |
    // Regular field
    _field.map((f) => [f]) |
    // Oneof: contributes its fields to the message
    _oneofDef |
    // Nested message (recursive) — contributes no fields to parent
    defer(() => _messageDef).as<List<ProtoField>>([]) |
    // Nested enum — contributes no fields
    _enumDef.as<List<ProtoField>>([]) |
    // Option/reserved/extensions/extend — skip
    _optionStatement.as<List<ProtoField>>([]) |
    _reservedStatement.as<List<ProtoField>>([]) |
    _extensionsStatement.as<List<ProtoField>>([]) |
    _extendDef.as<List<ProtoField>>([]);

final Parser<ParseError, ProtoDefinition> _messageDef = _skip
    .skipThen(string('local').skipThen(_skip).optional) // edition feature
    .skipThen(string('message'))
    .skipThen(_skip)
    .skipThen(_protoIdentifier)
    .flatMap(
      (name) => _skip
          .skipThen(char('{'))
          .skipThen(_skip)
          .skipThen(_messageBodyItem().many)
          .flatMap(
            (fieldGroups) => _skip
                .skipThen(char('}'))
                .skipThen(char(';').optional) // edition files may have };
                .skipThen(_skip)
                .map((_) {
                  final fields = fieldGroups.expand((g) => g).toList();
                  return ProtoMessageDef(name, fields) as ProtoDefinition;
                }),
          ),
    );

// ---- Enums ----

final Parser<ParseError, int> _protoInt = char('-').optional.flatMap(
  (neg) =>
  // Hex: 0x...
  (string('0x')
              .skipThen(
                satisfy(
                  (c) =>
                      (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
                      (c.compareTo('a') >= 0 && c.compareTo('f') <= 0) ||
                      (c.compareTo('A') >= 0 && c.compareTo('F') <= 0),
                  'hex digit',
                ).many1,
              )
              .map((ds) => int.parse(ds.join(), radix: 16)) |
          // Decimal
          digit().many1.map((ds) => int.parse(ds.join())))
      .map((v) => v * (neg != null ? -1 : 1)),
);

final Parser<ParseError, ProtoEnumValue> _enumValue = _skip
    .skipThen(_protoIdentifier)
    .flatMap(
      (name) => _skip
          .skipThen(char('='))
          .skipThen(_skip)
          .skipThen(_protoInt)
          .flatMap(
            (number) => _skip
                .skipThen(_balancedBrackets.optional) // enum value options
                .skipThen(_skip)
                .skipThen(char(';'))
                .skipThen(_skip)
                .map((_) => ProtoEnumValue(name, number)),
          ),
    );

/// Enum body item: value, option, or reserved.
Parser<ParseError, ProtoEnumValue?> _enumBodyItem() =>
    _enumValue.map<ProtoEnumValue?>((v) => v) |
    _optionStatement.as<ProtoEnumValue?>(null) |
    _reservedStatement.skipThen(_skip).as<ProtoEnumValue?>(null);

final Parser<ParseError, ProtoDefinition> _enumDef = _skip
    .skipThen(string('local').skipThen(_skip).optional) // edition feature
    .skipThen(string('enum'))
    .skipThen(_skip)
    .skipThen(_protoIdentifier)
    .flatMap(
      (name) => _skip
          .skipThen(char('{'))
          .skipThen(_skip)
          .skipThen(_enumBodyItem().many)
          .flatMap(
            (items) => _skip
                .skipThen(char('}'))
                .skipThen(char(';').optional) // edition files may have };
                .skipThen(_skip)
                .map(
                  (_) =>
                      ProtoEnumDef(
                            name,
                            items.whereType<ProtoEnumValue>().toList(),
                          )
                          as ProtoDefinition,
                ),
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
                                    (_balancedBraces |
                                        char(';').as<void>(null)),
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
          .skipThen(
            (_rpcMethod.map<ProtoMethod?>((m) => m) |
                    _optionStatement.as<ProtoMethod?>(null))
                .many,
          )
          .flatMap(
            (items) => _skip
                .skipThen(char('}'))
                .skipThen(_skip)
                .map(
                  (_) =>
                      ProtoServiceDef(
                            name,
                            items.whereType<ProtoMethod>().toList(),
                          )
                          as ProtoDefinition,
                ),
          ),
    );

// ---- Option statements (consumed and discarded) ----

/// Skip balanced braces `{ ... }` (for option aggregates, rpc bodies, etc.).
final Parser<ParseError, void> _balancedBraces = char('{')
    .skipThen(
      (char('{').notFollowedBy
                  .skipThen(char('}').notFollowedBy)
                  .skipThen(anyChar()) |
              defer(() => _balancedBraces).as<String>(''))
          .many,
    )
    .skipThen(char('}'))
    .as<void>(null);

/// Skip balanced brackets `[ ... ]` (for field options).
final Parser<ParseError, void> _balancedBrackets = char('[')
    .skipThen(
      (char('[').notFollowedBy
                  .skipThen(char(']').notFollowedBy)
                  .skipThen(anyChar()) |
              defer(() => _balancedBrackets).as<String>(''))
          .many,
    )
    .skipThen(char(']'))
    .as<void>(null);

/// Option statement: `option name = value;` — consumed and discarded.
final Parser<ParseError, void> _optionStatement = _skip
    .skipThen(string('option'))
    .skipThen(_skip)
    .skipThen(
      // Option name (may have parenthesized extension names and dotted suffixes)
      (char('(')
                  .skipThen(satisfy((c) => c != ')', 'opt char').many)
                  .skipThen(char(')')) |
              satisfy((c) => c != '=' && c != ';' && c != '\n', 'opt char'))
          .many1,
    )
    .skipThen(_skip)
    .skipThen(char('='))
    .skipThen(_skip)
    .skipThen(
      // Value: string, number, identifier, or aggregate { ... }
      (_balancedBraces |
              satisfy(
                (c) => c != ';' && c != '\n',
                'opt value char',
              ).many1.as<void>(null))
          .many1,
    )
    .skipThen(_skip)
    .skipThen(char(';'))
    .as<void>(null);

/// Reserved statement: `reserved 1, 2, 3;` or `reserved "name";`
final Parser<ParseError, void> _reservedStatement = _skip
    .skipThen(string('reserved'))
    .skipThen(_skip)
    .skipThen(satisfy((c) => c != ';', 'reserved char').many1)
    .skipThen(char(';'))
    .as<void>(null);

/// Extensions statement: `extensions 100 to max;` or with options on next line.
final Parser<ParseError, void> _extensionsStatement = _skip
    .skipThen(string('extensions'))
    .skipThen(_skip)
    .skipThen(
      (_balancedBrackets | satisfy((c) => c != ';' && c != '[', 'ext char'))
          .many1,
    )
    .skipThen(char(';'))
    .as<void>(null);

// ---- Top-level statements ----

final Parser<ParseError, String> _syntaxStatement = _skip
    .skipThen(string('syntax') | string('edition'))
    .skipThen(_skip)
    .skipThen(char('='))
    .skipThen(_skip)
    .skipThen(char('"'))
    .skipThen(
      satisfy((c) => c != '"', 'version char').many1.map((c) => c.join()),
    )
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
    .skipThen((string('public') | string('weak') | string('option')).optional)
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

/// Skip top-level option/extend/extensions statements (no AST node needed).
final Parser<ParseError, void> _topLevelSkip =
    _optionStatement |
    _extendDef |
    _extensionsStatement.skipThen(_skip) |
    _reservedStatement.skipThen(_skip);

final Parser<ParseError, ProtoDefinition> _definition =
    _packageStatement | _importStatement | _messageDef | _enumDef | _serviceDef;

/// A top-level item: either a definition (added to AST) or a skip (discarded).
final Parser<ParseError, ProtoDefinition?> _topLevelItem =
    _topLevelSkip.as<ProtoDefinition?>(null) |
    _definition.map<ProtoDefinition?>((d) => d);

final Parser<ParseError, ProtoFile> _protoFile = _skip
    .skipThen(_syntaxStatement.optional)
    .flatMap(
      (syntax) => _skip
          .skipThen(_topLevelItem.sepBy(_skip))
          .flatMap(
            (items) => _skip
                .skipThen(eof())
                .map(
                  (_) => ProtoFile(
                    syntax ?? 'proto3',
                    items.whereType<ProtoDefinition>().toList(),
                  ),
                ),
          ),
    );
