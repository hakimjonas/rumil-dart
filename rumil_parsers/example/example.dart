import 'package:rumil_parsers/rumil_parsers.dart';

void main() {
  // JSON
  final json = parseJson('{"name": "Alice", "age": 30}');
  print(json); // Success(JsonObject({name: "Alice", age: 30}))

  // CSV
  final csv = parseCsv('name,age\nAlice,30\nBob,25');
  print(csv);

  // TOML
  final toml = parseToml('[server]\nhost = "localhost"\nport = 8080\n');
  print(toml);

  // Typed decoding
  final decoder = fromJsonObject(
    (obj) => (
      name: obj.field('name', jsonString),
      age: obj.field('age', jsonInt),
    ),
  );
  final person = decoder.decode(
    const JsonObject({'name': JsonString('Alice'), 'age': JsonNumber(30)}),
  );
  print('${person.name}, age ${person.age}');
}
