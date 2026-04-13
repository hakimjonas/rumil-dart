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
]) {
  final ctx = _Ctx(config);
  return _ws
      .skipThen(_xmlElement(ctx))
      .thenSkip(_ws)
      .thenSkip(eof())
      .run(input);
}

enum _EntityKind { internal, external, unparsed }

/// Tracks a declared entity's kind, replacement text, and system ID.
class _EntityInfo {
  final _EntityKind kind;
  final String? value;
  final String? systemId;
  const _EntityInfo(this.kind, {this.value, this.systemId});
}

/// Internal parse context: user config + entity declarations from the DTD.
/// Built by `_doctypeDecl`, threaded to content parsers via `flatMap`.
class _Ctx {
  final XmlConfig config;
  final Map<String, _EntityInfo> entities;
  final bool strictEntityCheck;
  final Map<String, String> namespaces;
  final Set<(String, String)> tokenizedAttrs;

  const _Ctx(
    this.config, {
    this.entities = const {},
    this.strictEntityCheck = true,
    this.namespaces = const {'xml': 'http://www.w3.org/XML/1998/namespace'},
    this.tokenizedAttrs = const {},
  });
}

final Parser<ParseError, void> _ws = satisfy(
  (c) => c == ' ' || c == '\t' || c == '\r' || c == '\n',
  'whitespace',
).many.as<void>(null);

bool _isNameStartChar(String c) {
  final cp = c.codeUnitAt(0);
  return (cp >= 0x61 && cp <= 0x7A) ||
      (cp >= 0x41 && cp <= 0x5A) ||
      cp == 0x3A ||
      cp == 0x5F ||
      (cp >= 0xC0 && cp <= 0xD6) ||
      (cp >= 0xD8 && cp <= 0xF6) ||
      (cp >= 0xF8 && cp <= 0x2FF) ||
      (cp >= 0x370 && cp <= 0x37D) ||
      (cp >= 0x37F && cp <= 0x1FFF) ||
      (cp >= 0x200C && cp <= 0x200D) ||
      (cp >= 0x2070 && cp <= 0x218F) ||
      (cp >= 0x2C00 && cp <= 0x2FEF) ||
      (cp >= 0x3001 && cp <= 0xD7FF) ||
      (cp >= 0xF900 && cp <= 0xFDCF) ||
      (cp >= 0xFDF0 && cp <= 0xFFFD) ||
      (cp >= 0xD800 && cp <= 0xDB7F);
}

bool _isNameChar(String c) {
  final cp = c.codeUnitAt(0);
  return _isNameStartChar(c) ||
      cp == 0x2D ||
      cp == 0x2E ||
      (cp >= 0x30 && cp <= 0x39) ||
      cp == 0xB7 ||
      (cp >= 0x0300 && cp <= 0x036F) ||
      (cp >= 0x203F && cp <= 0x2040) ||
      (cp >= 0xDC00 && cp <= 0xDFFF);
}

final Parser<ParseError, String> _xmlName = satisfy(
      _isNameStartChar,
      'name start char',
    )
    .zip(satisfy(_isNameChar, 'name char').many)
    .map(((String, List<String>) pair) => pair.$1 + pair.$2.join());

bool _isNcNameStartChar(String c) =>
    _isNameStartChar(c) && c.codeUnitAt(0) != 0x3A;
bool _isNcNameChar(String c) => _isNameChar(c) && c.codeUnitAt(0) != 0x3A;
final Parser<ParseError, String> _ncName = satisfy(
      _isNcNameStartChar,
      'NCName start char',
    )
    .zip(satisfy(_isNcNameChar, 'NCName char').many)
    .map(((String, List<String>) pair) => pair.$1 + pair.$2.join());

final Parser<ParseError, QName> _qualifiedName = _xmlName.flatMap((name) {
  final colon = name.indexOf(':');
  if (colon < 0) return succeed(QName(name));
  if (colon == 0 ||
      colon == name.length - 1 ||
      name.indexOf(':', colon + 1) >= 0) {
    return failure<ParseError, QName>(
      CustomError('invalid QName: $name', Location.zero),
    );
  }
  return succeed(
    QName(name.substring(colon + 1), prefix: name.substring(0, colon)),
  );
});

Parser<ParseError, String> _charsUntil(String delim) => (string(delim)
    .notFollowedBy
    .skipThen(satisfy(_isXmlChar, 'XML char'))).many.map((cs) => cs.join());

bool _isXmlChar(String c) {
  final cp = c.codeUnitAt(0);
  return cp == 0x9 || cp == 0xA || cp == 0xD || (cp >= 0x20 && cp <= 0xFFFD);
}

final Parser<ParseError, String> _commentContent = (string('--').notFollowedBy
    .skipThen(satisfy(_isXmlChar, 'XML char'))).many.map((cs) => cs.join());

final Parser<ParseError, XmlNode> _xmlComment = string('<!--')
    .skipThen(_commentContent)
    .map((content) => XmlComment(content.trim()) as XmlNode)
    .thenSkip(string('-->'));

