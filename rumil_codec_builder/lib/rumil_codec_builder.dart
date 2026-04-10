/// Builder factories for build_runner integration.
library;

import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/ast_encoder_generator.dart';
import 'src/codec_generator.dart';

/// Generates `.codec.g.dart` for `@binarySerializable` classes.
Builder codecBuilder(BuilderOptions options) =>
    PartBuilder([const CodecGenerator()], '.codec.g.dart');

/// Generates `.ast.g.dart` for `@astSerializable` classes.
Builder astEncoderBuilder(BuilderOptions options) =>
    PartBuilder([const AstEncoderGenerator()], '.ast.g.dart');
