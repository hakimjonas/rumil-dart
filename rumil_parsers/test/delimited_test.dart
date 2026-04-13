/// Rigorous test suite for the delimited format parser.
///
/// Since no official conformance suite exists for CSV/TSV/delimited formats,
/// these tests ARE the specification. They document every guaranteed behavior
/// and cover adversarial edge cases that real-world data produces.
@TestOn('vm')
library;

import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

DelimitedDocument _parse(
  String input, [
  DelimitedConfig config = defaultDelimitedConfig,
]) {
  final r = parseDelimited(input, config);
  return switch (r) {
    Success(:final value) => value,
    Partial(:final value) => value,
    Failure(:final errors) => throw StateError('Parse failed: ${errors.first}'),
  };
}

(List<String>, DelimitedDocument) _parseH(
  String input, [
  DelimitedConfig? config,
]) {
  final r = parseDelimitedWithHeaders(input, config);
  return switch (r) {
    Success(:final value) => value,
    Partial(:final value) => value,
    Failure(:final errors) => throw StateError('Parse failed: ${errors.first}'),
  };
}

void main() {
  // =========================================================================
  // RFC 4180 CORE RULES
  // =========================================================================

  group('RFC 4180 core', () {
    test('simple comma-separated', () {
      expect(_parse('a,b,c'), [
        ['a', 'b', 'c'],
      ]);
    });

    test('multiple records separated by newline', () {
      expect(_parse('a,b\nc,d'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('CRLF line endings', () {
      expect(_parse('a,b\r\nc,d'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('trailing CRLF does not produce extra row', () {
      expect(_parse('a,b\r\nc,d\r\n'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('trailing LF does not produce extra row', () {
      expect(_parse('a,b\nc,d\n'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('empty fields', () {
      expect(_parse(',b,'), [
        ['', 'b', ''],
      ]);
    });

    test('single field', () {
      expect(_parse('hello'), [
        ['hello'],
      ]);
    });

    test('empty input', () {
      expect(_parse(''), [
        [''],
      ]);
    });

    test('only newline', () {
      expect(_parse('\n'), [
        [''],
      ]);
    });

    test('only CRLF', () {
      expect(_parse('\r\n'), [
        [''],
      ]);
    });
  });

  // =========================================================================
  // QUOTING — the hardest part of delimited parsing
  // =========================================================================

  group('Quoting', () {
    test('simple quoted field', () {
      expect(_parse('"hello",world'), [
        ['hello', 'world'],
      ]);
    });

    test('quoted field with comma inside', () {
      expect(_parse('"a,b",c'), [
        ['a,b', 'c'],
      ]);
    });

    test('quoted field with newline inside', () {
      expect(_parse('"a\nb",c'), [
        ['a\nb', 'c'],
      ]);
    });

    test('quoted field with CRLF inside', () {
      expect(_parse('"a\r\nb",c'), [
        ['a\r\nb', 'c'],
      ]);
    });

    test('escaped double quote inside quoted field', () {
      expect(_parse('"say ""hello""",done'), [
        ['say "hello"', 'done'],
      ]);
    });

    test('multiple escaped quotes', () {
      expect(_parse('"she said ""hi"" then ""bye"""'), [
        ['she said "hi" then "bye"'],
      ]);
    });

    test('empty quoted field', () {
      expect(_parse('"",b'), [
        ['', 'b'],
      ]);
    });

    test('quoted field at end of row', () {
      expect(_parse('a,"b"'), [
        ['a', 'b'],
      ]);
    });

    test('quoted field at start of file', () {
      expect(_parse('"a",b'), [
        ['a', 'b'],
      ]);
    });

    test('quoted field at end of file', () {
      expect(_parse('a,"b"'), [
        ['a', 'b'],
      ]);
    });

    test('all fields quoted', () {
      expect(_parse('"a","b","c"'), [
        ['a', 'b', 'c'],
      ]);
    });

    test('quote followed immediately by delimiter', () {
      expect(_parse('"val",next'), [
        ['val', 'next'],
      ]);
    });

    test('quoted field containing only spaces', () {
      expect(_parse('"   ",b'), [
        ['   ', 'b'],
      ]);
    });

    test('quoted field containing only a quote', () {
      expect(_parse('"""",b'), [
        ['"', 'b'],
      ]);
    });

    test('quoted field spanning multiple lines', () {
      expect(_parse('"line1\nline2\nline3",b'), [
        ['line1\nline2\nline3', 'b'],
      ]);
    });

    test('JSON embedded in quoted field', () {
      expect(
        _parse('"1","{""type"": ""Point"", ""coordinates"": [102.0, 0.5]}"'),
        [
          ['1', '{"type": "Point", "coordinates": [102.0, 0.5]}'],
        ],
      );
    });
  });

  // =========================================================================
  // BARE QUOTES (real-world, non-RFC)
  // =========================================================================

  group('Bare quotes in unquoted fields', () {
    test('quote mid-field (geographic notation)', () {
      expect(_parse('37.8"N,data'), [
        ['37.8"N', 'data'],
      ]);
    });

    test('quote at end of field', () {
      expect(_parse('12",next'), [
        ['12"', 'next'],
      ]);
    });

    test('multiple bare quotes in one field', () {
      expect(_parse('a"b"c,d'), [
        ['a"b"c', 'd'],
      ]);
    });

    test('bare quote does not start a quoted field', () {
      // First char is not a quote, so this is an unquoted field
      expect(_parse('x"y,z'), [
        ['x"y', 'z'],
      ]);
    });
  });

  // =========================================================================
  // LINE ENDING VARIATIONS
  // =========================================================================

  group('Line endings', () {
    test('LF only', () {
      expect(_parse('a\nb\nc'), [
        ['a'],
        ['b'],
        ['c'],
      ]);
    });

    test('CRLF only', () {
      expect(_parse('a\r\nb\r\nc'), [
        ['a'],
        ['b'],
        ['c'],
      ]);
    });

    test('CR only (old Mac)', () {
      // Our parser treats \r as line ending via common.newline()
      expect(_parse('a\rb\rc'), [
        ['a'],
        ['b'],
        ['c'],
      ]);
    });

    test('CRLF inside quoted field preserved', () {
      expect(_parse('"a\r\nb",c'), [
        ['a\r\nb', 'c'],
      ]);
    });

    test('LF inside quoted field preserved', () {
      expect(_parse('"a\nb",c'), [
        ['a\nb', 'c'],
      ]);
    });
  });

  // =========================================================================
  // TSV (Tab-Separated Values)
  // =========================================================================

  group('TSV', () {
    test('tab separated', () {
      expect(_parse('a\tb\tc', defaultTsvConfig), [
        ['a', 'b', 'c'],
      ]);
    });

    test('tabs with commas in values (commas are content)', () {
      expect(_parse('a,b\tc,d', defaultTsvConfig), [
        ['a,b', 'c,d'],
      ]);
    });

    test('parseTsv convenience', () {
      final r = parseTsv('a\tb\n1\t2');
      expect((r as Success).value, [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });
  });

  // =========================================================================
  // HEADERS
  // =========================================================================

  group('Headers', () {
    test('splits first row as headers', () {
      final (headers, rows) = _parseH('name,age\nAlice,30\nBob,25');
      expect(headers, ['name', 'age']);
      expect(rows, [
        ['Alice', '30'],
        ['Bob', '25'],
      ]);
    });

    test('single row = headers only, no data', () {
      final (headers, rows) = _parseH('name,age');
      expect(headers, ['name', 'age']);
      expect(rows, isEmpty);
    });

    test('empty input = empty headers', () {
      final (headers, rows) = _parseH('');
      expect(headers, ['']);
      expect(rows, isEmpty);
    });
  });

  // =========================================================================
  // CONFIGURATION OPTIONS
  // =========================================================================

  group('Config: trimWhitespace', () {
    test('trims spaces from fields', () {
      expect(_parse(' a , b ', const DelimitedConfig(trimWhitespace: true)), [
        ['a', 'b'],
      ]);
    });

    test('trims tabs from fields', () {
      expect(
        _parse('\ta\t,\tb\t', const DelimitedConfig(trimWhitespace: true)),
        [
          ['a', 'b'],
        ],
      );
    });
  });

  group('Config: skipEmptyLines', () {
    test('removes empty lines', () {
      expect(
        _parse('a\n\nb\n\nc', const DelimitedConfig(skipEmptyLines: true)),
        [
          ['a'],
          ['b'],
          ['c'],
        ],
      );
    });
  });

  group('Config: custom delimiter', () {
    test('semicolon', () {
      expect(_parse('a;b;c', const DelimitedConfig(delimiter: ';')), [
        ['a', 'b', 'c'],
      ]);
    });

    test('pipe', () {
      expect(_parse('a|b|c', const DelimitedConfig(delimiter: '|')), [
        ['a', 'b', 'c'],
      ]);
    });
  });

  // =========================================================================
  // BOM HANDLING
  // =========================================================================

  group('BOM', () {
    test('strips UTF-8 BOM from start', () {
      expect(_parse('\uFEFFa,b\n1,2'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('BOM only in first field, not treated as content', () {
      final doc = _parse('\uFEFFname,age');
      expect(doc[0][0], 'name'); // Not '\uFEFFname'
    });

    test('no BOM is fine', () {
      expect(_parse('a,b'), [
        ['a', 'b'],
      ]);
    });

    test('BOM in middle of file is content (not stripped)', () {
      expect(_parse('a,\uFEFFb'), [
        ['a', '\uFEFFb'],
      ]);
    });
  });

  // =========================================================================
  // DIALECT DETECTION
  // =========================================================================

  group('Dialect detection: delimiter', () {
    test('detects comma', () {
      expect(detectDialect('a,b,c\n1,2,3\n4,5,6').delimiter, ',');
    });

    test('detects tab', () {
      expect(detectDialect('a\tb\tc\n1\t2\t3').delimiter, '\t');
    });

    test('detects semicolon', () {
      expect(detectDialect('a;b;c\n1;2;3\n4;5;6').delimiter, ';');
    });

    test('detects pipe', () {
      expect(detectDialect('a|b|c\n1|2|3').delimiter, '|');
    });

    test('single-column file defaults to comma', () {
      expect(detectDialect('a\nb\nc').delimiter, ',');
    });

    test('empty file defaults to comma', () {
      expect(detectDialect('').delimiter, ',');
    });

    test('single row detection', () {
      expect(detectDialect('a\tb\tc').delimiter, '\t');
    });

    test('delimiter inside quoted field does not confuse detection', () {
      // Commas appear inside quotes, but tabs are the real delimiter
      expect(detectDialect('"a,b"\t"c,d"\n"e,f"\t"g,h"').delimiter, '\t');
    });
  });

  group('Dialect detection: header', () {
    test('header when first row is strings, second has numbers', () {
      expect(detectDialect('name,age,score\nAlice,30,95.5').hasHeader, true);
    });

    test('no header when all rows have numbers', () {
      expect(detectDialect('1,2,3\n4,5,6\n7,8,9').hasHeader, false);
    });

    test('no header when all rows are strings', () {
      expect(detectDialect('a,b,c\nd,e,f').hasHeader, false);
    });

    test('header detection with single data row', () {
      expect(detectDialect('name,value\ntest,42').hasHeader, true);
    });
  });

  group('Dialect detection: auto-parse', () {
    test('auto-detect and parse tab-separated', () {
      final r = parseDelimited('a\tb\tc\n1\t2\t3');
      expect((r as Success).value, [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
    });

    test('auto-detect and parse semicolon-separated', () {
      final r = parseDelimited('a;b;c\n1;2;3');
      expect((r as Success).value, [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
    });

    test('auto-detect and parse pipe-separated', () {
      final r = parseDelimited('a|b|c\n1|2|3');
      expect((r as Success).value, [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
    });
  });

  // =========================================================================
  // RAGGED ROWS
  // =========================================================================

  group('Ragged rows', () {
    test('preserve keeps short rows as-is', () {
      final doc = _parse(
        'a,b,c\n1,2\n4,5,6',
        const DelimitedConfig(raggedRows: RaggedRowPolicy.preserve),
      );
      expect(doc[0], ['a', 'b', 'c']);
      expect(doc[1], ['1', '2']);
      expect(doc[2], ['4', '5', '6']);
    });

    test('preserve keeps long rows as-is', () {
      final doc = _parse(
        'a,b\n1,2,3',
        const DelimitedConfig(raggedRows: RaggedRowPolicy.preserve),
      );
      expect(doc[1], ['1', '2', '3']);
    });

    test('padWithEmpty pads short rows', () {
      final doc = _parse(
        'a,b,c\n1\n4,5,6',
        const DelimitedConfig(raggedRows: RaggedRowPolicy.padWithEmpty),
      );
      expect(doc[1], ['1', '', '']);
    });

    test('padWithEmpty does not truncate long rows', () {
      final doc = _parse(
        'a,b\n1,2,3,4',
        const DelimitedConfig(raggedRows: RaggedRowPolicy.padWithEmpty),
      );
      expect(doc[1], ['1', '2', '3', '4']);
    });

    test('error throws on short row', () {
      expect(
        () => _parse(
          'a,b,c\n1,2',
          const DelimitedConfig(raggedRows: RaggedRowPolicy.error),
        ),
        throwsFormatException,
      );
    });

    test('error throws on long row', () {
      expect(
        () => _parse(
          'a,b\n1,2,3',
          const DelimitedConfig(raggedRows: RaggedRowPolicy.error),
        ),
        throwsFormatException,
      );
    });

    test('uniform rows pass error policy', () {
      expect(
        _parse(
          'a,b\n1,2\n3,4',
          const DelimitedConfig(raggedRows: RaggedRowPolicy.error),
        ),
        [
          ['a', 'b'],
          ['1', '2'],
          ['3', '4'],
        ],
      );
    });
  });

  // =========================================================================
  // ROBUST MODE (Tier 3) — per-row dialect adaptation
  // =========================================================================

  group('Robust parsing', () {
    test('uniform comma file', () {
      final r = parseDelimitedRobust('a,b,c\n1,2,3');
      expect((r as Success).value, [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
    });

    test('mixed comma and tab rows', () {
      final r = parseDelimitedRobust('a,b,c\n1,2,3\n4\t5\t6');
      expect((r as Success).value, [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
        ['4', '5', '6'],
      ]);
    });

    test('mixed comma and semicolon rows', () {
      final r = parseDelimitedRobust('a,b,c\n1,2,3\n4;5;6');
      expect((r as Success).value, [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
        ['4', '5', '6'],
      ]);
    });

    test('row that matches no delimiter falls back to default', () {
      final r = parseDelimitedRobust('a,b,c\n1,2,3\nno-delimiters-here');
      final doc = (r as Success<ParseError, DelimitedDocument>).value;
      expect(doc.length, 3);
      expect(doc[2], ['no-delimiters-here']);
    });

    test('every row different delimiter', () {
      final r = parseDelimitedRobust('a,b,c\n1\t2\t3\n4;5;6\n7|8|9');
      final doc = (r as Success<ParseError, DelimitedDocument>).value;
      expect(doc.length, 4);
      expect(doc[1], ['1', '2', '3']);
      expect(doc[2], ['4', '5', '6']);
      expect(doc[3], ['7', '8', '9']);
    });

    test('empty file', () {
      final r = parseDelimitedRobust('');
      expect((r as Success).value, isEmpty);
    });
  });

  // =========================================================================
  // UNICODE AND ENCODING
  // =========================================================================

  group('Unicode', () {
    test('CJK characters in fields', () {
      expect(_parse('名前,年齢\n太郎,30'), [
        ['名前', '年齢'],
        ['太郎', '30'],
      ]);
    });

    test('emoji in fields', () {
      expect(_parse('a,🎉\n1,🚀'), [
        ['a', '🎉'],
        ['1', '🚀'],
      ]);
    });

    test('accented characters', () {
      expect(_parse('café,naïve,résumé'), [
        ['café', 'naïve', 'résumé'],
      ]);
    });

    test('mixed scripts', () {
      expect(_parse('English,العربية,中文,日本語'), [
        ['English', 'العربية', '中文', '日本語'],
      ]);
    });
  });

  // =========================================================================
  // WHITESPACE EDGE CASES
  // =========================================================================

  group('Whitespace edge cases', () {
    test('field containing only spaces', () {
      expect(_parse('   ,b'), [
        ['   ', 'b'],
      ]);
    });

    test('field containing only tab', () {
      expect(_parse('\t,b'), [
        ['\t', 'b'],
      ]);
    });

    test('spaces around quoted field (not trimmed by default)', () {
      // RFC 4180 doesn't define this; we preserve spaces
      expect(_parse('  "val"  ,next'), [
        ['  "val"  ', 'next'],
      ]);
    });

    test('spaces around quoted field (trimmed when configured)', () {
      expect(
        _parse('  "val"  ,next', const DelimitedConfig(trimWhitespace: true)),
        [
          ['"val"', 'next'],
        ],
      );
    });
  });

  // =========================================================================
  // LARGE / DEGENERATE INPUTS
  // =========================================================================

  group('Large inputs', () {
    test('row with 100 fields', () {
      final row = List.generate(100, (i) => 'f$i').join(',');
      final doc = _parse(row);
      expect(doc[0].length, 100);
      expect(doc[0][0], 'f0');
      expect(doc[0][99], 'f99');
    });

    test('field with 10000 characters', () {
      final longField = 'x' * 10000;
      final doc = _parse('$longField,short');
      expect(doc[0][0].length, 10000);
      expect(doc[0][1], 'short');
    });

    test('1000 rows', () {
      final rows = List.generate(1000, (i) => '$i,${i * 2}').join('\n');
      final doc = _parse(rows);
      expect(doc.length, 1000);
      expect(doc[0], ['0', '0']);
      expect(doc[999], ['999', '1998']);
    });

    test('empty rows interspersed', () {
      final doc = _parse('a,b\n\nc,d\n\ne,f');
      expect(doc.length, 5); // Includes empty rows
      expect(doc[0], ['a', 'b']);
      expect(doc[1], ['']);
      expect(doc[2], ['c', 'd']);
    });

    test('empty rows skipped when configured', () {
      final doc = _parse(
        'a,b\n\nc,d\n\ne,f',
        const DelimitedConfig(skipEmptyLines: true),
      );
      expect(doc.length, 3);
      expect(doc[0], ['a', 'b']);
      expect(doc[1], ['c', 'd']);
      expect(doc[2], ['e', 'f']);
    });
  });

  // =========================================================================
  // SERIALIZATION ROUND-TRIP
  // =========================================================================

  group('Round-trip', () {
    test('simple round-trip', () {
      final original = [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ];
      final serialized = serializeCsv(original);
      final reparsed = _parse(serialized);
      expect(reparsed, original);
    });

    test('round-trip with commas and quotes in fields', () {
      final original = [
        ['has,comma', 'has"quote', 'normal'],
      ];
      final serialized = serializeCsv(original);
      final reparsed = _parse(serialized);
      expect(reparsed, original);
    });

    test('round-trip with newlines in fields', () {
      final original = [
        ['line1\nline2', 'normal'],
      ];
      final serialized = serializeCsv(original);
      final reparsed = _parse(serialized);
      expect(reparsed, original);
    });

    test('round-trip with headers', () {
      final headers = ['name', 'age'];
      final rows = [
        ['Alice', '30'],
        ['Bob', '25'],
      ];
      final serialized = serializeCsvWithHeaders(headers, rows);
      final (rHeaders, rRows) = _parseH(serialized);
      expect(rHeaders, headers);
      expect(rRows, rows);
    });
  });

  // =========================================================================
  // BACKWARD COMPATIBILITY
  // =========================================================================

  group('Backward compatibility', () {
    test('parseCsv still works', () {
      final r = parseCsv('a,b\n1,2');
      expect((r as Success).value, [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('parseTsv still works', () {
      final r = parseTsv('a\tb\n1\t2');
      expect((r as Success).value, [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('parseCsvWithHeaders still works', () {
      final r = parseCsvWithHeaders('name,age\nAlice,30');
      final (headers, rows) =
          (r as Success<ParseError, (List<String>, DelimitedDocument)>).value;
      expect(headers, ['name', 'age']);
      expect(rows, [
        ['Alice', '30'],
      ]);
    });

    test('CsvConfig is an alias for DelimitedConfig', () {
      const config = CsvConfig(delimiter: ';');
      expect(config.delimiter, ';');
      expect(config, isA<DelimitedConfig>());
    });

    test('CsvDocument is an alias for DelimitedDocument', () {
      final CsvDocument doc = [
        ['a', 'b'],
      ];
      expect(doc, isA<DelimitedDocument>());
    });
  });
}
