# YAML Indentation Fix + HCL Parser Spec

Two upstream additions needed before Lambé can claim real-world format support.

---

## 1. YAML: Nested Indentation-Based Block Structures

### The Problem

The current YAML parser (`lib/src/yaml.dart`) can only parse:
- Scalars: `null`, `true`, `42`, `3.14`, `"hello"`
- Flow collections: `{name: Alice}`, `[1, 2, 3]`
- Flat block mappings: `name: Alice\nage: 30\n`
- Flat block sequences: `- item1\n- item2\n`

It CANNOT parse nested indented structures:

```yaml
metadata:
  name: my-app
  labels:
    app: my-app
spec:
  containers:
    - name: web
      image: nginx
```

This is the most common YAML pattern. Every k8s manifest, CI config, Docker Compose file, and Helm chart uses it. Without this, YAML support is a demo, not a feature.

### Root Cause

`_blockMapping` (line 149) calls `_yamlScalar` for values — never `_yamlValue`. There's no indentation tracking. The Scala version has the same bug.

### The Fix: Indentation-Threaded Block Parsing

YAML's nesting is determined by indentation. A deeper indentation starts a nested block. Returning to the previous level ends it. The parser needs to:

1. Track the current indentation level
2. Parse block mapping values as: inline-scalar OR newline + deeper-block
3. Parse block sequence items as: inline-scalar OR newline + deeper-block
4. Determine "deeper" by counting leading spaces

**Key insight:** Rumil's `flatMap` lets you construct parsers dynamically based on parsed values. Parse the indentation (count spaces), then use `flatMap` to dispatch to a parser parameterized by that indent level.

### Implementation

Replace the current `_blockMapping` and `_blockSequence` with indentation-aware versions. All functions below are parameterized by indent level.

#### Indentation helpers

```dart
/// Match exactly [n] horizontal spaces.
Parser<ParseError, void> _indent(int n) =>
    n == 0 ? succeed<ParseError, void>(null) : common.hspace().times(n).as<void>(null);

/// Count leading spaces on the current line without consuming them.
/// Uses capture + lookAhead to peek.
Parser<ParseError, int> _peekIndent() =>
    common.hspace().many.capture.lookAhead.map((s) => s.length);
```

#### Block value dispatcher

```dart
/// Parse a block-level value at [minIndent] or deeper.
///
/// Peeks at the current line's indentation. If >= minIndent, tries
/// block mapping, block sequence, or scalar at that level.
Parser<ParseError, YamlValue> _blockValueAt(int minIndent) =>
    _peekIndent().flatMap((actualIndent) {
      if (actualIndent < minIndent) return failure<ParseError, YamlValue>(
        ParseError.expected('indentation >= $minIndent', 'indentation $actualIndent'),
      );
      return _blockMappingAt(actualIndent) |
             _blockSequenceAt(actualIndent) |
             _indent(actualIndent).skipThen(_yamlScalar);
    });
```

#### Block mapping (indentation-aware)

```dart
/// Parse a block mapping where all entries start at exactly [indent] spaces.
Parser<ParseError, YamlValue> _blockMappingAt(int indent) {
  // A single entry: key: value (inline or nested)
  final entry = _indent(indent).skipThen(
    _blockKey.flatMap((key) =>
      char(':').skipThen(
        // Inline value (same line): hspace+ then scalar/flow
        common.hspaces1().skipThen(_inlineValue).thenSkip(_lineEnd) |
        // Nested value (next line): newline then deeper block
        _lineEnd.skipThen(_blockValueAt(indent + 1))
      ).map((value) => (key, value))
    )
  );

  return entry.many1.map<YamlValue>((pairs) =>
    YamlMapping(Map.fromEntries(pairs.map((p) => MapEntry(p.$1, p.$2))))
  );
}

/// A mapping key: characters until `:` (not including newline or `#`).
Parser<ParseError, String> _blockKey = satisfy(
  (c) => c != ':' && c != '\n' && c != '#',
  'key char',
).many1.map((cs) => cs.join().trim());

/// An inline value: flow collection or scalar (same line).
Parser<ParseError, YamlValue> _inlineValue =
    _flowSequence | _flowMapping | _yamlScalar;

/// Line ending: optional comment, then newline or EOF.
Parser<ParseError, void> _lineEnd =
    common.hspaces().skipThen(_yamlComment | common.newline().as<void>(null));
