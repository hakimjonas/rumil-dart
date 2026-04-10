# YAML + HCL Followup

The YAML indentation fix is solid. The HCL parser has structural issues. 6 items.

---

## 1. Nested YAML round-trip tests — MISSING

The parser now handles nested indentation. The serializer outputs nested block style. But there are NO round-trip tests proving they're consistent.

Add to `test/serialize_test.dart` in the YAML round-trip group:

```dart
test('nested mapping round-trip', () {
  const ast = YamlMapping({
    'database': YamlMapping({
      'host': YamlString('localhost'),
      'port': YamlInteger(5432),
    }),
  });
  final s = serializeYaml(ast);
  final reparsed = _yamlDoc('$s\n');
  expect(reparsed, ast);
});

test('sequence of mappings round-trip', () {
  const ast = YamlMapping({
    'users': YamlSequence([
      YamlMapping({'name': YamlString('Alice'), 'age': YamlInteger(25)}),
      YamlMapping({'name': YamlString('Bob'), 'age': YamlInteger(30)}),
    ]),
  });
  final s = serializeYaml(ast);
  final reparsed = _yamlDoc('$s\n');
  expect(reparsed, ast);
});

test('deeply nested round-trip', () {
  const ast = YamlMapping({
    'a': YamlMapping({
      'b': YamlMapping({
        'c': YamlString('deep'),
      }),
    }),
  });
  final s = serializeYaml(ast);
  final reparsed = _yamlDoc('$s\n');
  expect(reparsed, ast);
});

test('mixed nesting round-trip', () {
  const ast = YamlMapping({
    'database': YamlMapping({
      'host': YamlString('localhost'),
      'ports': YamlSequence([YamlInteger(5432), YamlInteger(5433)]),
    }),
  });
  final s = serializeYaml(ast);
  final reparsed = _yamlDoc('$s\n');
  expect(reparsed, ast);
});
```

If any of these fail, the serializer's output format doesn't match what the parser expects. Fix whichever side is wrong.

---

## 2. HCL duplicate top-level keys — DESIGN BUG

`HclDocument = Map<String, HclValue>` loses data. Real Terraform files have multiple blocks of the same type:

```hcl
resource "aws_instance" "web" { ami = "abc" }
resource "aws_s3_bucket" "data" { bucket = "my-bucket" }
variable "region" { default = "us-east-1" }
variable "env" { default = "prod" }
```

With `Map<String, HclValue>`, only the LAST `resource` and LAST `variable` survive. The first is silently dropped.

**Fix:** Change the document type to preserve all entries:

```dart
/// An HCL document — ordered list of top-level entries.
///
/// Uses a list of pairs instead of a map because HCL allows
/// multiple blocks with the same type name.
typedef HclDocument = List<(String, HclValue)>;
```

Then `hclToNative` groups blocks by type:
```dart
Map<String, Object?> hclDocToNative(HclDocument doc) {
  final result = <String, Object?>{};
  for (final (key, value) in doc) {
    if (value is HclBlock) {
      // Group blocks by type: resource → [{...}, {...}]
      final existing = result[key];
      if (existing is List) {
        existing.add(hclToNative(value));
      } else if (existing != null) {
        result[key] = [existing, hclToNative(value)];
      } else {
        result[key] = hclToNative(value);
      }
    } else {
      result[key] = hclToNative(value);
    }
  }
  return result;
}
```

This also requires updating the parser, serializer, tests, and barrel exports.

The `_hclDocument` parser currently produces `Map.fromEntries(...)` — change to return `List<(String, HclValue)>` directly (which is what the intermediate `entries` variable already is).

---

## 3. HCL AstBuilder — MISSING

The spec says add `hclBuilder` to `ast_builder.dart`. Not done.

