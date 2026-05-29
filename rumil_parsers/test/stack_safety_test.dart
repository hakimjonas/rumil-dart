/// Deep-nesting stack-safety tests for the value layer.
///
/// rumil's parser interpreter is trampolined and stack-safe to arbitrary
/// depth. The operations that run *after* a parse — native conversion,
/// serialization, and composed decoding — historically recursed on nesting
/// depth, so a document that parsed fine would overflow the Dart call stack
/// on the very next step. These tests build deeply-nested ASTs directly
/// (isolating the value layer from the parser) and assert that every
/// value-layer operation completes without a stack overflow.
///
/// Depth is set past Dart's overflow threshold (~5k–15k frames) with a wide
/// margin, so a regression to naive recursion fails here loudly rather than
/// only on pathological production input.
library;

import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

/// Nesting depth for the stress cases. Comfortably past the native Dart
/// stack limit so any recursion-on-depth regression overflows.
const int _depth = 100000;

void main() {
  group('JSON value layer is stack-safe at depth', () {
    test('jsonToNative on a deeply-nested array', () {
      JsonValue node = const JsonInt(0);
      for (var i = 0; i < _depth; i++) {
        node = JsonArray([node]);
      }
      final native = jsonToNative(node);
      // Unwrap to confirm the structure survived intact.
      var current = native;
      var levels = 0;
      while (current is List) {
        current = current.first;
        levels++;
      }
      expect(levels, _depth);
      expect(current, 0);
    });

    test('jsonToNative on a deeply-nested object', () {
      JsonValue node = const JsonInt(0);
      for (var i = 0; i < _depth; i++) {
        node = JsonObject({'a': node});
      }
      final native = jsonToNative(node);
      var current = native;
      var levels = 0;
      while (current is Map) {
        current = current['a'];
        levels++;
      }
      expect(levels, _depth);
      expect(current, 0);
    });

    test('serializeJson (compact) on a deeply-nested array', () {
      JsonValue node = const JsonInt(0);
      for (var i = 0; i < _depth; i++) {
        node = JsonArray([node]);
      }
      final text = serializeJson(node);
      expect(text, '${'[' * _depth}0${']' * _depth}');
    });

    test('serializeJson (pretty) on a deeply-nested object', () {
      JsonValue node = const JsonInt(0);
      for (var i = 0; i < _depth; i++) {
        node = JsonObject({'a': node});
      }
      final text = serializeJson(node, config: JsonFormatConfig.pretty);
      // Just assert it completes and is well-formed at the ends.
      expect(text.startsWith('{\n'), isTrue);
      expect(text.trimRight().endsWith('}'), isTrue);
    });

    // NOTE: this pipeline test feeds *parsed* input, so its depth is bounded
    // by the parser's recursive-descent nesting ceiling (a rumil-core limit,
    // far below the value layer's), NOT by the value layer under test here.
    // The value-layer stress cases above build the AST directly at [_depth].
    // See `tool/nest_probe.dart` and the 0.9.0 release notes for the parser
    // nesting limit.
    test('parse-then-convert pipeline survives reasonable input', () {
      const pipelineDepth = 200;
      final source = '${'[' * pipelineDepth}0${']' * pipelineDepth}';
      final result = parseJson(source);
      final parsed = switch (result) {
        Success<ParseError, JsonValue>(:final value) => value,
        Partial<ParseError, JsonValue>(:final value) => value,
        Failure() => throw StateError('parse failed: ${result.errors}'),
      };
      final native = jsonToNative(parsed);
      expect(native, isA<List>());
    });
  });

  group('YAML value layer is stack-safe at depth', () {
    test('yamlToNative on a deeply-nested sequence', () {
      YamlValue node = const YamlInteger(0);
      for (var i = 0; i < _depth; i++) {
        node = YamlSequence([node]);
      }
      final native = yamlToNative(node);
      expect(native, isA<List>());
    });

    test('yamlToNative on a deeply-nested mapping', () {
      YamlValue node = const YamlInteger(0);
      for (var i = 0; i < _depth; i++) {
        node = YamlMapping({'a': node});
      }
      final native = yamlToNative(node);
      expect(native, isA<Map>());
    });

    test('resolveAnchors on a deeply-nested sequence', () {
      YamlValue node = const YamlInteger(0);
      for (var i = 0; i < _depth; i++) {
        node = YamlSequence([node]);
      }
      final resolved = resolveAnchors(node);
      expect(resolved, isA<YamlSequence>());
    });

    test('serializeYaml on a deeply-nested mapping', () {
      YamlValue node = const YamlInteger(0);
      for (var i = 0; i < _depth; i++) {
        node = YamlMapping({'a': node});
      }
      final text = serializeYaml(node);
      expect(text, isNotEmpty);
    });
  });

  group('TOML value layer is stack-safe at depth', () {
    test('tomlToNative on a deeply-nested array', () {
      TomlValue node = const TomlInteger(0);
      for (var i = 0; i < _depth; i++) {
        node = TomlArray([node]);
      }
      final native = tomlToNative(node);
      expect(native, isA<List>());
    });

    test('_serializeValue on a deeply-nested array', () {
      TomlValue node = const TomlInteger(0);
      for (var i = 0; i < _depth; i++) {
        node = TomlArray([node]);
      }
      // Inline array through the document serializer.
      final doc = {'k': node};
      final text = serializeToml(doc);
      expect(text, isNotEmpty);
    });
  });

  group('HCL value layer is stack-safe at depth', () {
    test('hclToNative on a deeply-nested list', () {
      HclValue node = const HclInt(0);
      for (var i = 0; i < _depth; i++) {
        node = HclList([node]);
      }
      final native = hclToNative(node);
      expect(native, isA<List>());
    });

    test('serializeHclValue on a deeply-nested list', () {
      HclValue node = const HclInt(0);
      for (var i = 0; i < _depth; i++) {
        node = HclList([node]);
      }
      final text = serializeHclValue(node);
      expect(text, '${'[' * _depth}0${']' * _depth}');
    });
  });

  group('XML value layer is stack-safe at depth', () {
    test('xmlToNative on deeply-nested elements', () {
      XmlNode node = XmlElement(QName('leaf'), const [], const [XmlText('x')]);
      for (var i = 0; i < _depth; i++) {
        node = XmlElement(QName('e$i'), const [], [node]);
      }
      final native = xmlToNative(node);
      expect(native, isA<Map>());
    });

    test('serializeXml on deeply-nested elements', () {
      XmlNode node = XmlElement(QName('leaf'), const [], const [XmlText('x')]);
      for (var i = 0; i < _depth; i++) {
        node = XmlElement(QName('e$i'), const [], [node]);
      }
      final text = serializeXml(node);
      expect(text, isNotEmpty);
    });
  });

  group('Composite decoders are stack-safe at depth', () {
    test('deeply-composed jsonListOf decodes a matching deep array', () {
      // A statically-composed decoder nested _depth levels deep.
      AstDecoder<JsonValue, Object?> decoder = jsonInt;
      for (var i = 0; i < _depth; i++) {
        decoder = jsonListOf(decoder);
      }
      JsonValue value = const JsonInt(0);
      for (var i = 0; i < _depth; i++) {
        value = JsonArray([value]);
      }
      final decoded = decoder.decode(value);
      expect(decoded, isA<List>());
    });
  });
}
