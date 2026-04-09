import 'package:rumil_codec/rumil_codec.dart';
import 'package:test/test.dart';

import '../example/example.dart';

void main() {
  group('Generated Person codec', () {
    test('round-trips', () {
      const person = Person('Alice', 30);
      final bytes = personCodec.encode(person);
      final decoded = personCodec.decode(bytes);
      expect(decoded.name, 'Alice');
      expect(decoded.age, 30);
    });

    test('wire format matches manual codec', () {
      const person = Person('Bob', 25);
      final generated = personCodec.encode(person);
      final manual = product2(stringCodec, intCodec)
          .xmap<Person>((r) => Person(r.$1, r.$2), (p) => (p.name, p.age))
          .encode(person);
      expect(generated, manual);
    });
  });

  group('Generated Shape codec', () {
    test('round-trips Circle', () {
      final shape = Circle(3.14);
      final bytes = shapeCodec.encode(shape);
      final decoded = shapeCodec.decode(bytes);
      expect(decoded, isA<Circle>());
      expect((decoded as Circle).radius, 3.14);
    });

    test('round-trips Rectangle', () {
      final shape = Rectangle(2.0, 4.0);
      final bytes = shapeCodec.encode(shape);
      final decoded = shapeCodec.decode(bytes);
      expect(decoded, isA<Rectangle>());
      final rect = decoded as Rectangle;
      expect(rect.width, 2.0);
      expect(rect.height, 4.0);
    });

    test('ordinal 0 = Circle, ordinal 1 = Rectangle', () {
      final circleBytes = shapeCodec.encode(Circle(1.0));
      final rectBytes = shapeCodec.encode(Rectangle(1.0, 2.0));
      expect(circleBytes[0], 0);
      expect(rectBytes[0], 1);
    });
  });

  group('Generated Expr codec (nested sealed)', () {
    test('round-trips Lit', () {
      final expr = Lit(42);
      final bytes = exprCodec.encode(expr);
      final decoded = exprCodec.decode(bytes);
      expect(decoded, isA<Lit>());
      expect((decoded as Lit).value, 42);
    });

    test('round-trips Add', () {
      final expr = Add(Lit(1), Lit(2));
      final bytes = exprCodec.encode(expr);
      final decoded = exprCodec.decode(bytes);
      expect(decoded, isA<Add>());
      final add = decoded as Add;
      expect((add.left as Lit).value, 1);
      expect((add.right as Lit).value, 2);
    });

    test('round-trips deeply nested', () {
      final expr = Add(Mul(Lit(1), Lit(2)), Lit(3));
      final bytes = exprCodec.encode(expr);
      final decoded = exprCodec.decode(bytes);
      expect(decoded, isA<Add>());
      final add = decoded as Add;
      expect(add.left, isA<Mul>());
      final mul = add.left as Mul;
      expect((mul.left as Lit).value, 1);
      expect((mul.right as Lit).value, 2);
      expect((add.right as Lit).value, 3);
    });

    test('ordinals: Lit=0, Add=1, Mul=2', () {
      expect(exprCodec.encode(Lit(0))[0], 0);
      expect(exprCodec.encode(Add(Lit(0), Lit(0)))[0], 1);
      expect(exprCodec.encode(Mul(Lit(0), Lit(0)))[0], 2);
    });
  });
}
