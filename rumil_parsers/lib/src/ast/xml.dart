/// XML AST types.
library;

/// Qualified name with optional namespace prefix.
class QName {
  /// The namespace prefix, or null for unprefixed names.
  final String? prefix;

  /// The local part of the name.
  final String localName;

  /// Creates a qualified name.
  const QName(this.localName, {this.prefix});

  /// Parse a `prefix:local` or plain `local` string.
  factory QName.parse(String name) {
    final parts = name.split(':');
    if (parts.length == 2) return QName(parts[1], prefix: parts[0]);
    return QName(name);
  }

  /// Format as `prefix:localName` or just `localName`.
  String format() => prefix != null ? '$prefix:$localName' : localName;

  @override
  bool operator ==(Object other) =>
      other is QName && prefix == other.prefix && localName == other.localName;
  @override
  int get hashCode => Object.hash(prefix, localName);
  @override
  String toString() => format();
}

/// XML attribute.
typedef XmlAttribute = ({QName name, String value});

/// An XML node.
sealed class XmlNode {
  /// Base constructor.
  const XmlNode();
}

/// An XML element with a tag name, attributes, and children.
final class XmlElement extends XmlNode {
  /// The element's qualified name.
  final QName name;

  /// The element's attributes.
  final List<XmlAttribute> attributes;

  /// The element's child nodes.
  final List<XmlNode> children;

  /// Creates an element.
  const XmlElement(this.name, this.attributes, this.children);
  @override
  String toString() => '<${name.format()}>';
}

/// A text node.
final class XmlText extends XmlNode {
  /// The text content.
  final String content;

  /// Creates a text node.
  const XmlText(this.content);
  @override
  String toString() => content;
}

/// A CDATA section.
final class XmlCData extends XmlNode {
  /// The CDATA content.
  final String content;

  /// Creates a CDATA node.
  const XmlCData(this.content);
}

/// An XML comment.
final class XmlComment extends XmlNode {
  /// The comment text.
  final String content;

  /// Creates a comment node.
  const XmlComment(this.content);
}

/// A processing instruction.
final class XmlPI extends XmlNode {
  /// The PI target (e.g. `xml-stylesheet`).
  final String target;

  /// The PI content.
  final String content;

  /// Creates a processing instruction.
  const XmlPI(this.target, this.content);
}

/// XML document.
class XmlDocument {
  /// The XML version (e.g. `1.0`).
  final String version;

  /// The declared encoding (e.g. `UTF-8`).
  final String? encoding;

  /// The standalone declaration.
  final bool? standalone;

  /// The root element.
  final XmlNode root;

  /// Creates a document.
  const XmlDocument({
    this.version = '1.0',
    this.encoding = 'UTF-8',
    this.standalone,
    required this.root,
  });
}

/// XML parsing configuration.
class XmlConfig {
  /// Whether to preserve whitespace-only text nodes.
  final bool preserveWhitespace;

  /// Whether to include comment nodes in the tree.
  final bool parseComments;

  /// Whether to include processing instructions in the tree.
  final bool parseProcessingInstructions;

  /// Whether to expand entity references (e.g. `&amp;` to `&`).
  final bool expandEntities;

  /// Creates a parse configuration.
  const XmlConfig({
    this.preserveWhitespace = false,
    this.parseComments = true,
    this.parseProcessingInstructions = true,
    this.expandEntities = true,
  });
}

/// Default XML configuration.
const defaultXmlConfig = XmlConfig();

/// Standard XML entity mappings.
const xmlEntities = <String, String>{
  'lt': '<',
  'gt': '>',
  'amp': '&',
  'quot': '"',
  'apos': "'",
};
