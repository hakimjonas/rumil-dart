# Completing the Sarati Port: Full Serialization Spec

## The Problem

The Scala Sarati library provides bidirectional format support: parse (string→AST) AND serialize (AST→string) for JSON, YAML, TOML, XML. The Dart port only has the parse half. This spec covers everything needed to complete the port.

No deferrals. Every gap is listed.

---

## Gap Matrix

| Component | Scala Sarati | Dart rumil_parsers | Status |
|-----------|:--:|:--:|--------|
| JSON parser | `parseJson` | `parseJson` | Done |
| JSON serializer (`formatJson`) | Full: compact + pretty + sortKeys + `\u00xx` | Partial: compact + pretty, missing sortKeys + control chars | **Fix** |
| YAML parser | `parseYaml` | `parseYaml` | Done |
| YAML serializer (`formatYaml`) | Full: block style, string quoting, key quoting | **Missing entirely** | **Build** |
| TOML parser | `parseToml` | `parseToml` | Done |
| TOML serializer (`serializeToml`) | Full: values + document with sections | `serializeToml` exists | Review |
| XML parser | `parseXml` | `parseXml` | Done |
| XML serializer (`formatXml`) | Full: indented, entity escaping, CDATA, PIs, QName | **Missing entirely** | **Build** |
| CSV parser | `parseCsv` | `parseCsv` | Done |
| CSV serializer | Not in Scala | **Missing** | **Build** |
| Proto parser | `parseProto` | `parseProto` | Done |
| Proto serializer | Not in Scala | `serializeProto` exists | Done |
| `AstBuilder` (native→AST) | Full: JSON, YAML, TOML, XML instances | **Missing entirely** | **Build** |
| AST→native decoders | Not in Sarati (per-consumer) | In Lambé's input.dart (wrong location) | **Move here** |
| Encoder infrastructure | `Encoder[-A, To]` trait + `contramap` | `AstEncoder<A, AST>` + `contramap` | Done |
| Encoder derivation (macros) | `Encoder.derived[A, To]` via Scala 3 quotes | **Missing** — needs rumil_codec_builder extension | **Build** |
| `ObjectBuilder` | Implicit via macro | `ObjectBuilder<AST>` exists | Done |
| JSON typed encoders | Full: primitives + composites + object | Full: primitives + composites + object | Done |
| YAML typed encoders | Not in Scala (uses AstBuilder) | Primitives + composites + mapping | Done |
| TOML typed encoders | Not in Scala (uses AstBuilder) | Primitives + list + table | Done |
| XML typed encoders | Not in Scala (uses AstBuilder) | **Missing** | **Build** |
| JSON format config | `(indent, newlines, sortKeys)` named tuple | Just `indent` string | **Fix** |
| Shared escape utilities | Per-format (each has own rules) | Duplicated between json + toml | **Fix** |

---

## 1. YAML Serializer

**File:** `lib/src/encode/yaml_encoders.dart` (add to existing file)

Port from: `sarati/ast/yaml/YamlTypes.scala` lines 34-108

```dart
/// Serialize a [YamlValue] to a YAML string.
///
/// Uses block style for mappings and sequences. Scalars are formatted
/// inline. Strings are quoted when they contain reserved words or
/// special characters.
String serializeYaml(YamlValue value, {int indent = 2, int depth = 0}) {
  final pad = ' ' * (indent * depth);
  return switch (value) {
    YamlNull() => '${pad}null',
    YamlBool(:final value) => '$pad$value',
    YamlInteger(:final value) => '$pad$value',
    YamlFloat(:final value) => switch (value) {
      _ when value.isNaN => '$pad.nan',
      _ when value == double.infinity => '$pad.inf',
      _ when value == double.negativeInfinity => '$pad-.inf',
      _ => '$pad$value',
    },
    YamlString(:final value) => '$pad${_quoteYamlString(value)}',
    YamlSequence(:final elements) => elements.isEmpty
        ? '$pad[]'
        : elements
            .map((e) => '$pad- ${serializeYaml(e, indent: indent, depth: depth + 1).trimLeft()}')
            .join('\n'),
    YamlMapping(:final pairs) => pairs.isEmpty
        ? '$pad{}'
        : pairs.entries.map((e) {
            final key = '$pad${_quoteYamlKey(e.key)}';
            return switch (e.value) {
              YamlMapping() || YamlSequence() =>
                '$key:\n${serializeYaml(e.value, indent: indent, depth: depth + 1)}',
              _ =>
                '$key: ${serializeYaml(e.value, indent: indent, depth: 0).trimLeft()}',
            };
          }).join('\n'),
  };
}

/// Serialize a YAML document with `---` marker.
String serializeYamlDocument(YamlValue root) =>
    '---\n${serializeYaml(root)}';
```

