/// Well-formed XML parser with namespace support.
library;

import 'package:rumil/rumil.dart';

import 'ast/xml.dart';
import 'common.dart' as common;

/// Parse an XML document.
Result<ParseError, XmlDocument> parseXml(
  String input, [
  XmlConfig config = defaultXmlConfig,
]) => _xmlDocument(config).run(input);

/// Parse an XML fragment (single element).
Result<ParseError, XmlNode> parseXmlFragment(
  String input, [
  XmlConfig config = defaultXmlConfig,
]) =>
    _ws.skipThen(_xmlElement(config)).thenSkip(_ws).thenSkip(eof()).run(input);

// ---- Whitespace ----

final Parser<ParseError, void> _ws = satisfy(
  (c) => c == ' ' || c == '\t' || c == '\r' || c == '\n',
  'whitespace',
).many.as<void>(null);

// ---- Names ----

final Parser<ParseError, String> _xmlName = satisfy(
      (c) =>
          (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
          (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
          c == '_' ||
          c == ':',
      'name start char',
    )
    .zip(
      satisfy(
        (c) =>
            (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
            (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
            (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
            c == '_' ||
            c == ':' ||
            c == '-' ||
            c == '.',
        'name char',
      ).many,
    )
    .map(((String, List<String>) pair) => pair.$1 + pair.$2.join());

final Parser<ParseError, QName> _qualifiedName = _xmlName.map(QName.parse);

// ---- Helpers ----

Parser<ParseError, String> _charsUntil(String delim) => (string(
  delim,
).notFollowedBy.skipThen(anyChar())).many.map((cs) => cs.join());

// ---- Comments, PIs, CDATA ----

final Parser<ParseError, XmlNode> _xmlComment = string('<!--')
    .skipThen(_charsUntil('-->'))
    .map((content) => XmlComment(content.trim()) as XmlNode)
    .thenSkip(string('-->'));

Parser<ParseError, XmlNode> _processingInstruction() => string('<?')
    .skipThen(_xmlName)
    .flatMap(
      (target) => _ws
          .skipThen(_charsUntil('?>'))
          .map((content) => XmlPI(target, content.trim()) as XmlNode),
    )
    .thenSkip(string('?>'));

final Parser<ParseError, XmlNode> _cdataSection = string('<![CDATA[')
    .skipThen(_charsUntil(']]>'))
    .map((content) => XmlCData(content) as XmlNode)
    .thenSkip(string(']]>'));

// ---- Entity/char references ----

Parser<ParseError, String> _entityRef(XmlConfig config) => char('&')
    .skipThen(_xmlName)
    .flatMap(
      (name) => char(';').map(
        (_) =>
            config.expandEntities
                ? (xmlEntities[name] ?? '&$name;')
                : '&$name;',
      ),
    );

final Parser<ParseError, String> _charRef =
    (string('&#x')
            .skipThen(common.hexDigit().many1)
            .map(
              (digits) =>
                  String.fromCharCode(int.parse(digits.join(), radix: 16)),
            )
            .thenSkip(char(';')) |
        (string('&#')
            .skipThen(digit().many1)
            .map((digits) => String.fromCharCode(int.parse(digits.join())))
            .thenSkip(char(';'))));

// ---- Text content ----

Parser<ParseError, XmlNode> _textContent(XmlConfig config) {
  final regularChar = satisfy(
    (c) => c != '<' && c != '&',
    'text char',
  ).map((c) => c);
  final entity = _entityRef(config);
  final charReference = _charRef;

  return (regularChar | entity | charReference).many1.map((parts) {
    final text = parts.join();
    final content = config.preserveWhitespace ? text : text.trim();
    return XmlText(content) as XmlNode;
  });
}

// ---- Attributes ----

Parser<ParseError, String> _attributeValue(XmlConfig config) {
  Parser<ParseError, String> quotedAttr(String q) => char(q)
      .skipThen(
        (_entityRef(config) |
                _charRef |
                satisfy((c) => c != q && c != '<' && c != '&', 'attr char'))
            .many
            .map((parts) => parts.join()),
      )
      .thenSkip(char(q));

  return quotedAttr('"') | quotedAttr("'");
}

Parser<ParseError, XmlAttribute> _attribute(XmlConfig config) => _qualifiedName
    .zip(
      _ws.skipThen(char('=')).skipThen(_ws).skipThen(_attributeValue(config)),
    )
    .map(((QName, String) pair) => (name: pair.$1, value: pair.$2));

Parser<ParseError, List<XmlAttribute>> _attributes(XmlConfig config) =>
    (_ws.skipThen(_attribute(config))).many;

// ---- Elements ----

Parser<ParseError, XmlNode> _selfClosingElement(XmlConfig config) => char('<')
    .skipThen(_qualifiedName)
    .flatMap(
      (name) => _attributes(config).flatMap(
        (attrs) => _ws
            .skipThen(string('/>'))
            .map((_) => XmlElement(name, attrs, const []) as XmlNode),
      ),
    );

Parser<ParseError, XmlNode> _normalElement(XmlConfig config) => char('<')
    .skipThen(_qualifiedName)
    .flatMap(
      (name) => _attributes(config).flatMap(
        (attrs) => _ws
            .skipThen(char('>'))
            .skipThen(_xmlContent(config))
            .flatMap(
              (children) => string('</')
                  .skipThen(_ws)
                  .skipThen(_qualifiedName)
                  .flatMap(
                    (closeName) => _ws
                        .skipThen(char('>'))
                        .map(
                          (_) => XmlElement(name, attrs, children) as XmlNode,
                        ),
                  ),
            ),
      ),
    );

Parser<ParseError, XmlNode> _xmlElement(XmlConfig config) =>
    _selfClosingElement(config) | _normalElement(config);

// ---- Content ----

Parser<ParseError, List<XmlNode>> _xmlContent(XmlConfig config) {
  final nodeParser =
      _cdataSection |
      (config.parseComments
          ? _xmlComment
          : failure<ParseError, XmlNode>(CustomError('', Location.zero))) |
      (config.parseProcessingInstructions
          ? _processingInstruction()
          : failure<ParseError, XmlNode>(CustomError('', Location.zero))) |
      _xmlElement(config) |
      _textContent(config);

  final wrapped =
      config.preserveWhitespace
          ? nodeParser
          : _ws.skipThen(nodeParser).thenSkip(_ws);

  return wrapped.many.map(
    (nodes) =>
        config.preserveWhitespace
            ? nodes
            : nodes.where((n) {
              if (n case XmlText(:final content)) return content.isNotEmpty;
              return true;
            }).toList(),
  );
}

// ---- Document ----

Parser<ParseError, XmlDocument> _xmlDocument(XmlConfig config) => _ws
    .skipThen(_xmlDecl.optional)
    .flatMap(
      (decl) => _ws
          .skipThen((_processingInstruction() | _xmlComment).many)
          .skipThen(
            _ws
                .skipThen(_xmlElement(config))
                .flatMap(
                  (root) => _ws.skipThen(eof()).map((_) {
                    final version = decl?.$1 ?? '1.0';
                    final encoding = decl?.$2;
                    final standalone = decl?.$3;
                    return XmlDocument(
                      version: version,
                      encoding: encoding,
                      standalone: standalone,
                      root: root,
                    );
                  }),
                ),
          ),
    );

final Parser<ParseError, (String, String?, bool?)> _xmlDecl = string('<?xml')
    .skipThen(_ws)
    .skipThen(string('version'))
    .skipThen(_ws)
    .skipThen(char('='))
    .skipThen(_ws)
    .skipThen(_simpleQuotedString)
    .flatMap(
      (version) => (_ws
          .skipThen(string('encoding'))
          .skipThen(_ws)
          .skipThen(char('='))
          .skipThen(_ws)
          .skipThen(_simpleQuotedString)).optional.flatMap(
        (encoding) => (_ws
            .skipThen(string('standalone'))
            .skipThen(_ws)
            .skipThen(char('='))
            .skipThen(_ws)
            .skipThen(_simpleQuotedString)).optional.flatMap(
          (standalone) => _ws
              .skipThen(string('?>'))
              .map(
                (_) => (
                  version,
                  encoding,
                  standalone != null ? standalone == 'yes' : null,
                ),
              ),
        ),
      ),
    );

final Parser<ParseError, String> _simpleQuotedString =
    (char('"')
            .skipThen(
              satisfy((c) => c != '"', 'char').many.map((cs) => cs.join()),
            )
            .thenSkip(char('"')) |
        (char("'")
            .skipThen(
              satisfy((c) => c != "'", 'char').many.map((cs) => cs.join()),
            )
            .thenSkip(char("'"))));
