/// Parses Markdown with optional YAML frontmatter.
///
/// Frontmatter is delimited by `---` lines at the start of the input.
/// Combines [parseYaml] and [parseMarkdown] without modifying either:
/// when no frontmatter is detected, or the leading `---` block is not
/// closed, the entire input is parsed as Markdown and `frontmatter` is
/// `null`.
library;

import 'package:rumil/rumil.dart';

import 'ast/markdown.dart';
import 'ast/yaml.dart';
import 'markdown.dart';
import 'yaml.dart';

/// A Markdown document paired with its optional YAML frontmatter.
///
/// `frontmatter` is `null` when the input has no leading `---` block
/// or when the block is malformed (no closing `---`). An empty
/// frontmatter block (`---\n---\n`) yields [YamlNull].
final class MarkdownDocument {
  /// Parsed YAML frontmatter, or `null` when absent.
  final YamlDocument? frontmatter;

  /// Parsed Markdown body.
  final MdDocument document;

  /// Creates a [MarkdownDocument].
  const MarkdownDocument({required this.frontmatter, required this.document});

  @override
  bool operator ==(Object other) =>
      other is MarkdownDocument &&
      frontmatter == other.frontmatter &&
      document == other.document;

  @override
  int get hashCode => Object.hash(frontmatter, document);
}

/// Parse Markdown that may have YAML frontmatter into a [MarkdownDocument].
///
/// Frontmatter rules:
///
/// - Detected only when the input starts with `---` followed by a newline.
/// - The block ends at the next line containing exactly `---` (with an
///   optional trailing newline). A trailing `\r` is tolerated.
/// - When the closing `---` is absent, the input is treated as plain
///   Markdown with no frontmatter (no error is raised).
/// - YAML parse errors inside a well-formed frontmatter block surface as
///   the result's failure.
///
/// Markdown parsing follows [parseMarkdown] semantics on the body slice
/// after the closing `---`.
Result<ParseError, MarkdownDocument> parseMarkdownWithFrontmatter(
  String input, {
  YamlParseConfig yamlConfig = const YamlParseConfig(),
}) {
  final split = _splitFrontmatter(input);
  if (split == null) {
    return parseMarkdown(
      input,
    ).map((doc) => MarkdownDocument(frontmatter: null, document: doc));
  }
  final (yamlText, body) = split;

  final YamlDocument frontmatter;
  if (yamlText.trim().isEmpty) {
    frontmatter = const YamlNull();
  } else {
    final yamlResult = parseYaml(yamlText, config: yamlConfig);
    switch (yamlResult) {
      case Success(:final value):
        frontmatter = value;
      case Partial(:final value):
        frontmatter = value;
      case Failure(:final errorThunk, :final furthest):
        return Failure(errorThunk, furthest);
    }
  }

  return parseMarkdown(
    body,
  ).map((doc) => MarkdownDocument(frontmatter: frontmatter, document: doc));
}

/// Splits [input] into `(yamlText, body)` if a frontmatter block is
/// present at the start, else returns `null`.
///
/// The opening fence must be `---` at offset 0 followed by `\n` (or
/// `\r\n`). The closing fence is the first line containing exactly
/// `---`, terminated by a newline or end-of-input. The returned
/// `body` begins at the character after the closing fence's newline
/// (or at end-of-input if the fence has no trailing newline).
(String, String)? _splitFrontmatter(String input) {
  if (!input.startsWith('---')) return null;

  // Opening fence must be followed by a newline.
  final afterOpen = _skipNewline(input, 3);
  if (afterOpen == null) return null;

  // Find closing fence: a line whose only content is `---`.
  var lineStart = afterOpen;
  while (lineStart < input.length) {
    final lineEnd = _findLineEnd(input, lineStart);
    final line = input.substring(lineStart, lineEnd);
    final trimmedRight =
        line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
    if (trimmedRight == '---') {
      final yamlText = input.substring(afterOpen, lineStart);
      final bodyStart = _skipNewline(input, lineEnd) ?? input.length;
      return (yamlText, input.substring(bodyStart));
    }
    final next = _skipNewline(input, lineEnd);
    if (next == null) return null;
    lineStart = next;
  }
  return null;
}

/// Returns the offset after the newline at [offset], or `null` if
/// [offset] is not at a newline. Handles `\n` and `\r\n`.
int? _skipNewline(String input, int offset) {
  if (offset >= input.length) return null;
  if (input.codeUnitAt(offset) == 0x0a) return offset + 1;
  if (input.codeUnitAt(offset) == 0x0d) {
    if (offset + 1 < input.length && input.codeUnitAt(offset + 1) == 0x0a) {
      return offset + 2;
    }
    return offset + 1;
  }
  return null;
}

/// Returns the offset of the next newline at or after [offset], or
/// `input.length` if no newline is found.
int _findLineEnd(String input, int offset) {
  for (var i = offset; i < input.length; i++) {
    final c = input.codeUnitAt(i);
    if (c == 0x0a || c == 0x0d) return i;
  }
  return input.length;
}
