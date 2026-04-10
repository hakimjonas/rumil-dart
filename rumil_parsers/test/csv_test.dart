import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/src/csv.dart';
import 'package:test/test.dart';

CsvDocument val_(Result<ParseError, CsvDocument> r) => switch (r) {
  Success<ParseError, CsvDocument>(:final value) => value,
  Partial<ParseError, CsvDocument>(:final value) => value,
  Failure() => throw StateError('Expected success, got ${r.errors}'),
};

void main() {
  group('CSV basic', () {
    test('single field', () {
      final doc = val_(parseCsv('hello'));
      expect(doc, [
        ['hello'],
      ]);
    });

    test('single row', () {
      final doc = val_(parseCsv('a,b,c'));
      expect(doc, [
        ['a', 'b', 'c'],
      ]);
    });

    test('multiple rows', () {
      final doc = val_(parseCsv('a,b\nc,d'));
      expect(doc, [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('empty fields', () {
      final doc = val_(parseCsv(',b,'));
      expect(doc, [
        ['', 'b', ''],
      ]);
    });

    test('empty input', () {
      final doc = val_(parseCsv(''));
      expect(doc, [
        [''],
      ]);
    });
  });

  group('CSV quoted fields', () {
    test('simple quoted', () {
      final doc = val_(parseCsv('"hello",world'));
      expect(doc, [
        ['hello', 'world'],
      ]);
    });

    test('quoted with comma', () {
      final doc = val_(parseCsv('"a,b",c'));
      expect(doc, [
        ['a,b', 'c'],
      ]);
    });

    test('quoted with newline', () {
      final doc = val_(parseCsv('"a\nb",c'));
      expect(doc, [
        ['a\nb', 'c'],
      ]);
    });

    test('escaped quotes (doubled)', () {
      final doc = val_(parseCsv('"say ""hello""",done'));
      expect(doc, [
        ['say "hello"', 'done'],
      ]);
    });

    test('empty quoted field', () {
      final doc = val_(parseCsv('"",b'));
      expect(doc, [
        ['', 'b'],
      ]);
    });
  });

  group('TSV', () {
    test('tab separated', () {
      final doc = val_(parseTsv('a\tb\tc'));
      expect(doc, [
        ['a', 'b', 'c'],
      ]);
    });

    test('tabs with commas in values', () {
      final doc = val_(parseTsv('a,b\tc,d'));
      expect(doc, [
        ['a,b', 'c,d'],
      ]);
    });
  });

  group('CSV with headers', () {
    test('splits headers from data', () {
      final r = parseCsvWithHeaders('name,age\nAlice,30\nBob,25');
      if (r case Success(:final value)) {
        expect(value.$1, ['name', 'age']);
        expect(value.$2, [
          ['Alice', '30'],
          ['Bob', '25'],
        ]);
      } else {
        throw StateError('Expected success');
      }
    });
  });

  group('CSV config', () {
    test('trim whitespace', () {
      const config = CsvConfig(trimWhitespace: true);
      final doc = val_(parseCsv(' a , b ', config));
      expect(doc, [
        ['a', 'b'],
      ]);
    });

    test('skip empty lines', () {
      const config = CsvConfig(skipEmptyLines: true);
      final doc = val_(parseCsv('a,b\n\nc,d', config));
      expect(doc, [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('custom delimiter', () {
      const config = CsvConfig(delimiter: ';');
      final doc = val_(parseCsv('a;b;c', config));
      expect(doc, [
        ['a', 'b', 'c'],
      ]);
    });
  });

  group('CSV realistic', () {
    test('employee data', () {
      const input = '''name,age,city
Alice,30,"New York"
Bob,25,"San Francisco"
"Charlie ""Chuck""",35,Chicago''';
      final doc = val_(parseCsv(input));
      expect(doc.length, 4);
      expect(doc[0], ['name', 'age', 'city']);
      expect(doc[1], ['Alice', '30', 'New York']);
      expect(doc[3][0], 'Charlie "Chuck"');
    });
  });
}
