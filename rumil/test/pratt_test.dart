import 'dart:math' as math;

import 'package:rumil/rumil.dart';
import 'package:test/test.dart';

T val<T>(Result<Object?, T> r) => switch (r) {
  Success<Object?, T>(:final value) => value,
  Partial<Object?, T>(:final value) => value,
  Failure() => throw StateError('Expected success, got $r'),
};

void main() {
  final num = digit().map(int.parse);

  group('pratt — parity with chainl1', () {
    Parser<ParseError, int> prattExpr() => pratt<int>(num, [
      InfixLeft(char('+'), 10, (int a, int b) => a + b),
      InfixLeft(char('-'), 10, (int a, int b) => a - b),
      InfixLeft(char('*'), 20, (int a, int b) => a * b),
      InfixLeft(char('/'), 20, (int a, int b) => a ~/ b),
    ]);

    test('single digit', () {
      expect(val(prattExpr().run('5')), 5);
    });

    test('left-associative subtraction', () {
      expect(val(prattExpr().run('5-3-1')), 1);
    });

    test('precedence: 1+2*3 = 7', () {
      expect(val(prattExpr().run('1+2*3')), 7);
    });

    test('precedence: 2*3+4 = 10', () {
      expect(val(prattExpr().run('2*3+4')), 10);
    });

    test('deep chain', () {
      // sum of 1..9 then +0 = 45
      expect(val(prattExpr().run('1+2+3+4+5+6+7+8+9')), 45);
    });
  });

  group('pratt — features beyond chainl1', () {
    test('right-associative power: 2^3^2 = 512', () {
      final p = pratt<int>(num, [
        InfixRight(
          char('^'),
          30,
          (int a, int b) => math.pow(a, b).toInt(),
        ),
      ]);
      expect(val(p.run('2^3^2')), 512);
    });

    test('prefix unary minus: -5+3 = -2', () {
      final p = pratt<int>(num, [
        InfixLeft(char('+'), 10, (int a, int b) => a + b),
        Prefix(char('-'), 40, (int a) => -a),
      ]);
      expect(val(p.run('-5+3')), -2);
    });

    test('prefix binds tighter than infix: -2^3 = -8 (i.e. (-2)^3)', () {
      final p = pratt<int>(num, [
        InfixRight(
          char('^'),
          30,
          (int a, int b) => math.pow(a, b).toInt(),
        ),
        Prefix(char('-'), 40, (int a) => -a),
      ]);
      // With prefix bp=40 > infix ^ bp=30, -2 binds before ^.
      expect(val(p.run('-2^3')), -8);
    });

    test('postfix applies to LHS: 5! with apply=n*10 → 50', () {
      final p = pratt<int>(num, [
        Postfix(char('!'), 50, (int a) => a * 10),
      ]);
      expect(val(p.run('5!')), 50);
    });

    test('postfix chains left-to-right: 5!!! with apply=n+1 → 8', () {
      final p = pratt<int>(num, [
        Postfix(char('!'), 50, (int a) => a + 1),
      ]);
      expect(val(p.run('5!!!')), 8);
    });

    test('mixed assoc: 1+2^3+4 = (1+(2^3))+4 = 13', () {
      final p = pratt<int>(num, [
        InfixLeft(char('+'), 10, (int a, int b) => a + b),
        InfixRight(
          char('^'),
          30,
          (int a, int b) => math.pow(a, b).toInt(),
        ),
      ]);
      expect(val(p.run('1+2^3+4')), 13);
    });

    test('three-level precedence: 1+2*3^2 = 1+(2*(3^2)) = 19', () {
      final p = pratt<int>(num, [
        InfixLeft(char('+'), 10, (int a, int b) => a + b),
        InfixLeft(char('*'), 20, (int a, int b) => a * b),
        InfixRight(
          char('^'),
          30,
          (int a, int b) => math.pow(a, b).toInt(),
        ),
      ]);
      expect(val(p.run('1+2*3^2')), 19);
    });

    test('no operators: pratt reduces to nud', () {
      final p = pratt<int>(num, []);
      expect(val(p.run('7')), 7);
    });
  });

  group('pratt — error paths', () {
    test('atom failure propagates as failure', () {
      final p = pratt<int>(num, [
        InfixLeft(char('+'), 10, (int a, int b) => a + b),
      ]);
      expect(p.run('x'), isA<Failure<Object?, Object?>>());
    });

    test('RHS failure after operator propagates', () {
      final p = pratt<int>(num, [
        InfixLeft(char('+'), 10, (int a, int b) => a + b),
      ]);
      expect(p.run('1+x'), isA<Failure<Object?, Object?>>());
    });

    test('unknown operator stops chain cleanly (no error)', () {
      final p = pratt<int>(num, [
        InfixLeft(char('+'), 10, (int a, int b) => a + b),
      ]);
      // Consumes "1+2", leaves "-3". partial success model: parseAll
      // behavior depends on run semantics — here we just check parsed prefix.
      expect(val(p.run('1+2-3')), 3);
    });
  });

  group('pratt — parenthesized sub-expressions', () {
    test('(1+2)*3 = 9', () {
      late final Parser<ParseError, int> expr;
      late final Parser<ParseError, int> atom;
      atom = Or(num, FlatMap(char('('), (_) => FlatMap(Defer(() => expr), (int e) => FlatMap(char(')'), (_) => Succeed(e)))));
      expr = pratt<int>(Defer(() => atom), [
        InfixLeft(char('+'), 10, (int a, int b) => a + b),
        InfixLeft(char('*'), 20, (int a, int b) => a * b),
      ]);
      expect(val(expr.run('(1+2)*3')), 9);
    });

    test('((2+3)*4)+5 = 25', () {
      late final Parser<ParseError, int> expr;
      late final Parser<ParseError, int> atom;
      atom = Or(num, FlatMap(char('('), (_) => FlatMap(Defer(() => expr), (int e) => FlatMap(char(')'), (_) => Succeed(e)))));
      expr = pratt<int>(Defer(() => atom), [
        InfixLeft(char('+'), 10, (int a, int b) => a + b),
        InfixLeft(char('-'), 10, (int a, int b) => a - b),
        InfixLeft(char('*'), 20, (int a, int b) => a * b),
      ]);
      expect(val(expr.run('((2+3)*4)+5')), 25);
    });
  });
}