Parser<ParseError, XmlNode> _processingInstruction() => string('<?')
    .skipThen(_xmlName)
    .flatMap(
      (target) =>
          target.toLowerCase() == 'xml'
              ? failure<ParseError, XmlNode>(
                CustomError('reserved PI target: $target', Location.zero),
              )
              : target.contains(':')
              ? failure<ParseError, XmlNode>(
                CustomError(
                  'colon in PI target: $target (must be NCName)',
                  Location.zero,
                ),
              )
              : string('?>').map((_) => XmlPI(target, '') as XmlNode) |
                  _ws1
                      .skipThen(_charsUntil('?>'))
                      .map(
                        (content) => XmlPI(target, content.trim()) as XmlNode,
                      )
                      .thenSkip(string('?>')),
    );

final Parser<ParseError, XmlNode> _cdataSection = string('<![CDATA[')
    .skipThen(_charsUntil(']]>'))
    .map((content) => XmlCData(content) as XmlNode)
    .thenSkip(string(']]>'));

Parser<ParseError, String> _entityRef(
  _Ctx ctx, {
  bool inAttribute = false,
}) => char('&')
    .skipThen(_xmlName)
    .flatMap(
      (name) => char(';').flatMap((_) {
        if (xmlEntities.containsKey(name)) {
          return succeed(
            ctx.config.expandEntities ? xmlEntities[name]! : '&$name;',
          );
        }
        final info = ctx.entities[name];
        if (info == null) {
          return ctx.strictEntityCheck
              ? failure<ParseError, String>(
                CustomError('undeclared entity: &$name;', Location.zero),
              )
              : succeed('&$name;');
        }
        if (info.kind == _EntityKind.unparsed) {
          return failure<ParseError, String>(
            CustomError('reference to unparsed entity: &$name;', Location.zero),
          );
        }
        if (inAttribute && info.kind == _EntityKind.external) {
          return failure<ParseError, String>(
            CustomError('external entity in attribute: &$name;', Location.zero),
          );
        }
        if (info.value != null) {
          final err = _checkReplacementText(
            info.value!,
            ctx,
            inAttribute: inAttribute,
          );
          if (err != null) {
            return failure<ParseError, String>(CustomError(err, Location.zero));
          }
        }
        if (info.kind == _EntityKind.external &&
            info.systemId != null &&
            ctx.config.resolveEntity != null) {
          final content = ctx.config.resolveEntity!(info.systemId!, null);
          if (content != null) {
            final err = _validateTextDecl(content);
            if (err != null) {
              return failure<ParseError, String>(
                CustomError(err, Location.zero),
              );
            }
          }
        }
        return succeed('&$name;');
      }),
    );

String? _validateTextDecl(String content) {
  if (content.startsWith('<?xml')) {
    final declEnd = content.indexOf('?>');
    if (declEnd < 0) return 'unterminated text declaration';
    final decl = content.substring(0, declEnd + 2);
    final result = _textDecl.run(decl);
    if (result is Failure) return 'malformed text declaration';
    final version = (result as Success).value as String?;
    if (version != null && version != '1.0') {
      return 'text declaration version $version (expected 1.0)';
    }
    return null;
  }
  if (content.length >= 5 &&
      content.substring(0, 5).toLowerCase() == '<?xml' &&
      !content.startsWith('<?xml')) {
    return 'text declaration must use lowercase <?xml';
  }
  final idx = content.indexOf('<?xml');
  if (idx > 0 && idx + 5 < content.length) {
    final after = content[idx + 5];
    if (after == ' ' || after == '\t' || after == '\r' || after == '\n') {
      return 'text declaration not at start of external entity';
    }
  }
  return null;
}

final Parser<ParseError, String?> _textDecl = string('<?xml')
    .skipThen(_ws1)
    .skipThen(
      string('version')
              .skipThen(_eq)
              .skipThen(_quoted(_versionNum))
              .flatMap(
                (v) => _ws1
                    .skipThen(string('encoding'))
                    .skipThen(_eq)
                    .skipThen(_quoted(_encName))
                    .map((_) => v as String?),
              ) |
          string(
            'encoding',
          ).skipThen(_eq).skipThen(_quoted(_encName)).as<String?>(null),
    )
    .thenSkip(_ws)
    .thenSkip(string('?>'));

String? _checkReplacementText(
  String text,
  _Ctx ctx, {
  required bool inAttribute,
}) {
  if (inAttribute) {
    if (text.contains('<')) {
      return '< in entity replacement text used in attribute';
    }
    if (text.contains('&')) {
      for (var i = 0; i < text.length; i++) {
        if (text[i] == '&' && i + 1 < text.length && text[i + 1] != '#') {
          final semi = text.indexOf(';', i + 1);
          if (semi > i + 1) {
            final ref = text.substring(i + 1, semi);
            final refInfo = ctx.entities[ref];
            if (refInfo != null && refInfo.kind == _EntityKind.external) {
              return 'indirect external entity ref &$ref; in attribute';
            }
            if (refInfo != null && refInfo.kind == _EntityKind.unparsed) {
              return 'indirect unparsed entity ref &$ref; in attribute';
            }
            if (refInfo?.value != null) {
              final inner = _checkReplacementText(
                refInfo!.value!,
                ctx,
                inAttribute: true,
              );
              if (inner != null) return inner;
            }
            i = semi;
          }
        }
      }
    }
  }
  if (text.contains('<') || text.contains('&')) {
    final result = _xmlContent(ctx).thenSkip(eof()).run(text);
    if (result is Failure) {
      return 'malformed entity replacement text';
    }
  }
  return null;
}