**String quoting rules** (from Scala):
```dart
/// Quote a YAML string value if it contains special characters or
/// could be confused with a YAML keyword.
String _quoteYamlString(String s) {
  if (s == 'true' || s == 'false' || s == 'null' || s == '~' || s.isEmpty) {
    return '"${_escapeYaml(s)}"';
  }
  if (s.contains(RegExp(r'[:#\n"' "'" r'{}\[\],]'))) {
    return '"${_escapeYaml(s)}"';
  }
  return s;
}

/// Quote a YAML key if needed.
String _quoteYamlKey(String key) {
  if (key == 'true' || key == 'false' || key == 'null' || key == '~' || key.isEmpty) {
    return '"$key"';
  }
  if (key.contains(RegExp(r'[:# {}\[\],]'))) {
    return '"$key"';
  }
  return key;
}

String _escapeYaml(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll('"', r'\"')
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\r')
    .replaceAll('\t', r'\t');
```

---

## 2. XML Serializer

**File:** `lib/src/encode/xml_encoders.dart` (new file)

Port from: `sarati/ast/xml/XmlTypes.scala` lines 78-131

```dart
/// Serialize an [XmlNode] to an XML string.
String serializeXml(XmlNode node, {int indent = 2, int depth = 0}) {
  final pad = ' ' * (indent * depth);
  return switch (node) {
    XmlElement(:final name, :final attributes, :final children) => ...,
    XmlText(:final content) => '$pad${_escapeXmlText(content)}',
    XmlCData(:final content) => '$pad<![CDATA[$content]]>',
    XmlComment(:final content) => '$pad<!--$content-->',
    XmlPI(:final target, :final content) => '$pad<?$target $content?>',
  };
}

/// Serialize with XML declaration.
String serializeXmlDocument(XmlNode root, {
  String version = '1.0',
  String? encoding = 'UTF-8',
  int indent = 2,
}) { ... }
```

**Entity escaping** (from Scala):
```dart
String _escapeXmlText(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _escapeXmlAttr(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
```

Also needs: `_formatQName(QName)` for prefixed element/attribute names.

Requires reading the XML AST types to match the Dart class names exactly.

---

## 3. CSV Serializer

**File:** `lib/src/encode/csv_encoders.dart` (new file)

Not in Scala Sarati but rumil_parsers parses CSV, so it should serialize CSV.

```dart
/// Serialize a [CsvDocument] to a CSV string.
String serializeCsv(List<List<String>> records, {CsvConfig? config}) {
  final cfg = config ?? const CsvConfig();
  return records.map((row) =>
    row.map((field) => _csvField(field, cfg)).join(cfg.delimiter)
  ).join('\n');
}

/// Serialize with headers.
String serializeCsvWithHeaders(List<String> headers, List<List<String>> rows, {CsvConfig? config}) {
  return serializeCsv([headers, ...rows], config: config);
}

String _csvField(String field, CsvConfig config) {
  if (field.contains(config.delimiter) || field.contains('"') || field.contains('\n')) {
    return '"${field.replaceAll('"', '""')}"';
  }
  return field;
}
```

---

## 4. AstBuilder (native → AST)

**File:** `lib/src/encode/ast_builder.dart` (new file)

Port from: `sarati/codec/AstBuilder.scala`

This is the critical bridge for converting `Object?` (native Dart types from JSON decoding or query evaluation) into format-specific AST nodes.

