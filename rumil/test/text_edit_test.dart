import 'package:rumil/rumil.dart';
import 'package:test/test.dart';

void main() {
  group('constructors and classification', () {
    test('insert', () {
      final e = TextEdit.insert(5, 'x');
      expect(e.startOffset, 5);
      expect(e.endOffset, 5);
      expect(e.newText, 'x');
      expect(e.isInsertion, isTrue);
      expect(e.isDeletion, isFalse);
      expect(e.isReplacement, isFalse);
    });

    test('delete', () {
      final e = TextEdit.delete(10, 15);
      expect(e.deleteLength, 5);
      expect(e.insertLength, 0);
      expect(e.isDeletion, isTrue);
      expect(e.isInsertion, isFalse);
    });

    test('replace', () {
      final e = TextEdit.replace(0, 3, 'bar');
      expect(e.isReplacement, isTrue);
      expect(e.deleteLength, 3);
      expect(e.insertLength, 3);
    });
  });

  group('lengthDelta', () {
    test('insertion grows', () {
      expect(TextEdit.insert(0, 'abc').lengthDelta, 3);
    });
    test('deletion shrinks', () {
      expect(TextEdit.delete(0, 4).lengthDelta, -4);
    });
    test('equal-size replacement is neutral', () {
      expect(TextEdit.replace(0, 3, 'xyz').lengthDelta, 0);
    });
    test('uneven replacement', () {
      expect(TextEdit.replace(0, 2, 'xyz').lengthDelta, 1);
    });
  });

  group('apply', () {
    test('insertion', () {
      expect(TextEdit.insert(2, 'XY').apply('abcd'), 'abXYcd');
    });
    test('insertion at start', () {
      expect(TextEdit.insert(0, 'X').apply('abc'), 'Xabc');
    });
    test('insertion at end', () {
      expect(TextEdit.insert(3, 'X').apply('abc'), 'abcX');
    });
    test('deletion', () {
      expect(TextEdit.delete(1, 3).apply('abcd'), 'ad');
    });
    test('replacement', () {
      expect(TextEdit.replace(1, 3, 'XYZ').apply('abcd'), 'aXYZd');
    });
  });

  group('affects', () {
    final e = TextEdit.replace(5, 10, 'x'); // edits [5,10)
    test('range fully before is unaffected', () {
      expect(e.affects(0, 5), isFalse);
    });
    test('range fully after is unaffected', () {
      expect(e.affects(10, 15), isFalse);
    });
    test('overlapping range is affected', () {
      expect(e.affects(7, 12), isTrue);
    });
    test('containing range is affected', () {
      expect(e.affects(0, 20), isTrue);
    });
  });

  group('adjustOffset', () {
    // Replace [5,10) (length 5) with 2 chars: lengthDelta = -3.
    final e = TextEdit.replace(5, 10, 'XY');
    test('before the edit: unchanged', () {
      expect(e.adjustOffset(3), 3);
      expect(e.adjustOffset(5), 5); // at start, unchanged
    });
    test('inside the deleted range: collapses to start', () {
      expect(e.adjustOffset(7), 5);
      expect(e.adjustOffset(9), 5);
    });
    test('after the edit: shifts by lengthDelta', () {
      expect(e.adjustOffset(10), 7); // 10 + (-3)
      expect(e.adjustOffset(20), 17);
    });
  });

  group('compose', () {
    test('shifts later edits by earlier deltas', () {
      // Two insertions; the second's offset must account for the first.
      final composed = TextEdit.compose([
        TextEdit.insert(0, 'AA'), // +2
        TextEdit.insert(5, 'B'), // original offset 5
      ]);
      expect(composed[0].startOffset, 0);
      expect(composed[1].startOffset, 7); // 5 + 2
    });

    test('applying composed edits left-to-right is consistent', () {
      var source = 'abcde';
      final composed = TextEdit.compose([
        TextEdit.insert(0, 'AA'),
        TextEdit.delete(2, 4), // delete 'cd' in the original
      ]);
      for (final e in composed) {
        source = e.apply(source);
      }
      // 'abcde' -> insert AA at 0 -> 'AAabcde'
      //          -> delete original [2,4)='cd', now at [4,6) -> 'AAabe'
      expect(source, 'AAabe');
    });

    test('empty list composes to empty', () {
      expect(TextEdit.compose(const []), isEmpty);
    });
  });

  group('toString', () {
    test('insertion form', () {
      expect(TextEdit.insert(3, 'x').toString(), contains('insert'));
    });
    test('deletion form', () {
      expect(TextEdit.delete(1, 4).toString(), contains('delete'));
    });
    test('replacement form', () {
      expect(TextEdit.replace(1, 4, 'xy').toString(), contains('replace'));
    });
  });
}
