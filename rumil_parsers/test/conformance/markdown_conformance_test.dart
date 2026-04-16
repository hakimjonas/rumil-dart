import 'dart:convert';
import 'dart:io';

import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

void main() {
  final specFile = File('test/conformance/spec/commonmark-0.31.2.json');
  final examples =
      (jsonDecode(specFile.readAsStringSync()) as List)
          .cast<Map<String, Object?>>();

  final sections = <String>{};
  for (final e in examples) {
    sections.add(e['section'] as String);
  }

  for (final section in sections) {
    group(section, () {
      final sectionExamples =
          examples.where((e) => e['section'] == section).toList();
      for (final example in sectionExamples) {
        final num = example['example'] as int;
        final md = example['markdown'] as String;
        final expectedHtml = example['html'] as String;

        test('example $num', () {
          final result = parseMarkdown(md);
          final doc = switch (result) {
            Success(:final value) => value,
            Partial(:final value) => value,
            Failure() => const MdDocument([]),
          };
          final actualHtml = mdToHtml(doc);

          expect(
            _normalize(actualHtml),
            _normalize(expectedHtml),
            reason:
                'Example $num ($section)\n'
                'Input: ${jsonEncode(md)}\n'
                'Expected: ${jsonEncode(expectedHtml)}\n'
                'Actual:   ${jsonEncode(actualHtml)}',
          );
        });
      }
    });
  }
}

String _normalize(String html) =>
    html
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'>\s+<'), '><')
        .replaceAll(RegExp(r'^\s+|\s+$'), '')
        .trim();

// ---------------------------------------------------------------------------
// MdNode -> HTML renderer (test-internal, not exported)
// ---------------------------------------------------------------------------

String mdToHtml(MdDocument doc) => doc.children.map(_renderNode).join('\n');

String _renderNode(MdNode node) => switch (node) {
  MdDocument(:final children) => children.map(_renderNode).join('\n'),
  MdHeading(:final level, :final children) =>
    '<h$level>${_renderInline(children)}</h$level>',
  MdParagraph(:final children) => '<p>${_renderInline(children)}</p>',
  MdBlockquote(:final children) =>
    '<blockquote>\n${children.map(_renderNode).join('\n')}\n</blockquote>',
  MdList(:final ordered, :final start, :final tight, :final items) =>
    _renderList(ordered, start, tight, items),
  MdListItem(:final children) => _renderListItem(children),
  MdCodeBlock(:final language, :final code) => _renderCodeBlock(language, code),
  MdHtmlBlock(:final html) => html,
  MdThematicBreak() => '<hr />',
  MdText(:final text) => _escapeHtml(text),
  MdEmphasis(:final children) => '<em>${_renderInline(children)}</em>',
  MdStrong(:final children) => '<strong>${_renderInline(children)}</strong>',
  MdLink(:final href, :final title, :final children) => _renderLink(
    href,
    title,
    children,
  ),
  MdImage(:final src, :final alt, :final title) => _renderImage(
    src,
    alt,
    title,
  ),
  MdCode(:final code) => '<code>${_escapeHtml(code)}</code>',
  MdHtmlInline(:final html) => html,
  MdHardBreak() => '<br />\n',
  MdSoftBreak() => '\n',
};

String _renderInline(List<MdNode> nodes) => nodes.map(_renderNode).join();

String _renderList(
  bool ordered,
  int? start,
  bool tight,
  List<MdListItem> items,
) {
  final tag = ordered ? 'ol' : 'ul';
  final startAttr =
      (ordered && start != null && start != 1) ? ' start="$start"' : '';
  final renderedItems = items
      .map((item) {
        if (tight) {
          return _renderTightListItem(item);
        }
        return _renderListItem(item.children);
      })
      .join('\n');
  return '<$tag$startAttr>\n$renderedItems\n</$tag>';
}

String _renderTightListItem(MdListItem item) {
  final buf = StringBuffer('<li>');
  for (final child in item.children) {
    if (child is MdParagraph) {
      buf.write(_renderInline(child.children));
    } else {
      buf.write(_renderNode(child));
    }
  }
  buf.write('</li>');
  return buf.toString();
}

String _renderListItem(List<MdNode> children) {
  final buf = StringBuffer('<li>\n');
  buf.write(children.map(_renderNode).join('\n'));
  buf.write('\n</li>');
  return buf.toString();
}

String _renderCodeBlock(String? language, String code) {
  if (language != null && language.isNotEmpty) {
    return '<pre><code class="language-$language">${_escapeHtml(code)}</code></pre>';
  }
  return '<pre><code>${_escapeHtml(code)}</code></pre>';
}

String _renderLink(String href, String? title, List<MdNode> children) {
  final titleAttr = title != null ? ' title="${_escapeAttr(title)}"' : '';
  return '<a href="${_escapeAttr(href)}"$titleAttr>${_renderInline(children)}</a>';
}

String _renderImage(String src, String alt, String? title) {
  final titleAttr = title != null ? ' title="${_escapeAttr(title)}"' : '';
  return '<img src="${_escapeAttr(src)}" alt="$alt"$titleAttr />';
}

String _escapeHtml(String input) => input
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _escapeAttr(String input) => input
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
