# Serialization Followup: Everything That's Missing or Wrong

Review of the serialization work against the spec (SERIALIZATION_SPEC.md) and the Scala Sarati originals at `/home/hakim/examples/sarati/`.

No deferrals. Fix everything listed here.

---

## Critical Issues

### 1. rumil_codec_builder: AST encoder code generation — NOT DONE

Spec section 9. This is the Dart equivalent of Scala's `Encoder.derived[A, To]` macro. The existing `rumil_codec_builder` generates `BinaryCodec<T>` for `@BinarySerializable`. It needs to ALSO generate `AstEncoder<T, JsonValue>` (and YAML, TOML, XML) for a new `@AstSerializable` annotation.

This is not a "nice to have." It's the Dart equivalent of `Encoder.derived` from `/home/hakim/examples/sarati/src/main/scala/net/ghoula/sarati/codec/Encoder.scala`. The Scala version uses compile-time macros to introspect product type fields and generate field-by-field encoding. The Dart version uses `build_runner` + `source_gen` + `analyzer` — the same approach already used for `@BinarySerializable`.

**What to build:**
- New annotation `@AstSerializable({formats})` in rumil_codec (alongside `@BinarySerializable`)
- New generator in rumil_codec_builder that reads `@AstSerializable` classes
- Generates `AstEncoder<T, JsonValue>` (and optionally YAML/TOML/XML) using the typed encoders
- Handles sealed class hierarchies with discriminator field
- See SERIALIZATION_SPEC.md section 9 for full details and generated code examples

### 2. `escapeToml` and `escapeYaml` are byte-for-byte identical

`lib/src/encode/escape.dart` lines 36-49. Two functions with identical bodies:

```dart
String escapeToml(String s) => s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')...;
String escapeYaml(String s) => s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')...;
```

Either share one implementation or document why they're separate. Currently they're copy-paste.

### 3. `escapeToml` and `escapeYaml` are incomplete vs `escapeJson`

`escapeJson` properly handles:
- `\b` (0x08), `\f` (0x0C) 
- All control chars below `\u0020` via `\u00xx` encoding
- Codeunit-level iteration

`escapeToml` and `escapeYaml` use naive `replaceAll` and miss:
- `\b`, `\f` (both TOML and YAML specs require escaping these in quoted strings)
- Control characters below 0x20 (passed through unescaped)

A bell character (`\x07`) in a TOML string will be written unescaped, producing invalid TOML. Fix: use the same codeunit-level approach as `escapeJson`, adjusted for format-specific rules.

### 4. No XML native decoder

`jsonToNative`, `yamlToNative`, `tomlToNative` exist in `native_decoders.dart`. No `xmlToNative`.

XML → native is harder (attributes, mixed content, namespaces), but a basic implementation should exist:
- `XmlElement` with only text children → `Map<String, Object?>`
- `XmlElement` with only `XmlText` child → extract text content
- `XmlElement` with mixed children → `Map` with children list
- `XmlText` → `String`

At minimum, provide `xmlToNative(XmlNode)` that handles the common case and throws on complex structures (mixed content, CDATA, PIs). This matches the Scala `AstBuilder[XmlNode]` which provides the reverse direction.

### 5. TOML missing `tomlMapEncoder` and `tomlNullableEncoder`

JSON has: `jsonMapEncoder`, `jsonNullableEncoder`
YAML has: `yamlMapEncoder`, `yamlNullableEncoder`
TOML has: neither

TOML has no null concept, but:
- `tomlNullableEncoder<A>(inner)` should skip the field entirely (not encode it) or use `TomlString('')`
- `tomlMapEncoder<A>(value)` should produce a `TomlTable` from `Map<String, A>` — this is needed for encoding arbitrary map structures

### 6. `AstBuilder.nativeToAst` — variable shadowing

Line 50-51 of `ast_builder.dart`:
```dart
if (value is Map<String, Object?>) {
    return builder.createObject({
      for (final MapEntry(:key, :value) in value.entries)
        key: nativeToAst(value, builder),
    });
```