Parser<ParseError, String> _validCharRef(int cp) {
  final valid =
      cp == 0x9 ||
      cp == 0xA ||
      cp == 0xD ||
      (cp >= 0x20 && cp <= 0xD7FF) ||
      (cp >= 0xE000 && cp <= 0xFFFD) ||
      (cp >= 0x10000 && cp <= 0x10FFFF);
  return valid
      ? succeed(String.fromCharCode(cp))
      : failure(CustomError('invalid char ref: $cp', Location.zero));
}

final Parser<ParseError, String> _charRef =
    (string('&#x')
            .skipThen(common.hexDigit().many1)
            .flatMap(
              (digits) =>
                  _validCharRef(int.tryParse(digits.join(), radix: 16) ?? -1),
            )
            .thenSkip(char(';')) |
        (string('&#')
            .skipThen(digit().many1)
            .flatMap(
              (digits) => _validCharRef(int.tryParse(digits.join()) ?? -1),
            )
            .thenSkip(char(';'))));

Parser<ParseError, XmlNode> _textContent(_Ctx ctx) {
  final regularChar = string(']]>').notFollowedBy
      .skipThen(
        satisfy((c) => c != '<' && c != '&' && _isXmlChar(c), 'text char'),
      )
      .map((c) => c);

  return (regularChar | _entityRef(ctx) | _charRef).many1.map((parts) {
    final text = parts.join();
    final content = ctx.config.preserveWhitespace ? text : text.trim();
    return XmlText(content) as XmlNode;
  });
}

Parser<ParseError, String> _attributeValue(_Ctx ctx) {
  Parser<ParseError, String> quotedAttr(String q) => char(q)
      .skipThen(
        (_entityRef(ctx, inAttribute: true) |
                _charRef |
                satisfy(
                  (c) => c != q && c != '<' && c != '&' && _isXmlChar(c),
                  'attr char',
                ))
            .many
            .map((parts) => parts.join()),
      )
      .thenSkip(char(q));

  return quotedAttr('"') | quotedAttr("'");
}

Parser<ParseError, XmlAttribute> _attribute(_Ctx ctx) => _qualifiedName
    .zip(_ws.skipThen(char('=')).skipThen(_ws).skipThen(_attributeValue(ctx)))
    .map(((QName, String) pair) => (name: pair.$1, value: pair.$2));

Parser<ParseError, List<XmlAttribute>> _attributes(_Ctx ctx) =>
    (_ws1.skipThen(_attribute(ctx))).many;

