/// YAML 1.2 conformance tests against the official yaml-test-suite.
///
/// Test data: https://github.com/yaml/yaml-test-suite (data branch)
/// Clone to /tmp: git clone --branch data https://github.com/yaml/yaml-test-suite /tmp/yaml-test-data
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

/// Root of the cloned yaml-test-suite data branch.
const _suiteDir = '/tmp/yaml-test-data';

void main() {
  final dir = Directory(_suiteDir);
  if (!dir.existsSync()) {
    print('SKIP: yaml-test-suite not found at $_suiteDir');
    print(
      'Clone it: git clone --branch data '
      'https://github.com/yaml/yaml-test-suite $_suiteDir',
    );
    return;
  }

  final testDirs =
      dir.listSync().whereType<Directory>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final c = _Counters();

  group('yaml-test-suite', () {
    for (final testDir in testDirs) {
      final id = testDir.path.split('/').last;
      final nameFile = File('${testDir.path}/===');
      final name =
          nameFile.existsSync() ? nameFile.readAsStringSync().trim() : id;

      final inFile = File('${testDir.path}/in.yaml');
      final jsonFile = File('${testDir.path}/in.json');
      final errorFile = File('${testDir.path}/error');
      final isError = errorFile.existsSync();

      if (!inFile.existsSync()) {
        c.skipped++;
        continue;
      }

      test('$id: $name', () {
        final input = inFile.readAsStringSync();

        if (isError) {
          final result = parseYaml(input);
          if (result is Failure) {
            c.errorCorrect++;
          } else {
            c.errorMissed++;
          }
          return;
        }

        if (!jsonFile.existsSync()) {
          c.skipped++;
          return;
        }

        final jsonText = jsonFile.readAsStringSync().trim();

        // Detect multi-document JSON (multiple top-level values).
        final expectedDocs = _parseMultiJson(jsonText);

        if (expectedDocs.length <= 1) {
          // Single document — use parseYaml.
          final result = parseYaml(input);

          late final YamlValue yamlValue;
          switch (result) {
            case Success(:final value):
            case Partial(:final value):
              yamlValue = value;
            case Failure(:final errors):
              c.failed++;
              c.failures.add('$id: $name — parse failed: $errors');
              fail('Parse failed: $errors');
          }

          try {
            final actual = yamlToNative(yamlValue);
            if (expectedDocs.isEmpty) {
              // Empty JSON — document should be null.
              expect(actual, isNull, reason: '$id: $name');
            } else {
              expect(
                _normalize(actual),
                equals(_normalize(expectedDocs.first)),
                reason: '$id: $name',
              );
            }
            c.passed++;
          } on Object catch (e) {
            c.failed++;
            c.failures.add('$id: $name — $e');
            rethrow;
          }
        } else {
          // Multi-document — use parseYamlMulti.
          final result = parseYamlMulti(input);

          late final List<YamlValue> yamlDocs;
          switch (result) {
            case Success(:final value):
            case Partial(:final value):
              yamlDocs = value;
            case Failure(:final errors):
              c.failed++;
              c.failures.add('$id: $name — parse failed: $errors');
              fail('Parse failed: $errors');
          }

          try {
            final actuals = [for (final doc in yamlDocs) yamlToNative(doc)];
            expect(
              [for (final a in actuals) _normalize(a)],
              equals([for (final e in expectedDocs) _normalize(e)]),
              reason: '$id: $name',
            );
            c.passed++;
          } on Object catch (e) {
            c.failed++;
            c.failures.add('$id: $name — $e');
            rethrow;
          }
        }
      });
    }
  });

  tearDownAll(() {
    print('\n=== YAML Conformance Summary ===');
    print('Passed:        ${c.passed}');
    print('Failed:        ${c.failed}');
    print('Skipped:       ${c.skipped}');
    print('Error correct: ${c.errorCorrect}');
    print('Error missed:  ${c.errorMissed}');
    if (c.failures.isNotEmpty) {
      print('\nFailures:');
      for (final f in c.failures) {
        print('  $f');
      }
    }
  });
}

/// Parse a JSON string that may contain multiple top-level values
/// (one per document, separated by whitespace).
List<Object?> _parseMultiJson(String text) {
  if (text.isEmpty) return [];
  final results = <Object?>[];
  var i = 0;
  while (i < text.length) {
    // Skip whitespace between values.
    while (i < text.length && _isJsonWhitespace(text.codeUnitAt(i))) {
      i++;
    }
    if (i >= text.length) break;
    // Find the end of the current JSON value.
    final start = i;
    i = _skipJsonValue(text, i);
    results.add(jsonDecode(text.substring(start, i)));
  }
  return results;
}

bool _isJsonWhitespace(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

/// Skip one JSON value starting at [i], return the index after it.
int _skipJsonValue(String text, int i) {
  if (i >= text.length) return i;
  return switch (text[i]) {
    '{' => _skipJsonBraced(text, i, '{', '}'),
    '[' => _skipJsonBraced(text, i, '[', ']'),
    '"' => _skipJsonString(text, i),
    _ => _skipJsonLiteral(text, i),
  };
}

int _skipJsonBraced(String text, int i, String open, String close) {
  var depth = 0;
  var inString = false;
  while (i < text.length) {
    final c = text[i];
    if (inString) {
      if (c == '\\') {
        i += 2;
        continue;
      }
      if (c == '"') inString = false;
    } else {
      if (c == '"') inString = true;
      if (c == open) depth++;
      if (c == close) {
        depth--;
        if (depth == 0) return i + 1;
      }
    }
    i++;
  }
  return i;
}

int _skipJsonString(String text, int i) {
  i++; // skip opening "
  while (i < text.length) {
    if (text[i] == '\\') {
      i += 2;
      continue;
    }
    if (text[i] == '"') return i + 1;
    i++;
  }
  return i;
}

int _skipJsonLiteral(String text, int i) {
  while (i < text.length &&
      !_isJsonWhitespace(text.codeUnitAt(i)) &&
      text[i] != ',' &&
      text[i] != '}' &&
      text[i] != ']') {
    i++;
  }
  return i;
}

/// Normalize values for comparison: convert ints/doubles consistently.
Object? _normalize(Object? v) => switch (v) {
  null => null,
  bool() => v,
  int() => v,
  final double d => d == d.truncateToDouble() ? d.toInt() : d,
  String() => v,
  List<Object?>() => [for (final e in v) _normalize(e)],
  Map<Object?, Object?>() => {
    for (final e in v.entries) e.key: _normalize(e.value),
  },
  _ => v.toString(),
};

class _Counters {
  int passed = 0;
  int failed = 0;
  int skipped = 0;
  int errorCorrect = 0;
  int errorMissed = 0;
  final failures = <String>[];
}