The function parameter `value` (the whole map) is shadowed by `MapEntry(:value)` (an entry's value). The code is correct but confusing. Rename the destructured variable:

```dart
for (final MapEntry(:key, value: entryValue) in value.entries)
    key: nativeToAst(entryValue, builder),
```

### 7. AstBuilder tests are thin

Only 5 test cases. Missing:
- Nested structures: `{'users': [{'name': 'Alice'}]}` → verify deep conversion
- Empty collections: `{}`, `[]`
- TOML builder with null → verify it produces `TomlString('')`
- Each format: nativeToAst → serialize → parse round-trip
- Error case: unsupported type (e.g., DateTime without builder support)

### 8. TOML key escaping

`_serializeTable` writes keys bare: `$key = ${_serializeValue(value)}`. But TOML v1.0 requires quoting keys that contain dots, spaces, or special characters:

```toml
"key.with.dots" = "value"
"key with spaces" = "value"
```

The Scala version has the same gap. Fix it in Dart:
```dart
String _quoteTomlKey(String key) {
  if (key.contains(RegExp(r'[.\s"\\#=\[\]]'))) return '"${escapeToml(key)}"';
  return key;
}
```

---

## Medium Issues

### 9. JSON round-trip tests compare strings, not ASTs

The test does:
```dart
expect(serializeJson(_json(serialized)), serializeJson(ast));
```

This compares serialized output strings. If the serializer has a consistent bug (always drops a field), both sides would match and the test would pass. Better: parse the serialized string and verify the AST matches structurally. 

Problem: the AST classes don't implement `operator ==`. Fix: add `operator ==` and `hashCode` to all AST classes (JsonValue, YamlValue, TomlValue, XmlNode), or write a structural equality helper. This also enables better test assertions throughout.

### 10. YAML round-trip test missing

The YAML serializer tests verify individual outputs (scalars, sequences, mappings) but there's no round-trip test (serialize → parse → verify). This is because the YAML parser is "simplified" and may not parse its own output for nested structures. 

At minimum: add round-trip tests for what the parser CAN handle (flat mappings, flow collections, scalar values). Document what can't be round-tripped and why.

### 11. Proto serializer: verify round-trip

The proto round-trip test only checks `contains()` on individual elements. It doesn't verify that `parseProto(serializeProto(ast))` produces the same AST. Add a proper structural round-trip test.

---

## Low Issues (but still fix them)

### 12. `_JsonAstBuilder.fromInt` loses precision

```dart
JsonValue fromInt(int n) => JsonNumber(n.toDouble());
```

`JsonNumber` stores `double`, so large ints (>2^53) lose precision. This matches the Scala version and is inherent to JSON's number representation. Document this limitation on the `fromInt` method.

### 13. TOML `_serializeTable` iterates entries twice

Lines 54-76: first pass writes simple values, second pass writes subtables. Output order may not match input order. Matches Scala behavior. Acceptable but document it.

### 14. CSV serializer uses `\r\n` line endings

`serializeCsv` uses `\r\n` (RFC 4180 compliant). Make sure the config allows `\n`-only line endings for Unix environments.

---

## Implementation Order

1. Fix `escapeToml`/`escapeYaml` (use codeunit-level approach, deduplicate)
2. Fix `nativeToAst` variable shadowing
3. Add `tomlMapEncoder`, `tomlNullableEncoder`
4. Add `xmlToNative` decoder
5. Fix TOML key escaping
6. Add `operator ==` / `hashCode` to all AST classes
7. Expand AstBuilder tests
8. Add YAML round-trip tests (for what the parser supports)
9. Fix JSON round-trip tests to compare ASTs
10. Fix proto round-trip test
11. Document `fromInt` precision limitation
12. **Build `@AstSerializable` codegen in rumil_codec_builder** — this is the biggest item

Items 1-10 are within rumil_parsers. Item 11 is documentation. Item 12 is rumil_codec_builder.

All of this should be done before rumil_parsers 0.3.0 ships.
