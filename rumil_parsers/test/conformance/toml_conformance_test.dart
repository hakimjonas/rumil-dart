/// TOML 1.1 conformance tests against the official toml-test suite.
///
/// Test data: https://github.com/toml-lang/toml-test
/// Clone to /tmp: git clone https://github.com/toml-lang/toml-test /tmp/toml-test
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

/// Root of the cloned toml-test suite.
const _suiteDir = '/tmp/toml-test/tests';

/// TOML version we target.
const _versionFile = '$_suiteDir/files-toml-1.1.0';

void main() {
  final dir = Directory(_suiteDir);
  if (!dir.existsSync()) {
    print('SKIP: toml-test not found at $_suiteDir');
    print(
      'Clone it: git clone '
      'https://github.com/toml-lang/toml-test /tmp/toml-test',
    );
    return;
  }

  final versionTests = File(_versionFile).readAsLinesSync().toSet();
  final c = _Counters();

  group('toml-test valid', () {
    final validFiles = _findTomlFiles(Directory('$_suiteDir/valid'));
    for (final file in validFiles) {
      final name = file.path.replaceFirst('$_suiteDir/valid/', '');
      if (!versionTests.contains('valid/$name')) continue;

      test(name, () {
        final input = file.readAsStringSync();
        final result = parseToml(input);
        if (result is Failure) {
          c.validFail++;
          c.failures.add('valid/$name — parse failed');
          fail('Should parse but failed: $name');
        } else {
          c.validPass++;
        }
      });
    }
  });

  group('toml-test invalid', () {
    final invalidFiles = _findTomlFiles(Directory('$_suiteDir/invalid'));
    for (final file in invalidFiles) {
      final name = file.path.replaceFirst('$_suiteDir/invalid/', '');
      if (!versionTests.contains('invalid/$name')) continue;

      test(name, () {
        String input;
        try {
          input = utf8.decode(file.readAsBytesSync());
        } on FormatException {
          c.invalidPass++;
          return;
        }
        final result = parseToml(input);
        if (result is Failure) {
          c.invalidPass++;
        } else {
          c.invalidFail++;
          fail('Should reject but accepted: $name');
        }
      });
    }
  });

  tearDownAll(() {
    print('\n=== TOML 1.1 Conformance Summary ===');
    print('Valid:   ${c.validPass} pass, ${c.validFail} fail');
    print('Invalid: ${c.invalidPass} rejected, ${c.invalidFail} accepted');
    final total = c.validPass + c.invalidPass;
    final totalTests = total + c.validFail + c.invalidFail;
    print('Total:   $total/$totalTests');
    if (c.failures.isNotEmpty) {
      print('\nFailures:');
      for (final f in c.failures) {
        print('  $f');
      }
    }
  });
}

List<File> _findTomlFiles(Directory dir) {
  if (!dir.existsSync()) return [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.toml'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

class _Counters {
  int validPass = 0;
  int validFail = 0;
  int invalidPass = 0;
  int invalidFail = 0;
  final failures = <String>[];
}
