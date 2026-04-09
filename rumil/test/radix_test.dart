import 'package:rumil/src/radix.dart';
import 'package:test/test.dart';

void main() {
  group('RadixNode', () {
    test('single string', () {
      final node = RadixNode.fromStrings(['hello']);
      expect(node.matchAtOrNull('hello world', 0), 'hello');
      expect(node.matchAtOrNull('goodbye', 0), isNull);
      expect(node.matchAt('hello', 0), 5);
      expect(node.matchAt('goodbye', 0), -1);
    });

    test('multiple strings with shared prefix', () {
      final node = RadixNode.fromStrings(['true', 'false', 'null']);
      expect(node.matchAtOrNull('true', 0), 'true');
      expect(node.matchAtOrNull('false', 0), 'false');
      expect(node.matchAtOrNull('null', 0), 'null');
      expect(node.matchAtOrNull('trueish', 0), 'true');
      expect(node.matchAtOrNull('truthy', 0), isNull);
      expect(node.matchAtOrNull('other', 0), isNull);
    });

    test('match at offset', () {
      final node = RadixNode.fromStrings(['abc', 'def']);
      expect(node.matchAtOrNull('xxxabc', 3), 'abc');
      expect(node.matchAtOrNull('xxxdef', 3), 'def');
      expect(node.matchAtOrNull('xxxghi', 3), isNull);
    });

    test('shared prefix strings', () {
      final node = RadixNode.fromStrings(['aaa', 'aab', 'bbb', 'bbc']);
      expect(node.matchAtOrNull('aaa', 0), 'aaa');
      expect(node.matchAtOrNull('aab', 0), 'aab');
      expect(node.matchAtOrNull('bbb', 0), 'bbb');
      expect(node.matchAtOrNull('bbc', 0), 'bbc');
      expect(node.matchAtOrNull('aac', 0), isNull);
    });

    test('prefix of another string', () {
      final node = RadixNode.fromStrings(['if', 'ifelse', 'else']);
      expect(node.matchAtOrNull('if', 0), 'if');
      expect(node.matchAtOrNull('ifelse', 0), 'ifelse');
      expect(node.matchAtOrNull('else', 0), 'else');
      expect(node.matchAtOrNull('iff', 0), 'if');
    });

    test('empty input', () {
      final node = RadixNode.fromStrings(['abc']);
      expect(node.matchAtOrNull('', 0), isNull);
    });

    test('input shorter than any target', () {
      final node = RadixNode.fromStrings(['hello']);
      expect(node.matchAtOrNull('hel', 0), isNull);
    });

    test('many alternatives', () {
      final keywords = [
        'abstract',
        'as',
        'assert',
        'async',
        'await',
        'break',
        'case',
        'catch',
        'class',
        'const',
        'continue',
        'default',
        'do',
        'else',
        'enum',
        'export',
        'extends',
        'factory',
        'final',
        'for',
      ];
      final node = RadixNode.fromStrings(keywords);
      for (final kw in keywords) {
        expect(node.matchAtOrNull(kw, 0), kw, reason: 'should match "$kw"');
      }
      expect(node.matchAtOrNull('xyz', 0), isNull);
      expect(node.matchAtOrNull('abs', 0), isNull);
    });

    test('duplicate strings handled', () {
      final node = RadixNode.fromStrings(['abc', 'abc', 'def']);
      expect(node.matchAtOrNull('abc', 0), 'abc');
      expect(node.matchAtOrNull('def', 0), 'def');
    });

    test('longest match wins', () {
      final node = RadixNode.fromStrings(['a', 'ab', 'abc']);
      expect(node.matchAtOrNull('abcdef', 0), 'abc');
      expect(node.matchAtOrNull('abxyz', 0), 'ab');
      expect(node.matchAtOrNull('axyz', 0), 'a');
    });
  });
}