```dart
/// Builds format-specific AST nodes from primitive Dart values.
///
/// Used to convert generic `Object?` data into typed AST for serialization.
/// Each format provides an implementation.
abstract interface class AstBuilder<AST> {
  /// Create an object/mapping node from named fields.
  AST createObject(Map<String, AST> fields);

  /// Create an array/sequence node from elements.
  AST createArray(List<AST> elements);

  /// Create a string node.
  AST fromString(String s);

  /// Create a number node from an integer.
  AST fromInt(int n);

  /// Create a number node from a double.
  AST fromDouble(double n);

  /// Create a boolean node.
  AST fromBool(bool b);

  /// Create a null/empty node.
  AST fromNull();
}

/// Convert a native Dart value to a format-specific AST using [builder].
///
/// Handles: `Map<String, Object?>`, `List<Object?>`, `String`, `int`,
/// `double`, `bool`, `null`. Throws on unsupported types.
AST nativeToAst<AST>(Object? value, AstBuilder<AST> builder) {
  if (value == null) return builder.fromNull();
  if (value is bool) return builder.fromBool(value);
  if (value is int) return builder.fromInt(value);
  if (value is double) return builder.fromDouble(value);
  if (value is String) return builder.fromString(value);
  if (value is List<Object?>) {
    return builder.createArray([for (final e in value) nativeToAst(e, builder)]);
  }
  if (value is Map<String, Object?>) {
    return builder.createObject({
      for (final MapEntry(:key, :value) in value.entries)
        key: nativeToAst(value, builder),
    });
  }
  throw ArgumentError('Unsupported type: ${value.runtimeType}');
}
```

**Format-specific instances:**

```dart
/// AstBuilder for JSON.
const AstBuilder<JsonValue> jsonBuilder = _JsonAstBuilder();

/// AstBuilder for YAML.
const AstBuilder<YamlValue> yamlBuilder = _YamlAstBuilder();

/// AstBuilder for TOML.
const AstBuilder<TomlValue> tomlBuilder = _TomlAstBuilder();

/// AstBuilder for XML.
const AstBuilder<XmlNode> xmlBuilder = _XmlAstBuilder();
```

Implementation follows the Scala instances exactly:
- JSON: `fromInt(n)` → `JsonNumber(n.toDouble())`, `fromNull()` → `const JsonNull()`, etc.
- YAML: `fromInt(n)` → `YamlInteger(n)`, `fromDouble(d)` → `YamlFloat(d)` (preserves int/double distinction)
- TOML: `fromNull()` → `TomlString('')` (TOML has no null — same as Scala)
- XML: `fromString(s)` → `XmlText(s)`, `createObject(fields)` → `XmlElement(qname('object'), [], [child elements])`

---

## 5. AST → Native Decoders

**File:** `lib/src/decode/native_decoders.dart` (new file)

Currently these live in Lambé's `input.dart`. They belong here, next to the AST types they decode.

```dart
/// Convert a [JsonValue] AST to native Dart types.
Object? jsonToNative(JsonValue v) => switch (v) {
  JsonNull() => null,
  JsonBool(:final value) => value,
  JsonNumber(:final value) =>
    value == value.truncateToDouble() ? value.toInt() : value,
  JsonString(:final value) => value,
  JsonArray(:final elements) => [for (final e in elements) jsonToNative(e)],
  JsonObject(:final fields) => {
    for (final MapEntry(:key, :value) in fields.entries)
      key: jsonToNative(value),
  },
};

/// Convert a [YamlValue] AST to native Dart types.
Object? yamlToNative(YamlValue v) => switch (v) {
  YamlNull() => null,
  YamlBool(:final value) => value,
  YamlInteger(:final value) => value,
  YamlFloat(:final value) => value,
  YamlString(:final value) => value,
  YamlSequence(:final elements) => [for (final e in elements) yamlToNative(e)],
  YamlMapping(:final pairs) => {
    for (final MapEntry(:key, :value) in pairs.entries)
      key: yamlToNative(value),
  },
};

/// Convert a [TomlDocument] to native Dart types.
Map<String, Object?> tomlDocToNative(TomlDocument doc) => {
  for (final MapEntry(:key, :value) in doc.entries) key: tomlToNative(value),
};

/// Convert a [TomlValue] AST to native Dart types.
Object? tomlToNative(TomlValue v) => switch (v) {
  TomlString(:final value) => value,
  TomlInteger(:final value) => value,
  TomlFloat(:final value) => value,
  TomlBool(:final value) => value,
  TomlDateTime(:final value) => value.toIso8601String(),
  TomlLocalDateTime(:final value) => value.toIso8601String(),
  TomlLocalDate(:final year, :final month, :final day) =>
    '$year-${_pad(month)}-${_pad(day)}',
  TomlLocalTime(:final hour, :final minute, :final second) =>
    '${_pad(hour)}:${_pad(minute)}:${_pad(second)}',
  TomlArray(:final elements) => [for (final e in elements) tomlToNative(e)],
  TomlTable(:final pairs) => {
    for (final MapEntry(:key, :value) in pairs.entries)
      key: tomlToNative(value),
  },
};

String _pad(int n) => n.toString().padLeft(2, '0');
```

