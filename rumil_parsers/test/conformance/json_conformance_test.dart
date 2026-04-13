/// JSON conformance tests against JSONTestSuite by Nicolas Seriot.
///
/// Test data: https://github.com/nst/JSONTestSuite
/// Clone to /tmp: git clone https://github.com/nst/JSONTestSuite /tmp/json-test-suite
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

/// Root of the cloned JSONTestSuite.
const _suiteDir = '/tmp/json-test-suite/test_parsing';

void main() {
  final dir = Directory(_suiteDir);
  if (!dir.existsSync()) {
    print('SKIP: JSONTestSuite not found at $_suiteDir');
    print(
      'Clone it: git clone '
      'https://github.com/nst/JSONTestSuite /tmp/json-test-suite',
    );
    return;
  }

  final files =
      dir.listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final c = _Counters();

  group('JSONTestSuite', () {
    for (final file in files) {
      final name = file.path.split('/').last;
      if (!name.endsWith('.json')) continue;

      final prefix = name.substring(0, 2);

      test(name, () {
        final bytes = file.readAsBytesSync();
        String input;
        try {
          input = utf8.decode(bytes);
        } on FormatException {
          switch (prefix) {
            case 'n_':
              c.nPass++;
            case 'i_':
              c.iReject++;
            case 'y_':
              c.yFail++;
              fail('Should accept but file is not valid UTF-8: $name');
          }
          return;
        }

        bool parsed;
        try {
          final result = parseJson(input);
          parsed = result is! Failure;
        } on StackOverflowError {
          parsed = false;
        }

        switch (prefix) {
          case 'y_':
            if (parsed) {
              c.yPass++;
            } else {
              c.yFail++;
              fail('Must accept: $name');
            }
          case 'n_':
            if (!parsed) {
              c.nPass++;
            } else {
              c.nFail++;
              fail('Must reject: $name');
            }
          case 'i_':
            if (parsed) {
              c.iAccept++;
            } else {
              c.iReject++;
            }
        }
      });
    }
  });

  tearDownAll(() {
    print('\n=== JSON Conformance Summary ===');
    print('y_ (must accept):  ${c.yPass} pass, ${c.yFail} fail');
    print('n_ (must reject):  ${c.nPass} pass, ${c.nFail} fail');
    print('i_ (impl-defined): ${c.iAccept} accept, ${c.iReject} reject');
    final total = c.yPass + c.nPass + c.iAccept + c.iReject;
    final mandatory = c.yPass + c.nPass;
    print('Mandatory: $mandatory/${c.yPass + c.yFail + c.nPass + c.nFail}');
    print('Total clean: $total/${total + c.yFail + c.nFail}');
  });
}

class _Counters {
  int yPass = 0;
  int yFail = 0;
  int nPass = 0;
  int nFail = 0;
  int iAccept = 0;
  int iReject = 0;
}
