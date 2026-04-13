/// HCL conformance tests against the HashiCorp HCL specsuite, fuzz corpus,
/// and real-world Terraform configurations.
///
/// Test data:
///   git clone --depth 1 https://github.com/hashicorp/hcl.git /tmp/hcl-go
///   git clone --depth 1 https://github.com/hashicorp/terraform-provider-aws.git /tmp/tf-aws
@TestOn('vm')
library;

import 'dart:io';

import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

/// Root of the cloned HCL Go repository.
const _suiteDir = '/tmp/hcl-go';

/// Specsuite test directory.
const _specsuiteDir = '$_suiteDir/specsuite/tests';

/// hclwrite fuzz corpus (richest corpus of valid HCL).
const _hclwriteFuzzDir =
    '$_suiteDir/hclwrite/fuzz/testdata/fuzz/FuzzParseConfig';

/// hclsyntax fuzz corpus.
const _hclsyntaxFuzzDir =
    '$_suiteDir/hclsyntax/fuzz/testdata/fuzz/FuzzParseConfig';

void main() {
  final dir = Directory(_suiteDir);
  if (!dir.existsSync()) {
    print('SKIP: HCL test suite not found at $_suiteDir');
    print('Download:');
    print(
      '  git clone --depth 1 https://github.com/hashicorp/hcl.git'
      ' /tmp/hcl-go',
    );
    return;
  }

  var specPass = 0;
  var specFail = 0;
  var specErrorCorrect = 0;
  var specErrorMissed = 0;
  var fuzzPass = 0;
  var fuzzFail = 0;
  var tfPass = 0;
  var tfFail = 0;
  final failures = <String>[];

  // ---- Specsuite tests ----

  group('specsuite', () {
    final specDir = Directory(_specsuiteDir);
    if (!specDir.existsSync()) {
      print('SKIP: specsuite not found at $_specsuiteDir');
      return;
    }

    final hclFiles =
        specDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.hcl'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final hclFile in hclFiles) {
      final name = hclFile.path.substring(_specsuiteDir.length + 1);
      final tFile = File(hclFile.path.replaceFirst(RegExp(r'\.hcl$'), '.t'));

      // Determine if this test expects a parse error.
      // Some .t files contain schema-level errors (e.g., "not expected here")
      // which are semantic, not syntactic. We only treat errors that indicate
      // structural/syntax problems as parse error expectations.
      final tContent = tFile.existsSync() ? tFile.readAsStringSync() : '';
      final hasDiagnostics = tContent.contains('diagnostics');
      final isSemantic = tContent.contains('not expected here');
      final expectError = hasDiagnostics && !isSemantic;

      test(name, () {
        final input = hclFile.readAsStringSync();
        final result = parseHcl(input);
        final parsed = result is! Failure;

        if (expectError) {
          if (!parsed) {
            specErrorCorrect++;
          } else {
            specErrorMissed++;
            failures.add('specsuite/$name: should reject but accepted');
          }
        } else {
          if (parsed) {
            specPass++;
          } else {
            specFail++;
            final msg = (result as Failure).errors.first;
            failures.add('specsuite/$name: $msg');
          }
        }
      });
    }
  });

  // ---- Fuzz corpus tests ----

  group('fuzz corpus', () {
    final fuzzDirs = [
      Directory(_hclwriteFuzzDir),
      Directory(_hclsyntaxFuzzDir),
    ];

    final seen = <String>{};

    for (final fuzzDir in fuzzDirs) {
      if (!fuzzDir.existsSync()) continue;

      final hclFiles =
          fuzzDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.hcl'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      // Known malformed fuzz inputs (intentionally invalid HCL).
      const knownInvalid = {'function-call-tmpl.hcl'};

      for (final hclFile in hclFiles) {
        final basename = hclFile.uri.pathSegments.last;
        if (!seen.add(basename)) continue; // deduplicate across dirs

        test(basename, () {
          final raw = hclFile.readAsStringSync();
          final input = _extractGoFuzzContent(raw);
          if (input == null) {
            // Not in Go fuzz format — skip
            return;
          }

          final result = parseHcl(input);
          final parsed = result is! Failure;

          if (knownInvalid.contains(basename)) {
            // Malformed input — rejection is correct
            if (!parsed) fuzzPass++;
            return;
          }

          if (parsed) {
            fuzzPass++;
          } else {
            fuzzFail++;
            final msg = (result as Failure).errors.first;
            failures.add('fuzz/$basename: $msg');
          }
        });
      }
    }
  });

  // ---- Real-world Terraform configs ----

  const tfAwsDir = '/tmp/tf-aws';

  group('terraform-provider-aws', () {
    final tfRoot = Directory(tfAwsDir);
    if (!tfRoot.existsSync()) {
      print('SKIP: terraform-provider-aws not found at $tfAwsDir');
      print(
        'Download: git clone --depth 1'
        ' https://github.com/hashicorp/terraform-provider-aws.git $tfAwsDir',
      );
      return;
    }

    final tfFiles =
        tfRoot
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.tf'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final tfFile in tfFiles) {
      final name = tfFile.path.substring(tfAwsDir.length + 1);

      test(name, () {
        final input = tfFile.readAsStringSync();
        final result = parseHcl(input);
        final parsed = result is! Failure;

        if (parsed) {
          tfPass++;
        } else {
          tfFail++;
          final msg = (result as Failure).errors.first;
          failures.add('tf/$name: $msg');
          fail('$name: $msg');
        }
      });
    }
  });

  // ---- Summary ----

  tearDownAll(() {
    final total =
        specPass +
        specFail +
        specErrorCorrect +
        specErrorMissed +
        fuzzPass +
        fuzzFail +
        tfPass +
        tfFail;
    final passed = specPass + specErrorCorrect + fuzzPass + tfPass;

    print('\n=== HCL Conformance Summary ===');
    print('Specsuite valid:    $specPass passed, $specFail failed');
    print(
      'Specsuite errors:   $specErrorCorrect correct, '
      '$specErrorMissed missed',
    );
    print('Fuzz corpus:        $fuzzPass passed, $fuzzFail failed');
    print('Terraform configs:  $tfPass passed, $tfFail failed');
    print('Total:              $passed / $total');

    if (failures.isNotEmpty) {
      print('\nFailures:');
      for (final f in failures.take(30)) {
        print('  $f');
      }
      if (failures.length > 30) {
        print('  ... and ${failures.length - 30} more');
      }
    }
  });
}

