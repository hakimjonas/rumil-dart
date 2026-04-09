import 'package:rumil/rumil.dart' hide fail;
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

TomlDocument doc_(Result<ParseError, TomlDocument> r) => switch (r) {
  Success<ParseError, TomlDocument>(:final value) => value,
  Partial<ParseError, TomlDocument>(:final value) => value,
  Failure() => throw StateError('Expected success, got ${r.errors}'),
};

void main() {
  // ---- Strings ----

  group('TOML strings', () {
    test('basic string', () {
      final d = doc_(parseToml('str = "hello world"\n'));
      expect((d['str'] as TomlString).value, 'hello world');
    });

    test('basic string with escapes', () {
      final d = doc_(parseToml('str = "line1\\nline2"\n'));
      final v = (d['str'] as TomlString).value;
      expect(v, contains('\n'));
      expect(v, 'line1\nline2');
    });

    test('basic string with unicode escape', () {
      final d = doc_(parseToml('str = "\\u0041"\n'));
      expect((d['str'] as TomlString).value, 'A');
    });

    test('literal string (no escapes)', () {
      final d = doc_(parseToml("str = 'C:\\\\Users\\\\path'\n"));
      expect((d['str'] as TomlString).value, 'C:\\\\Users\\\\path');
    });

    test('multi-line basic string', () {
      final d = doc_(parseToml('str = """\nmulti\nline\n"""\n'));
      expect((d['str'] as TomlString).value, 'multi\nline\n');
    });

    test('multi-line basic string strips first newline', () {
      final d = doc_(parseToml('str = """\nhello"""\n'));
      expect((d['str'] as TomlString).value, 'hello');
    });

    test('multi-line literal string', () {
      final d = doc_(parseToml("str = '''\nno \\escape\n'''\n"));
      expect((d['str'] as TomlString).value, 'no \\escape\n');
    });
  });

  // ---- Integers ----

  group('TOML integers', () {
    test('positive integer', () {
      final d = doc_(parseToml('num = 42\n'));
      expect((d['num'] as TomlInteger).value, 42);
    });

    test('negative integer', () {
      final d = doc_(parseToml('num = -17\n'));
      expect((d['num'] as TomlInteger).value, -17);
    });

    test('positive sign', () {
      final d = doc_(parseToml('num = +99\n'));
      expect((d['num'] as TomlInteger).value, 99);
    });

    test('hex integer', () {
      final d = doc_(parseToml('hex = 0xFF\n'));
      expect((d['hex'] as TomlInteger).value, 255);
    });

    test('octal integer', () {
      final d = doc_(parseToml('oct = 0o755\n'));
      expect((d['oct'] as TomlInteger).value, 493);
    });

    test('binary integer', () {
      final d = doc_(parseToml('bin = 0b11111111\n'));
      expect((d['bin'] as TomlInteger).value, 255);
    });

    test('underscores', () {
      final d = doc_(parseToml('num = 1_000_000\n'));
      expect((d['num'] as TomlInteger).value, 1000000);
    });
  });

  // ---- Floats ----

  group('TOML floats', () {
    test('simple float', () {
      final d = doc_(parseToml('pi = 3.14\n'));
      expect((d['pi'] as TomlFloat).value, 3.14);
    });

    test('float with exponent', () {
      final d = doc_(parseToml('num = 5e+22\n'));
      expect((d['num'] as TomlFloat).value, 5e+22);
    });

    test('float with fraction and exponent', () {
      final d = doc_(parseToml('num = 6.626e-34\n'));
      expect((d['num'] as TomlFloat).value, closeTo(6.626e-34, 1e-40));
    });

    test('infinity', () {
      final d = doc_(parseToml('val = inf\n'));
      expect((d['val'] as TomlFloat).value, double.infinity);
    });

    test('negative infinity', () {
      final d = doc_(parseToml('val = -inf\n'));
      expect((d['val'] as TomlFloat).value, double.negativeInfinity);
    });

    test('nan', () {
      final d = doc_(parseToml('val = nan\n'));
      expect((d['val'] as TomlFloat).value, isNaN);
    });
  });

  // ---- Booleans ----

  group('TOML booleans', () {
    test('true', () {
      final d = doc_(parseToml('flag = true\n'));
      expect((d['flag'] as TomlBool).value, true);
    });

    test('false', () {
      final d = doc_(parseToml('flag = false\n'));
      expect((d['flag'] as TomlBool).value, false);
    });
  });

  // ---- Datetimes ----

  group('TOML datetimes', () {
    test('offset datetime', () {
      final d = doc_(parseToml('dt = 1979-05-27T07:32:00Z\n'));
      final v = d['dt'] as TomlDateTime;
      expect(v.value.year, 1979);
      expect(v.value.month, 5);
      expect(v.value.day, 27);
      expect(v.value.isUtc, true);
    });

    test('offset datetime with offset', () {
      final d = doc_(parseToml('dt = 1979-05-27T07:32:00-08:00\n'));
      final v = d['dt'] as TomlDateTime;
      expect(v.value.isUtc, true);
      // 07:32 - (-08:00) = 15:32 UTC
      expect(v.value.hour, 15);
      expect(v.value.minute, 32);
    });

    test('local datetime', () {
      final d = doc_(parseToml('dt = 1979-05-27T07:32:00\n'));
      final v = d['dt'] as TomlLocalDateTime;
      expect(v.value.year, 1979);
      expect(v.value.hour, 7);
    });

    test('local date', () {
      final d = doc_(parseToml('dt = 1979-05-27\n'));
      final v = d['dt'] as TomlLocalDate;
      expect(v.year, 1979);
      expect(v.month, 5);
      expect(v.day, 27);
    });

    test('local time', () {
      final d = doc_(parseToml('dt = 07:32:00\n'));
      final v = d['dt'] as TomlLocalTime;
      expect(v.hour, 7);
      expect(v.minute, 32);
      expect(v.second, 0);
    });

    test('datetime with fractional seconds', () {
      final d = doc_(parseToml('dt = 1979-05-27T07:32:00.999999Z\n'));
      final v = d['dt'] as TomlDateTime;
      expect(v.value.year, 1979);
    });
  });

  // ---- Arrays ----

  group('TOML arrays', () {
    test('empty array', () {
      final d = doc_(parseToml('arr = []\n'));
      expect((d['arr'] as TomlArray).elements, isEmpty);
    });

    test('integer array', () {
      final d = doc_(parseToml('arr = [1, 2, 3]\n'));
      final elems = (d['arr'] as TomlArray).elements;
      expect(elems.length, 3);
      expect((elems[0] as TomlInteger).value, 1);
      expect((elems[1] as TomlInteger).value, 2);
      expect((elems[2] as TomlInteger).value, 3);
    });

    test('string array', () {
      final d = doc_(parseToml('arr = ["a", "b", "c"]\n'));
      final elems = (d['arr'] as TomlArray).elements;
      expect(elems.length, 3);
    });

    test('mixed array', () {
      final d = doc_(parseToml('arr = [1, "two", 3.0]\n'));
      final elems = (d['arr'] as TomlArray).elements;
      expect(elems[0], isA<TomlInteger>());
      expect(elems[1], isA<TomlString>());
      expect(elems[2], isA<TomlFloat>());
    });

    test('nested array', () {
      final d = doc_(parseToml('arr = [[1, 2], [3, 4]]\n'));
      final elems = (d['arr'] as TomlArray).elements;
      expect(elems.length, 2);
      expect(elems[0], isA<TomlArray>());
    });

    test('trailing comma', () {
      final d = doc_(parseToml('arr = [1, 2, 3,]\n'));
      expect((d['arr'] as TomlArray).elements.length, 3);
    });

    test('multi-line array', () {
      final d = doc_(parseToml('arr = [\n  1,\n  2,\n  3,\n]\n'));
      expect((d['arr'] as TomlArray).elements.length, 3);
    });
  });

  // ---- Inline tables ----

  group('TOML inline tables', () {
    test('empty inline table', () {
      final d = doc_(parseToml('tbl = {}\n'));
      expect((d['tbl'] as TomlTable).pairs, isEmpty);
    });

    test('inline table with values', () {
      final d = doc_(parseToml('point = { x = 1, y = 2 }\n'));
      final tbl = (d['point'] as TomlTable).pairs;
      expect((tbl['x'] as TomlInteger).value, 1);
      expect((tbl['y'] as TomlInteger).value, 2);
    });
  });

  // ---- Comments ----

  group('TOML comments', () {
    test('comment-only line', () {
      final d = doc_(parseToml('# comment\nkey = "value"\n'));
      expect((d['key'] as TomlString).value, 'value');
    });

    test('inline comment', () {
      final d = doc_(parseToml('key = "value" # inline comment\n'));
      expect((d['key'] as TomlString).value, 'value');
    });
  });

  // ---- Document structure ----

  group('TOML document structure', () {
    test('multiple key-value pairs', () {
      final d = doc_(parseToml('name = "Alice"\nage = 30\nactive = true\n'));
      expect((d['name'] as TomlString).value, 'Alice');
      expect((d['age'] as TomlInteger).value, 30);
      expect((d['active'] as TomlBool).value, true);
    });

    test('dotted key', () {
      final d = doc_(parseToml('a.b.c = 1\n'));
      final a = d['a'] as TomlTable;
      final b = a.pairs['b'] as TomlTable;
      expect((b.pairs['c'] as TomlInteger).value, 1);
    });

    test('table header', () {
      final d = doc_(parseToml('[owner]\nname = "Tom"\n'));
      final owner = d['owner'] as TomlTable;
      expect((owner.pairs['name'] as TomlString).value, 'Tom');
    });

    test('nested table headers', () {
      final d = doc_(
        parseToml(
          'title = "Test"\n\n[database]\nserver = "192.168.1.1"\nports = [8000, 8001]\n',
        ),
      );
      expect((d['title'] as TomlString).value, 'Test');
      final db = d['database'] as TomlTable;
      expect((db.pairs['server'] as TomlString).value, '192.168.1.1');
      expect((db.pairs['ports'] as TomlArray).elements.length, 2);
    });

    test('array table', () {
      final d = doc_(
        parseToml(
          '[[products]]\nname = "Hammer"\n\n[[products]]\nname = "Nail"\n',
        ),
      );
      final arr = d['products'] as TomlArray;
      expect(arr.elements.length, 2);
      final first = (arr.elements[0] as TomlTable).pairs;
      final second = (arr.elements[1] as TomlTable).pairs;
      expect((first['name'] as TomlString).value, 'Hammer');
      expect((second['name'] as TomlString).value, 'Nail');
    });

    test('blank lines between pairs', () {
      final d = doc_(parseToml('a = 1\n\n\nb = 2\n'));
      expect((d['a'] as TomlInteger).value, 1);
      expect((d['b'] as TomlInteger).value, 2);
    });

    test('quoted keys', () {
      final d = doc_(parseToml('"key with spaces" = "value"\n'));
      expect((d['key with spaces'] as TomlString).value, 'value');
    });

    test('configuration file', () {
      final d = doc_(
        parseToml('''
# Application configuration
title = "TOML Example"

[owner]
name = "Tom Preston-Werner"

[database]
server = "192.168.1.1"
ports = [8000, 8001, 8002]
connection_max = 5000
enabled = true
'''),
      );
      expect((d['title'] as TomlString).value, 'TOML Example');
      final owner = d['owner'] as TomlTable;
      expect((owner.pairs['name'] as TomlString).value, 'Tom Preston-Werner');
      final db = d['database'] as TomlTable;
      expect((db.pairs['enabled'] as TomlBool).value, true);
      expect((db.pairs['connection_max'] as TomlInteger).value, 5000);
    });
  });
}