Parser<ParseError, (List<XmlAttribute>, Map<String, String>)>
_validatedAttributes(_Ctx ctx, QName elementName) => _attributes(ctx).flatMap((
  attrs,
) {
  final seen = <String>{};
  for (final attr in attrs) {
    if (!seen.add(attr.name.format())) {
      return failure<ParseError, (List<XmlAttribute>, Map<String, String>)>(
        CustomError(
          'duplicate attribute: ${attr.name.format()}',
          Location.zero,
        ),
      );
    }
  }

  const xmlNs = 'http://www.w3.org/XML/1998/namespace';
  const xmlnsNs = 'http://www.w3.org/2000/xmlns/';

  String expandAttrValue(String value) {
    if (!value.contains('&')) return value;
    final buf = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      if (value[i] == '&') {
        final semi = value.indexOf(';', i + 1);
        if (semi > i + 1) {
          final ref = value.substring(i + 1, semi);
          final builtin = xmlEntities[ref];
          if (builtin != null) {
            buf.write(builtin);
          } else {
            final info = ctx.entities[ref];
            if (info != null && info.value != null) {
              buf.write(info.value!);
            } else {
              buf.write(value.substring(i, semi + 1));
            }
          }
          i = semi;
          continue;
        }
      }
      buf.write(value[i]);
    }
    return buf.toString();
  }

  String normalizeAttrValue(String value, QName attrName) {
    final key = (elementName.format(), attrName.format());
    if (ctx.tokenizedAttrs.contains(key)) {
      return value.trim().replaceAll(RegExp(r'\s+'), ' ');
    }
    return value;
  }

  final nsMap = Map<String, String>.of(ctx.namespaces);
  for (final attr in attrs) {
    if (attr.name.prefix == 'xmlns') {
      final prefix = attr.name.localName;
      final raw = expandAttrValue(attr.value);
      final uri = normalizeAttrValue(raw, attr.name);
      if (prefix == 'xml' && uri != xmlNs) {
        return failure<ParseError, (List<XmlAttribute>, Map<String, String>)>(
          CustomError('xmlns:xml must be $xmlNs', Location.zero),
        );
      }
      if (prefix == 'xmlns') {
        return failure<ParseError, (List<XmlAttribute>, Map<String, String>)>(
          CustomError('xmlns:xmlns is reserved', Location.zero),
        );
      }
      if (uri == xmlNs && prefix != 'xml') {
        return failure<ParseError, (List<XmlAttribute>, Map<String, String>)>(
          CustomError('only xml prefix may bind to $xmlNs', Location.zero),
        );
      }
      if (uri == xmlnsNs) {
        return failure<ParseError, (List<XmlAttribute>, Map<String, String>)>(
          CustomError('cannot bind prefix to $xmlnsNs', Location.zero),
        );
      }
      if (uri.isEmpty) {
        return failure<ParseError, (List<XmlAttribute>, Map<String, String>)>(
          CustomError(
            'empty namespace URI for prefix $prefix (illegal in 1.0)',
            Location.zero,
          ),
        );
      }
      nsMap[prefix] = uri;
    } else if (attr.name.prefix == null && attr.name.localName == 'xmlns') {
      final defaultUri = normalizeAttrValue(
        expandAttrValue(attr.value),
        attr.name,
      );
      if (defaultUri == xmlNs) {
        return failure<ParseError, (List<XmlAttribute>, Map<String, String>)>(
          CustomError(
            'xml namespace must not be default namespace',
            Location.zero,
          ),
        );
      }
      if (defaultUri == xmlnsNs) {
        return failure<ParseError, (List<XmlAttribute>, Map<String, String>)>(
          CustomError(
            'xmlns namespace must not be default namespace',
            Location.zero,
          ),
        );
      }
    }
  }

  if (elementName.prefix != null &&
      elementName.prefix != 'xml' &&
      !nsMap.containsKey(elementName.prefix)) {
    return failure<ParseError, (List<XmlAttribute>, Map<String, String>)>(
      CustomError('unbound prefix: ${elementName.prefix}', Location.zero),
    );
  }
  for (final attr in attrs) {
    if (attr.name.prefix != null &&
        attr.name.prefix != 'xml' &&
        attr.name.prefix != 'xmlns' &&
        !nsMap.containsKey(attr.name.prefix)) {
      return failure<ParseError, (List<XmlAttribute>, Map<String, String>)>(
        CustomError('unbound prefix: ${attr.name.prefix}', Location.zero),
      );
    }
  }

  final expandedNames = <String>{};
  for (final attr in attrs) {
    if (attr.name.prefix == 'xmlns' ||
        (attr.name.prefix == null && attr.name.localName == 'xmlns')) {
      continue;
    }
    final uri = attr.name.prefix != null ? (nsMap[attr.name.prefix] ?? '') : '';
    final expanded = '$uri\x00${attr.name.localName}';
    if (uri.isNotEmpty && !expandedNames.add(expanded)) {
      return failure<ParseError, (List<XmlAttribute>, Map<String, String>)>(
        CustomError(
          'duplicate expanded attribute: ${attr.name.format()}',
          Location.zero,
        ),
      );
    }
  }

  return succeed((attrs, nsMap));
});

Parser<ParseError, XmlNode> _selfClosingElement(_Ctx ctx) => char('<')
    .skipThen(_qualifiedName)
    .flatMap(
      (name) => _validatedAttributes(ctx, name).flatMap(
        ((List<XmlAttribute>, Map<String, String>) result) => _ws
            .skipThen(string('/>'))
            .map((_) => XmlElement(name, result.$1, const []) as XmlNode),
      ),
    );

Parser<ParseError, XmlNode> _normalElement(_Ctx ctx) => char('<')
    .skipThen(_qualifiedName)
    .flatMap(
      (name) => _validatedAttributes(ctx, name).flatMap((
        (List<XmlAttribute>, Map<String, String>) result,
      ) {
        final (attrs, nsMap) = result;
        final childCtx = _Ctx(
          ctx.config,
          entities: ctx.entities,
          strictEntityCheck: ctx.strictEntityCheck,
          namespaces: nsMap,
          tokenizedAttrs: ctx.tokenizedAttrs,
        );
        return _ws
            .skipThen(char('>'))
            .skipThen(_xmlContent(childCtx))
            .flatMap(
              (children) => _ws
                  .skipThen(string('</'))
                  .skipThen(_qualifiedName)
                  .flatMap(
                    (closeName) =>
                        closeName != name
                            ? failure<ParseError, XmlNode>(
                              CustomError(
                                'mismatched tag: '
                                'expected </${name.format()}>, '
                                'got </${closeName.format()}>',
                                Location.zero,
                              ),
                            )
                            : _ws
                                .skipThen(char('>'))
                                .map(
                                  (_) =>
                                      XmlElement(name, attrs, children)
                                          as XmlNode,
                                ),
                  ),
            );
      }),
    );

Parser<ParseError, XmlNode> _xmlElement(_Ctx ctx) =>
    _selfClosingElement(ctx) | _normalElement(ctx);

