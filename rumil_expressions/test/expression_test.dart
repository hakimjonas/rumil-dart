import 'package:rumil/rumil.dart';
import 'package:rumil_expressions/rumil_expressions.dart';
import 'package:test/test.dart';

void main() {
  final env = Environment.standard(
    variables: {'x': 10.0, 'y': 3.0, 'name': 'Alice', 'flag': true},
  );

  group('Arithmetic', () {
    test('integer literal', () => expect(evaluate('42'), 42.0));
    test('negative literal', () => expect(evaluate('-5'), -5.0));
    test('decimal literal', () => expect(evaluate('3.14'), 3.14));
    test('addition', () => expect(evaluate('1 + 2'), 3.0));
    test('subtraction', () => expect(evaluate('10 - 4'), 6.0));
    test('multiplication', () => expect(evaluate('3 * 7'), 21.0));
    test('division', () => expect(evaluate('10 / 4'), 2.5));
    test('modulo', () => expect(evaluate('10 % 3'), 1.0));
    test('precedence: * before +', () => expect(evaluate('2 + 3 * 4'), 14.0));
    test(
      'precedence: parens override',
      () => expect(evaluate('(2 + 3) * 4'), 20.0),
    );
    test('left associative', () => expect(evaluate('10 - 3 - 2'), 5.0));
    test('nested parens', () => expect(evaluate('((1 + 2) * (3 + 4))'), 21.0));
  });

  group('Strings', () {
    test('string literal', () => expect(evaluate('"hello"'), 'hello'));
    test(
      'string concatenation',
      () => expect(evaluate('"hello" + " " + "world"'), 'hello world'),
    );
    test(
      'string + number coercion',
      () => expect(evaluate('"count: " + 42'), 'count: 42.0'),
    );
  });

  group('Booleans', () {
    test('true', () => expect(evaluate('true'), true));
    test('false', () => expect(evaluate('false'), false));
    test('not', () => expect(evaluate('!true'), false));
    test('and', () => expect(evaluate('true && false'), false));
    test('or', () => expect(evaluate('true || false'), true));
  });

  group('Comparison', () {
    test('less than', () => expect(evaluate('1 < 2'), true));
    test('greater than', () => expect(evaluate('3 > 2'), true));
    test('less equal', () => expect(evaluate('2 <= 2'), true));
    test('greater equal', () => expect(evaluate('1 >= 2'), false));
    test('equal', () => expect(evaluate('1 == 1'), true));
    test('not equal', () => expect(evaluate('1 != 2'), true));
  });

  group('Variables', () {
    test('number variable', () => expect(evaluate('x', env), 10.0));
    test('variable in expression', () => expect(evaluate('x + y', env), 13.0));
    test('string variable', () => expect(evaluate('name', env), 'Alice'));
    test('boolean variable', () => expect(evaluate('flag', env), true));
    test(
      'undefined variable throws',
      () => expect(() => evaluate('z', env), throwsA(isA<EvalException>())),
    );
  });

  group('Functions', () {
    test('abs', () => expect(evaluate('abs(-5)', env), 5.0));
    test('sqrt', () => expect(evaluate('sqrt(9)', env), 3.0));
    test('min', () => expect(evaluate('min(3, 7)', env), 3.0));
    test('max', () => expect(evaluate('max(3, 7)', env), 7.0));
    test('ceil', () => expect(evaluate('ceil(2.3)', env), 3.0));
    test('floor', () => expect(evaluate('floor(2.9)', env), 2.0));
    test('round', () => expect(evaluate('round(2.5)', env), 3.0));
    test('length', () => expect(evaluate('length("hello")', env), 5.0));
    test(
      'uppercase',
      () => expect(evaluate('uppercase("hello")', env), 'HELLO'),
    );
    test(
      'lowercase',
      () => expect(evaluate('lowercase("HELLO")', env), 'hello'),
    );
    test(
      'undefined function throws',
      () =>
          expect(() => evaluate('foo(1)', env), throwsA(isA<EvalException>())),
    );
  });

  group('Custom functions', () {
    test('user-defined function', () {
      final custom = Environment.standard(
        functions: {'double': (args) => (args[0] as double) * 2},
      );
      expect(evaluate('double(21)', custom), 42.0);
    });
  });

  group('Conditional', () {
    test('ternary true', () => expect(evaluate('true ? 1 : 2'), 1.0));
    test('ternary false', () => expect(evaluate('false ? 1 : 2'), 2.0));
    test(
      'ternary with comparison',
      () => expect(evaluate('3 > 2 ? "yes" : "no"'), 'yes'),
    );
    test(
      'nested ternary',
      () => expect(evaluate('true ? false ? 1 : 2 : 3'), 2.0),
    );
  });

  group('Complex expressions', () {
    test(
      'formula with variables and functions',
      () => expect(evaluate('sqrt(x * x + y * y)', env), closeTo(10.44, 0.01)),
    );

    test(
      'boolean logic with comparison',
      () => expect(evaluate('x > 5 && y < 10', env), true),
    );

    test(
      'conditional with arithmetic',
      () => expect(evaluate('x > 0 ? x * 2 : -x', env), 20.0),
    );

    test(
      'string building',
      () => expect(evaluate('"Hello, " + name + "!"', env), 'Hello, Alice!'),
    );

    test(
      'chained comparisons via &&',
      () => expect(evaluate('1 < 2 && 2 < 3 && 3 < 4'), true),
    );
  });

  group('Error handling', () {
    test(
      'type error in arithmetic',
      () => expect(() => evaluate('"a" - 1'), throwsA(isA<EvalException>())),
    );

    test(
      'type error in boolean op',
      () => expect(() => evaluate('1 && true'), throwsA(isA<EvalException>())),
    );

    test(
      'parse error',
      () => expect(() => evaluate('1 +'), throwsA(isA<EvalException>())),
    );
  });

  group('Parse API', () {
    test('parse returns AST', () {
      final result = parse('1 + 2');
      expect(result, isA<Success<ParseError, Expr>>());
    });

    test('eval on pre-parsed AST', () {
      final result = parse('x + 1');
      final ast = result.valueOrNull!;
      expect(eval(ast, env), 11.0);
    });
  });
}
