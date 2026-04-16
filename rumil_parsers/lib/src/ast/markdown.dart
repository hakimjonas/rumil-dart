/// CommonMark Markdown AST types.
///
/// Typed node hierarchy — fields carry structured data (heading level as
/// `int`, link href as `String`), not string tags or attribute maps.
library;

import '_equality.dart';

/// A Markdown AST node.
sealed class MdNode {
  /// Base constructor.
  const MdNode();
}

// ---------------------------------------------------------------------------
// Block nodes
// ---------------------------------------------------------------------------

/// Top-level document containing block-level children.
final class MdDocument extends MdNode {
  /// The document's block-level children.
  final List<MdNode> children;

  /// Creates a document node.
  const MdDocument(this.children);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MdDocument && listEquals(children, other.children);
  @override
  int get hashCode => listHash(children);
  @override
  String toString() => 'MdDocument(${children.length} children)';
}

/// ATX or setext heading (levels 1–6).
final class MdHeading extends MdNode {
  /// The heading level (1–6).
  final int level;

  /// Inline content of the heading.
  final List<MdNode> children;

  /// Creates a heading node.
  const MdHeading(this.level, this.children);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MdHeading &&
          level == other.level &&
          listEquals(children, other.children);
  @override
  int get hashCode => Object.hash(level, listHash(children));
  @override
  String toString() => 'MdHeading($level)';
}

/// Paragraph containing inline content.
final class MdParagraph extends MdNode {
  /// Inline content of the paragraph.
  final List<MdNode> children;

  /// Creates a paragraph node.
  const MdParagraph(this.children);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MdParagraph && listEquals(children, other.children);
  @override
  int get hashCode => listHash(children);
  @override
  String toString() => 'MdParagraph(${children.length} children)';
}

/// Block quote.
final class MdBlockquote extends MdNode {
  /// Block-level children of the blockquote.
  final List<MdNode> children;

  /// Creates a blockquote node.
  const MdBlockquote(this.children);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MdBlockquote && listEquals(children, other.children);
  @override
  int get hashCode => listHash(children);
  @override
  String toString() => 'MdBlockquote(${children.length} children)';
}

/// Ordered or unordered list.
final class MdList extends MdNode {
  /// Whether this is an ordered list.
  final bool ordered;

  /// Starting number for ordered lists (null for unordered).
  final int? start;

  /// Whether the list is tight (no blank lines between items).
  final bool tight;

  /// The list items.
  final List<MdListItem> items;

