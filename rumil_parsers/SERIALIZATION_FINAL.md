# Final Remaining Work — No Excuses

7 items remain. Do all of them. Do not skip, defer, or mark anything as "blocked."

Items 9-11 are NOT blocked on `==`/`hashCode`. That's item 6 below. Do item 6 first, then 9-11 become unblocked. This is called ordering your work.

---

## 1. `operator ==` and `hashCode` on ALL AST classes

37 `final class` types across 5 AST files have no structural equality. Every sealed AST class needs `operator ==` and `hashCode` based on its fields. This is a prerequisite for proper round-trip tests and for any consumer comparing ASTs.

**Files:**
- `lib/src/ast/json.dart` — 6 classes: JsonNull, JsonBool, JsonNumber, JsonString, JsonArray, JsonObject
- `lib/src/ast/yaml.dart` — 7 classes: YamlNull, YamlBool, YamlInteger, YamlFloat, YamlString, YamlSequence, YamlMapping
- `lib/src/ast/toml.dart` — 10 classes: TomlString, TomlInteger, TomlFloat, TomlBool, TomlDateTime, TomlLocalDateTime, TomlLocalDate, TomlLocalTime, TomlArray, TomlTable
- `lib/src/ast/xml.dart` — 5 classes: XmlElement, XmlText, XmlCData, XmlComment, XmlPI (XmlElement already has one — verify it's correct, do the rest)
- `lib/src/ast/proto.dart` — 9 classes: ProtoFile, ProtoPackage, ProtoImport, ProtoMessageDef, ProtoEnumDef, ProtoServiceDef, ProtoField, ProtoMethod, ProtoEnumValue (plus types)

**Pattern** (same for every class):
```dart
final class JsonBool extends JsonValue {
  final bool value;
  const JsonBool(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is JsonBool && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
```

For classes with collection fields (List, Map), use `ListEquality`/`MapEquality` from `package:collection`, or `Object.hashAll` / deep comparison. If you don't want to add a dependency, write a simple deep equals helper:

```dart
bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (a[key] != b[key]) return false;
  }
  return true;
}
```

Do this FIRST. Everything else depends on it.

---

## 2. Expand AstBuilder tests

Current: 5 test cases. Required: comprehensive.

Add to `test/serialize_test.dart` in the AstBuilder group:

```dart
test('nested structure', () {
  final data = {'users': [{'name': 'Alice', 'age': 30}]};
  final ast = nativeToAst(data, jsonBuilder);
  final json = serializeJson(ast as JsonValue);
  final reparsed = _json(json);
  expect(reparsed, ast); // NOW WORKS because == is implemented
});

test('empty collections', () {
  expect(nativeToAst(<String, Object?>{}, jsonBuilder), const JsonObject({}));
  expect(nativeToAst(<Object?>[], jsonBuilder), const JsonArray([]));
});

test('TOML builder null produces empty string', () {
  expect(nativeToAst(null, tomlBuilder), const TomlString(''));
});

test('unsupported type throws', () {
  expect(() => nativeToAst(DateTime.now(), jsonBuilder), throwsArgumentError);
});

test('JSON native round-trip', () {
  final data = {'a': 1, 'b': [true, null, 'hello'], 'c': {'d': 3.14}};
  final ast = nativeToAst(data, jsonBuilder) as JsonValue;
  final native = jsonToNative(ast);
  expect(native, data);
});

test('YAML native round-trip', () {
  final data = {'x': 42, 'y': [1, 2, 3]};
  final ast = nativeToAst(data, yamlBuilder) as YamlValue;
  final native = yamlToNative(ast);
  expect(native, data);
});
```

---

## 3. Fix JSON round-trip tests to compare ASTs

Replace string comparison with structural comparison. Now that `==` exists:

```dart
test('compact', () {
  final input = '{"name":"Alice","age":30,"active":true}';
  final ast = _json(input);
  final serialized = serializeJson(ast);
  final reparsed = _json(serialized);
  expect(reparsed, ast);  // structural equality, not string comparison
});
```

Do this for ALL existing JSON round-trip tests.

---

## 4. Add YAML round-trip tests

The YAML parser is simplified but it CAN parse:
- Flat block mappings: `name: Alice\nage: 30\n`
- Flow collections: `{name: Alice, age: 30}`
- Block sequences: `- 1\n- 2\n- 3\n`
- Scalars: `null`, `true`, `42`, `3.14`, `hello`

Add round-trip tests for these:

```dart
group('YAML round-trip', () {
  test('scalars', () {
    for (final v in [const YamlNull(), const YamlBool(true), const YamlInteger(42)]) {
      final s = serializeYaml(v);
      // parse as scalar — the parser should handle single values
    }
  });

  test('flat mapping', () {
    final ast = const YamlMapping({'name': YamlString('Alice'), 'age': YamlInteger(30)});
    final s = serializeYaml(ast);
    // s = 'name: Alice\nage: 30'
    final reparsed = _yamlDoc(s);
    expect(reparsed, ast);
  });
});
```

If a specific round-trip fails because the parser can't handle it, document WHY in a comment and file it as a known limitation. Don't silently skip it.

---

## 5. Add Proto round-trip structural test

Replace the `contains()` checks with structural comparison:

```dart
test('structural round-trip', () {
  final input = 'syntax = "proto3";\n\nmessage Person {\n  string name = 1;\n  int32 age = 2;\n}\n';
  final ast = _protoFile(input);
  final serialized = serializeProto(ast);
  final reparsed = _protoFile(serialized);
  expect(reparsed, ast);  // structural equality
});
```

---

## 6. Document TOML `_serializeTable` double iteration

Add a doc comment to `_serializeTable` in `toml_encoders.dart`:

```dart
/// Serialize a TOML table's entries.
///
/// Iterates entries twice: first for inline values (scalars, arrays),
/// then for subtables and arrays of tables. This means output order
/// groups all inline values before all table sections, which may differ
/// from input order. This matches the Scala Sarati implementation.
void _serializeTable(...)
```

---

## 7. CSV line ending configurability

`serializeCsv` hardcodes `\r\n`. Add a `lineEnding` field to `CsvConfig`:

```dart
// In csv.dart or wherever CsvConfig is defined:
class CsvConfig {
  // ... existing fields ...
  final String lineEnding;
  const CsvConfig({..., this.lineEnding = '\r\n'});
}
```

Then in `csv_encoders.dart`:
```dart
String serializeCsv(List<List<String>> records, {CsvConfig config = defaultCsvConfig}) =>
    records.map((row) => row.map((f) => _csvField(f, config)).join(config.delimiter))
        .join(config.lineEnding);
```

---

## 8. `@AstSerializable` codegen in rumil_codec_builder

This is the biggest item. It's the Dart equivalent of the Scala `Encoder.derived[A, To]` macro at `/home/hakim/examples/sarati/src/main/scala/net/ghoula/sarati/codec/Encoder.scala`.

**What to build:**

In `rumil_codec` (where annotations live):
```dart
/// Marks a class for AST encoder code generation.
class AstSerializable {
  final List<AstFormat> formats;
  const AstSerializable({this.formats = const [AstFormat.json]});
}

enum AstFormat { json, yaml, toml, xml }
```

In `rumil_codec_builder` (where generators live), add a new generator alongside `CodecGenerator`:

```dart
class AstEncoderGenerator extends GeneratorForAnnotation<AstSerializable> {
  @override
  String generateForAnnotatedElement(Element element, ...) {
    // Read the class fields via analyzer
    // For each field, look up the corresponding AstEncoder by type
    // Generate an AstEncoder<T, JsonValue> implementation
    // For sealed classes, generate a discriminated switch
  }
}
```

Generated output for:
```dart
@AstSerializable()
class Person {
  final String name;
  final int age;
  const Person(this.name, this.age);
}
```

Produces:
```dart
const personJsonEncoder = _$PersonJsonEncoder();

class _$PersonJsonEncoder implements AstEncoder<Person, JsonValue> {
  const _$PersonJsonEncoder();
  @override
  JsonValue encode(Person value) {
    final b = ObjectBuilder<JsonValue>();
    b.field('name', value.name, jsonStringEncoder);
    b.field('age', value.age, jsonIntEncoder);
    return JsonObject(Map.fromEntries(b.entries.map((e) => MapEntry(e.$1, e.$2))));
  }
}
```

**The existing `CodecGenerator` in `rumil_codec_builder/lib/src/codec_generator.dart` is the template.** It already:
- Reads class fields via `ConstantReader` + `analyzer`
- Generates codec implementations for annotated classes
- Handles sealed class hierarchies with ordinal-based dispatch

The `AstEncoderGenerator` follows the same pattern but generates `AstEncoder<T, JsonValue>` instead of `BinaryCodec<T>`. The field-type-to-encoder mapping is:
- `String` → `jsonStringEncoder`
- `int` → `jsonIntEncoder`
- `double` → `jsonDoubleEncoder`
- `bool` → `jsonBoolEncoder`
- `List<X>` → `jsonListEncoder(xEncoder)`
- `X?` → `jsonNullableEncoder(xEncoder)`
- Another `@AstSerializable` class → reference its generated encoder

Register the new generator in `builder.dart` alongside the existing one. Generated files use `.ast.g.dart` extension.

Add tests in `rumil_codec_builder/test/` that verify the generated encoder compiles, encodes correctly, and round-trips through serialization.

**Read the Scala source at `/home/hakim/examples/sarati/src/main/scala/net/ghoula/sarati/codec/Encoder.scala` before implementing.** It shows exactly what compile-time introspection is needed.

---

## Verification

After ALL 8 items are done:

```bash
# rumil_parsers
dart analyze --fatal-infos
dart format --set-exit-if-changed .
dart test

# rumil_codec_builder
dart analyze --fatal-infos
dart format --set-exit-if-changed .
dart run build_runner build --delete-conflicting-outputs
dart test
```

Every test must be a structural round-trip where possible, not string comparison. Zero analyzer warnings. Zero deferred items.
