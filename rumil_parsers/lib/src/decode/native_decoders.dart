/// AST to native Dart type converters.
///
/// Every converter is an iterative depth-first walk over an explicit
/// worklist rather than a recursive descent, so converting a deeply-nested
/// document cannot overflow the Dart call stack. This matches the
/// stack-safety discipline of rumil's parser interpreter and the green-tree
/// layer (`GreenNodeOps.toSource`): a document that parses must also
/// convert, serialize, and decode without depth-bounded recursion.
///
/// ## The worklist shape
///
/// Each work item is a `(node, sink)` pair: `sink` is a closure that places
/// the converted result of `node` into its destination slot. A leaf calls
/// its sink directly; a container allocates its output (a `List` or `Map`),
/// sinks that container into its own slot immediately, then schedules one
/// child item per element/field whose sink writes into the freshly-allocated
/// container. Because the entire worklist drains before the converter
/// returns, every container is fully populated by the time the root sink's
/// value is read.
///
/// Map keys are *reserved* (inserted with a placeholder) in forward order
/// before child items are scheduled, so the final map preserves source field
/// order regardless of the order in which child items happen to run.
library;

import '../ast/hcl.dart';
import '../ast/json.dart';
import '../ast/toml.dart';
import '../ast/xml.dart';
import '../ast/yaml.dart';
import '../encode/hcl_encoders.dart' show serializeHclValue;
import '../yaml_resolve.dart';

/// A unit of conversion work: convert [node] and pass the result to [sink].
typedef _Sink = void Function(Object? result);

/// Convert a [JsonValue] to native Dart types.
///
/// `JsonInt` becomes [int] (preserved exactly even when above 2^53;
/// no lossy round-trip through [double]); `JsonDouble` becomes [double].
/// The discrimination is made at parse time and carried through the
/// AST, so this conversion is one match per node. Iterative (see the
/// library doc) so arbitrarily-deep documents convert without overflow.
Object? jsonToNative(JsonValue root) {
  final out = <Object?>[null];
  final stack = <(JsonValue, _Sink)>[(root, (v) => out[0] = v)];
  while (stack.isNotEmpty) {
    final (node, sink) = stack.removeLast();
    switch (node) {
      case JsonNull():
        sink(null);
      case JsonBool(:final value):
        sink(value);
      case JsonInt(:final value):
        sink(value);
      case JsonDouble(:final value):
        sink(value);
      case JsonString(:final value):
        sink(value);
      case JsonArray(:final elements):
        final list = List<Object?>.filled(elements.length, null);
        sink(list);
        for (var i = 0; i < elements.length; i++) {
          final idx = i;
          stack.add((elements[idx], (v) => list[idx] = v));
        }
      case JsonObject(:final fields):
        final map = <String, Object?>{};
        sink(map);
        for (final key in fields.keys) {
          map[key] = null; // reserve insertion order
        }
        for (final MapEntry(:key, :value) in fields.entries) {
          stack.add((value, (v) => map[key] = v));
        }
    }
  }
  return out[0];
}

/// Convert a [YamlValue] to native Dart types.
///
/// Resolves anchors and aliases internally before conversion.
/// Downstream consumers never see unresolved [YamlAnchor] or [YamlAlias].
Object? yamlToNative(YamlValue v) {
  final resolved = resolveAnchors(v);
  return _yamlToNativeResolved(resolved);
}

Object? _yamlToNativeResolved(YamlValue root) {
  final out = <Object?>[null];
  final stack = <(YamlValue, _Sink)>[(root, (v) => out[0] = v)];
  while (stack.isNotEmpty) {
    final (node, sink) = stack.removeLast();
    switch (node) {
      case YamlNull():
        sink(null);
      case YamlBool(:final value):
        sink(value);
      case YamlInteger(:final value):
        sink(value);
      case YamlFloat(:final value):
        sink(value);
      case YamlString(:final value):
        sink(value);
      case YamlSequence(:final elements):
        final list = List<Object?>.filled(elements.length, null);
        sink(list);
        for (var i = 0; i < elements.length; i++) {
          final idx = i;
          stack.add((elements[idx], (v) => list[idx] = v));
        }
      case YamlMapping(:final pairs):
        final map = <String, Object?>{};
        sink(map);
        for (final key in pairs.keys) {
          map[key] = null; // reserve insertion order
        }
        for (final MapEntry(:key, :value) in pairs.entries) {
          stack.add((value, (v) => map[key] = v));
        }
      case YamlAnchor() || YamlAlias():
        throw StateError('Unresolved anchor/alias in YAML');
    }
  }
  return out[0];
}

/// Convert a [TomlDocument] to native Dart types.
Map<String, Object?> tomlDocToNative(TomlDocument doc) => {
  for (final MapEntry(:key, :value) in doc.entries) key: tomlToNative(value),
};