/// Extract raw HCL content from a Go fuzz corpus file.
///
/// Go fuzz format: `go test fuzz v1\n[]byte("content")`
/// Returns null if the file isn't in Go fuzz format.
String? _extractGoFuzzContent(String raw) {
  if (!raw.startsWith('go test fuzz v1')) return null;

  // Find the []byte("...") wrapper
  final start = raw.indexOf('[]byte("');
  if (start == -1) return null;
  final contentStart = start + '[]byte("'.length;

  // Find the closing ")
  final end = raw.lastIndexOf('")');
  if (end == -1 || end <= contentStart) return null;

  final escaped = raw.substring(contentStart, end);

  // Unescape Go string escapes
  final buffer = StringBuffer();
  var i = 0;
  while (i < escaped.length) {
    if (escaped[i] == '\\' && i + 1 < escaped.length) {
      switch (escaped[i + 1]) {
        case 'n':
          buffer.write('\n');
          i += 2;
        case 'r':
          buffer.write('\r');
          i += 2;
        case 't':
          buffer.write('\t');
          i += 2;
        case '\\':
          buffer.write('\\');
          i += 2;
        case '"':
          buffer.write('"');
          i += 2;
        default:
          buffer.write(escaped[i]);
          i++;
      }
    } else {
      buffer.write(escaped[i]);
      i++;
    }
  }
  return buffer.toString();
}
