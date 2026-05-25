import 'package:rumil/rumil.dart';
import 'package:test/test.dart';

void _expectLoc(
  Location actual, {
  required int line,
  required int column,
  required int offset,
}) {
  expect(actual.line, line, reason: 'line');
  expect(actual.column, column, reason: 'column');
  expect(actual.offset, offset, reason: 'offset');
}

void main() {
  group('LineIndex', () {
    test('single-line source: offsets map to column 1..len+1 on line 1', () {
      final idx = LineIndex('hello');
      _expectLoc(idx.locationAt(0), line: 1, column: 1, offset: 0);
      _expectLoc(idx.locationAt(3), line: 1, column: 4, offset: 3);
      // EOF: one past the last character.
      _expectLoc(idx.locationAt(5), line: 1, column: 6, offset: 5);
    });

    test('multi-line source: newline char belongs to its preceding line', () {
      final idx = LineIndex('abc\ndef\nghi');
      _expectLoc(idx.locationAt(0), line: 1, column: 1, offset: 0);
      // The '\n' at offset 3 sits on line 1, column 4.
      _expectLoc(idx.locationAt(3), line: 1, column: 4, offset: 3);
      // The 'd' at offset 4 starts line 2.
      _expectLoc(idx.locationAt(4), line: 2, column: 1, offset: 4);
      _expectLoc(idx.locationAt(7), line: 2, column: 4, offset: 7);
      _expectLoc(idx.locationAt(8), line: 3, column: 1, offset: 8);
      // EOF.
      _expectLoc(idx.locationAt(11), line: 3, column: 4, offset: 11);
    });

    test('empty source: offset 0 is (1, 1)', () {
      final idx = LineIndex('');
      _expectLoc(idx.locationAt(0), line: 1, column: 1, offset: 0);
    });

    test('multiple consecutive newlines: each blank line is its own line', () {
      final idx = LineIndex('a\n\n\nb');
      _expectLoc(idx.locationAt(0), line: 1, column: 1, offset: 0);
      // Offset 1 is the first '\n' — on line 1, column 2.
      _expectLoc(idx.locationAt(1), line: 1, column: 2, offset: 1);
      // Offset 2 is the second '\n' — start of line 2 (which is blank).
      _expectLoc(idx.locationAt(2), line: 2, column: 1, offset: 2);
      // Offset 3 is the third '\n' — start of line 3 (also blank).
      _expectLoc(idx.locationAt(3), line: 3, column: 1, offset: 3);
      // Offset 4 is 'b' — start of line 4.
      _expectLoc(idx.locationAt(4), line: 4, column: 1, offset: 4);
    });

    test('offset past source.length: not clamped; resolves via last newline', () {
      final idx = LineIndex('abc\ndef');
      // Source has one '\n' at offset 3. locationAt(7) = column 7 - 3 = 4 on line 2.
      _expectLoc(idx.locationAt(7), line: 2, column: 4, offset: 7);
      // Past the last newline, column grows linearly with offset.
      _expectLoc(idx.locationAt(100), line: 2, column: 97, offset: 100);
    });

    test(
      'source without any newline: column = offset + 1 on line 1 for any offset',
      () {
        final idx = LineIndex('abc');
        _expectLoc(idx.locationAt(0), line: 1, column: 1, offset: 0);
        _expectLoc(idx.locationAt(3), line: 1, column: 4, offset: 3);
      },
    );

    test(
      'locationAt past end of a single-line source uses offset + 1 as the column',
      () {
        final idx = LineIndex('abc');
        _expectLoc(idx.locationAt(100), line: 1, column: 101, offset: 100);
      },
    );

    test('negative offset: clamped to 0 → (1, 1)', () {
      final idx = LineIndex('anything\nhere');
      _expectLoc(idx.locationAt(-1), line: 1, column: 1, offset: 0);
      _expectLoc(idx.locationAt(-999), line: 1, column: 1, offset: 0);
    });

    test('spanAt: both endpoints carry real line/column', () {
      final idx = LineIndex('hello\nworld');
      final span = idx.spanAt(0, 11);
      _expectLoc(span.start, line: 1, column: 1, offset: 0);
      _expectLoc(span.end, line: 2, column: 6, offset: 11);
    });

    test('spanAt with start == end: zero-width span at a single location', () {
      final idx = LineIndex('ab\ncd');
      final span = idx.spanAt(3, 3);
      _expectLoc(span.start, line: 2, column: 1, offset: 3);
      _expectLoc(span.end, line: 2, column: 1, offset: 3);
    });

    test('tab characters count as a single column (no tabstop expansion)', () {
      final idx = LineIndex('a\tb');
      // Offset 2 is 'b'; two columns after the start, regardless of tab width.
      _expectLoc(idx.locationAt(2), line: 1, column: 3, offset: 2);
    });

    test('UTF-16 code units: column counts code units, not codepoints', () {
      // '\u{1F600}' (emoji) occupies two UTF-16 code units in a Dart String.
      const src = 'a😀b'; // a + 😀 + b, length 4 in code units
      final idx = LineIndex(src);
      expect(src.length, 4);
      // 'b' sits at code-unit offset 3 → column 4.
      _expectLoc(idx.locationAt(3), line: 1, column: 4, offset: 3);
    });

    test('surrogate pair: each UTF-16 code unit is its own column', () {
      const src = 'a😀b'; // a + 😀 (high+low surrogates) + b
      final idx = LineIndex(src);
      expect(src.length, 4);
      // a — line 1, column 1.
      _expectLoc(idx.locationAt(0), line: 1, column: 1, offset: 0);
      // High surrogate — line 1, column 2.
      _expectLoc(idx.locationAt(1), line: 1, column: 2, offset: 1);
      // Low surrogate — line 1, column 3. The pair contributes two columns, not one.
      _expectLoc(idx.locationAt(2), line: 1, column: 3, offset: 2);
      // b — line 1, column 4.
      _expectLoc(idx.locationAt(3), line: 1, column: 4, offset: 3);
    });

    // --- Line-terminator policy: only \n is a terminator; \r is regular. ---

    test(
      'CRLF input: \\r is a trailing character of preceding line; \\n ends the line',
      () {
        final idx = LineIndex('a\r\nb');
        // 'a' at offset 0 — line 1, column 1.
        _expectLoc(idx.locationAt(0), line: 1, column: 1, offset: 0);
        // '\r' at offset 1 — still line 1, column 2 (a regular character).
        _expectLoc(idx.locationAt(1), line: 1, column: 2, offset: 1);
        // '\n' at offset 2 — still line 1, column 3 (newline sits on its preceding line).
        _expectLoc(idx.locationAt(2), line: 1, column: 3, offset: 2);
        // 'b' at offset 3 — first character of line 2.
        _expectLoc(idx.locationAt(3), line: 2, column: 1, offset: 3);
      },
    );

    test(
      'CRLF input with larger prose: each \\r consumes a column on its line',
      () {
        final idx = LineIndex('abc\r\ndef');
        _expectLoc(idx.locationAt(0), line: 1, column: 1, offset: 0);
        // '\r' at offset 3 — column 4 of line 1 (not a terminator).
        _expectLoc(idx.locationAt(3), line: 1, column: 4, offset: 3);
        // '\n' at offset 4 — column 5 of line 1 (the terminator itself sits on line 1).
        _expectLoc(idx.locationAt(4), line: 1, column: 5, offset: 4);
        // 'd' at offset 5 — first character of line 2.
        _expectLoc(idx.locationAt(5), line: 2, column: 1, offset: 5);
      },
    );

    test('CR-only input (legacy Mac Classic): \\r is not a terminator', () {
      final idx = LineIndex('a\rb');
      _expectLoc(idx.locationAt(0), line: 1, column: 1, offset: 0);
      // '\r' at offset 1 — still line 1, column 2.
      _expectLoc(idx.locationAt(1), line: 1, column: 2, offset: 1);
      // 'b' at offset 2 — still line 1, column 3.
      _expectLoc(idx.locationAt(2), line: 1, column: 3, offset: 2);
    });

    test('LF-only input (the canonical case) is unchanged', () {
      final idx = LineIndex('a\nb');
      _expectLoc(idx.locationAt(0), line: 1, column: 1, offset: 0);
      _expectLoc(idx.locationAt(1), line: 1, column: 2, offset: 1);
      _expectLoc(idx.locationAt(2), line: 2, column: 1, offset: 2);
    });

    test('locations carry the source string (format includes line:column)', () {
      final idx = LineIndex('first\nsecond');
      final loc = idx.locationAt(6); // 's' on line 2
      expect(loc.format(), '2:1 (offset 6)');
    });
  });
}
