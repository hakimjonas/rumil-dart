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
///
/// ## Serializers stream into a discarding sink
///
/// The indented pretty-printers (pretty JSON, YAML, XML) emit `indent * depth`
/// whitespace at every level, so a fully-materialized 100k-deep document is
/// Θ(depth²) ≈ tens of GB — physically impossible to hold as one `String`
/// regardless of whether the walk recurses or iterates. Stack-safety (call
/// depth) and output size (heap) are orthogonal concerns. To test the former
/// in isolation, the serializer cases write into a [_DiscardSink] via the
/// streaming `serialize*To(StringSink, ...)` API: the bytes are counted and
/// dropped, never accumulated, so the walk runs to full depth and only its
/// call-stack behaviour is under test. (Output *correctness* is pinned at
/// shallow depth by the `serialize_test.dart` / conformance suites.)
library;

import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

/// Nesting depth for the stress cases. Comfortably past the native Dart
/// stack limit so any recursion-on-depth regression overflows.
const int _depth = 100000;

/// A [StringSink] that counts the bytes written and discards them.
///
/// Lets the streaming serializers run at arbitrary depth without
/// materializing their (for indented formats, Θ(depth²)) output, so the test
/// exercises call-stack behaviour decoupled from output size.
final class _DiscardSink implements StringSink {
  /// Total UTF-16 code units written.
  int length = 0;

  @override
  void write(Object? obj) => length += '$obj'.length;

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    var first = true;
    for (final o in objects) {
      if (!first && separator.isNotEmpty) write(separator);
      write(o);
      first = false;
    }
  }

  @override
  void writeCharCode(int charCode) => length += 1;

  @override
  void writeln([Object? obj = '']) {
    write(obj);
    length += 1; // newline
  }
}

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

    test('serializeJsonTo (compact) on a deeply-nested array', () {
      JsonValue node = const JsonInt(0);
      for (var i = 0; i < _depth; i++) {
        node = JsonArray([node]);
      }
      // Compact output is O(depth), so it could be materialized — but stream
      // it for uniformity with the indented cases. `[` + `]` per level + `0`.
      final sink = _DiscardSink();
      serializeJsonTo(sink, node);
      expect(sink.length, _depth * 2 + 1);
    });

    test('serializeJsonTo (pretty) on a deeply-nested object', () {
      JsonValue node = const JsonInt(0);
      for (var i = 0; i < _depth; i++) {
        node = JsonObject({'a': node});
      }
      // Indented output is Θ(depth²) (tens of GB at this depth) — provably
      // never materialized: the discarding sink just confirms the walk runs
      // to full depth without overflowing the stack.
      final sink = _DiscardSink();
      serializeJsonTo(sink, node, config: JsonFormatConfig.pretty);
      expect(sink.length, greaterThan(0));
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
      expect(native, isA<List<Object?>>());
    });
  });

  group('YAML value layer is stack-safe at depth', () {
    test('yamlToNative on a deeply-nested sequence', () {
      YamlValue node = const YamlInteger(0);
      for (var i = 0; i < _depth; i++) {
        node = YamlSequence([node]);
      }
      final native = yamlToNative(node);
      expect(native, isA<List<Object?>>());
    });

    test('yamlToNative on a deeply-nested mapping', () {
      YamlValue node = const YamlInteger(0);
      for (var i = 0; i < _depth; i++) {
        node = YamlMapping({'a': node});
      }
      final native = yamlToNative(node);
      expect(native, isA<Map<String, Object?>>());
    });

    test('resolveAnchors on a deeply-nested sequence', () {
      YamlValue node = const YamlInteger(0);
      for (var i = 0; i < _depth; i++) {
        node = YamlSequence([node]);
      }
      final resolved = resolveAnchors(node);
      expect(resolved, isA<YamlSequence>());
    });

    test('serializeYamlTo on a deeply-nested mapping', () {
      YamlValue node = const YamlInteger(0);
      for (var i = 0; i < _depth; i++) {
        node = YamlMapping({'a': node});
      }
      // Block-style indentation is Θ(depth²); stream into a discarding sink.
      final sink = _DiscardSink();
      serializeYamlTo(sink, node);
      expect(sink.length, greaterThan(0));
    });
  });

  group('TOML value layer is stack-safe at depth', () {
    test('tomlToNative on a deeply-nested array', () {
      TomlValue node = const TomlInteger(0);
      for (var i = 0; i < _depth; i++) {
        node = TomlArray([node]);
      }
      final native = tomlToNative(node);
      expect(native, isA<List<Object?>>());
    });

    test('serializeTomlTo inline array on a deeply-nested array', () {
      TomlValue node = const TomlInteger(0);
      for (var i = 0; i < _depth; i++) {
        node = TomlArray([node]);
      }
      // Inline array through the document serializer (O(depth) output).
      final doc = {'k': node};
      final sink = _DiscardSink();
      serializeTomlTo(sink, doc);
      expect(sink.length, greaterThan(0));
    });
  });

  group('HCL value layer is stack-safe at depth', () {
    test('hclToNative on a deeply-nested list', () {
      HclValue node = const HclInt(0);
      for (var i = 0; i < _depth; i++) {
        node = HclList([node]);
      }
      final native = hclToNative(node);
      expect(native, isA<List<Object?>>());
    });

    test('serializeHclValueTo on a deeply-nested list', () {
      HclValue node = const HclInt(0);
      for (var i = 0; i < _depth; i++) {
        node = HclList([node]);
      }
      // Compact list output is O(depth): `[` + `]` per level + `0`.
      final sink = _DiscardSink();
      serializeHclValueTo(sink, node);
      expect(sink.length, _depth * 2 + 1);
    });
  });

  group('XML value layer is stack-safe at depth', () {
    test('xmlToNative on deeply-nested elements', () {
      XmlNode node = const XmlElement(QName('leaf'), [], [XmlText('x')]);
      for (var i = 0; i < _depth; i++) {
        node = XmlElement(QName('e$i'), const [], [node]);
      }
      final native = xmlToNative(node);
      expect(native, isA<Map<String, Object?>>());
    });

    test('serializeXmlTo on deeply-nested elements', () {
      XmlNode node = const XmlElement(QName('leaf'), [], [XmlText('x')]);
      for (var i = 0; i < _depth; i++) {
        node = XmlElement(QName('e$i'), const [], [node]);
      }
      // Indented element output is Θ(depth²); stream into a discarding sink.
      final sink = _DiscardSink();
      serializeXmlTo(sink, node);
      expect(sink.length, greaterThan(0));
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
      expect(decoded, isA<List<Object?>>());
    });
  });
}