Parser<ParseError, List<XmlNode>> _xmlContent(_Ctx ctx) {
  final nodeParser =
      _cdataSection |
      (ctx.config.parseComments
          ? _xmlComment
          : failure<ParseError, XmlNode>(CustomError('', Location.zero))) |
      (ctx.config.parseProcessingInstructions
          ? _processingInstruction()
          : failure<ParseError, XmlNode>(CustomError('', Location.zero))) |
      _xmlElement(ctx) |
      _textContent(ctx);

  final wrapped =
      ctx.config.preserveWhitespace
          ? nodeParser
          : _ws.skipThen(nodeParser).thenSkip(_ws);

  return wrapped.many.map(
    (nodes) =>
        ctx.config.preserveWhitespace
            ? nodes
            : nodes.where((n) {
              if (n case XmlText(:final content)) return content.isNotEmpty;
              return true;
            }).toList(),
  );
}

final Parser<ParseError, void> _ws1 = satisfy(
  (c) => c == ' ' || c == '\t' || c == '\r' || c == '\n',
  'whitespace',
).many1.as<void>(null);

final Parser<ParseError, void> _wsChar = satisfy(
  (c) => c == ' ' || c == '\t' || c == '\r' || c == '\n',
  'whitespace',
).as<void>(null);

final Parser<ParseError, void> _dtdQuoted =
    char('"')
        .skipThen(satisfy((c) => c != '"' && _isXmlChar(c), 'char').skipMany)
        .thenSkip(char('"')) |
    char("'")
        .skipThen(satisfy((c) => c != "'" && _isXmlChar(c), 'char').skipMany)
        .thenSkip(char("'"));

bool _isPubidChar(String c) {
  final cp = c.codeUnitAt(0);
  return cp == 0x20 ||
      cp == 0xD ||
      cp == 0xA ||
      (cp >= 0x61 && cp <= 0x7A) ||
      (cp >= 0x41 && cp <= 0x5A) ||
      (cp >= 0x30 && cp <= 0x39) ||
      cp == 0x2D ||
      cp == 0x27 ||
      cp == 0x28 ||
      cp == 0x29 ||
      cp == 0x2B ||
      cp == 0x2C ||
      cp == 0x2E ||
      cp == 0x2F ||
      cp == 0x3A ||
      cp == 0x3D ||
      cp == 0x3F ||
      cp == 0x3B ||
      cp == 0x21 ||
      cp == 0x2A ||
      cp == 0x23 ||
      cp == 0x40 ||
      cp == 0x24 ||
      cp == 0x5F ||
      cp == 0x25;
}

final Parser<ParseError, void> _pubidLiteral =
    char('"')
        .skipThen(
          satisfy((c) => c != '"' && _isPubidChar(c), 'pubid char').skipMany,
        )
        .thenSkip(char('"')) |
    char("'")
        .skipThen(
          satisfy((c) => c != "'" && _isPubidChar(c), 'pubid char').skipMany,
        )
        .thenSkip(char("'"));

String? _findEntityCycle(Map<String, _EntityInfo> entities) {
  final visited = <String>{};
  final stack = <String>{};

  bool hasCycle(String name) {
    if (stack.contains(name)) return true;
    if (visited.contains(name)) return false;
    visited.add(name);
    stack.add(name);

    final value = entities[name]?.value;
    if (value != null) {
      for (var i = 0; i < value.length; i++) {
        if (value[i] == '&' && i + 1 < value.length && value[i + 1] != '#') {
          final semi = value.indexOf(';', i + 1);
          if (semi > i + 1) {
            final refName = value.substring(i + 1, semi);
            if (hasCycle(refName)) return true;
            i = semi;
          }
        }
      }
    }

    stack.remove(name);
    return false;
  }

  for (final name in entities.keys) {
    if (hasCycle(name)) return name;
  }
  return null;
}

Parser<ParseError, String> _entityValue() {
  Parser<ParseError, String> quoted(String q) => char(q)
      .skipThen(
        (satisfy(
                  (c) => c != q && c != '&' && c != '%' && _isXmlChar(c),
                  'entity value char',
                ) |
                char('&').skipThen(
                  _xmlName.thenSkip(char(';')).map((name) => '&$name;') |
                      string('#x')
                          .skipThen(common.hexDigit().many1)
                          .thenSkip(char(';'))
                          .flatMap(
                            (d) => _validCharRef(
                              int.tryParse(d.join(), radix: 16) ?? -1,
                            ),
                          ) |
                      char('#')
                          .skipThen(digit().many1)
                          .thenSkip(char(';'))
                          .flatMap(
                            (d) => _validCharRef(int.tryParse(d.join()) ?? -1),
                          ),
                ))
            .many
            .map((parts) => parts.join()),
      )
      .thenSkip(char(q));

  return quoted('"') | quoted("'");
}

