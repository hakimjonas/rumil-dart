/// XML 1.0 conformance tests against the W3C XML Conformance Test Suite.
///
/// Test data: https://www.w3.org/XML/Test/
/// Download: wget https://www.w3.org/XML/Test/xmlts20130923.tar.gz -P /tmp/
///           cd /tmp && tar xzf xmlts20130923.tar.gz
@TestOn('vm')
library;

import 'dart:io';

import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

/// Root of the extracted W3C XML test suite.
const _suiteDir = '/tmp/xmlconf';

/// Sub-manifest files and their base paths.
const _manifests = [
  ('xmltest/xmltest.xml', 'xmltest/'),
  ('sun/sun-valid.xml', 'sun/'),
  ('sun/sun-invalid.xml', 'sun/'),
  ('sun/sun-not-wf.xml', 'sun/'),
  ('sun/sun-error.xml', 'sun/'),
  ('oasis/oasis.xml', 'oasis/'),
  ('ibm/ibm_oasis_invalid.xml', 'ibm/'),
  ('ibm/ibm_oasis_not-wf.xml', 'ibm/'),
  ('ibm/ibm_oasis_valid.xml', 'ibm/'),
  ('eduni/errata-2e/errata2e.xml', 'eduni/errata-2e/'),
  ('eduni/errata-3e/errata3e.xml', 'eduni/errata-3e/'),
  ('eduni/errata-4e/errata4e.xml', 'eduni/errata-4e/'),
  ('eduni/namespaces/1.0/rmt-ns10.xml', 'eduni/namespaces/1.0/'),
  ('eduni/namespaces/errata-1e/errata1e.xml', 'eduni/namespaces/errata-1e/'),
  ('eduni/misc/ht-bh.xml', 'eduni/misc/'),
  ('japanese/japanese.xml', 'japanese/'),
];

void main() {
  final dir = Directory(_suiteDir);
  if (!dir.existsSync()) {
    print('SKIP: W3C XML Test Suite not found at $_suiteDir');
    print('Download and extract:');
    print('  wget https://www.w3.org/XML/Test/xmlts20130923.tar.gz -P /tmp/');
    print('  cd /tmp && tar xzf xmlts20130923.tar.gz');
    return;
  }

  final tests = _loadAllTests();
  if (tests.isEmpty) {
    print('WARNING: No tests loaded from W3C XML suite');
    return;
  }

  var notWfPass = 0;
  var notWfFail = 0;
  var validPass = 0;
  var validFail = 0;
  var invalidPass = 0;
  var invalidFail = 0;
  var errorCount = 0;
  var skipped = 0;
  final failures = <String>[];

  group('W3C XML', () {
    for (final t in tests) {
      test('${t.id}: ${t.type}', () {
        // Skip tests requiring external parameter entities.
        if (t.entities == 'parameter' || t.entities == 'both') {
          skipped++;
          return;
        }

        final file = File(t.filePath);
        if (!file.existsSync()) {
          skipped++;
          return;
        }

        // Try reading the file; some use non-UTF-8 encodings.
        late final String input;
        try {
          input = file.readAsStringSync();
        } on Exception {
          skipped++; // Can't decode (non-UTF-8 without BOM)
          return;
        }

        // Provide entity resolver for external entity validation.
        final baseDir = file.parent.path;
        final config = XmlConfig(
          resolveEntity: (systemId, _) {
            final entityFile = File('$baseDir/$systemId');
            if (!entityFile.existsSync()) return null;
            try {
              return entityFile.readAsStringSync();
            } on Exception {
              return null;
            }
          },
        );
        final result = parseXml(input, config);
        var parsed = result is Success || result is Partial;

        // Encoding mismatch detection: if the file was read as UTF-8 but
        // the XML declaration claims a non-UTF-8 encoding, that's a fatal error.
        if (parsed && result is Success<ParseError, XmlDocument>) {
          final enc = result.value.encoding?.toUpperCase();
          if (enc != null && enc != 'UTF-8' && enc != 'US-ASCII') {
            // File was decoded as UTF-8 — check if the declared encoding
            // is compatible. UTF-16, ISO-8859-*, etc. are not.
            final bytes = file.readAsBytesSync();
            final hasBom =
                bytes.length >= 3 &&
                bytes[0] == 0xEF &&
                bytes[1] == 0xBB &&
                bytes[2] == 0xBF;
            // UTF-8 BOM + non-UTF-8 declaration = mismatch.
            // No BOM + non-UTF-8 declaration but file decoded as UTF-8 = mismatch.
            if (hasBom || !enc.startsWith('UTF-8')) {
              parsed = false;
            }
          }
        }

        switch (t.type) {
          case 'not-wf':
            if (!parsed) {
              notWfPass++;
            } else {
              notWfFail++;
              failures.add('${t.id} [not-wf] should reject but accepted');
            }
          case 'valid':
            if (parsed) {
              validPass++;
            } else {
              validFail++;
              final msg =
                  result is Failure
                      ? (result.errors.isNotEmpty
                          ? result.errors.first.toString()
                          : 'unknown')
                      : 'unknown';
              failures.add('${t.id} [valid] should accept: $msg');
            }
          case 'invalid':
            // Non-validating parser: accepting invalid docs is fine.
            if (parsed) {
              invalidPass++;
            } else {
              invalidFail++;
            }
          case 'error':
            errorCount++;
        }
      });
    }
  });

  tearDownAll(() {
    print('\n=== W3C XML Conformance Summary ===');
    print(
      'not-wf:  $notWfPass correct rejections, '
      '$notWfFail incorrect accepts',
    );
    print(
      'valid:   $validPass parsed, '
      '$validFail failed to parse',
    );
    print(
      'invalid: $invalidPass accepted (OK), '
      '$invalidFail rejected (also OK)',
    );
    print('error:   $errorCount (implementation-defined)');
    print('skipped: $skipped');
    print(
      'Score:   ${validPass + notWfPass} mandatory pass '
      '/ ${validPass + notWfPass + validFail + notWfFail} mandatory total',
    );
    if (failures.length <= 30) {
      for (final f in failures) {
        print('  $f');
      }
    } else {
      print('  (${failures.length} failures, showing first 30)');
      for (final f in failures.take(30)) {
        print('  $f');
      }
    }
  });
}