---

## 6. Fix JSON Serializer

**File:** `lib/src/encode/json_encoders.dart` (modify existing)

### 6a. Add `sortKeys` to config

Replace the `indent` string parameter with a proper config:

```dart
/// Configuration for JSON serialization.
class JsonFormatConfig {
  /// Indentation string (empty = compact).
  final String indent;

  /// Whether to sort object keys alphabetically.
  final bool sortKeys;

  const JsonFormatConfig({this.indent = '', this.sortKeys = false});

  static const compact = JsonFormatConfig();
  static const pretty = JsonFormatConfig(indent: '  ');
}

String serializeJson(JsonValue value, {JsonFormatConfig config = JsonFormatConfig.compact}) => ...
```

### 6b. Add control character escaping

The Scala version escapes `\b`, `\f`, and all control chars below `\u0020`:

```dart
String _escapeJsonString(String s) {
  final buffer = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    switch (c) {
      case 0x08: buffer.write(r'\b');
      case 0x09: buffer.write(r'\t');
      case 0x0A: buffer.write(r'\n');
      case 0x0C: buffer.write(r'\f');
      case 0x0D: buffer.write(r'\r');
      case 0x22: buffer.write(r'\"');
      case 0x5C: buffer.write(r'\\');
      default:
        if (c < 0x20) {
          buffer.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
        } else {
          buffer.writeCharCode(c);
        }
    }
  }
  return buffer.toString();
}
```

### 6c. Add sortKeys support in `_pretty` and `_compact`

When `config.sortKeys` is true, sort the entries of `JsonObject` by key before serializing.

---

## 7. Fix Shared Escape Utilities

**File:** `lib/src/encode/escape.dart` (new file)

Extract duplicated `_escapeString` into a shared location. Each format has slightly different rules:

```dart
/// Escape a string for JSON (RFC 8259 §7).
String escapeJson(String s) { ... } // handles \b, \f, \u00xx

/// Escape a string for TOML basic strings.
String escapeToml(String s) { ... } // same as JSON minus \b, \f

/// Escape a string for YAML double-quoted strings.
String escapeYaml(String s) { ... } // same as TOML

/// Escape text content for XML.
String escapeXmlText(String s) { ... } // &amp; &lt; &gt;

/// Escape attribute values for XML.
String escapeXmlAttr(String s) { ... } // &amp; &lt; &gt; &quot; &apos;
```

The JSON/TOML/YAML string escaping is nearly identical. Factor out the common core and add format-specific differences.

---

## 8. XML Typed Encoders

**File:** `lib/src/encode/xml_encoders.dart` (new file)

Following the pattern of json_encoders.dart, yaml_encoders.dart, toml_encoders.dart:

```dart
/// Encode a [String] as an XML text node.
const AstEncoder<String, XmlNode> xmlStringEncoder = ...;

/// Encode an [int] as an XML text node.
const AstEncoder<int, XmlNode> xmlIntEncoder = ...;

/// Encode a [double] as an XML text node.
const AstEncoder<double, XmlNode> xmlDoubleEncoder = ...;

/// Encode a [bool] as an XML text node.
const AstEncoder<bool, XmlNode> xmlBoolEncoder = ...;

/// Encode a `List<A>` as XML child elements.
AstEncoder<List<A>, XmlNode> xmlListEncoder<A>(AstEncoder<A, XmlNode> element, {String itemName = 'item'}) => ...;

/// Encode a typed value as an XML element using field builders.
AstEncoder<A, XmlNode> toXmlElement<A>(String name, void Function(ObjectBuilder<XmlNode> builder, A value) build) => ...;
```

Plus the serializer (`serializeXml`, `serializeXmlDocument`) as specified in section 2.

---

## 9. Code Generation for AST Encoders

**Package:** `rumil_codec_builder` (extend existing)

The Scala version uses `Encoder.derived[A, To]` via Scala 3 quotes/splice macros. The Dart equivalent uses `build_runner` + `source_gen`.

Currently `rumil_codec_builder` generates `BinaryCodec<T>` for `@BinarySerializable` classes. Extend it to also generate `AstEncoder<T, JsonValue>` (and potentially YAML, TOML, XML) for annotated classes.

### New annotation