final Parser<ParseError, String> _systemLiteral =
    char('"')
        .skipThen(
          satisfy(
            (c) => c != '"' && _isXmlChar(c),
            'char',
          ).many.map((cs) => cs.join()),
        )
        .thenSkip(char('"')) |
    char("'")
        .skipThen(
          satisfy(
            (c) => c != "'" && _isXmlChar(c),
            'char',
          ).many.map((cs) => cs.join()),
        )
        .thenSkip(char("'"));

final Parser<ParseError, void> _externalId =
    string('SYSTEM').skipThen(_ws1).skipThen(_dtdQuoted) |
    string('PUBLIC')
        .skipThen(_ws1)
        .skipThen(_pubidLiteral)
        .skipThen(_ws1)
        .skipThen(_dtdQuoted);

final Parser<ParseError, String> _externalIdCapture =
    string('SYSTEM').skipThen(_ws1).skipThen(_systemLiteral) |
    string('PUBLIC')
        .skipThen(_ws1)
        .skipThen(_pubidLiteral)
        .skipThen(_ws1)
        .skipThen(_systemLiteral);

final Parser<ParseError, void> _nmtoken = satisfy(
  _isNameChar,
  'name char',
).many1.as<void>(null);

Parser<ParseError, void> _cp() => (_xmlName.as<void>(null) | _contentGroup())
    .skipThen(oneOf('?*+').as<void>(null).optional)
    .as<void>(null);

Parser<ParseError, void> _contentGroup() => char('(')
    .skipThen(_ws)
    .skipThen(defer(_cp))
    .skipThen(
      (_ws
              .skipThen(char('|'))
              .skipThen(_ws)
              .skipThen(defer(_cp))).many1.skipThen(_ws).thenSkip(char(')')) |
          (_ws
              .skipThen(char(','))
              .skipThen(_ws)
              .skipThen(defer(_cp))).many.skipThen(_ws).thenSkip(char(')')),
    );

Parser<ParseError, void> _mixed() => char('(')
    .skipThen(_ws)
    .skipThen(string('#PCDATA'))
    .skipThen(
      (_ws.skipThen(char('|')).skipThen(_ws).skipThen(_xmlName.as<void>(null)))
              .many
              .skipThen(_ws)
              .thenSkip(string(')*')) |
          _ws.thenSkip(char(')')),
    );

Parser<ParseError, void> _contentspec() =>
    string('EMPTY').as<void>(null) |
    string('ANY').as<void>(null) |
    _mixed() |
    _contentGroup()
        .skipThen(oneOf('?*+').as<void>(null).optional)
        .as<void>(null);

Parser<ParseError, bool> _attType() {
  final tokenizedType = stringIn([
    'ID',
    'IDREF',
    'IDREFS',
    'ENTITY',
    'ENTITIES',
    'NMTOKEN',
    'NMTOKENS',
  ]).as<void>(null);

  final notationType = string('NOTATION')
      .skipThen(_ws1)
      .skipThen(char('('))
      .skipThen(_ws)
      .skipThen(_xmlName.as<void>(null))
      .skipThen(
        (_ws
            .skipThen(char('|'))
            .skipThen(_ws)
            .skipThen(_xmlName.as<void>(null))).many,
      )
      .skipThen(_ws)
      .thenSkip(char(')'));

  final enumeration = char('(')
      .skipThen(_ws)
      .skipThen(_nmtoken)
      .skipThen((_ws.skipThen(char('|')).skipThen(_ws).skipThen(_nmtoken)).many)
      .skipThen(_ws)
      .thenSkip(char(')'));

  return string('CDATA').as<bool>(false) |
      tokenizedType.as<bool>(true) |
      notationType.as<bool>(true) |
      enumeration.as<bool>(true);
}

Parser<ParseError, List<String>> _dtdAttValue() {
  Parser<ParseError, List<String>> quoted(String q) => char(q)
      .skipThen(
        (satisfy(
                  (c) => c != q && c != '<' && c != '&' && _isXmlChar(c),
                  'attr value char',
                ).as<String?>(null) |
                char('&').skipThen(
                  _xmlName.thenSkip(char(';')).map<String?>((n) => n) |
                      string('#x')
                          .skipThen(common.hexDigit().many1)
                          .thenSkip(char(';'))
                          .as<String?>(null) |
                      char('#')
                          .skipThen(digit().many1)
                          .thenSkip(char(';'))
                          .as<String?>(null),
                ))
            .many
            .map((parts) => parts.whereType<String>().toList()),
      )
      .thenSkip(char(q));

  return quoted('"') | quoted("'");
}

Parser<ParseError, List<String>> _defaultDecl() =>
    string('#REQUIRED').as<List<String>>(const []) |
    string('#IMPLIED').as<List<String>>(const []) |
    string('#FIXED').skipThen(_ws1).skipThen(_dtdAttValue()) |
    _dtdAttValue();

typedef _AttDefResult = ({String name, bool tokenized, List<String> refs});

Parser<ParseError, _AttDefResult> _attDef() => _ws1
    .skipThen(_xmlName)
    .flatMap(
      (attrName) => _ws1
          .skipThen(_attType())
          .flatMap(
            (tokenized) => _ws1
                .skipThen(_defaultDecl())
                .map(
                  (refs) => (name: attrName, tokenized: tokenized, refs: refs),
                ),
          ),
    );

