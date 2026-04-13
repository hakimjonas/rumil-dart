/// Proto3 conformance tests against real .proto files from the protobuf repo.
///
/// Test data: https://github.com/protocolbuffers/protobuf
/// Clone to /tmp: git clone --depth 1 https://github.com/protocolbuffers/protobuf /tmp/protobuf-repo
@TestOn('vm')
library;

import 'dart:io';

import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

/// Root of the cloned protobuf repo.
const _suiteDir = '/tmp/protobuf-repo';

void main() {
  final dir = Directory(_suiteDir);
  if (!dir.existsSync()) {
    print('SKIP: protobuf repo not found at $_suiteDir');
    print(
      'Clone it: git clone --depth 1 '
      'https://github.com/protocolbuffers/protobuf $_suiteDir',
    );
    return;
  }

  // Collect all .proto files under src/google/protobuf/
  final protoDir = Directory('$_suiteDir/src/google/protobuf');
  final protoFiles =
      protoDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.proto'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  var passed = 0;
  var failed = 0;
  final failures = <String>[];

  group('protobuf .proto files', () {
    for (final file in protoFiles) {
      final name = file.path.replaceFirst('$_suiteDir/src/', '');

      test(name, () {
        final input = file.readAsStringSync();
        final result = parseProto(input);

        switch (result) {
          case Success() || Partial():
            passed++;
          case Failure(:final errors):
            failed++;
            final msg = errors.isEmpty ? 'unknown error' : errors.first;
            failures.add('$name — $msg');
          // Don't fail the test — we're measuring baseline
        }
      });
    }
  });

  tearDownAll(() {
    print('\n=== Proto3 Conformance Summary ===');
    print('Parsed:  $passed / ${passed + failed}');
    print('Failed:  $failed');
    if (failures.isNotEmpty) {
      print('\nFailures:');
      for (final f in failures) {
        print('  $f');
      }
    }
  });
}