```dart
/// Marks a class for AST encoder generation.
///
/// Generates `AstEncoder<T, JsonValue>` by default.
/// Specify [formats] for additional formats.
class AstSerializable {
  final List<AstFormat> formats;
  const AstSerializable({this.formats = const [AstFormat.json]});
}

enum AstFormat { json, yaml, toml, xml }
```

### Generated output

For a class:
```dart
@AstSerializable()
class Person {
  final String name;
  final int age;
  const Person(this.name, this.age);
}
```

Generates:
```dart
// person.ast.g.dart
const personJsonEncoder = _PersonJsonEncoder();

class _PersonJsonEncoder implements AstEncoder<Person, JsonValue> {
  const _PersonJsonEncoder();
  @override
  JsonValue encode(Person value) {
    final builder = ObjectBuilder<JsonValue>();
    builder.field('name', value.name, jsonStringEncoder);
    builder.field('age', value.age, jsonIntEncoder);
    return JsonObject(
      Map.fromEntries(builder.entries.map((f) => MapEntry(f.$1, f.$2))),
    );
  }
}
```

### Implementation approach

The generator reads class fields via `source_gen`'s `ConstantReader` + `analyzer` API (same as the existing `CodecGenerator`). For each field, it looks up the appropriate primitive encoder by type. For nested classes annotated with `@AstSerializable`, it references the generated encoder.

This follows the Scala `Encoder.derived` macro exactly — introspect the product type's fields, generate field-by-field encoding using the `ObjectBuilder` and per-field `AstEncoder` instances.

### Sealed class support

For sealed hierarchies (like the existing `@BinarySerializable` sealed class support):

```dart
@AstSerializable()
sealed class Shape {}

@AstSerializable()
class Circle extends Shape { final double radius; ... }

@AstSerializable()
class Rect extends Shape { final double w, h; ... }
```

Generates a discriminated encoder:
```dart
const shapeJsonEncoder = _ShapeJsonEncoder();

class _ShapeJsonEncoder implements AstEncoder<Shape, JsonValue> {
  @override
  JsonValue encode(Shape value) => switch (value) {
    Circle() => JsonObject({'type': JsonString('Circle'), ...circleJsonEncoder.encode(value)}),
    Rect() => JsonObject({'type': JsonString('Rect'), ...rectJsonEncoder.encode(value)}),
  };
}
```

---

## 10. Barrel Export Updates

**File:** `lib/rumil_parsers.dart`

Add exports for all new public API:

```dart
// Serializers
export 'src/encode/json_encoders.dart' show serializeJson, JsonFormatConfig, ...;
export 'src/encode/yaml_encoders.dart' show serializeYaml, serializeYamlDocument, ...;
export 'src/encode/toml_encoders.dart' show serializeToml, ...;
export 'src/encode/xml_encoders.dart' show serializeXml, serializeXmlDocument, ...;
export 'src/encode/csv_encoders.dart' show serializeCsv, serializeCsvWithHeaders;
export 'src/encode/proto_encoders.dart' show serializeProto;

// AstBuilder
export 'src/encode/ast_builder.dart';

// Native decoders
export 'src/decode/native_decoders.dart';

// Escape utilities (if made public)
export 'src/encode/escape.dart';
```

---

## 11. Tests

**File:** `test/serialize_test.dart` (new)

### Round-trip tests for every format

The gold standard: `parse(serialize(parse(input))) == parse(input)`. Parse a known-good input, serialize to string, parse again, verify the AST matches.