```dart
/// AstBuilder for HCL.
const AstBuilder<HclValue> hclBuilder = _HclAstBuilder();

final class _HclAstBuilder implements AstBuilder<HclValue> {
  const _HclAstBuilder();
  @override HclValue createObject(Map<String, HclValue> fields) => HclObject(fields);
  @override HclValue createArray(List<HclValue> elements) => HclList(elements);
  @override HclValue fromString(String s) => HclString(s);
  @override HclValue fromInt(int n) => HclNumber(n);
  @override HclValue fromDouble(double n) => HclNumber(n);
  @override HclValue fromBool(bool b) => HclBool(b);
  @override HclValue fromNull() => const HclNull();
}
```

---

## 4. HCL round-trip test — MISSING

The HCL serializer tests use `contains()` checks. Add structural round-trip:

```dart
group('HCL round-trip', () {
  test('attributes', () {
    final input = 'name = "test"\nport = 8080\n';
    final doc = doc_(parseHcl(input));
    final serialized = serializeHcl(doc);
    final reparsed = doc_(parseHcl(serialized));
    expect(reparsed, doc);
  });

  test('block', () {
    final input = 'resource "aws_instance" "web" {\n  ami = "abc"\n}\n';
    final doc = doc_(parseHcl(input));
    final serialized = serializeHcl(doc);
    final reparsed = doc_(parseHcl(serialized));
    expect(reparsed, doc);
  });
});
```

Note: this will require updating after the `HclDocument` type change (item 2).

---

## 5. HCL string interpolation — MISSING

The spec lists `"hello-${var.env}"` as a feature. The current parser treats `${...}` as regular string characters. For querying Terraform files, string interpolation markers should be preserved (not evaluated — just parsed).

Options:
- Parse `${...}` as part of the string content (current behavior — lose the structure)
- Add `HclInterpolatedString` AST type with parts (like Lambé's `StringInterp`)
- Parse `${...}` and extract the reference path as metadata

For Lambé's querying use case, the simplest correct approach: parse `${var.name}` and keep it as a string `"${var.name}"`. The interpolation is a Terraform runtime feature, not something a query tool evaluates. The current behavior (treat as plain string chars) is actually acceptable for querying — you get the raw template string. But it should be documented.

If you want structural interpolation support later, add:
```dart
final class HclTemplate extends HclValue {
  final List<HclValue> parts; // HclString for literals, HclReference for ${...}
  const HclTemplate(this.parts);
}
```

For now: document that `${...}` in HCL strings is preserved as literal text, not parsed as interpolation. Add a test that verifies this:

```dart
test('string with interpolation markers preserved', () {
  final d = doc_(parseHcl(r'name = "hello-${var.env}"' '\n'));
  expect((d.firstWhere((e) => e.$1 == 'name').$2 as HclString).value,
      r'hello-${var.env}');
});
```

---

## 6. HCL serializer needs to handle the new document type

After changing `HclDocument` from `Map<String, HclValue>` to `List<(String, HclValue)>`, update `serializeHcl`:

```dart
String serializeHcl(HclDocument doc, {int indent = 2}) {
  final sb = StringBuffer();
  for (final (key, value) in doc) {
    if (value is HclBlock) {
      _serializeBlock(sb, value, indent, 0);
    } else {
      sb.writeln('$key = ${_serializeValue(value)}');
    }
  }
  return sb.toString();
}
```

---

## Implementation Order

1. Fix `HclDocument` type (item 2) — this changes the foundation, everything else depends on it
2. Update HCL parser to produce `List<(String, HclValue)>`
3. Update HCL serializer for new type
4. Update HCL native decoder (`hclDocToNative`)
5. Update all HCL tests
6. Add `hclBuilder` (item 3)
7. Add HCL round-trip tests (item 4)
8. Add nested YAML round-trip tests (item 1)
9. Document HCL string interpolation behavior (item 5)
10. Add multiple-block test:
```dart
test('multiple resource blocks', () {
  final d = doc_(parseHcl('''
resource "aws_instance" "web" { ami = "abc" }
resource "aws_s3_bucket" "data" { bucket = "my-bucket" }
'''));
  expect(d.where((e) => e.$1 == 'resource').length, 2);
});
```

## Verification

```bash
dart analyze --fatal-infos
dart format --set-exit-if-changed .
dart test
```

All 269 existing tests must still pass. New tests should bring the total to ~280+.
