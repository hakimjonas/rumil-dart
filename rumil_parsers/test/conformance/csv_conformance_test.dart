/// Delimited format (CSV) conformance tests against csv-spectrum.
///
/// Test data: https://github.com/maxogden/csv-spectrum
/// Clone to /tmp: git clone https://github.com/maxogden/csv-spectrum /tmp/csv-spectrum
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/src/delimited.dart';
import 'package:test/test.dart';

/// Root of the cloned csv-spectrum repo.
const _suiteDir = '/tmp/csv-spectrum';

/// Tests with known data quality issues in csv-spectrum (expected JSON
/// doesn't match input CSV — e.g., sanitized PII in JSON but not CSV).
const _dataQualitySkip = {'location_coordinates'};

void main() {
  final dir = Directory(_suiteDir);
  if (!dir.existsSync()) {
    print('SKIP: csv-spectrum not found at $_suiteDir');
    print(
      'Clone it: git clone https://github.com/maxogden/csv-spectrum $_suiteDir',
    );
    return;
  }

  final csvDir = Directory('$_suiteDir/csvs');
  final jsonDir = Directory('$_suiteDir/json');

  final csvFiles =
      csvDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.csv'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  var passed = 0;
  var failed = 0;
  var skipped = 0;

  group('csv-spectrum', () {
    for (final csvFile in csvFiles) {
      final name = csvFile.uri.pathSegments.last.replaceAll('.csv', '');
      final jsonFile = File('${jsonDir.path}/$name.json');

      if (!jsonFile.existsSync()) {
        skipped++;
        continue;
      }

      test(name, () {
        if (_dataQualitySkip.contains(name)) {
          skipped++;
          return; // Expected JSON has sanitized values that don't match CSV
        }
        final input = csvFile.readAsStringSync();
        final expectedJson = jsonDecode(jsonFile.readAsStringSync());

        final result = parseCsvWithHeaders(input);

        late final (List<String>, List<List<String>>) parsed;
        switch (result) {
          case Success(:final value):
          case Partial(:final value):
            parsed = value;
          case Failure(:final errors):
            failed++;
            fail('Parse failed: $errors');
        }

        final (headers, rows) = parsed;

        // Convert to list-of-maps format matching csv-spectrum's JSON.
        final actual = <Map<String, String>>[
          for (final row in rows)
            {
              for (var i = 0; i < headers.length; i++)
                headers[i]: i < row.length ? row[i] : '',
            },
        ];

        // csv-spectrum JSON is either a list of objects or a single object.
        final expected =
            expectedJson is List
                ? expectedJson.cast<Map<String, dynamic>>()
                : [expectedJson as Map<String, dynamic>];

        expect(actual.length, expected.length, reason: '$name: row count');
        for (var i = 0; i < actual.length; i++) {
          for (final key in expected[i].keys) {
            expect(
              actual[i][key],
              expected[i][key],
              reason: '$name: row $i, field "$key"',
            );
          }
        }
        passed++;
      });
    }
  });

  tearDownAll(() {
    print('\n=== CSV Conformance Summary ===');
    print('Passed:  $passed');
    print('Failed:  $failed');
    print('Skipped: $skipped');
  });
}