typedef _DtdEntry =
    ({
      (String, _EntityInfo)? entity,
      bool peRef,
      List<String> defaultRefs,
      List<(String, String, bool)> attrTypes,
    });
typedef _SubsetResult =
    ({
      Map<String, _EntityInfo> entities,
      bool hasPERefs,
      Set<(String, String)> tokenizedAttrs,
    });
const _DtdEntry _noEntry = (
  entity: null,
  peRef: false,
  defaultRefs: <String>[],
  attrTypes: <(String, String, bool)>[],
);

Parser<ParseError, _Ctx> _doctypeDecl(XmlConfig config) {
  final ndataDecl = _ws1
      .skipThen(string('NDATA'))
      .skipThen(_ws1)
      .skipThen(_xmlName);

  final geDecl = _ncName.flatMap(
    (name) => _ws1
        .skipThen(
          _entityValue().map(
                (value) => (
                  name,
                  _EntityInfo(_EntityKind.internal, value: value),
                ),
              ) |
              _externalIdCapture.flatMap(
                (sysId) =>
                    ndataDecl.map(
                      (_) => (
                        name,
                        _EntityInfo(_EntityKind.unparsed, systemId: sysId),
                      ),
                    ) |
                    succeed<ParseError, (String, _EntityInfo)>((
                      name,
                      _EntityInfo(_EntityKind.external, systemId: sysId),
                    )),
              ),
        )
        .thenSkip(_ws)
        .thenSkip(char('>')),
  );

  final peDecl = char('%')
      .skipThen(_ws1)
      .skipThen(_ncName.as<void>(null))
      .skipThen(_ws1)
      .skipThen(_entityValue().as<void>(null) | _externalId)
      .skipThen(_ws)
      .thenSkip(char('>'));

  final entityDecl = string('ENTITY')
      .skipThen(_ws1)
      .skipThen(
        peDecl.as<_DtdEntry>(_noEntry) |
            geDecl.map<_DtdEntry>(
              (e) => (
                entity: e,
                peRef: false,
                defaultRefs: const <String>[],
                attrTypes: const <(String, String, bool)>[],
              ),
            ),
      );

  final elementDecl = string('ELEMENT')
      .skipThen(_ws1)
      .skipThen(_xmlName.as<void>(null))
      .skipThen(_ws1)
      .skipThen(_contentspec())
      .skipThen(_ws)
      .thenSkip(char('>'));

  final attlistDecl = string('ATTLIST')
      .skipThen(_ws1)
      .skipThen(_xmlName)
      .flatMap(
        (elemName) => _attDef().many
            .map((defs) {
              final refs = defs.expand((_AttDefResult d) => d.refs).toList();
              final types =
                  defs
                      .map((_AttDefResult d) => (elemName, d.name, d.tokenized))
                      .toList();
              return (refs, types);
            })
            .thenSkip(_ws)
            .thenSkip(char('>')),
      );

  final publicId = string('PUBLIC').skipThen(_ws1).skipThen(_pubidLiteral);
  final notationDecl = string('NOTATION')
      .skipThen(_ws1)
      .skipThen(_ncName.as<void>(null))
      .skipThen(_ws1)
      .skipThen(_externalId | publicId)
      .skipThen(_ws)
      .thenSkip(char('>'));

  final comment = string(
    '<!--',
  ).skipThen(_commentContent).thenSkip(string('-->')).as<_DtdEntry>(_noEntry);
  final pi = string('<?')
      .skipThen(_xmlName)
      .flatMap(
        (target) =>
            target.toLowerCase() == 'xml'
                ? failure<ParseError, _DtdEntry>(
                  CustomError('reserved PI target: $target', Location.zero),
                )
                : (string('?>').as<_DtdEntry>(_noEntry) |
                    _ws1
                        .skipThen(_charsUntil('?>'))
                        .thenSkip(string('?>'))
                        .as<_DtdEntry>(_noEntry)),
      );
  final markupDecl = string('<!').skipThen(
    entityDecl |
        elementDecl.as<_DtdEntry>(_noEntry) |
        attlistDecl.map<_DtdEntry>(
          ((List<String>, List<(String, String, bool)>) r) => (
            entity: null,
            peRef: false,
            defaultRefs: r.$1,
            attrTypes: r.$2,
          ),
        ) |
        notationDecl.as<_DtdEntry>(_noEntry),
  );
  final peRef = char('%').skipThen(_xmlName).thenSkip(char(';')).as<_DtdEntry>((
    entity: null,
    peRef: true,
    defaultRefs: <String>[],
    attrTypes: <(String, String, bool)>[],
  ));

  final internalSubset = (comment |
          pi |
          markupDecl |
          peRef |
          _wsChar.as<_DtdEntry>(_noEntry))
      .many
      .flatMap((items) {
        final entities = <String, _EntityInfo>{};
        var hasPERefs = false;
        final tokenized = <(String, String)>{};
        for (final (:entity, :peRef, :defaultRefs, :attrTypes) in items) {
          if (entity != null) entities.putIfAbsent(entity.$1, () => entity.$2);
          if (peRef) hasPERefs = true;
          for (final ref in defaultRefs) {
            if (xmlEntities.containsKey(ref)) continue;
            final info = entities[ref];
            if (info == null) {
              return failure<ParseError, _SubsetResult>(
                CustomError(
                  'undeclared entity &$ref; in attribute default',
                  Location.zero,
                ),
              );
            }
            if (info.kind == _EntityKind.external) {
              return failure<ParseError, _SubsetResult>(
                CustomError(
                  'external entity &$ref; in attribute default',
                  Location.zero,
                ),
              );
            }
            if (info.kind == _EntityKind.unparsed) {
              return failure<ParseError, _SubsetResult>(
                CustomError(
                  'unparsed entity &$ref; in attribute default',
                  Location.zero,
                ),
              );
            }
          }
          for (final (elem, attr, isTokenized) in attrTypes) {
            if (isTokenized) tokenized.add((elem, attr));
          }
        }
        final cycle = _findEntityCycle(entities);
        if (cycle != null) {
          return failure<ParseError, _SubsetResult>(
            CustomError('circular entity reference: $cycle', Location.zero),
          );
        }
        return succeed<ParseError, _SubsetResult>((
          entities: entities,
          hasPERefs: hasPERefs,
          tokenizedAttrs: tokenized,
        ));
      });

  final bracketedSubset = char(
    '[',
  ).skipThen(internalSubset).thenSkip(char(']')).thenSkip(_ws);

  return string('<!DOCTYPE')
      .skipThen(_ws1)
      .skipThen(_xmlName.as<void>(null))
      .skipThen((_ws1.skipThen(_externalId).as<bool>(true)).optional)
      .flatMap(
        (hasExternalId) => _ws
            .skipThen(bracketedSubset.optional)
            .flatMap(
              (subset) => char('>').map((_) {
                final entities = subset?.entities ?? <String, _EntityInfo>{};
                final hasPERefs = subset?.hasPERefs ?? false;
                final hasExternalMarkup = (hasExternalId ?? false) || hasPERefs;
                return _Ctx(
                  config,
                  entities: entities,
                  strictEntityCheck: !hasExternalMarkup,
                  tokenizedAttrs:
                      subset?.tokenizedAttrs ?? const <(String, String)>{},
                );
              }),
            ),
      );
}

