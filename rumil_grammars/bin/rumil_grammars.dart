/// The `rumil_grammars` generator CLI.
///
/// Reads an IR grammar (JSON produced by [grammarToJson]) and writes a
/// tree-sitter `grammar.json` into a target directory. The input is
/// validated before emission; a failing grammar exits non-zero with
/// the validation problems on stderr.
///
/// Usage:
///
/// ```sh
/// dart run bin/rumil_grammars.dart --input grammar.ir.json --out .
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:rumil_grammars/rumil_grammars.dart';

void main(List<String> arguments) {
  String? inputPath;
  String? outDir;
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    switch (argument) {
      case '--input' || '--out':
        if (i + 1 >= arguments.length) {
          stderr.writeln('rumil_grammars: missing value for $argument');
          stderr.write(_usage);
          exitCode = 2;
          return;
        }
        i++;
        if (argument == '--input') inputPath = arguments[i];
        if (argument == '--out') outDir = arguments[i];
      case '--help' || '-h':
        stdout.writeln(_usage);
        return;
      default:
        stderr.writeln('rumil_grammars: unknown argument "$argument"');
        stderr.write(_usage);
        exitCode = 2;
        return;
    }
  }
  if (inputPath == null || outDir == null) {
    stderr.writeln('rumil_grammars: both --input and --out are required');
    stderr.write(_usage);
    exitCode = 2;
    return;
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(File(inputPath).readAsStringSync());
  } on FileSystemException catch (e) {
    stderr.writeln('rumil_grammars: cannot read $inputPath: ${e.message}');
    exitCode = 2;
    return;
  } on FormatException catch (e) {
    stderr.writeln(
      'rumil_grammars: $inputPath is not valid JSON: ${e.message}',
    );
    exitCode = 2;
    return;
  }
  final Grammar grammar;
  try {
    grammar = grammarFromJson(_asRootMap(decoded));
  } on FormatException catch (e) {
    stderr.writeln('rumil_grammars: invalid grammar IR: ${e.message}');
    exitCode = 2;
    return;
  }

  try {
    validate(grammar);
  } on GrammarValidationError catch (e) {
    stderr.write('rumil_grammars: validation failed\n$e\n');
    exitCode = 1;
    return;
  }

  final outDirectory = Directory(outDir);
  if (!outDirectory.existsSync()) {
    outDirectory.createSync(recursive: true);
  }
  final target = '${outDirectory.path}/grammar.json';
  File(target).writeAsStringSync(emitGrammarJson(grammar));
  stdout.writeln('wrote $target');
}

Map<String, Object?> _asRootMap(Object? decoded) {
  if (decoded is Map<String, Object?>) return decoded;
  if (decoded is Map<dynamic, dynamic>) {
    return decoded.map((key, item) => MapEntry(key as String, item));
  }
  throw const FormatException('top level of an IR grammar must be an object');
}

const String _usage = '''
usage: dart run bin/rumil_grammars.dart --input <grammar.ir.json> --out <dir>

Reads a grammar IR JSON document and writes tree-sitter grammar.json
into <dir>. The IR is validated before emission.
''';