  /// Creates a list node.
  const MdList({
    required this.ordered,
    this.start,
    required this.tight,
    required this.items,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MdList &&
          ordered == other.ordered &&
          start == other.start &&
          tight == other.tight &&
          listEquals(items, other.items);
  @override
  int get hashCode => Object.hash(ordered, start, tight, listHash(items));
  @override
  String toString() =>
      'MdList(${ordered ? "ordered" : "unordered"}, ${items.length} items)';
}

/// A single list item.
final class MdListItem extends MdNode {
  /// Block-level children of the list item.
  final List<MdNode> children;

  /// Creates a list item node.
  const MdListItem(this.children);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MdListItem && listEquals(children, other.children);
  @override
  int get hashCode => listHash(children);
  @override
  String toString() => 'MdListItem(${children.length} children)';
}

/// Fenced or indented code block.
final class MdCodeBlock extends MdNode {
  /// The info string (language hint), or null.
  final String? language;

  /// The code content.
  final String code;

  /// Creates a code block node.
  const MdCodeBlock(this.code, {this.language});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MdCodeBlock &&
          language == other.language &&
          code == other.code;
  @override
  int get hashCode => Object.hash(language, code);
  @override
  String toString() => 'MdCodeBlock(${language ?? "plain"})';
}

/// Raw HTML block (types 1–7 per CommonMark spec).
final class MdHtmlBlock extends MdNode {
  /// The raw HTML content.
  final String html;

  /// Creates an HTML block node.
  const MdHtmlBlock(this.html);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MdHtmlBlock && html == other.html;
  @override
  int get hashCode => html.hashCode;
  @override
  String toString() => 'MdHtmlBlock(${html.length} chars)';
}

/// Thematic break (horizontal rule).
final class MdThematicBreak extends MdNode {
  /// Creates a thematic break node.
  const MdThematicBreak();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MdThematicBreak;
  @override
  int get hashCode => 0;
  @override
  String toString() => 'MdThematicBreak';
}

// ---------------------------------------------------------------------------
// Inline nodes
// ---------------------------------------------------------------------------

/// Plain text content.
final class MdText extends MdNode {
  /// The text value.
  final String text;

  /// Creates a text node.
  const MdText(this.text);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MdText && text == other.text;
  @override
  int get hashCode => text.hashCode;
  @override
  String toString() => 'MdText("$text")';
}

/// Emphasis (typically rendered as italic).
final class MdEmphasis extends MdNode {
  /// Inline content of the emphasis.
  final List<MdNode> children;

  /// Creates an emphasis node.
  const MdEmphasis(this.children);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MdEmphasis && listEquals(children, other.children);
  @override
  int get hashCode => listHash(children);
  @override
  String toString() => 'MdEmphasis(${children.length} children)';
}

/// Strong emphasis (typically rendered as bold).
final class MdStrong extends MdNode {
  /// Inline content of the strong emphasis.
  final List<MdNode> children;

  /// Creates a strong emphasis node.
  const MdStrong(this.children);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MdStrong && listEquals(children, other.children);
  @override
  int get hashCode => listHash(children);
  @override
  String toString() => 'MdStrong(${children.length} children)';
}

/// Hyperlink.
final class MdLink extends MdNode {
  /// Link destination URL.
  final String href;

  /// Optional link title.
  final String? title;

  /// Inline content (link text).
  final List<MdNode> children;

  /// Creates a link node.
  const MdLink({required this.href, this.title, required this.children});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MdLink &&
          href == other.href &&
          title == other.title &&
          listEquals(children, other.children);
  @override
  int get hashCode => Object.hash(href, title, listHash(children));
  @override
  String toString() => 'MdLink($href)';
}

/// Image.
final class MdImage extends MdNode {
  /// Image source URL.
  final String src;

  /// Alt text.
  final String alt;

  /// Optional image title.
  final String? title;

  /// Creates an image node.
  const MdImage({required this.src, required this.alt, this.title});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MdImage &&
          src == other.src &&
          alt == other.alt &&
          title == other.title;
  @override
  int get hashCode => Object.hash(src, alt, title);
  @override
  String toString() => 'MdImage($src)';
}

/// Inline code span.
final class MdCode extends MdNode {
  /// The code content.
  final String code;

  /// Creates an inline code node.
  const MdCode(this.code);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MdCode && code == other.code;
  @override
  int get hashCode => code.hashCode;
  @override
  String toString() => 'MdCode("$code")';
}

/// Raw inline HTML.
final class MdHtmlInline extends MdNode {
  /// The raw HTML content.
  final String html;

  /// Creates an inline HTML node.
  const MdHtmlInline(this.html);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MdHtmlInline && html == other.html;
  @override
  int get hashCode => html.hashCode;
  @override
  String toString() => 'MdHtmlInline("$html")';
}

/// Hard line break.
final class MdHardBreak extends MdNode {
  /// Creates a hard break node.
  const MdHardBreak();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MdHardBreak;
  @override
  int get hashCode => 1;
  @override
  String toString() => 'MdHardBreak';
}

/// Soft line break.
final class MdSoftBreak extends MdNode {
  /// Creates a soft break node.
  const MdSoftBreak();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MdSoftBreak;
  @override
  int get hashCode => 2;
  @override
  String toString() => 'MdSoftBreak';
}
