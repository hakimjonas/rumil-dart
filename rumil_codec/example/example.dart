import 'package:rumil_codec/rumil_codec.dart';

class Person {
  final String name;
  final int age;
  Person(this.name, this.age);
  @override
  String toString() => 'Person($name, $age)';
}

void main() {
  // Primitive round-trip
  final bytes = intCodec.encode(42);
  print(intCodec.decode(bytes)); // 42

  // Compose for domain types via product + xmap
  final personCodec = product2(
    stringCodec,
    intCodec,
  ).xmap((r) => Person(r.$1, r.$2), (p) => (p.name, p.age));

  final encoded = personCodec.encode(Person('Alice', 30));
  print(personCodec.decode(encoded)); // Person(Alice, 30)

  // Composites
  final listCodec = intCodec.list;
  print(listCodec.decode(listCodec.encode([1, 2, 3]))); // [1, 2, 3]
}
