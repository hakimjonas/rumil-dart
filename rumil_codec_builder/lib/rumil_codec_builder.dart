/// Builder factory for build_runner integration.
library;

import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/codec_generator.dart';

/// Creates the build_runner [Builder] that generates `.codec.g.dart` files
/// for classes annotated with `@binarySerializable`.
Builder codecBuilder(BuilderOptions options) =>
    PartBuilder([const CodecGenerator()], '.codec.g.dart');