// ---------------------------------------------------------------------------
// Test case model and manifest parsing
// ---------------------------------------------------------------------------

class _TestCase {
  final String id;
  final String type; // not-wf, valid, invalid, error
  final String filePath; // Absolute path to test XML file
  final String entities; // none, general, parameter, both
  final String sections; // Spec section reference

  _TestCase({
    required this.id,
    required this.type,
    required this.filePath,
    required this.entities,
    required this.sections,
  });
}

/// Load all test cases from sub-manifest files.
List<_TestCase> _loadAllTests() {
  final tests = <_TestCase>[];

  for (final (manifestPath, defaultBase) in _manifests) {
    final file = File('$_suiteDir/$manifestPath');
    if (!file.existsSync()) continue;

    final content = file.readAsStringSync();

    // Track xml:base from TESTCASES elements for URI resolution.
    // The sub-manifests may have nested TESTCASES with xml:base.
    final baseStack = <String>[defaultBase];

    // Scan for TESTCASES and TEST elements.
    final tagPattern = RegExp(
      r'<(TESTCASES|/TESTCASES|TEST)\b([^>]*?)(/?)>',
      dotAll: true,
    );

    for (final match in tagPattern.allMatches(content)) {
      final tag = match.group(1)!;
      final attrs = match.group(2) ?? '';
      // match.group(3) == '/' for self-closing, ignored — we only need attrs.

      if (tag == 'TESTCASES') {
        final base = _attr(attrs, 'xml:base');
        if (base != null) {
          baseStack.add(base);
        } else {
          baseStack.add(baseStack.last);
        }
      } else if (tag == '/TESTCASES') {
        if (baseStack.length > 1) baseStack.removeLast();
      } else if (tag == 'TEST') {
        final type = _attr(attrs, 'TYPE') ?? '';
        final id = _attr(attrs, 'ID') ?? '';
        final uri = _attr(attrs, 'URI') ?? '';
        final entities = _attr(attrs, 'ENTITIES') ?? 'none';
        final sections = _attr(attrs, 'SECTIONS') ?? '';
        final recommendation = _attr(attrs, 'RECOMMENDATION') ?? '';
        // Skip XML 1.1 tests.
        if (recommendation.contains('1.1') ||
            recommendation.contains('NS1.1')) {
          continue;
        }

        // We target 5th edition. Skip tests marked for earlier editions
        // only (e.g. EDITION="1 2 3 4" means the test doesn't apply to 5th).
        final edition = _attr(attrs, 'EDITION') ?? '';
        if (edition.isNotEmpty && !edition.contains('5')) {
          continue;
        }

        // Our parser is namespace-aware. Skip tests that require
        // namespace processing to be disabled (NAMESPACE="no").
        final namespace = _attr(attrs, 'NAMESPACE') ?? '';
        if (namespace == 'no') {
          continue;
        }

        final base = baseStack.last;
        final resolvedPath = '$_suiteDir/$base$uri';

        tests.add(
          _TestCase(
            id: id,
            type: type,
            filePath: resolvedPath,
            entities: entities,
            sections: sections,
          ),
        );

        // If TEST is not self-closing, the content between tags is just
        // the description text — we don't need it.
      }
    }
  }

  return tests;
}

/// Extract an attribute value from an attribute string.
String? _attr(String attrs, String name) {
  final pattern = RegExp('$name\\s*=\\s*["\']([^"\']*)["\']');
  final match = pattern.firstMatch(attrs);
  return match?.group(1);
}