```

#### Block sequence (indentation-aware)

```dart
/// Parse a block sequence where all `- ` markers start at exactly [indent] spaces.
Parser<ParseError, YamlValue> _blockSequenceAt(int indent) {
  // A single item: "- " then value (inline or nested)
  final item = _indent(indent).skipThen(
    char('-').skipThen(common.hspace().many1).skipThen(
      // Inline value on same line after "- "
      _inlineValue.thenSkip(_lineEnd) |
      // Or: the value IS a nested block starting at indent + 2
      // (2 = length of "- ")
      _lineEnd.skipThen(_blockValueAt(indent + 2))
    ) |
    // Compact nested mapping: "- key: value" (item is a mapping entry)
    char('-').skipThen(common.hspace().many1).skipThen(
      _blockMappingAt(indent + 2)
    )
  );

  return item.many1.map<YamlValue>(YamlSequence.new);
}
```

**Compact nested mapping** is important. This is the common pattern:

```yaml
users:
  - name: Alice
    age: 25
  - name: Bob
    age: 30
```

Here each `- ` is followed by a mapping entry, and subsequent entries at the same indent level (`indent + 2`) continue the same mapping. The sequence item IS the mapping.

#### Updating the top-level parsers

```dart
/// The top-level YAML value.
final Parser<ParseError, YamlValue> _yamlValue =
    _flowSequence | _flowMapping | _blockValueAt(0);
```

The existing `_blockSequence` and `_blockMapping` (non-parameterized) are removed. All block parsing goes through `_blockValueAt`.

### Test Cases

Add to `test/yaml_test.dart`:

```dart
group('Nested indentation', () {
  test('mapping with nested mapping', () {
    final yaml = 'metadata:\n  name: my-app\n  version: 1.0\n';
    // metadata → {name: my-app, version: 1.0}
  });

  test('mapping with nested sequence', () {
    final yaml = 'tags:\n  - admin\n  - user\n';
    // tags → [admin, user]
  });

  test('deeply nested mapping', () {
    final yaml = 'a:\n  b:\n    c: deep\n';
    // a → {b → {c: deep}}
  });

  test('sequence of mappings (compact notation)', () {
    final yaml = 'users:\n  - name: Alice\n    age: 25\n  - name: Bob\n    age: 30\n';
    // users → [{name: Alice, age: 25}, {name: Bob, age: 30}]
  });

  test('mixed nesting', () {
    final yaml = 'database:\n  host: localhost\n  ports:\n    - 5432\n    - 5433\n';
    // database → {host: localhost, ports: [5432, 5433]}
  });

  test('real-world: k8s deployment', () {
    final yaml = '''
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  labels:
    app: my-app
spec:
  replicas: 3
''';
    // Full nested structure
  });

  test('real-world: simple.yaml fixture', () {
    // Parse the test/resources/yaml/simple.yaml fixture:
    // name: Alice Smith
    // age: 30
    // email: alice@example.com
    // active: true
    // tags:
    //   - user
    //   - admin
    //   - verified
  });

  test('empty value (null implicit)', () {
    final yaml = 'key:\nother: value\n';
    // key → null (empty value after colon + newline, next line is at same indent = new entry)
  });
});

group('Indentation edge cases', () {
  test('inconsistent indentation is an error', () {
    final yaml = 'a:\n  b: 1\n c: 2\n'; // 2 spaces then 1 space
    // Should fail or handle gracefully
  });

  test('tabs are NOT indentation (YAML spec)', () {
    // YAML 1.2 forbids tabs for indentation
  });

  test('flat mapping still works (depth 0)', () {
    // Existing test: name: Alice\nage: 30\n
    // Must still pass — backward compatible
  });

  test('flat sequence still works (depth 0)', () {
    // Existing test: - item1\n- item2\n
    // Must still pass
  });
});
```

### Serializer round-trip

Once the parser handles nested structures, update the YAML round-trip tests in `test/serialize_test.dart`:

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
```

### Backward Compatibility

All existing YAML tests must still pass. The flat block mapping and flat block sequence are special cases of the indentation-aware parser at depth 0. The flow collection parser is unchanged.

---

## 2. HCL Parser + Serializer

### What Is HCL

