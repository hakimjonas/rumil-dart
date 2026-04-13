import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/src/ast/xml.dart';
import 'package:rumil_parsers/src/xml.dart';
import 'package:test/test.dart';

XmlNode frag(String input) {
  final r = parseXmlFragment(input);
  if (r case Success<ParseError, XmlNode>(:final value)) return value;
  throw StateError('Parse failed: ${r.errors}');
}

XmlDocument doc(String input) {
  final r = parseXml(input);
  if (r case Success<ParseError, XmlDocument>(:final value)) return value;
  throw StateError('Parse failed: ${r.errors}');
}

void main() {
  group('XML elements', () {
    test('self-closing', () {
      final n = frag('<br/>');
      expect(n, isA<XmlElement>());
      expect((n as XmlElement).name.localName, 'br');
      expect(n.children, isEmpty);
    });

    test('empty element', () {
      final n = frag('<div></div>');
      expect(n, isA<XmlElement>());
      expect((n as XmlElement).name.localName, 'div');
    });

    test('with text content', () {
      final n = frag('<p>hello</p>');
      final el = n as XmlElement;
      expect(el.children.length, 1);
      expect((el.children[0] as XmlText).content, 'hello');
    });

    test('nested elements', () {
      final n = frag('<div><p>text</p></div>');
      final div = n as XmlElement;
      expect(div.children.length, 1);
      final p = div.children[0] as XmlElement;
      expect(p.name.localName, 'p');
    });

    test('with attributes', () {
      final n = frag('<a href="http://example.com" class="link">click</a>');
      final el = n as XmlElement;
      expect(el.attributes.length, 2);
      expect(el.attributes[0].name.localName, 'href');
      expect(el.attributes[0].value, 'http://example.com');
      expect(el.attributes[1].name.localName, 'class');
    });

    test('self-closing with attributes', () {
      final n = frag('<img src="pic.png" width="100"/>');
      final el = n as XmlElement;
      expect(el.attributes.length, 2);
      expect(el.children, isEmpty);
    });
  });

  group('XML namespaces', () {
    test('prefixed element', () {
      final n = frag(
        '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">'
        '</soap:Envelope>',
      );
      final el = n as XmlElement;
      expect(el.name.prefix, 'soap');
      expect(el.name.localName, 'Envelope');
    });

    test('prefixed attribute', () {
      final n = frag('<root xml:lang="en"></root>');
      final el = n as XmlElement;
      expect(el.attributes[0].name.prefix, 'xml');
      expect(el.attributes[0].name.localName, 'lang');
    });

    test('unbound prefix rejected', () {
      final r = parseXmlFragment('<a:foo/>');
      expect(r, isA<Failure<dynamic, dynamic>>());
    });
  });

  group('Unicode names', () {
    test('Latin extended', () {
      final n = frag('<café/>');
      expect((n as XmlElement).name.localName, 'café');
    });

    test('CJK element', () {
      final n = frag('<日本語/>');
      expect((n as XmlElement).name.localName, '日本語');
    });

    test('Thai element', () {
      final n = frag('<ภาษา>text</ภาษา>');
      final el = n as XmlElement;
      expect(el.name.localName, 'ภาษา');
      expect((el.children[0] as XmlText).content, 'text');
    });

    test('digit in name rejected as start', () {
      final r = parseXmlFragment('  <1abc/>  ');
      expect(r, isA<Failure<dynamic, dynamic>>());
    });
  });

  group('XML special content', () {
    test('CDATA section', () {
      final n = frag('<data><![CDATA[<not>xml</not>]]></data>');
      final el = n as XmlElement;
      expect(el.children.length, 1);
      expect(el.children[0], isA<XmlCData>());
      expect((el.children[0] as XmlCData).content, '<not>xml</not>');
    });

    test('comment', () {
      final n = frag('<root><!-- a comment --></root>');
      final el = n as XmlElement;
      expect(el.children.length, 1);
      expect(el.children[0], isA<XmlComment>());
      expect((el.children[0] as XmlComment).content, 'a comment');
    });

    test('entity references', () {
      final n = frag('<p>&lt;hello&gt;</p>');
      final el = n as XmlElement;
      expect((el.children[0] as XmlText).content, '<hello>');
    });

    test('character reference decimal', () {
      final n = frag('<p>&#65;</p>');
      final el = n as XmlElement;
      expect((el.children[0] as XmlText).content, 'A');
    });

    test('character reference hex', () {
      final n = frag('<p>&#x41;</p>');
      final el = n as XmlElement;
      expect((el.children[0] as XmlText).content, 'A');
    });
  });

  group('XML document', () {
    test('simple document', () {
      final d = doc('<?xml version="1.0"?><root/>');
      expect(d.version, '1.0');
      expect((d.root as XmlElement).name.localName, 'root');
    });

    test('document with encoding', () {
      final d = doc('<?xml version="1.0" encoding="UTF-8"?><root/>');
      expect(d.encoding, 'UTF-8');
    });

    test('standalone yes', () {
      final d = doc('<?xml version="1.0" standalone="yes"?><root/>');
      expect(d.standalone, true);
    });

    test('version with trailing space rejected', () {
      final r = parseXml('<?xml version="1.0 "?><root/>');
      expect(r, isA<Failure<dynamic, dynamic>>());
    });

    test('standalone YES (uppercase) rejected', () {
      final r = parseXml('<?xml version="1.0" standalone="YES"?><root/>');
      expect(r, isA<Failure<dynamic, dynamic>>());
    });

    test('encoding with leading space rejected', () {
      final r = parseXml('<?xml version="1.0" encoding=" UTF-8"?><root/>');
      expect(r, isA<Failure<dynamic, dynamic>>());
    });

    test('realistic document', () {
      const input = '''<?xml version="1.0" encoding="UTF-8"?>
<catalog>
  <book id="1">
    <title>Dart in Action</title>
    <author>Hakim</author>
  </book>
  <book id="2">
    <title>Parser Combinators</title>
    <author>Rumil</author>
  </book>
</catalog>''';
      final d = doc(input);
      final catalog = d.root as XmlElement;
      expect(catalog.name.localName, 'catalog');
      expect(catalog.children.length, 2);
      final book1 = catalog.children[0] as XmlElement;
      expect(book1.attributes[0].value, '1');
    });
  });

  group('XML whitespace', () {
    test('whitespace around elements', () {
      final n = frag('  <root>  <child/>  </root>  ');
      expect(n, isA<XmlElement>());
    });
  });

  group('Phase 1: well-formedness', () {
    test('mismatched tags rejected', () {
      final r = parseXml('<?xml version="1.0"?><a></b>');
      expect(r, isA<Failure<dynamic, dynamic>>());
    });

    test('duplicate attributes rejected', () {
      final r = parseXmlFragment('<e a="1" a="2"/>');
      expect(r, isA<Failure<dynamic, dynamic>>());
    });

    test('DOCTYPE with internal subset', () {
      final d = doc(
        '<!DOCTYPE doc [\n'
        '<!ELEMENT doc (#PCDATA)>\n'
        ']>\n'
        '<doc>hello</doc>',
      );
      expect((d.root as XmlElement).name.localName, 'doc');
    });

    test('DOCTYPE SYSTEM external ID', () {
      final d = doc(
        '<!DOCTYPE doc SYSTEM "doc.dtd">\n'
        '<doc/>',
      );
      expect((d.root as XmlElement).name.localName, 'doc');
    });

    test('DOCTYPE PUBLIC external ID', () {
      final d = doc(
        '<!DOCTYPE doc PUBLIC "-//Test//EN" "doc.dtd">\n'
        '<doc/>',
      );
      expect((d.root as XmlElement).name.localName, 'doc');
    });

    test('comment with -- rejected', () {
      final r = parseXml(
        '<?xml version="1.0"?><doc><!-- bad -- comment --></doc>',
      );
      expect(r, isA<Failure<dynamic, dynamic>>());
    });

    test('comment ending with --- rejected', () {
      final r = parseXml('<?xml version="1.0"?><doc><!-- bad ---></doc>');
      expect(r, isA<Failure<dynamic, dynamic>>());
    });

    test(']]> in text content rejected', () {
      final r = parseXml('<?xml version="1.0"?><doc>]]></doc>');
      expect(r, isA<Failure<dynamic, dynamic>>());
    });

    test('illegal XML char in content rejected', () {
      final r = parseXml('<?xml version="1.0"?><doc>\x01</doc>');
      expect(r, isA<Failure<dynamic, dynamic>>());
    });

    test('invalid char reference rejected', () {
      final r = parseXml('<?xml version="1.0"?><doc>&#0;</doc>');
      expect(r, isA<Failure<dynamic, dynamic>>());
    });

    test('valid char reference accepted', () {
      final n = frag('<doc>&#65;</doc>');
      final el = n as XmlElement;
      expect((el.children[0] as XmlText).content, 'A');
    });

    test('PI target xml rejected', () {
      final r = parseXmlFragment('<?XML version="1.0"?><doc/>');
      expect(r, isA<Failure<dynamic, dynamic>>());
    });

    test('ENTITY syntax in DOCTYPE validated', () {
      // PUBLIC needs two quoted strings
      final r = parseXml(
        '<!DOCTYPE doc [\n'
        '<!ENTITY foo PUBLIC "some public id">\n'
        ']>\n'
        '<doc/>',
      );
      expect(r, isA<Failure<dynamic, dynamic>>());
    });

    test('undeclared entity rejected (no DTD)', () {
      final r = parseXml('<?xml version="1.0"?><doc>&foo;</doc>');
      expect(r, isA<Failure<dynamic, dynamic>>());
    });

    test('undeclared entity rejected (internal DTD only)', () {
      final r = parseXml(
        '<!DOCTYPE doc [\n'
        '<!ENTITY e "value">\n'
        ']>\n'
        '<doc>&f;</doc>',
      );
      expect(r, isA<Failure<dynamic, dynamic>>());
    });

    test('declared entity accepted', () {
      final d = doc(
        '<!DOCTYPE doc [\n'
        '<!ENTITY e "value">\n'
        '<!ELEMENT doc (#PCDATA)>\n'
        ']>\n'
        '<doc>&e;</doc>',
      );
      expect(d.root, isA<XmlElement>());
    });

    test('undeclared entity OK with external subset', () {
      // External subset may declare entities we don't see.
      final d = doc(
        '<!DOCTYPE doc SYSTEM "doc.dtd">\n'
        '<doc>&maybe;</doc>',
      );
      expect(d.root, isA<XmlElement>());
    });

    test('unparsed entity reference rejected', () {
      final r = parseXml(
        '<!DOCTYPE doc [\n'
        '<!NOTATION n SYSTEM "n">\n'
        '<!ENTITY e SYSTEM "e" NDATA n>\n'
        ']>\n'
        '<doc>&e;</doc>',
      );
      expect(r, isA<Failure<dynamic, dynamic>>());
    });

    test('external entity in attribute rejected', () {
      final r = parseXml(
        '<!DOCTYPE doc [\n'
        '<!ENTITY e SYSTEM "e.xml">\n'
        ']>\n'
        '<doc a="&e;"/>',
      );
      expect(r, isA<Failure<dynamic, dynamic>>());
    });
  });
}
