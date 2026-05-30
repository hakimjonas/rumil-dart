/// Encoders and serializer for XML.
library;

import '../ast/xml.dart';
import 'encoder.dart';
import 'escape.dart';
import 'sink_walk.dart';

// ---- Typed encoders ----

/// Encode a [String] as an XML text node.
const AstEncoder<String, XmlNode> xmlStringEncoder = _XmlStringEncoder();

/// Encode an [int] as an XML text node.
const AstEncoder<int, XmlNode> xmlIntEncoder = _XmlIntEncoder();

/// Encode a [double] as an XML text node.
const AstEncoder<double, XmlNode> xmlDoubleEncoder = _XmlDoubleEncoder();

/// Encode a [bool] as an XML text node.
const AstEncoder<bool, XmlNode> xmlBoolEncoder = _XmlBoolEncoder();

/// Encode a `List<A>` as XML child elements wrapped in a tag.
AstEncoder<List<A>, XmlNode> xmlListEncoder<A>(
  AstEncoder<A, XmlNode> element, {
  String itemName = 'item',
}) => _XmlListEncoder<A>(element, itemName);

/// Encode a typed value as an XML element using field builders.
AstEncoder<A, XmlNode> toXmlElement<A>(
  String name,
  void Function(ObjectBuilder<XmlNode> builder, A value) build,
) => _XmlElementEncoder<A>(name, build);

// ---- Serializer ----

/// Serialize an [XmlNode] to an XML string.
///
/// Thin wrapper over [serializeXmlTo]; output is byte-for-byte identical.
String serializeXml(XmlNode node, {int indent = 2, int depth = 0}) {
  final buffer = StringBuffer();
  serializeXmlTo(buffer, node, indent: indent, depth: depth);
  return buffer.toString();
}

/// Serialize an [XmlNode] into [sink].
///
/// Iterative (see `sink_walk.dart`): deeply-nested elements serialize without
/// overflowing the Dart call stack. The single-text-child inline form,
/// self-closing empty elements, attribute formatting, and `indent * depth`
/// padding are all preserved exactly; like every indented pretty-printer the
/// padded form's total size is Θ(depth²), but streaming to [sink] keeps peak
/// memory bounded.
void serializeXmlTo(
  StringSink sink,
  XmlNode root, {
  int indent = 2,
  int depth = 0,
}) {
  final walk = SinkWalk();

  // Mutually recursive *in scheduling* only — see `sink_walk.dart`.
  late final void Function(XmlNode, int) emit;
  emit = (XmlNode node, int depth) {
    final pad = ' ' * (indent * depth);
    switch (node) {
      case XmlText(:final content):
        sink.write('$pad${escapeXmlText(content)}');
      case XmlCData(:final content):
        sink.write('$pad<![CDATA[$content]]>');
      case XmlComment(:final content):
        sink.write('$pad<!--$content-->');
      case XmlPI(:final target, :final content):
        sink.write('$pad<?$target $content?>');
      case XmlElement(:final name, :final attributes, :final children):
        final tag = name.format();
        final attrs =
            attributes.isEmpty
                ? ''
                : ' ${attributes.map((a) => '${a.name.format()}="${escapeXmlAttr(a.value)}"').join(' ')}';

        if (children.isEmpty) {
          sink.write('$pad<$tag$attrs/>');
          return;
        }

        if (children.length == 1 && children.first is XmlText) {
          final text = escapeXmlText((children.first as XmlText).content);
          sink.write('$pad<$tag$attrs>$text</$tag>');
          return;
        }

        sink.write('$pad<$tag$attrs>\n');
        final steps = <SinkStep>[];
        for (var i = 0; i < children.length; i++) {
          final c = children[i];
          if (i > 0) steps.add(() => sink.write('\n'));
          steps.add(() => emit(c, depth + 1));
        }
        steps.add(() => sink.write('\n$pad</$tag>'));
        walk.pushAll(steps);
    }
  };

  emit(root, depth);
  walk.run();
}

/// Serialize with XML declaration.
String serializeXmlDocument(
  XmlNode root, {
  String version = '1.0',
  String? encoding = 'UTF-8',
  int indent = 2,
}) {
  final sb = StringBuffer('<?xml version="$version"');
  if (encoding != null) sb.write(' encoding="$encoding"');
  sb.writeln('?>');
  sb.write(serializeXml(root, indent: indent));
  return sb.toString();
}

// ---- Implementations ----

final class _XmlStringEncoder implements AstEncoder<String, XmlNode> {
  const _XmlStringEncoder();
  @override
  XmlNode encode(String value) => XmlText(value);
}

final class _XmlIntEncoder implements AstEncoder<int, XmlNode> {
  const _XmlIntEncoder();
  @override
  XmlNode encode(int value) => XmlText('$value');
}

final class _XmlDoubleEncoder implements AstEncoder<double, XmlNode> {
  const _XmlDoubleEncoder();
  @override
  XmlNode encode(double value) => XmlText('$value');
}

final class _XmlBoolEncoder implements AstEncoder<bool, XmlNode> {
  const _XmlBoolEncoder();
  @override
  XmlNode encode(bool value) => XmlText('$value');
}

final class _XmlListEncoder<A> implements AstEncoder<List<A>, XmlNode> {
  final AstEncoder<A, XmlNode> _element;
  final String _itemName;
  const _XmlListEncoder(this._element, this._itemName);
  @override
  XmlNode encode(List<A> value) => XmlElement(
    QName(_itemName),
    const [],
    value.map(_element.encode).toList(),
  );
}

final class _XmlElementEncoder<A> implements AstEncoder<A, XmlNode> {
  final String _name;
  final void Function(ObjectBuilder<XmlNode>, A) _build;
  const _XmlElementEncoder(this._name, this._build);
  @override
  XmlNode encode(A value) {
    final builder = ObjectBuilder<XmlNode>();
    _build(builder, value);
    final children =
        builder.entries.map((f) {
          final child = f.$2;
          if (child is XmlElement) return child;
          return XmlElement(QName(f.$1), const [], [child]);
        }).toList();
    return XmlElement(QName(_name), const [], children);
  }
}
