import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

MarkdownDocument _ok(Result<ParseError, MarkdownDocument> r) => switch (r) {
  Success(:final value) => value,
  Partial(:final value) => value,
  Failure() => throw StateError('Expected success, got ${r.errors}'),
};

void main() {
  group('parseMarkdownWithFrontmatter', () {
    test('file with frontmatter populates both fields', () {
      const input = '''---
title: About
count: 3
---

# Hello

World.
''';
      final doc = _ok(parseMarkdownWithFrontmatter(input));
      expect(doc.frontmatter, isA<YamlMapping>());
      final pairs = (doc.frontmatter! as YamlMapping).pairs;
      expect((pairs['title']! as YamlString).value, 'About');
      expect((pairs['count']! as YamlInteger).value, 3);

      // Body parsed as Markdown.
      expect(doc.document.children, isNotEmpty);
      expect(doc.document.children.first, isA<MdHeading>());
    });

    test('file without frontmatter has null frontmatter', () {
      const input = '# Just markdown\n\nNo frontmatter here.\n';
      final doc = _ok(parseMarkdownWithFrontmatter(input));
      expect(doc.frontmatter, isNull);

      // Body matches plain parseMarkdown output exactly.
      final plain = switch (parseMarkdown(input)) {
        Success(:final value) => value,
        Partial(:final value) => value,
        Failure() => throw StateError('plain parseMarkdown failed'),
      };
      expect(doc.document, equals(plain));
    });

    test('empty frontmatter block yields YamlNull', () {
      const input = '---\n---\n\n# Body\n';
      final doc = _ok(parseMarkdownWithFrontmatter(input));
      expect(doc.frontmatter, isA<YamlNull>());
      expect(doc.document.children, isNotEmpty);
    });

    test('unclosed frontmatter falls back to plain markdown', () {
      // No closing `---`, so the input is treated as plain Markdown.
      const input = '---\ntitle: oops\n\n# Body\n';
      final doc = _ok(parseMarkdownWithFrontmatter(input));
      expect(doc.frontmatter, isNull);

      final plain = switch (parseMarkdown(input)) {
        Success(:final value) => value,
        Partial(:final value) => value,
        Failure() => throw StateError('plain parseMarkdown failed'),
      };
      expect(doc.document, equals(plain));
    });

    test('does not detect frontmatter when --- is not at offset 0', () {
      const input = '\n---\ntitle: nope\n---\n\n# Body\n';
      final doc = _ok(parseMarkdownWithFrontmatter(input));
      expect(doc.frontmatter, isNull);
    });

    test('handles CRLF line endings', () {
      const input = '---\r\ntitle: CRLF\r\n---\r\n\r\n# Body\r\n';
      final doc = _ok(parseMarkdownWithFrontmatter(input));
      expect(doc.frontmatter, isA<YamlMapping>());
      final pairs = (doc.frontmatter! as YamlMapping).pairs;
      expect((pairs['title']! as YamlString).value, 'CRLF');
    });

    test('whitespace-only frontmatter yields YamlNull', () {
      const input = '---\n   \n---\n\n# Body\n';
      final doc = _ok(parseMarkdownWithFrontmatter(input));
      expect(doc.frontmatter, isA<YamlNull>());
    });

    test('frontmatter end-of-file with no body', () {
      const input = '---\ntitle: only-meta\n---';
      final doc = _ok(parseMarkdownWithFrontmatter(input));
      expect(doc.frontmatter, isA<YamlMapping>());
      expect(doc.document.children, isEmpty);
    });

    test('frontmatter end-of-file with trailing newline, no body', () {
      const input = '---\ntitle: only-meta\n---\n';
      final doc = _ok(parseMarkdownWithFrontmatter(input));
      expect(doc.frontmatter, isA<YamlMapping>());
      expect(doc.document.children, isEmpty);
    });

    test('--- inside body (after blank line) is not treated as a fence', () {
      // The closing --- is on the line at offset >0 already because the
      // opening was at 0; once the *real* close is found, anything after
      // is body. Subsequent --- lines in the body remain plain Markdown
      // (thematic breaks).
      const input = '''---
title: t
---

# Hello

---

After break.
''';
      final doc = _ok(parseMarkdownWithFrontmatter(input));
      expect(doc.frontmatter, isA<YamlMapping>());
      // The body's --- becomes a thematic break.
      final hasBreak = doc.document.children.any((n) => n is MdThematicBreak);
      expect(hasBreak, isTrue);
    });

    test('MarkdownDocument equality and hashCode', () {
      const input = '---\ntitle: t\n---\n\n# H\n';
      final a = _ok(parseMarkdownWithFrontmatter(input));
      final b = _ok(parseMarkdownWithFrontmatter(input));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