HashiCorp Configuration Language. Used by Terraform, Packer, Vault, Consul, Nomad. The primary configuration format for infrastructure-as-code.

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"

  tags = {
    Name = "HelloWorld"
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

output "instance_ip" {
  value = aws_instance.web.public_ip
}
```

### HCL AST Types

**File:** `lib/src/ast/hcl.dart` (new)

```dart
/// An HCL value.
sealed class HclValue {
  const HclValue();
}

/// HCL string (bare or quoted).
final class HclString extends HclValue {
  final String value;
  const HclString(this.value);
}

/// HCL number (integer or float).
final class HclNumber extends HclValue {
  final num value;
  const HclNumber(this.value);
}

/// HCL boolean.
final class HclBool extends HclValue {
  final bool value;
  const HclBool(this.value);
}

/// HCL null.
final class HclNull extends HclValue {
  const HclNull();
}

/// HCL list (tuple): `[1, "two", true]`.
final class HclList extends HclValue {
  final List<HclValue> elements;
  const HclList(this.elements);
}

/// HCL object (map): `{ key = "value" }`.
final class HclObject extends HclValue {
  final Map<String, HclValue> fields;
  const HclObject(this.fields);
}

/// HCL block: `resource "aws_instance" "web" { ... }`.
final class HclBlock extends HclValue {
  final String type;
  final List<String> labels;
  final Map<String, HclValue> body;
  const HclBlock(this.type, this.labels, this.body);
}

/// HCL reference: `aws_instance.web.public_ip`.
final class HclReference extends HclValue {
  final String path;
  const HclReference(this.path);
}

/// An HCL document (list of top-level attributes and blocks).
typedef HclDocument = Map<String, HclValue>;
```

All classes need `==`/`hashCode` following the same pattern as JSON/YAML/TOML/XML ASTs.

### HCL Grammar

```
document    → (attribute | block)* EOF
block       → IDENT label* '{' body '}'
label       → STRING
body        → (attribute | block)*
attribute   → IDENT '=' expression
expression  → literal | list | object | reference | funcCall
literal     → STRING | NUMBER | BOOL | NULL
list        → '[' (expression (',' expression)*)? ']'
object      → '{' (IDENT '=' expression)* '}'
reference   → IDENT ('.' IDENT)*
funcCall    → IDENT '(' (expression (',' expression)*)? ')'
STRING      → '"' (char | '\(' expression ')')* '"'   // interpolation
IDENT       → [a-zA-Z_][a-zA-Z0-9_-]*
```

Note: HCL uses `{ }` for nesting, NOT indentation. This is straightforward PEG parsing — no indentation tricks needed.

### HCL Parser

**File:** `lib/src/hcl.dart` (new)

```dart
/// Parse an HCL document.
Result<ParseError, HclDocument> parseHcl(String input) =>
    _ws.skipThen(_hclDocument).thenSkip(_ws).thenSkip(eof()).run(input);
```

Key parsers:

```dart
// Whitespace including comments
final _ws = (whitespace() | _lineComment | _blockComment).many.as<void>(null);
final _lineComment = (string('#') | string('//')).skipThen(satisfy((c) => c != '\n', 'comment').many);
final _blockComment = string('/*').skipThen(/* consume until */ */);

// Identifiers: letters, digits, underscores, hyphens
final _ident = (letter() | char('_')).zip((alphaNum() | char('_') | char('-')).many)
    .map((p) => p.$1 + p.$2.join());

// String with interpolation: "${var.name}"
final _hclString = char('"').skipThen(_hclStringPart.many).thenSkip(char('"'))
    .map((parts) => /* collapse or create interpolated string */);

// Block: type "label" "label" { body }
final _block = _ident.flatMap((type) =>
  _stringLit.many.flatMap((labels) =>
    _sym('{').skipThen(_body).thenSkip(_sym('}'))
      .map((body) => HclBlock(type, labels, body))
  )
);

// Attribute: key = value
final _attribute = _ident.flatMap((key) =>
  _sym('=').skipThen(_expression).map((value) => (key, value))
);

// Reference: aws_instance.web.public_ip
final _reference = _ident.sepBy1(char('.')).map((parts) => HclReference(parts.join('.')));
```

### HCL Serializer

**File:** `lib/src/encode/hcl_encoders.dart` (new)

```dart
/// Serialize an [HclDocument] to HCL text.
String serializeHcl(HclDocument doc, {int indent = 2}) { ... }
```

Handles:
- Attributes: `key = value`
- Blocks: `type "label" { ... }` with indented body
- Inline objects: `{ key = "value" }`
- Lists: `[1, 2, 3]`
- String escaping and interpolation markers

### HCL Native Decoder

**File:** add to `lib/src/decode/native_decoders.dart`

```dart
/// Convert an [HclValue] to native Dart types.
///
/// Blocks are converted to maps with `_type` and `_labels` metadata fields.
Object? hclToNative(HclValue v) => switch (v) {
  HclString(:final value) => value,
  HclNumber(:final value) => value,
  HclBool(:final value) => value,
  HclNull() => null,
  HclList(:final elements) => [for (final e in elements) hclToNative(e)],
  HclObject(:final fields) => {
    for (final MapEntry(:key, :value) in fields.entries)
      key: hclToNative(value),
  },
  HclBlock(:final type, :final labels, :final body) => {
    '_type': type,
    '_labels': labels,
    for (final MapEntry(:key, :value) in body.entries)
      key: hclToNative(value),
  },
  HclReference(:final path) => path,
};
```

### HCL AstBuilder

Add to `lib/src/encode/ast_builder.dart`:

```dart
const AstBuilder<HclValue> hclBuilder = _HclAstBuilder();
```

### HCL Tests

**File:** `test/hcl_test.dart` (new)

```dart
group('HCL attributes', () {
  test('string', () { parseHcl('name = "Alice"') });
  test('number', () { parseHcl('port = 8080') });
  test('bool', () { parseHcl('enabled = true') });
  test('list', () { parseHcl('ports = [80, 443]') });
  test('object', () { parseHcl('tags = { Name = "web" }') });
  test('reference', () { parseHcl('value = aws_instance.web.id') });
});

group('HCL blocks', () {
  test('simple block', () { parseHcl('resource "aws_instance" "web" { ami = "abc" }') });
  test('nested blocks', () { parseHcl('terraform { backend "s3" { bucket = "state" } }') });
  test('block with no labels', () { parseHcl('locals { x = 1 }') });
});

group('HCL comments', () {
  test('hash comment', () { parseHcl('# comment\nname = "test"') });
  test('slash comment', () { parseHcl('// comment\nname = "test"') });
  test('block comment', () { parseHcl('/* comment */\nname = "test"') });
});

group('HCL string interpolation', () {
  test('simple interpolation', () { parseHcl('name = "hello-${var.env}"') });
  test('nested reference', () { parseHcl('ami = "${data.aws_ami.latest.id}"') });
});

group('HCL round-trip', () {
  test('serialize then parse', () {
    final doc = parseHcl(input);
    final serialized = serializeHcl(doc);
    final reparsed = parseHcl(serialized);
    expect(reparsed, doc); // structural equality
  });
});

group('HCL real-world', () {
  test('terraform main.tf', () {
    // Parse a realistic Terraform configuration
  });
});
```

### HCL Native Decoder Tests

```dart
group('hclToNative', () {
  test('attributes', () { ... });
  test('blocks include _type and _labels', () { ... });
  test('nested blocks', () { ... });
  test('references become strings', () { ... });
});
```

---

## 3. Barrel Export Updates

Add to `lib/rumil_parsers.dart`:

```dart
// AST types
export 'src/ast/hcl.dart';

// Parsers
export 'src/hcl.dart' show parseHcl;

// Encoders + serializers
export 'src/encode/hcl_encoders.dart';

// Native decoders
// (hclToNative added to existing native_decoders.dart)
```

---

## 4. Implementation Order

1. **YAML indentation fix** — highest priority, most impactful
   - Implement `_peekIndent`, `_indent`, `_blockValueAt`, `_blockMappingAt`, `_blockSequenceAt`
   - Update `_yamlValue` to use `_blockValueAt(0)`
   - Verify all existing YAML tests still pass
   - Add nested indentation tests
   - Add round-trip tests for nested structures

2. **HCL AST types** — standalone, no deps
   - With `==`/`hashCode` on all classes

3. **HCL parser** — depends on AST types
   - Start with attributes + blocks + literals
   - Then add references, string interpolation, function calls

4. **HCL serializer** — depends on AST types

5. **HCL native decoder** — depends on AST types

6. **HCL AstBuilder** — depends on AST types + builder infrastructure

7. **Tests** — alongside each step

8. **Barrel exports** — last

---

## 5. Verification

```bash
dart analyze --fatal-infos
dart format --set-exit-if-changed .
dart test
```

All existing 243 tests must still pass. New tests for YAML indentation + HCL should bring the total to ~300+.

Round-trip tests required for:
- Nested YAML mappings
- YAML sequences of mappings (compact notation)
- HCL attributes + blocks

The YAML fix MUST enable parsing `test/resources/yaml/simple.yaml` (the fixture that's been sitting there untested).
