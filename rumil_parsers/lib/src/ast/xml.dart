/// XML AST types.
library;

/// Qualified name with optional namespace prefix.
class QName {
  final String? prefix;
  final String localName;
  const QName(this.localName, {this.prefix});

  factory QName.parse(String name) {
    final parts = name.split(':');
    if (parts.length == 2) return QName(parts[1], prefix: parts[0]);
    return QName(name);
  }

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
  const XmlNode();
}

final class XmlElement extends XmlNode {
  final QName name;
  final List<XmlAttribute> attributes;
  final List<XmlNode> children;
  const XmlElement(this.name, this.attributes, this.children);
  @override
  String toString() => '<${name.format()}>';
}

final class XmlText extends XmlNode {
  final String content;
  const XmlText(this.content);
  @override
  String toString() => content;
}

final class XmlCData extends XmlNode {
  final String content;
  const XmlCData(this.content);
}

final class XmlComment extends XmlNode {
  final String content;
  const XmlComment(this.content);
}

final class XmlPI extends XmlNode {
  final String target;
  final String content;
  const XmlPI(this.target, this.content);
}

/// XML document.
class XmlDocument {
  final String version;
  final String? encoding;
  final bool? standalone;
  final XmlNode root;
  const XmlDocument({
    this.version = '1.0',
    this.encoding = 'UTF-8',
    this.standalone,
    required this.root,
  });
}

/// XML parsing configuration.
class XmlConfig {
  final bool preserveWhitespace;
  final bool parseComments;
  final bool parseProcessingInstructions;
  final bool expandEntities;
  const XmlConfig({
    this.preserveWhitespace = false,
    this.parseComments = true,
    this.parseProcessingInstructions = true,
    this.expandEntities = true,
  });
}

const defaultXmlConfig = XmlConfig();

const xmlEntities = <String, String>{
  'lt': '<',
  'gt': '>',
  'amp': '&',
  'quot': '"',
  'apos': "'",
};
