/// Format parsers, serializers, and AST codecs built on Rumil.
library;

// AST types
export 'src/ast/hcl.dart';
export 'src/ast/json.dart';
export 'src/ast/proto.dart';
export 'src/ast/toml.dart';
export 'src/ast/xml.dart';
export 'src/ast/yaml.dart';

// Shared utilities
export 'src/common.dart';
export 'src/encode/escape.dart';

// Parsers
export 'src/csv.dart'
    show
        parseCsv,
        parseTsv,
        parseCsvWithHeaders,
        CsvConfig,
        CsvDocument,
        defaultCsvConfig,
        defaultTsvConfig;
export 'src/hcl.dart' show parseHcl;
export 'src/json.dart' show parseJson;
export 'src/proto.dart' show parseProto;
export 'src/toml.dart' show parseToml;
export 'src/xml.dart' show parseXml, parseXmlFragment;
export 'src/yaml.dart' show parseYaml;

// Decoders (AST → typed Dart)
export 'src/decode/decoder.dart';
export 'src/decode/json_decoders.dart';
export 'src/decode/native_decoders.dart';
export 'src/decode/toml_decoders.dart';
export 'src/decode/yaml_decoders.dart';

// Encoders (typed Dart → AST)
export 'src/encode/ast_builder.dart';
export 'src/encode/encoder.dart';
export 'src/encode/json_encoders.dart';
export 'src/encode/toml_encoders.dart';
export 'src/encode/xml_encoders.dart';
export 'src/encode/yaml_encoders.dart';

// Serializers (AST → string)
export 'src/encode/csv_encoders.dart';
export 'src/encode/hcl_encoders.dart';
export 'src/encode/proto_encoders.dart' show serializeProto;