Parser<ParseError, XmlDocument> _xmlDocument(XmlConfig config) {
  final misc = (_ws.skipThen(_processingInstruction() | _xmlComment)).many;

  final xmlDeclOrNothing =
      string(
        '<?xml',
      ).lookAhead.skipThen(_xmlDecl.map<(String, String?, bool?)?>((d) => d)) |
      succeed<ParseError, (String, String?, bool?)?>(null);

  return xmlDeclOrNothing.flatMap(
    (decl) => misc
        .skipThen(_ws)
        .skipThen(_doctypeDecl(config).optional)
        .flatMap((dtdCtx) {
          final ctx = dtdCtx ?? _Ctx(config);
          return misc.skipThen(
            _ws
                .skipThen(_xmlElement(ctx))
                .flatMap(
                  (root) => misc.skipThen(_ws).skipThen(eof()).map((_) {
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
          );
        }),
  );
}

final Parser<ParseError, void> _eq = _ws
    .skipThen(char('='))
    .skipThen(_ws)
    .as<void>(null);

Parser<ParseError, String> _quoted(Parser<ParseError, String> inner) =>
    char('"').skipThen(inner).thenSkip(char('"')) |
    char("'").skipThen(inner).thenSkip(char("'"));

final Parser<ParseError, String> _versionNum = string(
  '1.',
).zip(digit().many1).map(((String, List<String>) p) => '${p.$1}${p.$2.join()}');

final Parser<ParseError, String> _encName = satisfy(
      (c) =>
          (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
          (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0),
      'encoding name start',
    )
    .zip(
      satisfy(
        (c) =>
            (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
            (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
            (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
            c == '.' ||
            c == '_' ||
            c == '-',
        'encoding name char',
      ).many,
    )
    .map(((String, List<String>) p) => p.$1 + p.$2.join());

final Parser<ParseError, bool> _standaloneValue =
    string('yes').as<bool>(true) | string('no').as<bool>(false);

final Parser<ParseError, (String, String?, bool?)> _xmlDecl = string('<?xml')
    .skipThen(_ws1)
    .skipThen(string('version'))
    .skipThen(_eq)
    .skipThen(_quoted(_versionNum))
    .flatMap(
      (version) => (_ws1
          .skipThen(string('encoding'))
          .skipThen(_eq)
          .skipThen(_quoted(_encName))).optional.flatMap(
        (encoding) => (_ws1
            .skipThen(string('standalone'))
            .skipThen(_eq)
            .skipThen(
              _quoted(_standaloneValue.map((b) => b ? 'yes' : 'no')),
            )).optional.flatMap(
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