```dart
group('JSON round-trip', () {
  test('compact', () {
    final input = '{"name":"Alice","age":30,"active":true,"tags":["admin","user"]}';
    final ast = _jsonDoc(parseJson(input));
    final serialized = serializeJson(ast);
    final reparsed = _jsonDoc(parseJson(serialized));
    expect(reparsed, ast); // structural equality
  });

  test('pretty', () { ... });
  test('sortKeys', () { ... });
  test('empty object', () { ... });
  test('nested arrays', () { ... });
  test('string escaping: quotes, newlines, tabs, control chars', () { ... });
  test('unicode escaping', () { ... });
  test('numbers: integer, float, negative, zero', () { ... });
});

group('YAML round-trip', () {
  test('block mapping', () { ... });
  test('block sequence', () { ... });
  test('nested mapping + sequence', () { ... });
  test('string quoting: reserved words (true, false, null, ~)', () { ... });
  test('string quoting: special chars (colon, hash, newline)', () { ... });
  test('float special values: .nan, .inf, -.inf', () { ... });
  test('empty mapping', () { ... });
  test('empty sequence', () { ... });
});

group('TOML round-trip', () {
  test('simple key-value', () { ... });
  test('nested tables', () { ... });
  test('array tables', () { ... });
  test('inline table', () { ... });
  test('datetime formats', () { ... });
  test('float special values: nan, inf, -inf', () { ... });
  test('string escaping', () { ... });
});

group('XML round-trip', () {
  test('simple element', () { ... });
  test('attributes', () { ... });
  test('nested elements', () { ... });
  test('self-closing empty element', () { ... });
  test('text content escaping', () { ... });
  test('attribute value escaping', () { ... });
  test('CDATA', () { ... });
  test('comments', () { ... });
  test('processing instructions', () { ... });
  test('namespaced elements (QName with prefix)', () { ... });
});

group('CSV round-trip', () {
  test('simple records', () { ... });
  test('quoted fields', () { ... });
  test('fields with delimiter', () { ... });
  test('fields with newline', () { ... });
  test('fields with quotes', () { ... });
  test('empty fields', () { ... });
  test('TSV', () { ... });
  test('with headers', () { ... });
});

group('Proto round-trip', () {
  test('message with fields', () { ... });
  test('enum', () { ... });
  test('service with rpcs', () { ... });
  test('nested messages', () { ... });
  test('map fields', () { ... });
  test('repeated fields', () { ... });
  test('imports', () { ... });
  test('optional fields', () { ... });  // currently broken — fix in serializer
});
```

### AstBuilder tests

```dart
group('AstBuilder', () {
  group('nativeToAst', () {
    test('null', () { ... });
    test('bool', () { ... });
    test('int', () { ... });
    test('double', () { ... });
    test('string', () { ... });
    test('list', () { ... });
    test('map', () { ... });
    test('nested', () { ... });
  });

  // Test for each format: build AST from native, serialize, parse, verify
  group('JSON: native → AST → string → AST', () { ... });
  group('YAML: native → AST → string → AST', () { ... });
  group('TOML: native → AST → string → AST', () { ... });
});
```

### Native decoder tests

```dart
group('Native decoders', () {
  group('jsonToNative', () {
    test('preserves int', () { ... });
    test('null', () { ... });
    test('nested', () { ... });
  });
  group('yamlToNative', () { ... });
  group('tomlToNative', () { ... });
});
```

---

## 12. Known Issues to Fix in Existing Code

1. **`_escapeString` duplication** — json_encoders.dart and toml_encoders.dart have identical implementations. Extract to `escape.dart`.

2. **Proto serializer: optional fields** — `FieldRule.optional` is not distinguished from singular in the output. The Dart proto AST has `FieldRule.optional` but the serializer only checks for `FieldRule.repeated`. Fix: emit `optional` keyword when `field.rule == FieldRule.optional`.

3. **JSON `JsonNumber` loses int** — `JsonNumber(value.toDouble())` in `_JsonIntEncoder` loses the int/double distinction. The `serializeJson` function checks `value == value.truncateToDouble()` to recover it, which works but is fragile. Consider whether `JsonNumber` should hold `num` instead of `double` (breaking change to AST).

---

## 13. Implementation Order

1. **escape.dart** — shared utilities (unblocks everything else)
2. **Fix JSON serializer** — add sortKeys, control char escaping, use shared escaping
3. **YAML serializer** — port from Scala, uses shared escaping
4. **XML serializer + encoders** — port from Scala, uses shared escaping
5. **CSV serializer** — small, self-contained
6. **AstBuilder** — the native→AST bridge, unblocks format conversion
7. **Native decoders** — move from Lambé, straightforward
8. **Fix proto serializer** — optional field support
9. **Barrel export updates** — wire everything to the public API
10. **Tests** — round-trip for all formats
11. **rumil_codec_builder extension** — AST encoder code generation

---

## 14. Version Impact

This is a significant addition to rumil_parsers. Since the public API is purely additive (new exports, no breaking changes to existing parse functions), it can ship as **rumil_parsers 0.3.0** (minor version bump).

The rumil_codec_builder extension (item 11) is also additive — new annotation, new generator. Ships as **rumil_codec_builder 0.3.0**.

If `JsonNumber` changes from `double` to `num` (section 12, item 3), that's a breaking change requiring **rumil_parsers 1.0.0** or a careful migration. Consider deferring this to a major version bump.