/// Convert a [TomlValue] to native Dart types.
///
/// Datetime types are returned as ISO 8601 strings. Iterative (see the
/// library doc) so deeply-nested arrays and tables convert without overflow.
Object? tomlToNative(TomlValue root) {
  final out = <Object?>[null];
  final stack = <(TomlValue, _Sink)>[(root, (v) => out[0] = v)];
  while (stack.isNotEmpty) {
    final (node, sink) = stack.removeLast();
    switch (node) {
      case TomlString(:final value):
        sink(value);
      case TomlInteger(:final value):
        sink(value);
      case TomlFloat(:final value):
        sink(value);
      case TomlBool(:final value):
        sink(value);
      case TomlDateTime(:final value):
        sink(value.toIso8601String());
      case TomlLocalDateTime(:final value):
        sink(value.toIso8601String());
      case TomlLocalDate(:final year, :final month, :final day):
        sink('$year-${_pad(month)}-${_pad(day)}');
      case TomlLocalTime(:final hour, :final minute, :final second):
        sink('${_pad(hour)}:${_pad(minute)}:${_pad(second)}');
      case TomlArray(:final elements):
        final list = List<Object?>.filled(elements.length, null);
        sink(list);
        for (var i = 0; i < elements.length; i++) {
          final idx = i;
          stack.add((elements[idx], (v) => list[idx] = v));
        }
      case TomlTable(:final pairs):
        final map = <String, Object?>{};
        sink(map);
        for (final key in pairs.keys) {
          map[key] = null; // reserve insertion order
        }
        for (final MapEntry(:key, :value) in pairs.entries) {
          stack.add((value, (v) => map[key] = v));
        }
    }
  }
  return out[0];
}

/// Convert an [XmlNode] to native Dart types.
///
/// Elements with only text children return the text content.
/// Elements with child elements return a `Map<String, Object?>`.
/// Throws on CDATA, comments, and processing instructions.
///
/// Iterative (see the library doc): deeply-nested elements convert without
/// overflow. Duplicate child-element local names follow last-write-wins, with
/// the field's position fixed at its first occurrence — matching the previous
/// map-literal construction.
Object? xmlToNative(XmlNode root) {
  final out = <Object?>[null];
  final stack = <(XmlNode, _Sink)>[(root, (v) => out[0] = v)];
  while (stack.isNotEmpty) {
    final (node, sink) = stack.removeLast();
    switch (node) {
      case XmlText(:final content):
        sink(content);
      case XmlCData(:final content):
        sink(content);
      case XmlComment():
        sink(null);
      case XmlPI():
        sink(null);
      case XmlElement(:final children):
        final textChildren = children.whereType<XmlText>().toList();
        if (textChildren.length == children.length) {
          sink(textChildren.map((t) => t.content).join());
        } else {
          final elementChildren = children.whereType<XmlElement>().toList();
          final map = <String, Object?>{};
          sink(map);
          for (final child in elementChildren) {
            map[child.name.localName] = null; // reserve first-occurrence order
          }
          // Schedule in reverse so child items run in source order, giving
          // last-write-wins for duplicate local names (matches the literal).
          for (var i = elementChildren.length - 1; i >= 0; i--) {
            final child = elementChildren[i];
            final key = child.name.localName;
            stack.add((child, (v) => map[key] = v));
          }
        }
    }
  }
  return out[0];
}

/// Convert an [HclDocument] to native Dart types.
///
/// Blocks always become lists, regardless of count, so the shape is
/// uniform across N=1 and N≥2 cases. The AST already distinguishes
/// blocks ([HclBlock]) from attributes; the decoder uses that
/// discriminator instead of inferring container shape from key
/// collisions. Attribute-keyed entries follow last-write-wins.
Map<String, Object?> hclDocToNative(HclDocument doc) {
  final result = <String, Object?>{};
  for (final (key, value) in doc) {
    final native = hclToNative(value);
    if (value is HclBlock) {
      final existing = result[key];
      if (existing is List) {
        existing.add(native);
      } else {
        result[key] = [native];
      }
    } else {
      result[key] = native;
    }
  }
  return result;
}

/// Convert an [HclValue] to native Dart types.
///
/// Blocks include `_type` and `_labels` metadata fields.
/// Expression nodes are serialized back to their HCL string form since
/// this is a non-evaluating parser. Iterative (see the library doc) so
/// deeply-nested lists, objects, and blocks convert without overflow.
Object? hclToNative(HclValue root) {
  final out = <Object?>[null];
  final stack = <(HclValue, _Sink)>[(root, (v) => out[0] = v)];
  while (stack.isNotEmpty) {
    final (node, sink) = stack.removeLast();
    switch (node) {
      case HclString(:final value):
        sink(value);
      case HclInt(:final value):
        sink(value);
      case HclDouble(:final value):
        sink(value);
      case HclBool(:final value):
        sink(value);
      case HclNull():
        sink(null);
      case HclList(:final elements):
        final list = List<Object?>.filled(elements.length, null);
        sink(list);
        for (var i = 0; i < elements.length; i++) {
          final idx = i;
          stack.add((elements[idx], (v) => list[idx] = v));
        }
      case HclObject(:final fields):
        final map = <String, Object?>{};
        sink(map);
        for (final key in fields.keys) {
          map[key] = null; // reserve insertion order
        }
        for (final MapEntry(:key, :value) in fields.entries) {
          stack.add((value, (v) => map[key] = v));
        }
      case HclBlock(:final type, :final labels, :final body):
        final map = <String, Object?>{'_type': type, '_labels': labels};
        sink(map);
        for (final key in body.keys) {
          map[key] = null; // reserve insertion order after the metadata fields
        }
        for (final MapEntry(:key, :value) in body.entries) {
          stack.add((value, (v) => map[key] = v));
        }
      case HclReference(:final path):
        sink(path);
      case HclUnaryOp() ||
          HclBinaryOp() ||
          HclConditional() ||
          HclFunctionCall() ||
          HclIndex() ||
          HclGetAttr() ||
          HclAttrSplat() ||
          HclFullSplat() ||
          HclForTuple() ||
          HclForObject() ||
          HclParenExpr() ||
          HclTemplate() ||
          HclHeredoc():
        sink(serializeHclValue(node));
    }
  }
  return out[0];
}

String _pad(int n) => n.toString().padLeft(2, '0');
