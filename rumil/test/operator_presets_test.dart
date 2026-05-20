import 'package:rumil/rumil.dart';
import 'package:test/test.dart';

T _val<T>(Result<Object?, T> r) => switch (r) {
  Success<Object?, T>(:final value) => value,
  Partial<Object?, T>(:final value) => value,
  Failure() => throw StateError('Expected success, got $r'),
};

/// Toy AST for testing the C-family preset.
sealed class _Expr {
  const _Expr();
}

final class _Num extends _Expr {
  final int value;
  const _Num(this.value);
  @override
  String toString() => '$value';
}

final class _Bin extends _Expr {
  final String op;
  final _Expr l;
  final _Expr r;
  const _Bin(this.op, this.l, this.r);
  @override
  String toString() => '($l $op $r)';
}

final class _Un extends _Expr {
  final String op;
  final _Expr operand;
  const _Un(this.op, this.operand);
  @override
  String toString() => '($op$operand)';
}

void main() {
  // Atom: an integer literal as `_Num`.
  final atom = digit().many1.capture.map<_Expr>((s) => _Num(int.parse(s)));

  Parser<ParseError, _Expr> exprWith({
    Parser<ParseError, String> Function(String)? customSym,
  }) {
    final sym = customSym ?? string;
    return pratt<_Expr>(
      atom,
      cFamilyPrecedence<_Expr>(sym: sym, binary: _Bin.new, unary: _Un.new),
    );
  }

  group('cFamilyPrecedence — precedence', () {
    test('multiplicative binds tighter than additive', () {
      expect(_val(exprWith().run('1+2*3')).toString(), '(1 + (2 * 3))');
    });

    test('additive binds tighter than comparison', () {
      expect(_val(exprWith().run('1+2<3')).toString(), '((1 + 2) < 3)');
    });

    test('comparison binds tighter than equality', () {
      expect(
        _val(exprWith().run('1<2==3>4')).toString(),
        '((1 < 2) == (3 > 4))',
      );
    });

    test('equality binds tighter than &&', () {
      expect(
        _val(exprWith().run('1==2&&3!=4')).toString(),
        '((1 == 2) && (3 != 4))',
      );
    });

    test('&& binds tighter than ||', () {
      expect(
        _val(exprWith().run('1&&2||3&&4')).toString(),
        '((1 && 2) || (3 && 4))',
      );
    });

    test('left-associative across additive', () {
      expect(_val(exprWith().run('1-2-3')).toString(), '((1 - 2) - 3)');
    });

    test('left-associative across multiplicative', () {
      expect(_val(exprWith().run('8/2/2')).toString(), '((8 / 2) / 2)');
    });
  });

  group('cFamilyPrecedence — comparison ordering', () {
    test('<= matches before <', () {
      // If `<` were tried first it would consume the `<` and leave `=`,
      // failing the rhs parse. Order in the preset prevents this.
      expect(_val(exprWith().run('1<=2')).toString(), '(1 <= 2)');
    });

    test('>= matches before >', () {
      expect(_val(exprWith().run('1>=2')).toString(), '(1 >= 2)');
    });
  });

  group('cFamilyPrecedence — prefix unary', () {
    test('prefix - negates the rhs', () {
      expect(_val(exprWith().run('-5')).toString(), '(-5)');
    });

    test('prefix ! applies to the rhs', () {
      expect(_val(exprWith().run('!1')).toString(), '(!1)');
    });

    test('prefix binds tighter than infix', () {
      // `-1+2` is `(-1) + 2`, not `-(1+2)`.
      expect(_val(exprWith().run('-1+2')).toString(), '((-1) + 2)');
    });

    test('chained prefixes compose', () {
      expect(_val(exprWith().run('--5')).toString(), '(-(-5))');
      expect(_val(exprWith().run('!!1')).toString(), '(!(!1))');
    });
  });

  group('cFamilyPrecedence — sym override', () {
    test('per-symbol customization via dispatch on the input', () {
      // Override `/` to require a notFollowedBy guard against a second `/`.
      // (Not strictly necessary in this test grammar, but demonstrates the
      // pattern lambe uses for `/` vs `//`.)
      final divSym = string('/').thenSkip(char('/').notFollowedBy);
      Parser<ParseError, String> custom(String s) =>
          s == '/' ? divSym : string(s);
      expect(
        _val(exprWith(customSym: custom).run('8/2/2')).toString(),
        '((8 / 2) / 2)',
      );
    });
  });

  group('cFamilyPrecedence — extending the preset', () {
    test('appending custom operators with list concat', () {
      // Add a right-associative `^` (power) at bp 65 (between * and prefix).
      final atom = digit().many1.capture.map<_Expr>((s) => _Num(int.parse(s)));
      final operators = [
        ...cFamilyPrecedence<_Expr>(
          sym: string,
          binary: _Bin.new,
          unary: _Un.new,
        ),
        InfixRight(string('^'), 65, (_Expr a, _Expr b) => _Bin('^', a, b)),
      ];
      final expr = pratt<_Expr>(atom, operators);
      // Right-associative: `2^3^2` = `2^(3^2)`.
      expect(_val(expr.run('2^3^2')).toString(), '(2 ^ (3 ^ 2))');
      // Higher than * but lower than prefix: `2*3^2` = `2*(3^2)`,
      // and `-2^3` = `(-2)^3` because prefix at bp 70 > infix at bp 65.
      expect(_val(expr.run('2*3^2')).toString(), '(2 * (3 ^ 2))');
      expect(_val(expr.run('-2^3')).toString(), '((-2) ^ 3)');
    });
  });
}
