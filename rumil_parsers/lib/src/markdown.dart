/// Parses CommonMark 0.31.2 Markdown into [MdNode] trees.
///
/// Built on Rumil parser combinators with left recursion, memoization,
/// and typed errors with source locations. Full conformance with the
/// CommonMark 0.31.2 specification (652 examples).
library;

import 'package:rumil/rumil.dart';

import 'ast/markdown.dart';

/// Parse CommonMark Markdown into an [MdDocument].
Result<ParseError, MdDocument> parseMarkdown(String input) {
  final normalized =
      input.contains('\r')
          ? input.replaceAll('\r\n', '\n').replaceAll('\r', '\n')
          : input;
  final tabExpanded =
      normalized.contains('\t') ? _expandTabs(normalized) : normalized;
  final withNewline =
      tabExpanded.isEmpty || tabExpanded.endsWith('\n')
          ? tabExpanded
          : '$tabExpanded\n';

  // Phase 1: parse and collect link reference definitions.
  // Phase 2 (only if refs found): re-run with refs so forward references resolve.
  _linkRefs.clear();
  _paragraphCache.clear();
  final phase1 = _document.run(withNewline);
  if (_linkRefs.isEmpty) {
    return phase1.map(MdDocument.new);
  }
  final refs = Map<String, (String, String?)>.of(_linkRefs);
  _linkRefs
    ..clear()
    ..addAll(refs);
  final phase2 = _document.run(withNewline);
  return phase2.map(MdDocument.new);
}

MdDocument _markdownInner(String input) {
  final withNewline =
      input.isEmpty || input.endsWith('\n') ? input : '$input\n';
  final result = _document.run(withNewline);
  return switch (result) {
    Success(:final value) => MdDocument(value),
    Partial(:final value) => MdDocument(value),
    Failure() => const MdDocument([]),
  };
}

String _expandTabs(String input) {
  final buf = StringBuffer();
  var col = 0;
  for (var i = 0; i < input.length; i++) {
    if (input[i] == '\t') {
      final spaces = 4 - (col % 4);
      for (var s = 0; s < spaces; s++) {
        buf.write(' ');
      }
      col += spaces;
    } else if (input[i] == '\n') {
      buf.write('\n');
      col = 0;
    } else {
      buf.write(input[i]);
      col++;
    }
  }
  return buf.toString();
}

final _linkRefs = <String, (String, String?)>{};
final _paragraphCache = <String, bool>{};

final Parser<ParseError, String> _newline = char('\n');

final Parser<ParseError, void> _optSpaces = satisfy(
  (c) => c == ' ' || c == '\t',
  'space',
).many.as<void>(null);

final Parser<ParseError, String> _restOfLine = satisfy(
  (c) => c != '\n',
  'non-newline',
).many.capture.thenSkip(_newline);

final Parser<ParseError, String> _restOfLineOrEof = satisfy(
  (c) => c != '\n',
  'non-newline',
).many.capture.thenSkip(_newline | eof().map((_) => ''));

final Parser<ParseError, void> _blankLine = satisfy(
  (c) => c == ' ' || c == '\t',
  'space',
).many.thenSkip(_newline).as<void>(null);

final Parser<ParseError, void> _optBlankLines = _blankLine.many.as<void>(null);

final Parser<ParseError, List<MdNode>> _document = _optBlankLines
    .skipThen(_blockElement.many)
    .thenSkip(_optBlankLines)
    .thenSkip(eof());

final Parser<ParseError, MdNode> _blockElement = _optBlankLines.skipThen(
  _htmlBlock |
      _thematicBreak |
      _atxHeading |
      _fencedCodeBlock |
      _indentedCodeBlock |
      _linkRefDef |
      _setextHeading |
      _blockquote |
      _orderedList |
      _unorderedList |
      _paragraph,
);

/// Skips setext headings — for blockquote/list content with lazy setext lines.
final Parser<ParseError, MdNode> _blockElementNoSetext = _optBlankLines
    .skipThen(
      _htmlBlock |
          _thematicBreak |
          _atxHeading |
          _fencedCodeBlock |
          _indentedCodeBlock |
          _linkRefDef |
          _blockquote |
          _orderedList |
          _unorderedList |
          _paragraph,
    );

final Parser<ParseError, List<MdNode>> _documentNoSetext = _optBlankLines
    .skipThen(_blockElementNoSetext.many)
    .thenSkip(_optBlankLines)
    .thenSkip(eof());

final Parser<ParseError, int> _indentGuard = satisfy(
  (c) => c == ' ',
  'space',
).manyAtLeast(0).capture.flatMap((spaces) {
  if (spaces.length > 3) {
    return failure<ParseError, int>(
      CustomError('too much indent', Location.zero),
    );
  }
  return succeed<ParseError, int>(spaces.length);
});

final Parser<ParseError, MdNode> _thematicBreak = _indentGuard.skipThen(
  _thematicBreakBody,
);

final Parser<ParseError, MdNode> _thematicBreakBody = satisfy(
  (c) => c == '*' || c == '-' || c == '_',
  'rule char',
).flatMap((ch) {
  final ruleChar = satisfy((c) => c == ch || c == ' ' || c == '\t', 'rule');
  return ruleChar.many.capture
      .thenSkip(_newline | eof().map((_) => ''))
      .flatMap((rest) {
        final count = 1 + rest.split('').where((c) => c == ch).length;
        if (count < 3) {
          return failure<ParseError, MdNode>(
            CustomError('thematic break needs 3+ chars', Location.zero),
          );
        }
        return succeed<ParseError, MdNode>(const MdThematicBreak());
      });
});

final Parser<ParseError, MdNode> _atxHeading = _indentGuard.skipThen(
  _atxHeadingBody,
);

final Parser<ParseError, MdNode> _atxHeadingBody = char(
  '#',
).many1.capture.flatMap((hashes) {
  final level = hashes.length;
  if (level > 6) {
    return failure<ParseError, MdNode>(
      CustomError('heading level > 6', Location.zero),
    );
  }
  final withContent = char(' ')
      .skipThen(_atxContent)
      .map(
        (content) => MdHeading(level, _parseInline(content.trim())) as MdNode,
      );
  final empty = (_newline | eof().map((_) => '')).map(
    (_) => MdHeading(level, const []) as MdNode,
  );
  return withContent | empty;
});

final Parser<ParseError, MdNode> _setextHeading = _setextContent.flatMap(
  (lines) => _setextUnderline.map((level) {
    final content = lines.join('\n').trimRight();
    return MdHeading(level, _parseInline(content));
  }),
);

final Parser<ParseError, String> _atxContent = _restOfLineOrEof.map(
  _stripClosingHashes,
);

final Parser<ParseError, String> _atxClosingStripper = () {
  final trailingSpaces = _optSpaces.thenSkip(eof());
  final allHashes = char('#').many1.skipThen(trailingSpaces).as<String>('');
  final closingSuffix = satisfy(
    (c) => c == ' ' || c == '\t',
    'ws',
  ).many1.skipThen(char('#').many1).skipThen(trailingSpaces);
  final contentChar = closingSuffix.notFollowedBy.skipThen(
    satisfy((c) => c != '\n', 'c'),
  );
  final withClosing = contentChar.many.capture.thenSkip(closingSuffix);
  final plain = satisfy((c) => c != '\n', 'c').many.capture.thenSkip(eof());
  return allHashes | withClosing | plain;
}();

String _stripClosingHashes(String line) {
  final result = _atxClosingStripper.run(line);
  return switch (result) {
    Success(:final value) => value,
    Partial(:final value) => value,
    Failure() => line,
  };
}

final Parser<ParseError, List<String>> _setextContent = _setextLine.many1;

final Parser<ParseError, String> _setextLine = _thematicBreak.notFollowedBy
    .skipThen(_setextUnderline.notFollowedBy)
    .skipThen(_blankLine.notFollowedBy)
    .skipThen(_atxHeading.notFollowedBy)
    .skipThen(_fencedCodeBlock.notFollowedBy)
    .skipThen(_blockquoteLine.notFollowedBy)
    .skipThen(_ulListItemWithMarker.notFollowedBy)
    .skipThen(_olListItemWithDelim.notFollowedBy)
    .skipThen(_indentGuard.skipThen(_restOfLine));

final Parser<ParseError, int> _setextUnderline = _indentGuard.skipThen(
  char('=').many1
          .thenSkip(_optSpaces)
          .thenSkip(_newline | eof().map((_) => ''))
          .map((_) => 1) |
      char('-').many1
          .thenSkip(_optSpaces)
          .thenSkip(_newline | eof().map((_) => ''))
          .map((_) => 2),
);

final Parser<ParseError, MdNode> _fencedCodeBlock = _indentGuard.flatMap(
  _fencedCodeBody,
);

Parser<ParseError, MdNode> _fencedCodeBody(int indent) {
  final backtickFence = char('`').manyAtLeast(3).capture;
  final tildeFence = char('~').manyAtLeast(3).capture;

  return (backtickFence | tildeFence).flatMap((fence) {
    final fenceChar = fence[0];
    final fenceLen = fence.length;

    if (fenceChar == '`') {
      return satisfy((c) => c != '\n' && c != '`', 'info char').many.capture
          .thenSkip(_newline | eof().map((_) => ''))
          .flatMap(
            (info) =>
                _fencedCodeContent(fenceChar, fenceLen, indent).map((code) {
                  final lang = _resolveEntities(
                    _resolveBackslashEscapes(info.trim()),
                  );
                  final langWord =
                      lang.contains(' ')
                          ? lang.substring(0, lang.indexOf(' '))
                          : lang;
                  return MdCodeBlock(
                    code,
                    language: langWord.isNotEmpty ? langWord : null,
                  );
                }),
          );
    } else {
      return _restOfLine.flatMap(
        (info) => _fencedCodeContent(fenceChar, fenceLen, indent).map((code) {
          final lang = _resolveEntities(_resolveBackslashEscapes(info.trim()));
          final langWord =
              lang.contains(' ') ? lang.substring(0, lang.indexOf(' ')) : lang;
          return MdCodeBlock(
            code,
            language: langWord.isNotEmpty ? langWord : null,
          );
        }),
      );
    }
  });
}

Parser<ParseError, void> _stripUpTo(int n) =>
    n <= 0
        ? succeed<ParseError, void>(null)
        : char(' ').optional.skipThen(_stripUpTo(n - 1));

Parser<ParseError, String> _fencedCodeContent(
  String fenceChar,
  int fenceLen,
  int indent,
) {
  final closingFence = _indentGuard
      .skipThen(char(fenceChar).manyAtLeast(fenceLen).as<void>(null))
      .thenSkip(_optSpaces)
      .thenSkip(_newline | eof().map((_) => ''));

  final contentLine = closingFence.notFollowedBy
      .skipThen(_stripUpTo(indent))
      .skipThen(_restOfLine);

  return contentLine.many
      .thenSkip(closingFence | eof().map((_) => ''))
      .map((lines) => lines.isEmpty ? '' : '${lines.join('\n')}\n');
}

final Parser<ParseError, String> _indentedCodeLine = string(
  '    ',
).skipThen(_restOfLine);

final Parser<ParseError, String> _indentedBlankLine = _blankLine.map((_) => '');

final Parser<ParseError, MdNode> _indentedCodeBlock = _indentedCodeLine.flatMap(
  (first) => (_indentedCodeLine | _indentedBlankLine).many.map((rest) {
    final lines = [first, ...rest];
    final trimmed =
        lines.reversed.skipWhile((l) => l.isEmpty).toList().reversed.toList();
    final code = '${trimmed.join('\n')}\n';
    return MdCodeBlock(code);
  }),
);

final Parser<ParseError, MdNode> _htmlBlock = _indentGuard.skipThen(
  _htmlBlockBody,
);

final Parser<ParseError, MdNode> _htmlBlockBody =
    _htmlBlock1 |
    _htmlBlock2 |
    _htmlBlock3 |
    _htmlBlock4 |
    _htmlBlock5 |
    _htmlBlock6 |
    _htmlBlock7;

final Parser<ParseError, MdNode> _htmlBlock1 = _htmlBlockTypeParsed(
  char('<')
      .skipThen(
        stringIn([
          'pre',
          'script',
          'style',
          'textarea',
          'PRE',
          'SCRIPT',
          'STYLE',
          'TEXTAREA',
          'Pre',
          'Script',
          'Style',
          'Textarea',
        ]),
      )
      .thenSkip(
        satisfy((c) => c == ' ' || c == '\t' || c == '>' || c == '\n', 'end') |
            eof().map((_) => ''),
      ),
  string('</')
      .skipThen(
        stringIn([
          'pre',
          'script',
          'style',
          'textarea',
          'PRE',
          'SCRIPT',
          'STYLE',
          'TEXTAREA',
          'Pre',
          'Script',
          'Style',
          'Textarea',
        ]),
      )
      .thenSkip(char('>')),
);

final Parser<ParseError, MdNode> _htmlBlock2 = _htmlBlockTypeParsed(
  string('<!--'),
  string('-->'),
);

final Parser<ParseError, MdNode> _htmlBlock3 = _htmlBlockTypeParsed(
  string('<?'),
  string('?>'),
);

final Parser<ParseError, MdNode> _htmlBlock4 = _htmlBlockTypeParsed(
  string('<!').skipThen(
    satisfy((c) => c.compareTo('A') >= 0 && c.compareTo('Z') <= 0, 'upper'),
  ),
  char('>'),
);

final Parser<ParseError, MdNode> _htmlBlock5 = _htmlBlockTypeParsed(
  string('<![CDATA['),
  string(']]>'),
);

final Parser<ParseError, MdNode> _htmlBlock6 = _htmlBlock6Or7(true);

final Parser<ParseError, MdNode> _htmlBlock7 = _htmlBlock6Or7(false);

Parser<ParseError, MdNode> _htmlBlockTypeParsed(
  Parser<ParseError, Object?> start,
  Parser<ParseError, Object?> end,
) => _restOfLine.flatMap((firstLine) {
  if (start.run(firstLine) is Failure) {
    return failure<ParseError, MdNode>(
      CustomError('not html block', Location.zero),
    );
  }
  if (_lineContains(end, firstLine)) {
    return succeed<ParseError, MdNode>(MdHtmlBlock('$firstLine\n'));
  }
  return _htmlBlockLinesParsed(
    end,
  ).map((rest) => MdHtmlBlock('$firstLine\n${rest.join('\n')}\n'));
});

bool _lineContains(Parser<ParseError, Object?> pattern, String line) {
  final findPattern = (pattern.notFollowedBy.skipThen(
    anyChar(),
  )).many.skipThen(pattern);
  return findPattern.run(line) is! Failure;
}

Parser<ParseError, List<String>> _htmlBlockLinesParsed(
  Parser<ParseError, Object?> end,
) {
  final nonEndLine = _restOfLine.flatMap(
    (line) =>
        _lineContains(end, line)
            ? failure<ParseError, String>(CustomError('end', Location.zero))
            : succeed<ParseError, String>(line),
  );
  final endLine = _restOfLine.flatMap(
    (line) =>
        _lineContains(end, line)
            ? succeed<ParseError, String>(line)
            : failure<ParseError, String>(
              CustomError('not end', Location.zero),
            ),
  );
  return nonEndLine.many.flatMap(
    (before) =>
        endLine.map((last) => [...before, last]) |
        succeed<ParseError, List<String>>(before),
  );
}

const _blockTags = {
  'address',
  'article',
  'aside',
  'base',
  'basefont',
  'blockquote',
  'body',
  'caption',
  'center',
  'col',
  'colgroup',
  'dd',
  'details',
  'dialog',
  'dir',
  'div',
  'dl',
  'dt',
  'fieldset',
  'figcaption',
  'figure',
  'footer',
  'form',
  'frame',
  'frameset',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'head',
  'header',
  'hr',
  'html',
  'iframe',
  'legend',
  'li',
  'link',
  'main',
  'menu',
  'menuitem',
  'nav',
  'noframes',
  'ol',
  'optgroup',
  'option',
  'p',
  'param',
  'search',
  'section',
  'summary',
  'table',
  'tbody',
  'td',
  'tfoot',
  'th',
  'thead',
  'title',
  'tr',
  'track',
  'ul',
};

Parser<ParseError, MdNode> _htmlBlock6Or7(bool isType6) =>
    _restOfLine.flatMap((firstLine) {
      final trimmed = firstLine.trimLeft();
      final startParser = isType6 ? _htmlBlock6Start : _htmlBlock7Start;
      if (startParser.run(trimmed) is Failure) {
        return failure<ParseError, MdNode>(
          CustomError('not html block 6/7', Location.zero),
        );
      }
      return _nonBlankLine.many.map((rest) {
        final lines = [firstLine, ...rest];
        return MdHtmlBlock('${lines.join('\n')}\n') as MdNode;
      });
    });

final Parser<ParseError, String> _tagNameParser = satisfy(
  (c) =>
      (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
      (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0),
  'alpha',
).flatMap(
  (first) => satisfy(
    (c) =>
        (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
        (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
        (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
        c == '-',
    'tag char',
  ).many.capture.map((rest) => '$first$rest'),
);

final Parser<ParseError, void> _htmlBlock6Start = (char(
  '<',
).skipThen(char('/').optional).skipThen(_tagNameParser)).flatMap((tag) {
  if (!_blockTags.contains(tag.toLowerCase())) {
    return failure<ParseError, void>(
      CustomError('not block tag', Location.zero),
    );
  }
  return (satisfy((c) => c == ' ' || c == '\t' || c == '\n', 'ws') |
              char('>') |
              string('/>').map((_) => ''))
          .as<void>(null) |
      eof();
});

final Parser<ParseError, void> _htmlBlock7Start = () {
  final attrName = satisfy(
    (c) =>
        (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
        (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
        c == '_' ||
        c == ':',
    'attr start',
  ).skipThen(
    satisfy(
      (c) =>
          (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
          (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
          (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
          c == '_' ||
          c == ':' ||
          c == '.' ||
          c == '-',
      'attr char',
    ).many,
  );
  final unquoted =
      satisfy(
        (c) =>
            c != ' ' &&
            c != '\t' &&
            c != '\n' &&
            c != '"' &&
            c != "'" &&
            c != '=' &&
            c != '<' &&
            c != '>' &&
            c != '`',
        'unquoted',
      ).many1;
  final singleQuoted = char(
    "'",
  ).skipThen(satisfy((c) => c != "'", 'sq char').many).thenSkip(char("'"));
  final doubleQuoted = char(
    '"',
  ).skipThen(satisfy((c) => c != '"', 'dq char').many).thenSkip(char('"'));
  final attrValue = unquoted | singleQuoted | doubleQuoted;
  final attribute = satisfy((c) => c == ' ' || c == '\t' || c == '\n', 'ws')
      .many1
      .skipThen(attrName)
      .skipThen(
        (_optSpaces
            .skipThen(char('='))
            .skipThen(_optSpaces)
            .skipThen(attrValue)).optional,
      );
  final openTag = char('<').skipThen(_tagNameParser).flatMap((tag) {
    if (_blockTags.contains(tag.toLowerCase())) {
      return failure<ParseError, void>(CustomError('block tag', Location.zero));
    }
    return attribute.many
        .skipThen(_optSpaces)
        .skipThen(string('/>') | string('>'))
        .skipThen(_optSpaces)
        .thenSkip(eof());
  });
  final closeTag = string('</').skipThen(_tagNameParser).flatMap((tag) {
    if (_blockTags.contains(tag.toLowerCase())) {
      return failure<ParseError, void>(CustomError('block tag', Location.zero));
    }
    return _optSpaces.skipThen(char('>')).skipThen(_optSpaces).thenSkip(eof());
  });
  return openTag | closeTag;
}();

final Parser<ParseError, String> _nonBlankLine = _blankLine.notFollowedBy
    .skipThen(_restOfLine);

final Parser<ParseError, void> _lazyGuardBase = _blankLine.notFollowedBy
    .skipThen(_blockquoteLine.notFollowedBy)
    .skipThen(_thematicBreak.notFollowedBy)
    .skipThen(_atxHeading.notFollowedBy)
    .skipThen(_fencedCodeBlock.notFollowedBy)
    .skipThen(_htmlBlock.notFollowedBy);

final Parser<ParseError, String> _lazyCandidateLine = _lazyGuardBase
    .skipThen(_ulNonEmptyItem.notFollowedBy)
    .skipThen(_olStartingWith1.notFollowedBy)
    .skipThen(_restOfLine);

final Parser<ParseError, MdNode> _blockquote = _blockquoteLine.many1.flatMap(
  (lines) => _bqContinue(lines.join('\n'), false),
);

Parser<ParseError, MdNode> _bqContinue(String content, bool hasLazySetext) {
  final tryBqLine = _blockquoteLine.flatMap(
    (line) => _bqContinue('$content\n$line', hasLazySetext),
  );
  // Track if this lazy line is a setext underline (spec: setext
  // heading underline cannot be a lazy continuation line).
  final tryLazy = _lazyCandidateLine.flatMap((line) {
    if (_innerEndsWithParagraph(content)) {
      final lazySetext = hasLazySetext || _isSetextUnderline(line);
      return _bqContinue('$content\n$line', lazySetext);
    }
    return failure<ParseError, MdNode>(
      CustomError('lazy not valid', Location.zero),
    );
  });
  final done = succeed<ParseError, void>(null).map((_) {
    final inner =
        hasLazySetext
            ? _markdownInnerNoSetext(content)
            : _markdownInner(content);
    return MdBlockquote(inner.children) as MdNode;
  });
  return tryBqLine | tryLazy | done;
}

bool _innerEndsWithParagraph(String content) {
  final lastNewline = content.lastIndexOf('\n');
  final lastLine =
      lastNewline < 0 ? content : content.substring(lastNewline + 1);
  if (lastLine.trim().isEmpty) return false;
  final cached = _paragraphCache[content];
  if (cached != null) return cached;
  final result = _document.run('$content\n');
  final nodes = switch (result) {
    Success(:final value) => value,
    Partial(:final value) => value,
    Failure() => <MdNode>[],
  };
  final answer = nodes.isNotEmpty && _endsWithParagraph(nodes.last);
  _paragraphCache[content] = answer;
  return answer;
}

bool _endsWithParagraph(MdNode node) => switch (node) {
  MdParagraph() => true,
  MdBlockquote(:final children) when children.isNotEmpty => _endsWithParagraph(
    children.last,
  ),
  MdList(:final items) when items.isNotEmpty => _endsWithParagraph(items.last),
  MdListItem(:final children) when children.isNotEmpty => _endsWithParagraph(
    children.last,
  ),
  _ => false,
};

bool _isSetextUnderline(String line) {
  final input = line.endsWith('\n') ? line : '$line\n';
  return _setextUnderline.run(input) is! Failure;
}

MdDocument _markdownInnerNoSetext(String input) {
  final withNewline =
      input.isEmpty || input.endsWith('\n') ? input : '$input\n';
  final result = _documentNoSetext.run(withNewline);
  return switch (result) {
    Success(:final value) => MdDocument(value),
    Partial(:final value) => MdDocument(value),
    Failure() => const MdDocument([]),
  };
}

final Parser<ParseError, String> _blockquoteLine = _indentGuard.skipThen(
  char('>').skipThen(
    char(' ').optional.skipThen(_restOfLine) | _newline.map((_) => ''),
  ),
);

final Parser<ParseError, MdNode> _unorderedList = _ulListItemWithMarker.flatMap(
  (first) {
    final marker = first.$1;
    final nextItem = _blankLine.many1
        .as(true)
        .optional
        .flatMap(
          (hadBlanks) => _ulListItemForMarker(
            marker,
          ).map((content) => (hadBlanks ?? false, content)),
        );
    return nextItem.many.map((rest) {
      final contents = [first.$2, ...rest.map((r) => r.$2)];
      final hasBlankBetween = rest.any((r) => r.$1);
      final loose = hasBlankBetween || contents.any(_hasDirectBlankLine);
      final tight = !loose;
      return MdList(
            ordered: false,
            tight: tight,
            items:
                contents
                    .map(
                      (content) =>
                          MdListItem(_parseListItemContent(content, tight)),
                    )
                    .toList(),
          )
          as MdNode;
    });
  },
);

Parser<ParseError, String> _ulListItemForMarker(String marker) =>
    _thematicBreak.notFollowedBy.skipThen(
      _indentGuard.flatMap(
        (indent) => char(marker).skipThen(_ulMarkerAfter(indent)),
      ),
    );

final Parser<ParseError, (String, String)> _ulListItemWithMarker =
    _thematicBreak.notFollowedBy.skipThen(
      _indentGuard.flatMap(
        (indent) => satisfy(
          (c) => c == '-' || c == '+' || c == '*',
          'list marker',
        ).flatMap(
          (marker) =>
              _ulMarkerAfter(indent).map((content) => (marker, content)),
        ),
      ),
    );

Parser<ParseError, String> _ulMarkerAfter(int indent) =>
    satisfy((c) => c == ' ', 'space').many1.capture.flatMap(
      (spaces) => _restOfLine.flatMap((first) {
        final spacesAfter =
            (first.trim().isEmpty || spaces.length > 4) ? 1 : spaces.length;
        final contentIndent = indent + 1 + spacesAfter;
        final prefix = spaces.length > 4 ? ' ' * (spaces.length - 1) : '';
        return _listItemContWithLazy(contentIndent, '$prefix$first');
      }),
    ) |
    _newline.skipThen(
      _blankLine.notFollowedBy
          .skipThen(string(' ' * (indent + 2)).skipThen(_restOfLine))
          .many
          .map((lines) => lines.join('\n')),
    );

Parser<ParseError, String> _listItemContWithLazy(
  int contentIndent,
  String firstLine,
) => _listItemContinuation(contentIndent).flatMap((rest) {
  final content = rest.isEmpty ? firstLine : '$firstLine\n${rest.join('\n')}';
  return _extendWithLazyThenCont(content, contentIndent);
});

Parser<ParseError, String> _extendWithLazyThenCont(
  String content,
  int contentIndent,
) {
  if (!_innerEndsWithParagraph(content)) {
    return succeed<ParseError, String>(content);
  }
  return _listLazyCandidateLine.flatMap((line) {
        final extended = '$content\n$line';
        return _listItemContinuation(contentIndent).flatMap((more) {
          final full =
              more.isEmpty ? extended : '$extended\n${more.join('\n')}';
          return _extendWithLazyThenCont(full, contentIndent);
        });
      }) |
      succeed<ParseError, String>(content);
}

/// A lazy continuation candidate for list items: same as blockquote lazy
/// but also rejects ALL list item markers (not just those that interrupt
/// paragraphs), since within a list, any marker ends the current item.
final Parser<ParseError, String> _listLazyCandidateLine = _lazyGuardBase
    .skipThen(_ulListItemWithMarker.notFollowedBy)
    .skipThen(_olListItemWithDelim.notFollowedBy)
    .skipThen(_restOfLine);

final Parser<ParseError, MdNode> _orderedList = _olListItemWithDelim.flatMap((
  first,
) {
  final delim = first.$1;
  final nextItem = _blankLine.many1
      .as(true)
      .optional
      .flatMap(
        (hadBlanks) => _olListItemForDelim(
          delim,
        ).map((item) => (hadBlanks ?? false, item)),
      );
  return nextItem.many.map((rest) {
    final allItems = [(first.$2, first.$3), ...rest.map((r) => r.$2)];
    final contents = allItems.map((i) => i.$2).toList();
    final hasBlankBetween = rest.any((r) => r.$1);
    final loose = hasBlankBetween || contents.any(_hasDirectBlankLine);
    final tight = !loose;
    final start = allItems.first.$1;
    return MdList(
          ordered: true,
          start: start != 1 ? start : null,
          tight: tight,
          items:
              allItems
                  .map(
                    (item) => MdListItem(_parseListItemContent(item.$2, tight)),
                  )
                  .toList(),
        )
        as MdNode;
  });
});

final Parser<ParseError, (String, int, String)> _olListItemWithDelim =
    _indentGuard.flatMap(_olMarkerLineWithDelim);

Parser<ParseError, String> _olItemContent(int indent, int markerLen) =>
    (satisfy((c) => c == ' ', 'space').many1.capture.flatMap(
      (spaces) => _restOfLine.flatMap((first) {
        final spacesAfter =
            (first.trim().isEmpty || spaces.length > 4) ? 1 : spaces.length;
        final contentIndent = indent + markerLen + spacesAfter;
        final prefix = spaces.length > 4 ? ' ' * (spaces.length - 1) : '';
        return _listItemContWithLazy(contentIndent, '$prefix$first');
      }),
    )) |
    _newline.skipThen(
      _listItemContinuation(
        indent + markerLen + 1,
      ).map((lines) => lines.join('\n')),
    );

Parser<ParseError, (String, int, String)> _olMarkerLineWithDelim(int indent) =>
    digit().many1.capture.flatMap((digits) {
      if (digits.length > 9) {
        return failure<ParseError, (String, int, String)>(
          CustomError('too many digits', Location.zero),
        );
      }
      final num = int.parse(digits);
      final markerLen = digits.length + 1;
      return satisfy((c) => c == '.' || c == ')', 'list delimiter').flatMap(
        (delim) =>
            _olItemContent(indent, markerLen).map((c) => (delim, num, c)),
      );
    });

Parser<ParseError, (int, String)> _olListItemForDelim(String delim) =>
    _indentGuard.flatMap(
      (indent) => digit().many1.capture.flatMap((digits) {
        if (digits.length > 9) {
          return failure<ParseError, (int, String)>(
            CustomError('too many digits', Location.zero),
          );
        }
        final num = int.parse(digits);
        final markerLen = digits.length + 1;
        return char(
          delim,
        ).skipThen(_olItemContent(indent, markerLen).map((c) => (num, c)));
      }),
    );

Parser<ParseError, List<String>> _listItemContinuation(int indent) {
  final indentStr = ' ' * indent;
  final contentLine = _blankLine.notFollowedBy.skipThen(
    string(indentStr).skipThen(_restOfLine),
  );
  final blankThenContent = _blankLine.many1
      .thenSkip(string(indentStr).lookAhead)
      .map((blanks) => List.filled(blanks.length, ''));

  return (blankThenContent | contentLine.map((l) => [l])).many.map(
    (groups) => groups.expand((g) => g).toList(),
  );
}

List<MdNode> _parseListItemContent(String content, bool tight) {
  if (content.trim().isEmpty) return const [];
  if (tight) {
    final parsed = _markdownInner(content);
    final result = <MdNode>[];
    final children = parsed.children;
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      if (child is MdParagraph) {
        result.addAll(child.children);
        if (i + 1 < children.length) {
          result.add(const MdSoftBreak());
        }
      } else {
        result.add(child);
        if (i + 1 < children.length && children[i + 1] is MdParagraph) {
          result.add(const MdSoftBreak());
        }
      }
    }
    return result;
  } else {
    final parsed = _markdownInner(content);
    return parsed.children;
  }
}

bool _hasDirectBlankLine(String content) {
  final lines = content.split('\n');
  var inFence = false;
  String? fenceChar;
  var fenceLen = 0;
  var subListIndent = -1; // -1 = not in sub-list
  var prevBlank = false;
  var seenNonBlank = false;

  for (final line in lines) {
    final trimmed = line.trimRight();
    final isBlank = trimmed.isEmpty;

    if (inFence) {
      final closeResult = _fenceCloseLine(fenceChar!, fenceLen).run('$line\n');
      if (closeResult is! Failure) {
        inFence = false;
        seenNonBlank = true;
        prevBlank = false;
      }
      continue;
    }

    if (!isBlank) {
      final fenceResult = _fenceOpenLine.run('$line\n');
      if (fenceResult case Success(:final value) || Partial(:final value)) {
        if (prevBlank && seenNonBlank) return true;
        fenceChar = value.$1;
        fenceLen = value.$2;
        inFence = true;
        seenNonBlank = true;
        prevBlank = false;
        continue;
      }
    }

    if (!isBlank && subListIndent < 0) {
      final listResult = _ulListItemWithMarker.run('$line\n');
      final olResult = _olListItemWithDelim.run('$line\n');
      if (listResult is! Failure || olResult is! Failure) {
        if (prevBlank && seenNonBlank) return true;
        final indent = line.length - line.trimLeft().length;
        subListIndent = indent;
        seenNonBlank = true;
        prevBlank = false;
        continue;
      }
    }

    if (subListIndent >= 0) {
      if (isBlank) {
        prevBlank = true;
        continue;
      }
      final indent = line.length - line.trimLeft().length;
      if (indent > subListIndent) {
        prevBlank = false;
        continue;
      }
      final listResult = _ulListItemWithMarker.run('$line\n');
      final olResult = _olListItemWithDelim.run('$line\n');
      if ((listResult is! Failure || olResult is! Failure) &&
          indent == subListIndent) {
        prevBlank = false;
        continue;
      }
      subListIndent = -1;
      seenNonBlank = true;
    }

    if (isBlank) {
      if (seenNonBlank) {
        prevBlank = true;
      }
      continue;
    }

    if (prevBlank && seenNonBlank) {
      return true;
    }
    prevBlank = false;
    seenNonBlank = true;
  }
  return false;
}

final Parser<ParseError, (String, int)> _fenceOpenLine = _indentGuard.skipThen(
  () {
    final backtick = char('`').manyAtLeast(3).capture;
    final tilde = char('~').manyAtLeast(3).capture;
    return (backtick | tilde).flatMap(
      (fence) => _restOfLine.map((_) => (fence[0], fence.length)),
    );
  }(),
);

Parser<ParseError, void> _fenceCloseLine(String fenceChar, int fenceLen) =>
    _indentGuard
        .skipThen(char(fenceChar).manyAtLeast(fenceLen).as<void>(null))
        .thenSkip(_optSpaces)
        .thenSkip(_newline | eof().map((_) => ''));

final Parser<ParseError, MdNode> _linkRefDef = _indentGuard.skipThen(
  _linkRefDefBody,
);

final Parser<ParseError, MdNode> _linkRefDefBody = () {
  final labelChar =
      (char('\\')
          .skipThen(satisfy((c) => _asciiPunctuation.contains(c), 'escaped'))
          .map((c) => '\\$c')) |
      satisfy((c) => c != ']' && c != '[' && c != '\\', 'label char');
  final label = char('[')
      .skipThen(labelChar.many1.capture)
      .thenSkip(string(']:'))
      .flatMap(
        (text) =>
            text.trim().isEmpty
                ? failure<ParseError, String>(
                  CustomError('blank label', Location.zero),
                )
                : succeed<ParseError, String>(text),
      );

  final linkWs = satisfy((c) => c == ' ' || c == '\t', 'ws').many
      .skipThen(
        (_newline.skipThen(
          satisfy((c) => c == ' ' || c == '\t', 'ws').many,
        )).optional,
      )
      .as<void>(null);

  final angleDest = char('<')
      .skipThen(
        (char('\\').skipThen(anyChar()) |
                satisfy((c) => c != '>' && c != '\n' && c != '\\', 'dest char'))
            .many
            .capture,
      )
      .thenSkip(char('>'));
  final bareDest =
      satisfy(
        (c) => c != ' ' && c != '\n' && c != '\t',
        'dest char',
      ).many1.capture;
  final dest = angleDest | bareDest;

  final titleOnLine = satisfy(
    (c) => c == ' ' || c == '\t',
    'ws',
  ).many1.skipThen(_linkTitle);
  final titleNextLine = _optSpaces
      .skipThen(_newline)
      .skipThen(satisfy((c) => c == ' ' || c == '\t', 'ws').many)
      .skipThen(_linkTitle);
  final withTitle = (titleOnLine | titleNextLine)
      .thenSkip(_optSpaces)
      .thenSkip(_newline | eof().map((_) => ''))
      .map<String?>((t) => t);
  final withoutTitle = _optSpaces
      .skipThen(_newline | eof().map((_) => ''))
      .as<String?>(null);

  return label.flatMap(
    (labelText) => linkWs
        .skipThen(dest)
        .flatMap(
          (destText) => (withTitle | withoutTitle).map((t) {
            final normalized = _collapseWhitespace(_caseFold(labelText)).trim();
            _linkRefs.putIfAbsent(
              normalized,
              () => (
                _processUrl(destText),
                t != null ? _processTitle(t) : null,
              ),
            );
            return const MdDocument([]) as MdNode;
          }),
        ),
  );
}();

final Parser<ParseError, String> _linkTitle = () {
  Parser<ParseError, String> quoted(String q) {
    final escaped = char('\\').skipThen(anyChar());
    final blankLineGuard = string('\n\n').notFollowedBy;
    final plain = blankLineGuard.skipThen(
      satisfy((c) => c != q && c != '\\', 'title char'),
    );
    return char(q).skipThen((escaped | plain).many.capture).thenSkip(char(q));
  }

  final parenEscaped = char('\\').skipThen(anyChar());
  final parenBlankGuard = string('\n\n').notFollowedBy;
  final parenPlain = parenBlankGuard.skipThen(
    satisfy((c) => c != ')' && c != '\\', 'title char'),
  );
  return quoted('"') |
      quoted("'") |
      char(
        '(',
      ).skipThen((parenEscaped | parenPlain).many.capture).thenSkip(char(')'));
}();

final Parser<ParseError, MdNode> _paragraph = _paragraphFirstLine.flatMap(
  (first) => _paragraphContLine.many.map((rest) {
    final content =
        rest.isEmpty
            ? first.trimRight()
            : '$first\n${rest.join('\n')}'.trimRight();
    return MdParagraph(_parseInline(content)) as MdNode;
  }),
);

final Parser<ParseError, String> _paragraphFirstLine = _blankLine.notFollowedBy
    .skipThen(_thematicBreak.notFollowedBy)
    .skipThen(_atxHeading.notFollowedBy)
    .skipThen(_fencedCodeBlock.notFollowedBy)
    .skipThen(_htmlBlock.notFollowedBy)
    .skipThen(_blockquoteLine.notFollowedBy)
    .skipThen(_ulListItemWithMarker.notFollowedBy)
    .skipThen(_olListItemWithDelim.notFollowedBy)
    .skipThen(_indentGuard.skipThen(_restOfLine));

final Parser<ParseError, void> _olStartingWith1 = _indentGuard.skipThen(
  char('1')
      .skipThen(satisfy((c) => c == '.' || c == ')', 'delim'))
      .skipThen(char(' '))
      .as<void>(null),
);

final Parser<ParseError, MdNode> _htmlBlockInterrupting = _indentGuard.skipThen(
  _htmlBlock1 |
      _htmlBlock2 |
      _htmlBlock3 |
      _htmlBlock4 |
      _htmlBlock5 |
      _htmlBlock6,
);

/// A non-empty UL item (marker + space + content). Empty items can't
/// interrupt paragraphs.
final Parser<ParseError, void> _ulNonEmptyItem = _thematicBreak.notFollowedBy
    .skipThen(_indentGuard)
    .skipThen(
      satisfy(
        (c) => c == '-' || c == '+' || c == '*',
        'marker',
      ).skipThen(char(' ')).as<void>(null),
    );

final Parser<ParseError, String> _paragraphContLine = _blankLine.notFollowedBy
    .skipThen(_thematicBreak.notFollowedBy)
    .skipThen(_atxHeading.notFollowedBy)
    .skipThen(_fencedCodeBlock.notFollowedBy)
    // Type 7 HTML blocks cannot interrupt a paragraph (spec §4.6)
    .skipThen(_htmlBlockInterrupting.notFollowedBy)
    .skipThen(_blockquoteLine.notFollowedBy)
    // Empty UL items (marker + newline) can't interrupt paragraphs
    .skipThen(_ulNonEmptyItem.notFollowedBy)
    // Only OL starting with 1 interrupts a paragraph (spec §5.3)
    .skipThen(_olStartingWith1.notFollowedBy)
    .skipThen(_restOfLine);

List<MdNode> _parseInline(String text) {
  if (text.isEmpty) return const [];
  final result = _inlineTokens.run(text);
  final tokens = switch (result) {
    Success(:final value) => value,
    Partial(:final value) => value,
    Failure() => <_Token>[],
  };
  _classifyDelimiters(tokens);
  final nodes = _processEmphasis(tokens);
  return _mergeTextNodes(nodes);
}

sealed class _Token {}

final class _TextToken extends _Token {
  final String text;
  _TextToken(this.text);
}

final class _NodeToken extends _Token {
  final MdNode node;
  final String firstChar;
  final String lastChar;
  _NodeToken(this.node, {this.firstChar = '', this.lastChar = ''});
}

final class _DelimToken extends _Token {
  final String ch;
  int count;
  bool canOpen;
  bool canClose;
  bool active;
  _DelimToken(
    this.ch,
    this.count, {
    required this.canOpen,
    required this.canClose,
  }) : active = true;
}

final class _SoftBreakToken extends _Token {}

final class _HardBreakToken extends _Token {}

final Parser<ParseError, List<_Token>> _inlineTokens = _inlineToken.many;

final Parser<ParseError, _Token> _inlineToken =
    _iCodeSpanOrLiteral |
    _iBackslashEscape |
    _iAutolink |
    _iRawHtmlInline |
    _iEntity |
    _iDelimRun |
    _iImage |
    _iLink |
    _iHardBreak |
    _iSoftBreak |
    _iPlainText;

final Parser<ParseError, _Token> _iCodeSpanOrLiteral =
    _iCodeSpan |
    char('`').many1.capture.map((ticks) => _TextToken(ticks) as _Token);

final Parser<ParseError, _Token> _iCodeSpan = char('`').many1.capture.flatMap((
  open,
) {
  final n = open.length;
  final backtickRun = char('`').many1.capture;
  final nonBacktick = satisfy((c) => c != '`', 'non-backtick').many1.capture;
  final segment =
      nonBacktick |
      backtickRun.flatMap((run) {
        if (run.length == n) {
          return failure<ParseError, String>(
            CustomError('close', Location.zero),
          );
        }
        return succeed<ParseError, String>(run);
      });
  return segment.many.capture
      .thenSkip(string('`' * n))
      .thenSkip(char('`').notFollowedBy)
      .map((raw) {
        var content = raw.replaceAll('\n', ' ');
        if (content.length >= 2 &&
            content.startsWith(' ') &&
            content.endsWith(' ') &&
            content.trim().isNotEmpty) {
          content = content.substring(1, content.length - 1);
        }
        return _NodeToken(MdCode(content), firstChar: '`', lastChar: '`')
            as _Token;
      });
});

const _asciiPunctuation =
    r'!"#$%&'
    "'"
    r'()*+,-./:;<=>?@[\]^_`{|}~';

final Parser<ParseError, _Token> _iBackslashEscape = char('\\').skipThen(
  char('\n').map((_) => _HardBreakToken() as _Token) |
      satisfy(
        (c) => _asciiPunctuation.contains(c),
        'punctuation',
      ).map((c) => _TextToken(c) as _Token) |
      succeed<ParseError, _Token>(_TextToken('\\')),
);

final Parser<ParseError, _Token> _iAutolink = char(
  '<',
).skipThen(_iUriAutolink | _iEmailAutolink);

final Parser<ParseError, _Token> _iUriAutolink = satisfy(
  (c) =>
      (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
      (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0),
  'scheme start',
).flatMap((first) {
  final schemeRest =
      satisfy(
        (c) =>
            (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
            (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
            (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
            c == '+' ||
            c == '.' ||
            c == '-',
        'scheme char',
      ).manyAtLeast(1).capture;
  return schemeRest.thenSkip(char(':')).flatMap((rest) {
    if (rest.length > 31) {
      return failure<ParseError, _Token>(
        CustomError('scheme too long', Location.zero),
      );
    }
    final scheme = '$first$rest:';
    return satisfy(
      (c) => c != '>' && c != ' ' && c != '\n' && c != '<',
      'uri char',
    ).many.capture.thenSkip(char('>')).map((uri) {
      final href = '$scheme$uri';
      return _NodeToken(
            MdLink(href: _percentEncodeUrl(href), children: [MdText(href)]),
            firstChar: '<',
            lastChar: '>',
          )
          as _Token;
    });
  });
});

final Parser<ParseError, _Token> _iEmailAutolink = () {
  final localChar = satisfy(
    (c) =>
        (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
        (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
        (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
        '.!#\$%&\'*+/=?^_`{|}~-'.contains(c),
    'email local',
  );
  final domainChar = satisfy(
    (c) =>
        (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
        (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
        (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
        c == '-' ||
        c == '.',
    'domain char',
  );
  return localChar.many1.capture
      .thenSkip(char('@'))
      .zip(domainChar.many1.capture)
      .thenSkip(char('>'))
      .map((pair) {
        final email = '${pair.$1}@${pair.$2}';
        return _NodeToken(
              MdLink(href: 'mailto:$email', children: [MdText(email)]),
              firstChar: '<',
              lastChar: '>',
            )
            as _Token;
      });
}();

final Parser<ParseError, _Token> _iRawHtmlInline = char('<').skipThen(
  _iHtmlComment |
      _iHtmlPI |
      _iHtmlCDATA |
      _iHtmlDecl |
      _iHtmlCloseTag |
      _iHtmlOpenTag,
);

final Parser<ParseError, _Token> _iHtmlComment = string('!--').skipThen(
  char('>').map(
        (_) =>
            _NodeToken(
                  const MdHtmlInline('<!-->'),
                  firstChar: '<',
                  lastChar: '>',
                )
                as _Token,
      ) |
      string('->').map(
        (_) =>
            _NodeToken(
                  const MdHtmlInline('<!--->'),
                  firstChar: '<',
                  lastChar: '>',
                )
                as _Token,
      ) |
      (string('-->').notFollowedBy
          .skipThen(anyChar())
          .many
          .capture
          .thenSkip(string('-->'))
          .map(
            (c) =>
                _NodeToken(
                      MdHtmlInline('<!--$c-->'),
                      firstChar: '<',
                      lastChar: '>',
                    )
                    as _Token,
          )),
);

final Parser<ParseError, _Token> _iHtmlPI = char('?')
    .skipThen(string('?>').notFollowedBy.skipThen(anyChar()).many.capture)
    .thenSkip(string('?>'))
    .map(
      (c) =>
          _NodeToken(MdHtmlInline('<?$c?>'), firstChar: '<', lastChar: '>')
              as _Token,
    );

final Parser<ParseError, _Token> _iHtmlCDATA = string('![CDATA[')
    .skipThen(string(']]>').notFollowedBy.skipThen(anyChar()).many.capture)
    .thenSkip(string(']]>'))
    .map(
      (c) =>
          _NodeToken(
                MdHtmlInline('<![CDATA[$c]]>'),
                firstChar: '<',
                lastChar: '>',
              )
              as _Token,
    );

final Parser<ParseError, _Token> _iHtmlDecl = char('!')
    .skipThen(
      satisfy(
        (c) => c.compareTo('A') >= 0 && c.compareTo('Z') <= 0,
        'upper',
      ).many1.capture,
    )
    .flatMap(
      (tag) => satisfy((c) => c == ' ' || c == '\t' || c == '\n', 'ws')
          .skipThen(satisfy((c) => c != '>', 'decl char').many.capture)
          .thenSkip(char('>'))
          .map(
            (content) =>
                _NodeToken(
                      MdHtmlInline('<!$tag $content>'),
                      firstChar: '<',
                      lastChar: '>',
                    )
                    as _Token,
          ),
    );

final Parser<ParseError, _Token> _iHtmlCloseTag = char('/')
    .skipThen(_htmlTagName)
    .flatMap(
      (tag) => satisfy((c) => c == ' ' || c == '\t' || c == '\n', 'ws')
          .many
          .capture
          .thenSkip(char('>'))
          .map(
            (ws) =>
                _NodeToken(
                      MdHtmlInline('</$tag$ws>'),
                      firstChar: '<',
                      lastChar: '>',
                    )
                    as _Token,
          ),
    );

final Parser<ParseError, _Token> _iHtmlOpenTag = _htmlTagName.flatMap(
  (tag) => _htmlAttrs.flatMap(
    (attrs) => satisfy(
      (c) => c == ' ' || c == '\t' || c == '\n',
      'ws',
    ).many.capture.flatMap((ws) {
      final selfClose =
          string('/>').map((_) => '/>') | char('>').map((_) => '>');
      return selfClose.map(
        (close) =>
            _NodeToken(
                  MdHtmlInline('<$tag$attrs$ws$close'),
                  firstChar: '<',
                  lastChar: '>',
                )
                as _Token,
      );
    }),
  ),
);

final Parser<ParseError, String> _htmlTagName = satisfy(
  (c) =>
      (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
      (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0),
  'tag start',
).flatMap(
  (first) => satisfy(
    (c) =>
        (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
        (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
        (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
        c == '-',
    'tag char',
  ).many.capture.map((rest) => '$first$rest'),
);

final Parser<ParseError, String> _htmlAttrs = _htmlAttr.many.map(
  (attrs) => attrs.join(),
);

final Parser<ParseError, String> _htmlAttr = satisfy(
  (c) => c == ' ' || c == '\t' || c == '\n',
  'ws',
).many1.capture.flatMap((ws) {
  final attrName = satisfy(
    (c) =>
        (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
        (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
        c == '_' ||
        c == ':',
    'attr start',
  ).flatMap(
    (first) => satisfy(
      (c) =>
          (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
          (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
          (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
          c == '_' ||
          c == '.' ||
          c == ':' ||
          c == '-',
      'attr char',
    ).many.capture.map((rest) => '$first$rest'),
  );

  final attrValue = satisfy(
    (c) => c == ' ' || c == '\t' || c == '\n',
    'ws',
  ).many.capture.flatMap(
    (ws2) => char('=').flatMap(
      (_) => satisfy((c) => c == ' ' || c == '\t' || c == '\n', 'ws')
          .many
          .capture
          .flatMap((ws3) => _htmlAttrValue.map((val) => '$ws2=$ws3$val')),
    ),
  );

  return attrName.flatMap(
    (name) =>
        attrValue.map((val) => '$ws$name$val') |
        succeed<ParseError, String>('$ws$name'),
  );
});

final Parser<ParseError, String> _htmlAttrValue =
    (char('"')
        .skipThen(satisfy((c) => c != '"', 'dq char').many.capture)
        .thenSkip(char('"'))
        .map((v) => '"$v"')) |
    (char("'")
        .skipThen(satisfy((c) => c != "'", 'sq char').many.capture)
        .thenSkip(char("'"))
        .map((v) => "'$v'")) |
    satisfy(
      (c) =>
          c != '"' &&
          c != "'" &&
          c != '=' &&
          c != '<' &&
          c != '>' &&
          c != '`' &&
          c != ' ' &&
          c != '\t' &&
          c != '\n',
      'unquoted',
    ).many1.capture;

final Parser<ParseError, _Token> _iEntity = char(
  '&',
).skipThen(_iNamedEntity | _iHexEntity | _iDecEntity);

final Parser<ParseError, _Token> _iNamedEntity = satisfy(
  (c) =>
      (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
      (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0),
  'entity start',
).flatMap(
  (first) => satisfy(
    (c) =>
        (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
        (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
        (c.compareTo('0') >= 0 && c.compareTo('9') <= 0),
    'entity char',
  ).many.capture.thenSkip(char(';')).flatMap((rest) {
    final name = '$first$rest';
    final decoded = _htmlEntities[name];
    if (decoded != null) {
      return succeed<ParseError, _Token>(_TextToken(decoded));
    }
    return failure<ParseError, _Token>(
      CustomError('unknown entity: $name', Location.zero),
    );
  }),
);

final Parser<ParseError, _Token> _iDecEntity = char('#')
    .skipThen(digit().manyAtLeast(1).capture)
    .thenSkip(char(';'))
    .flatMap((digits) {
      if (digits.length > 7) {
        return failure<ParseError, _Token>(
          CustomError('too many digits', Location.zero),
        );
      }
      final code = int.parse(digits);
      if (code == 0 || code > 0x10FFFF) {
        return succeed<ParseError, _Token>(_TextToken('\u{FFFD}'));
      }
      return succeed<ParseError, _Token>(_TextToken(String.fromCharCode(code)));
    });

final Parser<ParseError, _Token> _iHexEntity = char('#')
    .skipThen(oneOf('xX'))
    .skipThen(
      satisfy(
        (c) =>
            (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
            (c.compareTo('a') >= 0 && c.compareTo('f') <= 0) ||
            (c.compareTo('A') >= 0 && c.compareTo('F') <= 0),
        'hex digit',
      ).manyAtLeast(1).capture,
    )
    .thenSkip(char(';'))
    .map((digits) {
      if (digits.length > 6) return _TextToken('\u{FFFD}') as _Token;
      final code = int.parse(digits, radix: 16);
      if (code == 0) return _TextToken('\u{FFFD}') as _Token;
      return _TextToken(String.fromCharCode(code)) as _Token;
    });

final Parser<ParseError, _Token> _iDelimRun = satisfy(
  (c) => c == '*' || c == '_',
  'delim',
).flatMap(
  (ch) => char(ch).many.capture.map((rest) {
    final count = 1 + rest.length;
    return _DelimToken(ch, count, canOpen: false, canClose: false) as _Token;
  }),
);

final Parser<ParseError, _Token> _iImage = string('![')
    .skipThen(_bracketContent)
    .thenSkip(char(']'))
    .flatMap(
      (label) =>
          _inlineDest.map(
            (dest) =>
                _NodeToken(
                      MdImage(
                        src: dest.$1,
                        alt: _extractPlainText(label),
                        title: dest.$2,
                      ),
                      firstChar: '!',
                      lastChar: ')',
                    )
                    as _Token,
          ) |
          _refDest(label).map(
            (dest) =>
                _NodeToken(
                      MdImage(
                        src: dest.$1,
                        alt: _extractPlainText(label),
                        title: dest.$2,
                      ),
                      firstChar: '!',
                      lastChar: ']',
                    )
                    as _Token,
          ),
    );

final Parser<ParseError, _Token> _iLink = char(
  '[',
).skipThen(_bracketContent).thenSkip(char(']')).flatMap((label) {
  final children = _parseInline(label);
  if (_containsLink(children)) {
    return failure<ParseError, _Token>(
      CustomError('nested link', Location.zero),
    );
  }
  return _inlineDest.map(
        (dest) =>
            _NodeToken(
                  MdLink(href: dest.$1, title: dest.$2, children: children),
                  firstChar: '[',
                  lastChar: ')',
                )
                as _Token,
      ) |
      _refDest(label).map(
        (dest) =>
            _NodeToken(
                  MdLink(href: dest.$1, title: dest.$2, children: children),
                  firstChar: '[',
                  lastChar: ']',
                )
                as _Token,
      );
});

final Parser<ParseError, String> _bracketContent = () {
  final escaped = char('\\').skipThen(anyChar()).map((c) => '\\$c');
  final nested = char('[')
      .skipThen(defer(() => _bracketContent))
      .thenSkip(char(']'))
      .map((inner) => '[$inner]');
  final codeSpan = char('`').many1.capture.flatMap((open) {
    final n = open.length;
    final close = string('`' * n).thenSkip(char('`').notFollowedBy);
    final segment =
        satisfy((c) => c != '`', 'non-bt').many1.capture |
        char('`').many1.capture.flatMap(
          (run) =>
              run.length == n
                  ? failure<ParseError, String>(
                    CustomError('close', Location.zero),
                  )
                  : succeed<ParseError, String>(run),
        );
    return segment.many.capture.thenSkip(close).map((c) => '$open$c$open');
  });
  final htmlTag = char('<')
      .skipThen(satisfy((c) => c != '>', 'tag char').many1.capture)
      .thenSkip(char('>'))
      .map((c) => '<$c>');
  final plain = satisfy(
    (c) => c != '[' && c != ']' && c != '\\' && c != '`' && c != '<',
    'bracket content',
  );
  return (escaped | codeSpan | htmlTag | nested | plain).many.capture;
}();

final Parser<ParseError, (String, String?)> _inlineDest = char('(')
    .skipThen(_inlineWs)
    .skipThen(_linkDest)
    .flatMap(
      (dest) => _inlineWs
          .skipThen(_inlineLinkTitle.optional)
          .thenSkip(_inlineWs)
          .thenSkip(char(')'))
          .map(
            (title) => (
              _processUrl(dest),
              title != null ? _processTitle(title) : null,
            ),
          ),
    );

final Parser<ParseError, void> _inlineWs = satisfy(
  (c) => c == ' ' || c == '\t' || c == '\n',
  'ws',
).many.as<void>(null);

final Parser<ParseError, String> _linkDest =
    (char('<')
        .skipThen(
          (char('\\').skipThen(anyChar()) |
                  satisfy(
                    (c) => c != '>' && c != '\n' && c != '<' && c != '\\',
                    'dest char',
                  ))
              .many
              .capture,
        )
        .thenSkip(char('>'))) |
    _bareLinkDest;

final Parser<ParseError, String> _bareLinkDest = () {
  final escaped = char('\\')
      .skipThen(satisfy((c) => _asciiPunctuation.contains(c), 'esc'))
      .map((c) => '\\$c');
  final parenGroup = char('(')
      .skipThen(defer(() => _bareLinkDest))
      .thenSkip(char(')'))
      .map((inner) => '($inner)');
  final bareBackslash = char('\\')
      .thenSkip(
        satisfy((c) => _asciiPunctuation.contains(c), 'punct').notFollowedBy,
      )
      .map((_) => '\\');
  final plain = satisfy(
    (c) =>
        c != '(' &&
        c != ')' &&
        c != ' ' &&
        c != '\t' &&
        c != '\n' &&
        c != '\\' &&
        c != '<',
    'dest char',
  ).map((c) => c);
  return (escaped | parenGroup | bareBackslash | plain).many.capture;
}();

final Parser<ParseError, String> _inlineLinkTitle =
    (char('"')
        .skipThen(
          (char('\\').skipThen(anyChar()) | satisfy((c) => c != '"', 'tq'))
              .many
              .capture,
        )
        .thenSkip(char('"'))) |
    (char("'")
        .skipThen(
          (char('\\').skipThen(anyChar()) | satisfy((c) => c != "'", 'tq'))
              .many
              .capture,
        )
        .thenSkip(char("'"))) |
    (char('(')
        .skipThen(
          (char('\\').skipThen(anyChar()) | satisfy((c) => c != ')', 'tq'))
              .many
              .capture,
        )
        .thenSkip(char(')')));

bool _containsLink(List<MdNode> nodes) {
  for (final node in nodes) {
    if (node is MdLink) return true;
    if (node is MdEmphasis && _containsLink(node.children)) return true;
    if (node is MdStrong && _containsLink(node.children)) return true;
  }
  return false;
}

Parser<ParseError, (String, String?)> _refDest(String label) {
  final explicit = char('[')
      .skipThen(satisfy((c) => c != ']', 'ref char').many.capture)
      .thenSkip(char(']'))
      .flatMap((ref) {
        final refLabel = ref.isEmpty ? label : ref;
        final normalized = _collapseWhitespace(_caseFold(refLabel)).trim();
        final entry = _linkRefs[normalized];
        if (entry == null) {
          return failure<ParseError, (String, String?)>(
            CustomError('ref not found', Location.zero),
          );
        }
        return succeed<ParseError, (String, String?)>(entry);
      });

  // Shortcut: just [label] — not followed by [ (per spec §6.6).
  final shortcut = char('[').notFollowedBy.flatMap((_) {
    final normalized = _collapseWhitespace(_caseFold(label)).trim();
    final entry = _linkRefs[normalized];
    if (entry == null) {
      return failure<ParseError, (String, String?)>(
        CustomError('ref not found', Location.zero),
      );
    }
    return succeed<ParseError, (String, String?)>(entry);
  });

  return explicit | shortcut;
}

String _collapseWhitespace(String s) {
  final buf = StringBuffer();
  var prevWs = false;
  for (final r in s.runes) {
    if (r == 0x20 || r == 0x09 || r == 0x0A || r == 0x0D || r == 0x0C) {
      if (!prevWs) {
        buf.write(' ');
        prevWs = true;
      }
    } else {
      buf.writeCharCode(r);
      prevWs = false;
    }
  }
  return buf.toString();
}

final Parser<ParseError, _Token> _iHardBreak = string('  ')
    .skipThen(satisfy((c) => c == ' ', 'space').many)
    .thenSkip(char('\n'))
    .map((_) => _HardBreakToken() as _Token);

final Parser<ParseError, _Token> _iSoftBreak = char(
  '\n',
).map((_) => _SoftBreakToken() as _Token);

final Parser<ParseError, _Token> _iPlainText = satisfy(
  (c) => true,
  'any',
).map((c) => _TextToken(c) as _Token);

String _extractPlainText(String text) {
  final nodes = _parseInline(text);
  return _collectText(nodes);
}

String _collectText(List<MdNode> nodes) {
  final buf = StringBuffer();
  for (final node in nodes) {
    switch (node) {
      case MdText(:final text):
        buf.write(text);
      case MdHardBreak():
        buf.write('\n');
      case MdSoftBreak():
        buf.write('\n');
      case MdImage(:final alt):
        buf.write(alt);
      case MdEmphasis(:final children):
        buf.write(_collectText(children));
      case MdStrong(:final children):
        buf.write(_collectText(children));
      case MdLink(:final children):
        buf.write(_collectText(children));
      case MdCode(:final code):
        buf.write(code);
      case MdHtmlInline(:final html):
        buf.write(html);
      case MdDocument(:final children):
        buf.write(_collectText(children));
      default:
        break;
    }
  }
  return buf.toString();
}

final Parser<ParseError, String> _backslashEscapeResolver = (char(
          '\\',
        ).skipThen(satisfy((c) => _asciiPunctuation.contains(c), 'esc')) |
        anyChar())
    .many
    .map((parts) => parts.join());

String _resolveBackslashEscapes(String text) {
  if (!text.contains('\\')) return text;
  final result = _backslashEscapeResolver.run(text);
  return switch (result) {
    Success(:final value) => value,
    Partial(:final value) => value,
    Failure() => text,
  };
}

final Parser<ParseError, String> _entityResolver = () {
  final namedEntity = char('&').skipThen(
    satisfy(
      (c) =>
          (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
          (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0),
      'alpha',
    ).flatMap(
      (first) => satisfy(
        (c) =>
            (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
            (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
            (c.compareTo('0') >= 0 && c.compareTo('9') <= 0),
        'alnum',
      ).many.capture.thenSkip(char(';')).flatMap((rest) {
        final name = '$first$rest';
        final decoded = _htmlEntities[name];
        if (decoded != null) {
          return succeed<ParseError, String>(decoded);
        }
        return failure<ParseError, String>(
          CustomError('unknown entity', Location.zero),
        );
      }),
    ),
  );
  final decEntity = string('&#').skipThen(
    satisfy(
      (c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0,
      'digit',
    ).many1.capture.thenSkip(char(';')).map((digits) {
      final code = int.parse(digits);
      return code == 0 ? '\u{FFFD}' : String.fromCharCode(code);
    }),
  );
  final hexEntity = string('&#').skipThen(
    satisfy((c) => c == 'x' || c == 'X', 'xX').skipThen(
      satisfy(
        (c) =>
            (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
            (c.compareTo('a') >= 0 && c.compareTo('f') <= 0) ||
            (c.compareTo('A') >= 0 && c.compareTo('F') <= 0),
        'hex',
      ).many1.capture.thenSkip(char(';')).map((hex) {
        final code = int.parse(hex, radix: 16);
        return code == 0 ? '\u{FFFD}' : String.fromCharCode(code);
      }),
    ),
  );
  return (namedEntity | hexEntity | decEntity | anyChar()).many.map(
    (parts) => parts.join(),
  );
}();

String _resolveEntities(String text) {
  if (!text.contains('&')) return text;
  final result = _entityResolver.run(text);
  return switch (result) {
    Success(:final value) => value,
    Partial(:final value) => value,
    Failure() => text,
  };
}

String _percentEncodeUrl(String url) {
  final buf = StringBuffer();
  var i = 0;
  while (i < url.length) {
    final c = url.codeUnitAt(i);
    if (c == 0x25 && // %
        i + 2 < url.length &&
        _isHexDigit(url.codeUnitAt(i + 1)) &&
        _isHexDigit(url.codeUnitAt(i + 2))) {
      buf.write(url.substring(i, i + 3));
      i += 3;
      continue;
    }
    if (_isUrlSafe(c) && c <= 0x7E) {
      buf.writeCharCode(c);
      i++;
      continue;
    }
    final rune = url.runes.elementAt(url.substring(0, i).runes.length);
    if (rune <= 0x7F) {
      _percentEncodeByte(buf, rune);
      i++;
    } else {
      final utf8Bytes = _runeToUtf8(rune);
      for (final b in utf8Bytes) {
        _percentEncodeByte(buf, b);
      }
      i += String.fromCharCode(rune).length;
    }
  }
  return buf.toString();
}

List<int> _runeToUtf8(int rune) {
  if (rune <= 0x7F) return [rune];
  if (rune <= 0x7FF) return [0xC0 | (rune >> 6), 0x80 | (rune & 0x3F)];
  if (rune <= 0xFFFF) {
    return [
      0xE0 | (rune >> 12),
      0x80 | ((rune >> 6) & 0x3F),
      0x80 | (rune & 0x3F),
    ];
  }
  return [
    0xF0 | (rune >> 18),
    0x80 | ((rune >> 12) & 0x3F),
    0x80 | ((rune >> 6) & 0x3F),
    0x80 | (rune & 0x3F),
  ];
}

void _percentEncodeByte(StringBuffer buf, int byte) {
  buf.write('%');
  buf.write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
}

bool _isHexDigit(int c) =>
    (c >= 0x30 && c <= 0x39) || // 0-9
    (c >= 0x41 && c <= 0x46) || // A-F
    (c >= 0x61 && c <= 0x66); // a-f

bool _isUrlSafe(int c) =>
    (c >= 0x41 && c <= 0x5A) || // A-Z
    (c >= 0x61 && c <= 0x7A) || // a-z
    (c >= 0x30 && c <= 0x39) || // 0-9
    c == 0x2D || // -
    c == 0x2E || // .
    c == 0x5F || // _
    c == 0x7E || // ~
    c == 0x3A || // :
    c == 0x2F || // /
    c == 0x3F || // ?
    c == 0x23 || // #
    c == 0x40 || // @
    c == 0x21 || // !
    c == 0x24 || // $
    c == 0x26 || // &
    c == 0x27 || // '
    c == 0x28 || // (
    c == 0x29 || // )
    c == 0x2A || // *
    c == 0x2B || // +
    c == 0x2C || // ,
    c == 0x3B || // ;
    c == 0x3D || // =
    c == 0x25; // %

String _processUrl(String raw) =>
    _percentEncodeUrl(_resolveEntities(_resolveBackslashEscapes(raw)));

String _processTitle(String raw) =>
    _resolveEntities(_resolveBackslashEscapes(raw));

bool _isUnicodeWhitespace(String c) =>
    c == ' ' ||
    c == '\t' ||
    c == '\n' ||
    c == '\r' ||
    c == '\u000C' ||
    c == '\u00A0';

final _unicodePunctuation = RegExp(r'\p{P}|\p{S}', unicode: true);

bool _isPunctuation(String c) =>
    _asciiPunctuation.contains(c) || _unicodePunctuation.hasMatch(c);

void _classifyDelimiters(List<_Token> tokens) {
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (token is! _DelimToken) continue;

    final before = i > 0 ? _lastCharOf(tokens[i - 1]) : '\n';
    final after = i + 1 < tokens.length ? _firstCharOf(tokens[i + 1]) : '\n';

    final leftFlanking =
        !_isUnicodeWhitespace(after) &&
        (!_isPunctuation(after) ||
            _isUnicodeWhitespace(before) ||
            _isPunctuation(before));
    final rightFlanking =
        !_isUnicodeWhitespace(before) &&
        (!_isPunctuation(before) ||
            _isUnicodeWhitespace(after) ||
            _isPunctuation(after));

    if (token.ch == '*') {
      token
        ..canOpen = leftFlanking
        ..canClose = rightFlanking;
    } else {
      token
        ..canOpen = leftFlanking && (!rightFlanking || _isPunctuation(before))
        ..canClose = rightFlanking && (!leftFlanking || _isPunctuation(after));
    }
  }
}

String _lastCharOf(_Token token) => switch (token) {
  _TextToken(:final text) => text.isNotEmpty ? text[text.length - 1] : '\n',
  _DelimToken(:final ch) => ch,
  _NodeToken(:final lastChar) => lastChar.isNotEmpty ? lastChar : '\n',
  _SoftBreakToken() => '\n',
  _HardBreakToken() => '\n',
};

String _firstCharOf(_Token token) => switch (token) {
  _TextToken(:final text) => text.isNotEmpty ? text[0] : '\n',
  _DelimToken(:final ch) => ch,
  _NodeToken(:final firstChar) => firstChar.isNotEmpty ? firstChar : '\n',
  _SoftBreakToken() => '\n',
  _HardBreakToken() => '\n',
};

/// Spec §6.2 delimiter stack algorithm. Imperative by design — the spec
/// describes this as a mutable procedure with index manipulation on a
/// token list. This is post-processing on combinator output (like the
/// YAML parser's _assembleBlockScalar), not input parsing. A recursive
/// reducer would obscure the 1:1 correspondence with the spec algorithm.
List<MdNode> _processEmphasis(List<_Token> tokens) {
  // Per spec §6.2, openerBottom is keyed by (char, canOpen, origLength % 3).
  final openerBottom = <(String, bool, int), int>{};

  for (var closeIdx = 0; closeIdx < tokens.length; closeIdx++) {
    final closer = tokens[closeIdx];
    if (closer is! _DelimToken || !closer.canClose || !closer.active) continue;

    final ch = closer.ch;
    final bottomKey = (ch, closer.canOpen, closer.count % 3);
    var openIdx = closeIdx - 1;
    final bottom = openerBottom[bottomKey] ?? -1;

    while (openIdx > bottom) {
      final opener = tokens[openIdx];
      if (opener is _DelimToken &&
          opener.ch == ch &&
          opener.canOpen &&
          opener.active) {
        if ((closer.canOpen || opener.canClose) &&
            (opener.count + closer.count) % 3 == 0 &&
            opener.count % 3 != 0) {
          openIdx--;
          continue;
        }
        final strong = opener.count >= 2 && closer.count >= 2;
        final used = strong ? 2 : 1;

        final innerTokens = tokens.sublist(openIdx + 1, closeIdx);
        final innerNodes = _tokensToNodes(innerTokens);

        tokens.removeRange(openIdx + 1, closeIdx);
        closeIdx = openIdx + 1;

        tokens.insert(
          openIdx + 1,
          _NodeToken(strong ? MdStrong(innerNodes) : MdEmphasis(innerNodes)),
        );

        opener.count -= used;
        closer.count -= used;

        if (opener.count == 0) {
          tokens.removeAt(openIdx);
          closeIdx--;
        }
        if (closer.count == 0) {
          final ci = opener.count == 0 ? openIdx + 1 : openIdx + 2;
          if (ci < tokens.length && tokens[ci] == closer) {
            tokens.removeAt(ci);
          }
          closeIdx = opener.count == 0 ? openIdx : openIdx + 1;
        }
        break;
      }
      openIdx--;
    }

    if (openIdx <= bottom) {
      // Per spec: set bottom to element BEFORE current_position.
      // This allows the failed closer to still be used as an opener later.
      openerBottom[bottomKey] = closeIdx - 1;
    }
  }

  return _tokensToNodes(tokens);
}

List<MdNode> _tokensToNodes(List<_Token> tokens) {
  final nodes = <MdNode>[];
  for (final token in tokens) {
    switch (token) {
      case _TextToken(:final text):
        nodes.add(MdText(text));
      case _NodeToken(:final node):
        nodes.add(node);
      case _DelimToken():
        nodes.add(MdText(token.ch * token.count));
      case _SoftBreakToken():
        nodes.add(const MdSoftBreak());
      case _HardBreakToken():
        nodes.add(const MdHardBreak());
        nodes.add(const MdSoftBreak());
    }
  }
  return nodes;
}

List<MdNode> _mergeTextNodes(List<MdNode> nodes) {
  if (nodes.isEmpty) return nodes;
  final merged = <MdNode>[];
  for (final node in nodes) {
    if (node is MdText && merged.isNotEmpty && merged.last is MdText) {
      final prev = merged.removeLast() as MdText;
      merged.add(MdText('${prev.text}${node.text}'));
    } else {
      merged.add(node);
    }
  }
  return merged;
}

/// Unicode full case folding for link label matching. Dart's toLowerCase()
/// does simple case mapping; full case folding expands some characters to
/// multi-character strings (e.g. ẞ U+1E9E → ss, ﬃ U+FB03 → ffi).
/// Only the characters where full folding differs from simple lowercasing.
String _caseFold(String s) {
  final lower = s.toLowerCase();
  final buf = StringBuffer();
  for (final rune in lower.runes) {
    final fold = _fullCaseFolding[rune];
    if (fold != null) {
      buf.write(fold);
    } else {
      buf.writeCharCode(rune);
    }
  }
  return buf.toString();
}

const _fullCaseFolding = <int, String>{
  0x00DF: 'ss', // ß → ss
  0x0130: 'i\u0307', // İ → i + combining dot above
  0x0149: '\u02BCn', // ŉ → ʼn
  0xFB00: 'ff', // ﬀ → ff
  0xFB01: 'fi', // ﬁ → fi
  0xFB02: 'fl', // ﬂ → fl
  0xFB03: 'ffi', // ﬃ → ffi
  0xFB04: 'ffl', // ﬄ → ffl
  0xFB05: 'st', // ﬅ → st
  0xFB06: 'st', // ﬆ → st
};

const _htmlEntities = <String, String>{
  'AElig': '\u00c6',
  'AMP': '&',
  'Aacute': '\u00c1',
  'Abreve': '\u0102',
  'Acirc': '\u00c2',
  'Acy': '\u0410',
  'Afr': '\u{1d504}',
  'Agrave': '\u00c0',
  'Alpha': '\u0391',
  'Amacr': '\u0100',
  'And': '\u2a53',
  'Aogon': '\u0104',
  'Aopf': '\u{1d538}',
  'ApplyFunction': '\u2061',
  'Aring': '\u00c5',
  'Ascr': '\u{1d49c}',
  'Assign': '\u2254',
  'Atilde': '\u00c3',
  'Auml': '\u00c4',
  'Backslash': '\u2216',
  'Barv': '\u2ae7',
  'Barwed': '\u2306',
  'Bcy': '\u0411',
  'Because': '\u2235',
  'Bernoullis': '\u212c',
  'Beta': '\u0392',
  'Bfr': '\u{1d505}',
  'Bopf': '\u{1d539}',
  'Breve': '\u02d8',
  'Bscr': '\u212c',
  'Bumpeq': '\u224e',
  'CHcy': '\u0427',
  'COPY': '\u00a9',
  'Cacute': '\u0106',
  'Cap': '\u22d2',
  'CapitalDifferentialD': '\u2145',
  'Cayleys': '\u212d',
  'Ccaron': '\u010c',
  'Ccedil': '\u00c7',
  'Ccirc': '\u0108',
  'Cconint': '\u2230',
  'Cdot': '\u010a',
  'Cedilla': '\u00b8',
  'CenterDot': '\u00b7',
  'Cfr': '\u212d',
  'Chi': '\u03a7',
  'CircleDot': '\u2299',
  'CircleMinus': '\u2296',
  'CirclePlus': '\u2295',
  'CircleTimes': '\u2297',
  'ClockwiseContourIntegral': '\u2232',
  'CloseCurlyDoubleQuote': '\u201d',
  'CloseCurlyQuote': '\u2019',
  'Colon': '\u2237',
  'Colone': '\u2a74',
  'Congruent': '\u2261',
  'Conint': '\u222f',
  'ContourIntegral': '\u222e',
  'Copf': '\u2102',
  'Coproduct': '\u2210',
  'CounterClockwiseContourIntegral': '\u2233',
  'Cross': '\u2a2f',
  'Cscr': '\u{1d49e}',
  'Cup': '\u22d3',
  'CupCap': '\u224d',
  'DD': '\u2145',
  'DDotrahd': '\u2911',
  'DJcy': '\u0402',
  'DScy': '\u0405',
  'DZcy': '\u040f',
  'Dagger': '\u2021',
  'Darr': '\u21a1',
  'Dashv': '\u2ae4',
  'Dcaron': '\u010e',
  'Dcy': '\u0414',
  'Del': '\u2207',
  'Delta': '\u0394',
  'Dfr': '\u{1d507}',
  'DiacriticalAcute': '\u00b4',
  'DiacriticalDot': '\u02d9',
  'DiacriticalDoubleAcute': '\u02dd',
  'DiacriticalGrave': '`',
  'DiacriticalTilde': '\u02dc',
  'Diamond': '\u22c4',
  'DifferentialD': '\u2146',
  'Dopf': '\u{1d53b}',
  'Dot': '\u00a8',
  'DotDot': '\u20dc',
  'DotEqual': '\u2250',
  'DoubleContourIntegral': '\u222f',
  'DoubleDot': '\u00a8',
  'DoubleDownArrow': '\u21d3',
  'DoubleLeftArrow': '\u21d0',
  'DoubleLeftRightArrow': '\u21d4',
  'DoubleLeftTee': '\u2ae4',
  'DoubleLongLeftArrow': '\u27f8',
  'DoubleLongLeftRightArrow': '\u27fa',
  'DoubleLongRightArrow': '\u27f9',
  'DoubleRightArrow': '\u21d2',
  'DoubleRightTee': '\u22a8',
  'DoubleUpArrow': '\u21d1',
  'DoubleUpDownArrow': '\u21d5',
  'DoubleVerticalBar': '\u2225',
  'DownArrow': '\u2193',
  'DownArrowBar': '\u2913',
  'DownArrowUpArrow': '\u21f5',
  'DownBreve': '\u0311',
  'DownLeftRightVector': '\u2950',
  'DownLeftTeeVector': '\u295e',
  'DownLeftVector': '\u21bd',
  'DownLeftVectorBar': '\u2956',
  'DownRightTeeVector': '\u295f',
  'DownRightVector': '\u21c1',
  'DownRightVectorBar': '\u2957',
  'DownTee': '\u22a4',
  'DownTeeArrow': '\u21a7',
  'Downarrow': '\u21d3',
  'Dscr': '\u{1d49f}',
  'Dstrok': '\u0110',
  'ENG': '\u014a',
  'ETH': '\u00d0',
  'Eacute': '\u00c9',
  'Ecaron': '\u011a',
  'Ecirc': '\u00ca',
  'Ecy': '\u042d',
  'Edot': '\u0116',
  'Efr': '\u{1d508}',
  'Egrave': '\u00c8',
  'Element': '\u2208',
  'Emacr': '\u0112',
  'EmptySmallSquare': '\u25fb',
  'EmptyVerySmallSquare': '\u25ab',
  'Eogon': '\u0118',
  'Eopf': '\u{1d53c}',
  'Epsilon': '\u0395',
  'Equal': '\u2a75',
  'EqualTilde': '\u2242',
  'Equilibrium': '\u21cc',
  'Escr': '\u2130',
  'Esim': '\u2a73',
  'Eta': '\u0397',
  'Euml': '\u00cb',
  'Exists': '\u2203',
  'ExponentialE': '\u2147',
  'Fcy': '\u0424',
  'Ffr': '\u{1d509}',
  'FilledSmallSquare': '\u25fc',
  'FilledVerySmallSquare': '\u25aa',
  'Fopf': '\u{1d53d}',
  'ForAll': '\u2200',
  'Fouriertrf': '\u2131',
  'Fscr': '\u2131',
  'GJcy': '\u0403',
  'GT': '>',
  'Gamma': '\u0393',
  'Gammad': '\u03dc',
  'Gbreve': '\u011e',
  'Gcedil': '\u0122',
  'Gcirc': '\u011c',
  'Gcy': '\u0413',
  'Gdot': '\u0120',
  'Gfr': '\u{1d50a}',
  'Gg': '\u22d9',
  'Gopf': '\u{1d53e}',
  'GreaterEqual': '\u2265',
  'GreaterEqualLess': '\u22db',
  'GreaterFullEqual': '\u2267',
  'GreaterGreater': '\u2aa2',
  'GreaterLess': '\u2277',
  'GreaterSlantEqual': '\u2a7e',
  'GreaterTilde': '\u2273',
  'Gscr': '\u{1d4a2}',
  'Gt': '\u226b',
  'HARDcy': '\u042a',
  'Hacek': '\u02c7',
  'Hat': '^',
  'Hcirc': '\u0124',
  'Hfr': '\u210c',
  'HilbertSpace': '\u210b',
  'Hopf': '\u210d',
  'HorizontalLine': '\u2500',
  'Hscr': '\u210b',
  'Hstrok': '\u0126',
  'HumpDownHump': '\u224e',
  'HumpEqual': '\u224f',
  'IEcy': '\u0415',
  'IJlig': '\u0132',
  'IOcy': '\u0401',
  'Iacute': '\u00cd',
  'Icirc': '\u00ce',
  'Icy': '\u0418',
  'Idot': '\u0130',
  'Ifr': '\u2111',
  'Igrave': '\u00cc',
  'Im': '\u2111',
  'Imacr': '\u012a',
  'ImaginaryI': '\u2148',
  'Implies': '\u21d2',
  'Int': '\u222c',
  'Integral': '\u222b',
  'Intersection': '\u22c2',
  'InvisibleComma': '\u2063',
  'InvisibleTimes': '\u2062',
  'Iogon': '\u012e',
  'Iopf': '\u{1d540}',
  'Iota': '\u0399',
  'Iscr': '\u2110',
  'Itilde': '\u0128',
  'Iukcy': '\u0406',
  'Iuml': '\u00cf',
  'Jcirc': '\u0134',
  'Jcy': '\u0419',
  'Jfr': '\u{1d50d}',
  'Jopf': '\u{1d541}',
  'Jscr': '\u{1d4a5}',
  'Jsercy': '\u0408',
  'Jukcy': '\u0404',
  'KHcy': '\u0425',
  'KJcy': '\u040c',
  'Kappa': '\u039a',
  'Kcedil': '\u0136',
  'Kcy': '\u041a',
  'Kfr': '\u{1d50e}',
  'Kopf': '\u{1d542}',
  'Kscr': '\u{1d4a6}',
  'LJcy': '\u0409',
  'LT': '<',
  'Lacute': '\u0139',
  'Lambda': '\u039b',
  'Lang': '\u27ea',
  'Laplacetrf': '\u2112',
  'Larr': '\u219e',
  'Lcaron': '\u013d',
  'Lcedil': '\u013b',
  'Lcy': '\u041b',
  'LeftAngleBracket': '\u27e8',
  'LeftArrow': '\u2190',
  'LeftArrowBar': '\u21e4',
  'LeftArrowRightArrow': '\u21c6',
  'LeftCeiling': '\u2308',
  'LeftDoubleBracket': '\u27e6',
  'LeftDownTeeVector': '\u2961',
  'LeftDownVector': '\u21c3',
  'LeftDownVectorBar': '\u2959',
  'LeftFloor': '\u230a',
  'LeftRightArrow': '\u2194',
  'LeftRightVector': '\u294e',
  'LeftTee': '\u22a3',
  'LeftTeeArrow': '\u21a4',
  'LeftTeeVector': '\u295a',
  'LeftTriangle': '\u22b2',
  'LeftTriangleBar': '\u29cf',
  'LeftTriangleEqual': '\u22b4',
  'LeftUpDownVector': '\u2951',
  'LeftUpTeeVector': '\u2960',
  'LeftUpVector': '\u21bf',
  'LeftUpVectorBar': '\u2958',
  'LeftVector': '\u21bc',
  'LeftVectorBar': '\u2952',
  'Leftarrow': '\u21d0',
  'Leftrightarrow': '\u21d4',
  'LessEqualGreater': '\u22da',
  'LessFullEqual': '\u2266',
  'LessGreater': '\u2276',
  'LessLess': '\u2aa1',
  'LessSlantEqual': '\u2a7d',
  'LessTilde': '\u2272',
  'Lfr': '\u{1d50f}',
  'Ll': '\u22d8',
  'Lleftarrow': '\u21da',
  'Lmidot': '\u013f',
  'LongLeftArrow': '\u27f5',
  'LongLeftRightArrow': '\u27f7',
  'LongRightArrow': '\u27f6',
  'Longleftarrow': '\u27f8',
  'Longleftrightarrow': '\u27fa',
  'Longrightarrow': '\u27f9',
  'Lopf': '\u{1d543}',
  'LowerLeftArrow': '\u2199',
  'LowerRightArrow': '\u2198',
  'Lscr': '\u2112',
  'Lsh': '\u21b0',
  'Lstrok': '\u0141',
  'Lt': '\u226a',
  'Map': '\u2905',
  'Mcy': '\u041c',
  'MediumSpace': '\u205f',
  'Mellintrf': '\u2133',
  'Mfr': '\u{1d510}',
  'MinusPlus': '\u2213',
  'Mopf': '\u{1d544}',
  'Mscr': '\u2133',
  'Mu': '\u039c',
  'NJcy': '\u040a',
  'Nacute': '\u0143',
  'Ncaron': '\u0147',
  'Ncedil': '\u0145',
  'Ncy': '\u041d',
  'NegativeMediumSpace': '\u200b',
  'NegativeThickSpace': '\u200b',
  'NegativeThinSpace': '\u200b',
  'NegativeVeryThinSpace': '\u200b',
  'NestedGreaterGreater': '\u226b',
  'NestedLessLess': '\u226a',
  'NewLine': '\u000a',
  'Nfr': '\u{1d511}',
  'NoBreak': '\u2060',
  'NonBreakingSpace': '\u00a0',
  'Nopf': '\u2115',
  'Not': '\u2aec',
  'NotCongruent': '\u2262',
  'NotCupCap': '\u226d',
  'NotDoubleVerticalBar': '\u2226',
  'NotElement': '\u2209',
  'NotEqual': '\u2260',
  'NotEqualTilde': '\u2242\u0338',
  'NotExists': '\u2204',
  'NotGreater': '\u226f',
  'NotGreaterEqual': '\u2271',
  'NotGreaterFullEqual': '\u2267\u0338',
  'NotGreaterGreater': '\u226b\u0338',
  'NotGreaterLess': '\u2279',
  'NotGreaterSlantEqual': '\u2a7e\u0338',
  'NotGreaterTilde': '\u2275',
  'NotHumpDownHump': '\u224e\u0338',
  'NotHumpEqual': '\u224f\u0338',
  'NotLeftTriangle': '\u22ea',
  'NotLeftTriangleBar': '\u29cf\u0338',
  'NotLeftTriangleEqual': '\u22ec',
  'NotLess': '\u226e',
  'NotLessEqual': '\u2270',
  'NotLessGreater': '\u2278',
  'NotLessLess': '\u226a\u0338',
  'NotLessSlantEqual': '\u2a7d\u0338',
  'NotLessTilde': '\u2274',
  'NotNestedGreaterGreater': '\u2aa2\u0338',
  'NotNestedLessLess': '\u2aa1\u0338',
  'NotPrecedes': '\u2280',
  'NotPrecedesEqual': '\u2aaf\u0338',
  'NotPrecedesSlantEqual': '\u22e0',
  'NotReverseElement': '\u220c',
  'NotRightTriangle': '\u22eb',
  'NotRightTriangleBar': '\u29d0\u0338',
  'NotRightTriangleEqual': '\u22ed',
  'NotSquareSubset': '\u228f\u0338',
  'NotSquareSubsetEqual': '\u22e2',
  'NotSquareSuperset': '\u2290\u0338',
  'NotSquareSupersetEqual': '\u22e3',
  'NotSubset': '\u2282\u20d2',
  'NotSubsetEqual': '\u2288',
  'NotSucceeds': '\u2281',
  'NotSucceedsEqual': '\u2ab0\u0338',
  'NotSucceedsSlantEqual': '\u22e1',
  'NotSucceedsTilde': '\u227f\u0338',
  'NotSuperset': '\u2283\u20d2',
  'NotSupersetEqual': '\u2289',
  'NotTilde': '\u2241',
  'NotTildeEqual': '\u2244',
  'NotTildeFullEqual': '\u2247',
  'NotTildeTilde': '\u2249',
  'NotVerticalBar': '\u2224',
  'Nscr': '\u{1d4a9}',
  'Ntilde': '\u00d1',
  'Nu': '\u039d',
  'OElig': '\u0152',
  'Oacute': '\u00d3',
  'Ocirc': '\u00d4',
  'Ocy': '\u041e',
  'Odblac': '\u0150',
  'Ofr': '\u{1d512}',
  'Ograve': '\u00d2',
  'Omacr': '\u014c',
  'Omega': '\u03a9',
  'Omicron': '\u039f',
  'Oopf': '\u{1d546}',
  'OpenCurlyDoubleQuote': '\u201c',
  'OpenCurlyQuote': '\u2018',
  'Or': '\u2a54',
  'Oscr': '\u{1d4aa}',
  'Oslash': '\u00d8',
  'Otilde': '\u00d5',
  'Otimes': '\u2a37',
  'Ouml': '\u00d6',
  'OverBar': '\u203e',
  'OverBrace': '\u23de',
  'OverBracket': '\u23b4',
  'OverParenthesis': '\u23dc',
  'PartialD': '\u2202',
  'Pcy': '\u041f',
  'Pfr': '\u{1d513}',
  'Phi': '\u03a6',
  'Pi': '\u03a0',
  'PlusMinus': '\u00b1',
  'Poincareplane': '\u210c',
  'Popf': '\u2119',
  'Pr': '\u2abb',
  'Precedes': '\u227a',
  'PrecedesEqual': '\u2aaf',
  'PrecedesSlantEqual': '\u227c',
  'PrecedesTilde': '\u227e',
  'Prime': '\u2033',
  'Product': '\u220f',
  'Proportion': '\u2237',
  'Proportional': '\u221d',
  'Pscr': '\u{1d4ab}',
  'Psi': '\u03a8',
  'QUOT': '"',
  'Qfr': '\u{1d514}',
  'Qopf': '\u211a',
  'Qscr': '\u{1d4ac}',
  'RBarr': '\u2910',
  'REG': '\u00ae',
  'Racute': '\u0154',
  'Rang': '\u27eb',
  'Rarr': '\u21a0',
  'Rarrtl': '\u2916',
  'Rcaron': '\u0158',
  'Rcedil': '\u0156',
  'Rcy': '\u0420',
  'Re': '\u211c',
  'ReverseElement': '\u220b',
  'ReverseEquilibrium': '\u21cb',
  'ReverseUpEquilibrium': '\u296f',
  'Rfr': '\u211c',
  'Rho': '\u03a1',
  'RightAngleBracket': '\u27e9',
  'RightArrow': '\u2192',
  'RightArrowBar': '\u21e5',
  'RightArrowLeftArrow': '\u21c4',
  'RightCeiling': '\u2309',
  'RightDoubleBracket': '\u27e7',
  'RightDownTeeVector': '\u295d',
  'RightDownVector': '\u21c2',
  'RightDownVectorBar': '\u2955',
  'RightFloor': '\u230b',
  'RightTee': '\u22a2',
  'RightTeeArrow': '\u21a6',
  'RightTeeVector': '\u295b',
  'RightTriangle': '\u22b3',
  'RightTriangleBar': '\u29d0',
  'RightTriangleEqual': '\u22b5',
  'RightUpDownVector': '\u294f',
  'RightUpTeeVector': '\u295c',
  'RightUpVector': '\u21be',
  'RightUpVectorBar': '\u2954',
  'RightVector': '\u21c0',
  'RightVectorBar': '\u2953',
  'Rightarrow': '\u21d2',
  'Ropf': '\u211d',
  'RoundImplies': '\u2970',
  'Rrightarrow': '\u21db',
  'Rscr': '\u211b',
  'Rsh': '\u21b1',
  'RuleDelayed': '\u29f4',
  'SHCHcy': '\u0429',
  'SHcy': '\u0428',
  'SOFTcy': '\u042c',
  'Sacute': '\u015a',
  'Sc': '\u2abc',
  'Scaron': '\u0160',
  'Scedil': '\u015e',
  'Scirc': '\u015c',
  'Scy': '\u0421',
  'Sfr': '\u{1d516}',
  'ShortDownArrow': '\u2193',
  'ShortLeftArrow': '\u2190',
  'ShortRightArrow': '\u2192',
  'ShortUpArrow': '\u2191',
  'Sigma': '\u03a3',
  'SmallCircle': '\u2218',
  'Sopf': '\u{1d54a}',
  'Sqrt': '\u221a',
  'Square': '\u25a1',
  'SquareIntersection': '\u2293',
  'SquareSubset': '\u228f',
  'SquareSubsetEqual': '\u2291',
  'SquareSuperset': '\u2290',
  'SquareSupersetEqual': '\u2292',
  'SquareUnion': '\u2294',
  'Sscr': '\u{1d4ae}',
  'Star': '\u22c6',
  'Sub': '\u22d0',
  'Subset': '\u22d0',
  'SubsetEqual': '\u2286',
  'Succeeds': '\u227b',
  'SucceedsEqual': '\u2ab0',
  'SucceedsSlantEqual': '\u227d',
  'SucceedsTilde': '\u227f',
  'SuchThat': '\u220b',
  'Sum': '\u2211',
  'Sup': '\u22d1',
  'Superset': '\u2283',
  'SupersetEqual': '\u2287',
  'Supset': '\u22d1',
  'THORN': '\u00de',
  'TRADE': '\u2122',
  'TSHcy': '\u040b',
  'TScy': '\u0426',
  'Tab': '\u0009',
  'Tau': '\u03a4',
  'Tcaron': '\u0164',
  'Tcedil': '\u0162',
  'Tcy': '\u0422',
  'Tfr': '\u{1d517}',
  'Therefore': '\u2234',
  'Theta': '\u0398',
  'ThickSpace': '\u205f\u200a',
  'ThinSpace': '\u2009',
  'Tilde': '\u223c',
  'TildeEqual': '\u2243',
  'TildeFullEqual': '\u2245',
  'TildeTilde': '\u2248',
  'Topf': '\u{1d54b}',
  'TripleDot': '\u20db',
  'Tscr': '\u{1d4af}',
  'Tstrok': '\u0166',
  'Uacute': '\u00da',
  'Uarr': '\u219f',
  'Uarrocir': '\u2949',
  'Ubrcy': '\u040e',
  'Ubreve': '\u016c',
  'Ucirc': '\u00db',
  'Ucy': '\u0423',
  'Udblac': '\u0170',
  'Ufr': '\u{1d518}',
  'Ugrave': '\u00d9',
  'Umacr': '\u016a',
  'UnderBar': '_',
  'UnderBrace': '\u23df',
  'UnderBracket': '\u23b5',
  'UnderParenthesis': '\u23dd',
  'Union': '\u22c3',
  'UnionPlus': '\u228e',
  'Uogon': '\u0172',
  'Uopf': '\u{1d54c}',
  'UpArrow': '\u2191',
  'UpArrowBar': '\u2912',
  'UpArrowDownArrow': '\u21c5',
  'UpDownArrow': '\u2195',
  'UpEquilibrium': '\u296e',
  'UpTee': '\u22a5',
  'UpTeeArrow': '\u21a5',
  'Uparrow': '\u21d1',
  'Updownarrow': '\u21d5',
  'UpperLeftArrow': '\u2196',
  'UpperRightArrow': '\u2197',
  'Upsi': '\u03d2',
  'Upsilon': '\u03a5',
  'Uring': '\u016e',
  'Uscr': '\u{1d4b0}',
  'Utilde': '\u0168',
  'Uuml': '\u00dc',
  'VDash': '\u22ab',
  'Vbar': '\u2aeb',
  'Vcy': '\u0412',
  'Vdash': '\u22a9',
  'Vdashl': '\u2ae6',
  'Vee': '\u22c1',
  'Verbar': '\u2016',
  'Vert': '\u2016',
  'VerticalBar': '\u2223',
  'VerticalLine': '|',
  'VerticalSeparator': '\u2758',
  'VerticalTilde': '\u2240',
  'VeryThinSpace': '\u200a',
  'Vfr': '\u{1d519}',
  'Vopf': '\u{1d54d}',
  'Vscr': '\u{1d4b1}',
  'Vvdash': '\u22aa',
  'Wcirc': '\u0174',
  'Wedge': '\u22c0',
  'Wfr': '\u{1d51a}',
  'Wopf': '\u{1d54e}',
  'Wscr': '\u{1d4b2}',
  'Xfr': '\u{1d51b}',
  'Xi': '\u039e',
  'Xopf': '\u{1d54f}',
  'Xscr': '\u{1d4b3}',
  'YAcy': '\u042f',
  'YIcy': '\u0407',
  'YUcy': '\u042e',
  'Yacute': '\u00dd',
  'Ycirc': '\u0176',
  'Ycy': '\u042b',
  'Yfr': '\u{1d51c}',
  'Yopf': '\u{1d550}',
  'Yscr': '\u{1d4b4}',
  'Yuml': '\u0178',
  'ZHcy': '\u0416',
  'Zacute': '\u0179',
  'Zcaron': '\u017d',
  'Zcy': '\u0417',
  'Zdot': '\u017b',
  'ZeroWidthSpace': '\u200b',
  'Zeta': '\u0396',
  'Zfr': '\u2128',
  'Zopf': '\u2124',
  'Zscr': '\u{1d4b5}',
  'aacute': '\u00e1',
  'abreve': '\u0103',
  'ac': '\u223e',
  'acE': '\u223e\u0333',
  'acd': '\u223f',
  'acirc': '\u00e2',
  'acute': '\u00b4',
  'acy': '\u0430',
  'aelig': '\u00e6',
  'af': '\u2061',
  'afr': '\u{1d51e}',
  'agrave': '\u00e0',
  'alefsym': '\u2135',
  'aleph': '\u2135',
  'alpha': '\u03b1',
  'amacr': '\u0101',
  'amalg': '\u2a3f',
  'amp': '&',
  'and': '\u2227',
  'andand': '\u2a55',
  'andd': '\u2a5c',
  'andslope': '\u2a58',
  'andv': '\u2a5a',
  'ang': '\u2220',
  'ange': '\u29a4',
  'angle': '\u2220',
  'angmsd': '\u2221',
  'angmsdaa': '\u29a8',
  'angmsdab': '\u29a9',
  'angmsdac': '\u29aa',
  'angmsdad': '\u29ab',
  'angmsdae': '\u29ac',
  'angmsdaf': '\u29ad',
  'angmsdag': '\u29ae',
  'angmsdah': '\u29af',
  'angrt': '\u221f',
  'angrtvb': '\u22be',
  'angrtvbd': '\u299d',
  'angsph': '\u2222',
  'angst': '\u00c5',
  'angzarr': '\u237c',
  'aogon': '\u0105',
  'aopf': '\u{1d552}',
  'ap': '\u2248',
  'apE': '\u2a70',
  'apacir': '\u2a6f',
  'ape': '\u224a',
  'apid': '\u224b',
  'apos': '\'',
  'approx': '\u2248',
  'approxeq': '\u224a',
  'aring': '\u00e5',
  'ascr': '\u{1d4b6}',
  'ast': '*',
  'asymp': '\u2248',
  'asympeq': '\u224d',
  'atilde': '\u00e3',
  'auml': '\u00e4',
  'awconint': '\u2233',
  'awint': '\u2a11',
  'bNot': '\u2aed',
  'backcong': '\u224c',
  'backepsilon': '\u03f6',
  'backprime': '\u2035',
  'backsim': '\u223d',
  'backsimeq': '\u22cd',
  'barvee': '\u22bd',
  'barwed': '\u2305',
  'barwedge': '\u2305',
  'bbrk': '\u23b5',
  'bbrktbrk': '\u23b6',
  'bcong': '\u224c',
  'bcy': '\u0431',
  'bdquo': '\u201e',
  'becaus': '\u2235',
  'because': '\u2235',
  'bemptyv': '\u29b0',
  'bepsi': '\u03f6',
  'bernou': '\u212c',
  'beta': '\u03b2',
  'beth': '\u2136',
  'between': '\u226c',
  'bfr': '\u{1d51f}',
  'bigcap': '\u22c2',
  'bigcirc': '\u25ef',
  'bigcup': '\u22c3',
  'bigodot': '\u2a00',
  'bigoplus': '\u2a01',
  'bigotimes': '\u2a02',
  'bigsqcup': '\u2a06',
  'bigstar': '\u2605',
  'bigtriangledown': '\u25bd',
  'bigtriangleup': '\u25b3',
  'biguplus': '\u2a04',
  'bigvee': '\u22c1',
  'bigwedge': '\u22c0',
  'bkarow': '\u290d',
  'blacklozenge': '\u29eb',
  'blacksquare': '\u25aa',
  'blacktriangle': '\u25b4',
  'blacktriangledown': '\u25be',
  'blacktriangleleft': '\u25c2',
  'blacktriangleright': '\u25b8',
  'blank': '\u2423',
  'blk12': '\u2592',
  'blk14': '\u2591',
  'blk34': '\u2593',
  'block': '\u2588',
  'bne': '=\u20e5',
  'bnequiv': '\u2261\u20e5',
  'bnot': '\u2310',
  'bopf': '\u{1d553}',
  'bot': '\u22a5',
  'bottom': '\u22a5',
  'bowtie': '\u22c8',
  'boxDL': '\u2557',
  'boxDR': '\u2554',
  'boxDl': '\u2556',
  'boxDr': '\u2553',
  'boxH': '\u2550',
  'boxHD': '\u2566',
  'boxHU': '\u2569',
  'boxHd': '\u2564',
  'boxHu': '\u2567',
  'boxUL': '\u255d',
  'boxUR': '\u255a',
  'boxUl': '\u255c',
  'boxUr': '\u2559',
  'boxV': '\u2551',
  'boxVH': '\u256c',
  'boxVL': '\u2563',
  'boxVR': '\u2560',
  'boxVh': '\u256b',
  'boxVl': '\u2562',
  'boxVr': '\u255f',
  'boxbox': '\u29c9',
  'boxdL': '\u2555',
  'boxdR': '\u2552',
  'boxdl': '\u2510',
  'boxdr': '\u250c',
  'boxh': '\u2500',
  'boxhD': '\u2565',
  'boxhU': '\u2568',
  'boxhd': '\u252c',
  'boxhu': '\u2534',
  'boxminus': '\u229f',
  'boxplus': '\u229e',
  'boxtimes': '\u22a0',
  'boxuL': '\u255b',
  'boxuR': '\u2558',
  'boxul': '\u2518',
  'boxur': '\u2514',
  'boxv': '\u2502',
  'boxvH': '\u256a',
  'boxvL': '\u2561',
  'boxvR': '\u255e',
  'boxvh': '\u253c',
  'boxvl': '\u2524',
  'boxvr': '\u251c',
  'bprime': '\u2035',
  'breve': '\u02d8',
  'brvbar': '\u00a6',
  'bscr': '\u{1d4b7}',
  'bsemi': '\u204f',
  'bsim': '\u223d',
  'bsime': '\u22cd',
  'bsol': '\\',
  'bsolb': '\u29c5',
  'bsolhsub': '\u27c8',
  'bull': '\u2022',
  'bullet': '\u2022',
  'bump': '\u224e',
  'bumpE': '\u2aae',
  'bumpe': '\u224f',
  'bumpeq': '\u224f',
  'cacute': '\u0107',
  'cap': '\u2229',
  'capand': '\u2a44',
  'capbrcup': '\u2a49',
  'capcap': '\u2a4b',
  'capcup': '\u2a47',
  'capdot': '\u2a40',
  'caps': '\u2229\ufe00',
  'caret': '\u2041',
  'caron': '\u02c7',
  'ccaps': '\u2a4d',
  'ccaron': '\u010d',
  'ccedil': '\u00e7',
  'ccirc': '\u0109',
  'ccups': '\u2a4c',
  'ccupssm': '\u2a50',
  'cdot': '\u010b',
  'cedil': '\u00b8',
  'cemptyv': '\u29b2',
  'cent': '\u00a2',
  'centerdot': '\u00b7',
  'cfr': '\u{1d520}',
  'chcy': '\u0447',
  'check': '\u2713',
  'checkmark': '\u2713',
  'chi': '\u03c7',
  'cir': '\u25cb',
  'cirE': '\u29c3',
  'circ': '\u02c6',
  'circeq': '\u2257',
  'circlearrowleft': '\u21ba',
  'circlearrowright': '\u21bb',
  'circledR': '\u00ae',
  'circledS': '\u24c8',
  'circledast': '\u229b',
  'circledcirc': '\u229a',
  'circleddash': '\u229d',
  'cire': '\u2257',
  'cirfnint': '\u2a10',
  'cirmid': '\u2aef',
  'cirscir': '\u29c2',
  'clubs': '\u2663',
  'clubsuit': '\u2663',
  'colon': ':',
  'colone': '\u2254',
  'coloneq': '\u2254',
  'comma': ',',
  'commat': '@',
  'comp': '\u2201',
  'compfn': '\u2218',
  'complement': '\u2201',
  'complexes': '\u2102',
  'cong': '\u2245',
  'congdot': '\u2a6d',
  'conint': '\u222e',
  'copf': '\u{1d554}',
  'coprod': '\u2210',
  'copy': '\u00a9',
  'copysr': '\u2117',
  'crarr': '\u21b5',
  'cross': '\u2717',
  'cscr': '\u{1d4b8}',
  'csub': '\u2acf',
  'csube': '\u2ad1',
  'csup': '\u2ad0',
  'csupe': '\u2ad2',
  'ctdot': '\u22ef',
  'cudarrl': '\u2938',
  'cudarrr': '\u2935',
  'cuepr': '\u22de',
  'cuesc': '\u22df',
  'cularr': '\u21b6',
  'cularrp': '\u293d',
  'cup': '\u222a',
  'cupbrcap': '\u2a48',
  'cupcap': '\u2a46',
  'cupcup': '\u2a4a',
  'cupdot': '\u228d',
  'cupor': '\u2a45',
  'cups': '\u222a\ufe00',
  'curarr': '\u21b7',
  'curarrm': '\u293c',
  'curlyeqprec': '\u22de',
  'curlyeqsucc': '\u22df',
  'curlyvee': '\u22ce',
  'curlywedge': '\u22cf',
  'curren': '\u00a4',
  'curvearrowleft': '\u21b6',
  'curvearrowright': '\u21b7',
  'cuvee': '\u22ce',
  'cuwed': '\u22cf',
  'cwconint': '\u2232',
  'cwint': '\u2231',
  'cylcty': '\u232d',
  'dArr': '\u21d3',
  'dHar': '\u2965',
  'dagger': '\u2020',
  'daleth': '\u2138',
  'darr': '\u2193',
  'dash': '\u2010',
  'dashv': '\u22a3',
  'dbkarow': '\u290f',
  'dblac': '\u02dd',
  'dcaron': '\u010f',
  'dcy': '\u0434',
  'dd': '\u2146',
  'ddagger': '\u2021',
  'ddarr': '\u21ca',
  'ddotseq': '\u2a77',
  'deg': '\u00b0',
  'delta': '\u03b4',
  'demptyv': '\u29b1',
  'dfisht': '\u297f',
  'dfr': '\u{1d521}',
  'dharl': '\u21c3',
  'dharr': '\u21c2',
  'diam': '\u22c4',
  'diamond': '\u22c4',
  'diamondsuit': '\u2666',
  'diams': '\u2666',
  'die': '\u00a8',
  'digamma': '\u03dd',
  'disin': '\u22f2',
  'div': '\u00f7',
  'divide': '\u00f7',
  'divideontimes': '\u22c7',
  'divonx': '\u22c7',
  'djcy': '\u0452',
  'dlcorn': '\u231e',
  'dlcrop': '\u230d',
  'dollar': '\$',
  'dopf': '\u{1d555}',
  'dot': '\u02d9',
  'doteq': '\u2250',
  'doteqdot': '\u2251',
  'dotminus': '\u2238',
  'dotplus': '\u2214',
  'dotsquare': '\u22a1',
  'doublebarwedge': '\u2306',
  'downarrow': '\u2193',
  'downdownarrows': '\u21ca',
  'downharpoonleft': '\u21c3',
  'downharpoonright': '\u21c2',
  'drbkarow': '\u2910',
  'drcorn': '\u231f',
  'drcrop': '\u230c',
  'dscr': '\u{1d4b9}',
  'dscy': '\u0455',
  'dsol': '\u29f6',
  'dstrok': '\u0111',
  'dtdot': '\u22f1',
  'dtri': '\u25bf',
  'dtrif': '\u25be',
  'duarr': '\u21f5',
  'duhar': '\u296f',
  'dwangle': '\u29a6',
  'dzcy': '\u045f',
  'dzigrarr': '\u27ff',
  'eDDot': '\u2a77',
  'eDot': '\u2251',
  'eacute': '\u00e9',
  'easter': '\u2a6e',
  'ecaron': '\u011b',
  'ecir': '\u2256',
  'ecirc': '\u00ea',
  'ecolon': '\u2255',
  'ecy': '\u044d',
  'edot': '\u0117',
  'ee': '\u2147',
  'efDot': '\u2252',
  'efr': '\u{1d522}',
  'eg': '\u2a9a',
  'egrave': '\u00e8',
  'egs': '\u2a96',
  'egsdot': '\u2a98',
  'el': '\u2a99',
  'elinters': '\u23e7',
  'ell': '\u2113',
  'els': '\u2a95',
  'elsdot': '\u2a97',
  'emacr': '\u0113',
  'empty': '\u2205',
  'emptyset': '\u2205',
  'emptyv': '\u2205',
  'emsp': '\u2003',
  'emsp13': '\u2004',
  'emsp14': '\u2005',
  'eng': '\u014b',
  'ensp': '\u2002',
  'eogon': '\u0119',
  'eopf': '\u{1d556}',
  'epar': '\u22d5',
  'eparsl': '\u29e3',
  'eplus': '\u2a71',
  'epsi': '\u03b5',
  'epsilon': '\u03b5',
  'epsiv': '\u03f5',
  'eqcirc': '\u2256',
  'eqcolon': '\u2255',
  'eqsim': '\u2242',
  'eqslantgtr': '\u2a96',
  'eqslantless': '\u2a95',
  'equals': '=',
  'equest': '\u225f',
  'equiv': '\u2261',
  'equivDD': '\u2a78',
  'eqvparsl': '\u29e5',
  'erDot': '\u2253',
  'erarr': '\u2971',
  'escr': '\u212f',
  'esdot': '\u2250',
  'esim': '\u2242',
  'eta': '\u03b7',
  'eth': '\u00f0',
  'euml': '\u00eb',
  'euro': '\u20ac',
  'excl': '!',
  'exist': '\u2203',
  'expectation': '\u2130',
  'exponentiale': '\u2147',
  'fallingdotseq': '\u2252',
  'fcy': '\u0444',
  'female': '\u2640',
  'ffilig': '\ufb03',
  'fflig': '\ufb00',
  'ffllig': '\ufb04',
  'ffr': '\u{1d523}',
  'filig': '\ufb01',
  'fjlig': 'fj',
  'flat': '\u266d',
  'fllig': '\ufb02',
  'fltns': '\u25b1',
  'fnof': '\u0192',
  'fopf': '\u{1d557}',
  'forall': '\u2200',
  'fork': '\u22d4',
  'forkv': '\u2ad9',
  'fpartint': '\u2a0d',
  'frac12': '\u00bd',
  'frac13': '\u2153',
  'frac14': '\u00bc',
  'frac15': '\u2155',
  'frac16': '\u2159',
  'frac18': '\u215b',
  'frac23': '\u2154',
  'frac25': '\u2156',
  'frac34': '\u00be',
  'frac35': '\u2157',
  'frac38': '\u215c',
  'frac45': '\u2158',
  'frac56': '\u215a',
  'frac58': '\u215d',
  'frac78': '\u215e',
  'frasl': '\u2044',
  'frown': '\u2322',
  'fscr': '\u{1d4bb}',
  'gE': '\u2267',
  'gEl': '\u2a8c',
  'gacute': '\u01f5',
  'gamma': '\u03b3',
  'gammad': '\u03dd',
  'gap': '\u2a86',
  'gbreve': '\u011f',
  'gcirc': '\u011d',
  'gcy': '\u0433',
  'gdot': '\u0121',
  'ge': '\u2265',
  'gel': '\u22db',
  'geq': '\u2265',
  'geqq': '\u2267',
  'geqslant': '\u2a7e',
  'ges': '\u2a7e',
  'gescc': '\u2aa9',
  'gesdot': '\u2a80',
  'gesdoto': '\u2a82',
  'gesdotol': '\u2a84',
  'gesl': '\u22db\ufe00',
  'gesles': '\u2a94',
  'gfr': '\u{1d524}',
  'gg': '\u226b',
  'ggg': '\u22d9',
  'gimel': '\u2137',
  'gjcy': '\u0453',
  'gl': '\u2277',
  'glE': '\u2a92',
  'gla': '\u2aa5',
  'glj': '\u2aa4',
  'gnE': '\u2269',
  'gnap': '\u2a8a',
  'gnapprox': '\u2a8a',
  'gne': '\u2a88',
  'gneq': '\u2a88',
  'gneqq': '\u2269',
  'gnsim': '\u22e7',
  'gopf': '\u{1d558}',
  'grave': '`',
  'gscr': '\u210a',
  'gsim': '\u2273',
  'gsime': '\u2a8e',
  'gsiml': '\u2a90',
  'gt': '>',
  'gtcc': '\u2aa7',
  'gtcir': '\u2a7a',
  'gtdot': '\u22d7',
  'gtlPar': '\u2995',
  'gtquest': '\u2a7c',
  'gtrapprox': '\u2a86',
  'gtrarr': '\u2978',
  'gtrdot': '\u22d7',
  'gtreqless': '\u22db',
  'gtreqqless': '\u2a8c',
  'gtrless': '\u2277',
  'gtrsim': '\u2273',
  'gvertneqq': '\u2269\ufe00',
  'gvnE': '\u2269\ufe00',
  'hArr': '\u21d4',
  'hairsp': '\u200a',
  'half': '\u00bd',
  'hamilt': '\u210b',
  'hardcy': '\u044a',
  'harr': '\u2194',
  'harrcir': '\u2948',
  'harrw': '\u21ad',
  'hbar': '\u210f',
  'hcirc': '\u0125',
  'hearts': '\u2665',
  'heartsuit': '\u2665',
  'hellip': '\u2026',
  'hercon': '\u22b9',
  'hfr': '\u{1d525}',
  'hksearow': '\u2925',
  'hkswarow': '\u2926',
  'hoarr': '\u21ff',
  'homtht': '\u223b',
  'hookleftarrow': '\u21a9',
  'hookrightarrow': '\u21aa',
  'hopf': '\u{1d559}',
  'horbar': '\u2015',
  'hscr': '\u{1d4bd}',
  'hslash': '\u210f',
  'hstrok': '\u0127',
  'hybull': '\u2043',
  'hyphen': '\u2010',
  'iacute': '\u00ed',
  'ic': '\u2063',
  'icirc': '\u00ee',
  'icy': '\u0438',
  'iecy': '\u0435',
  'iexcl': '\u00a1',
  'iff': '\u21d4',
  'ifr': '\u{1d526}',
  'igrave': '\u00ec',
  'ii': '\u2148',
  'iiiint': '\u2a0c',
  'iiint': '\u222d',
  'iinfin': '\u29dc',
  'iiota': '\u2129',
  'ijlig': '\u0133',
  'imacr': '\u012b',
  'image': '\u2111',
  'imagline': '\u2110',
  'imagpart': '\u2111',
  'imath': '\u0131',
  'imof': '\u22b7',
  'imped': '\u01b5',
  'in': '\u2208',
  'incare': '\u2105',
  'infin': '\u221e',
  'infintie': '\u29dd',
  'inodot': '\u0131',
  'int': '\u222b',
  'intcal': '\u22ba',
  'integers': '\u2124',
  'intercal': '\u22ba',
  'intlarhk': '\u2a17',
  'intprod': '\u2a3c',
  'iocy': '\u0451',
  'iogon': '\u012f',
  'iopf': '\u{1d55a}',
  'iota': '\u03b9',
  'iprod': '\u2a3c',
  'iquest': '\u00bf',
  'iscr': '\u{1d4be}',
  'isin': '\u2208',
  'isinE': '\u22f9',
  'isindot': '\u22f5',
  'isins': '\u22f4',
  'isinsv': '\u22f3',
  'isinv': '\u2208',
  'it': '\u2062',
  'itilde': '\u0129',
  'iukcy': '\u0456',
  'iuml': '\u00ef',
  'jcirc': '\u0135',
  'jcy': '\u0439',
  'jfr': '\u{1d527}',
  'jmath': '\u0237',
  'jopf': '\u{1d55b}',
  'jscr': '\u{1d4bf}',
  'jsercy': '\u0458',
  'jukcy': '\u0454',
  'kappa': '\u03ba',
  'kappav': '\u03f0',
  'kcedil': '\u0137',
  'kcy': '\u043a',
  'kfr': '\u{1d528}',
  'kgreen': '\u0138',
  'khcy': '\u0445',
  'kjcy': '\u045c',
  'kopf': '\u{1d55c}',
  'kscr': '\u{1d4c0}',
  'lAarr': '\u21da',
  'lArr': '\u21d0',
  'lAtail': '\u291b',
  'lBarr': '\u290e',
  'lE': '\u2266',
  'lEg': '\u2a8b',
  'lHar': '\u2962',
  'lacute': '\u013a',
  'laemptyv': '\u29b4',
  'lagran': '\u2112',
  'lambda': '\u03bb',
  'lang': '\u27e8',
  'langd': '\u2991',
  'langle': '\u27e8',
  'lap': '\u2a85',
  'laquo': '\u00ab',
  'larr': '\u2190',
  'larrb': '\u21e4',
  'larrbfs': '\u291f',
  'larrfs': '\u291d',
  'larrhk': '\u21a9',
  'larrlp': '\u21ab',
  'larrpl': '\u2939',
  'larrsim': '\u2973',
  'larrtl': '\u21a2',
  'lat': '\u2aab',
  'latail': '\u2919',
  'late': '\u2aad',
  'lates': '\u2aad\ufe00',
  'lbarr': '\u290c',
  'lbbrk': '\u2772',
  'lbrace': '{',
  'lbrack': '[',
  'lbrke': '\u298b',
  'lbrksld': '\u298f',
  'lbrkslu': '\u298d',
  'lcaron': '\u013e',
  'lcedil': '\u013c',
  'lceil': '\u2308',
  'lcub': '{',
  'lcy': '\u043b',
  'ldca': '\u2936',
  'ldquo': '\u201c',
  'ldquor': '\u201e',
  'ldrdhar': '\u2967',
  'ldrushar': '\u294b',
  'ldsh': '\u21b2',
  'le': '\u2264',
  'leftarrow': '\u2190',
  'leftarrowtail': '\u21a2',
  'leftharpoondown': '\u21bd',
  'leftharpoonup': '\u21bc',
  'leftleftarrows': '\u21c7',
  'leftrightarrow': '\u2194',
  'leftrightarrows': '\u21c6',
  'leftrightharpoons': '\u21cb',
  'leftrightsquigarrow': '\u21ad',
  'leftthreetimes': '\u22cb',
  'leg': '\u22da',
  'leq': '\u2264',
  'leqq': '\u2266',
  'leqslant': '\u2a7d',
  'les': '\u2a7d',
  'lescc': '\u2aa8',
  'lesdot': '\u2a7f',
  'lesdoto': '\u2a81',
  'lesdotor': '\u2a83',
  'lesg': '\u22da\ufe00',
  'lesges': '\u2a93',
  'lessapprox': '\u2a85',
  'lessdot': '\u22d6',
  'lesseqgtr': '\u22da',
  'lesseqqgtr': '\u2a8b',
  'lessgtr': '\u2276',
  'lesssim': '\u2272',
  'lfisht': '\u297c',
  'lfloor': '\u230a',
  'lfr': '\u{1d529}',
  'lg': '\u2276',
  'lgE': '\u2a91',
  'lhard': '\u21bd',
  'lharu': '\u21bc',
  'lharul': '\u296a',
  'lhblk': '\u2584',
  'ljcy': '\u0459',
  'll': '\u226a',
  'llarr': '\u21c7',
  'llcorner': '\u231e',
  'llhard': '\u296b',
  'lltri': '\u25fa',
  'lmidot': '\u0140',
  'lmoust': '\u23b0',
  'lmoustache': '\u23b0',
  'lnE': '\u2268',
  'lnap': '\u2a89',
  'lnapprox': '\u2a89',
  'lne': '\u2a87',
  'lneq': '\u2a87',
  'lneqq': '\u2268',
  'lnsim': '\u22e6',
  'loang': '\u27ec',
  'loarr': '\u21fd',
  'lobrk': '\u27e6',
  'longleftarrow': '\u27f5',
  'longleftrightarrow': '\u27f7',
  'longmapsto': '\u27fc',
  'longrightarrow': '\u27f6',
  'looparrowleft': '\u21ab',
  'looparrowright': '\u21ac',
  'lopar': '\u2985',
  'lopf': '\u{1d55d}',
  'loplus': '\u2a2d',
  'lotimes': '\u2a34',
  'lowast': '\u2217',
  'lowbar': '_',
  'loz': '\u25ca',
  'lozenge': '\u25ca',
  'lozf': '\u29eb',
  'lpar': '(',
  'lparlt': '\u2993',
  'lrarr': '\u21c6',
  'lrcorner': '\u231f',
  'lrhar': '\u21cb',
  'lrhard': '\u296d',
  'lrm': '\u200e',
  'lrtri': '\u22bf',
  'lsaquo': '\u2039',
  'lscr': '\u{1d4c1}',
  'lsh': '\u21b0',
  'lsim': '\u2272',
  'lsime': '\u2a8d',
  'lsimg': '\u2a8f',
  'lsqb': '[',
  'lsquo': '\u2018',
  'lsquor': '\u201a',
  'lstrok': '\u0142',
  'lt': '<',
  'ltcc': '\u2aa6',
  'ltcir': '\u2a79',
  'ltdot': '\u22d6',
  'lthree': '\u22cb',
  'ltimes': '\u22c9',
  'ltlarr': '\u2976',
  'ltquest': '\u2a7b',
  'ltrPar': '\u2996',
  'ltri': '\u25c3',
  'ltrie': '\u22b4',
  'ltrif': '\u25c2',
  'lurdshar': '\u294a',
  'luruhar': '\u2966',
  'lvertneqq': '\u2268\ufe00',
  'lvnE': '\u2268\ufe00',
  'mDDot': '\u223a',
  'macr': '\u00af',
  'male': '\u2642',
  'malt': '\u2720',
  'maltese': '\u2720',
  'map': '\u21a6',
  'mapsto': '\u21a6',
  'mapstodown': '\u21a7',
  'mapstoleft': '\u21a4',
  'mapstoup': '\u21a5',
  'marker': '\u25ae',
  'mcomma': '\u2a29',
  'mcy': '\u043c',
  'mdash': '\u2014',
  'measuredangle': '\u2221',
  'mfr': '\u{1d52a}',
  'mho': '\u2127',
  'micro': '\u00b5',
  'mid': '\u2223',
  'midast': '*',
  'midcir': '\u2af0',
  'middot': '\u00b7',
  'minus': '\u2212',
  'minusb': '\u229f',
  'minusd': '\u2238',
  'minusdu': '\u2a2a',
  'mlcp': '\u2adb',
  'mldr': '\u2026',
  'mnplus': '\u2213',
  'models': '\u22a7',
  'mopf': '\u{1d55e}',
  'mp': '\u2213',
  'mscr': '\u{1d4c2}',
  'mstpos': '\u223e',
  'mu': '\u03bc',
  'multimap': '\u22b8',
  'mumap': '\u22b8',
  'nGg': '\u22d9\u0338',
  'nGt': '\u226b\u20d2',
  'nGtv': '\u226b\u0338',
  'nLeftarrow': '\u21cd',
  'nLeftrightarrow': '\u21ce',
  'nLl': '\u22d8\u0338',
  'nLt': '\u226a\u20d2',
  'nLtv': '\u226a\u0338',
  'nRightarrow': '\u21cf',
  'nVDash': '\u22af',
  'nVdash': '\u22ae',
  'nabla': '\u2207',
  'nacute': '\u0144',
  'nang': '\u2220\u20d2',
  'nap': '\u2249',
  'napE': '\u2a70\u0338',
  'napid': '\u224b\u0338',
  'napos': '\u0149',
  'napprox': '\u2249',
  'natur': '\u266e',
  'natural': '\u266e',
  'naturals': '\u2115',
  'nbsp': '\u00a0',
  'nbump': '\u224e\u0338',
  'nbumpe': '\u224f\u0338',
  'ncap': '\u2a43',
  'ncaron': '\u0148',
  'ncedil': '\u0146',
  'ncong': '\u2247',
  'ncongdot': '\u2a6d\u0338',
  'ncup': '\u2a42',
  'ncy': '\u043d',
  'ndash': '\u2013',
  'ne': '\u2260',
  'neArr': '\u21d7',
  'nearhk': '\u2924',
  'nearr': '\u2197',
  'nearrow': '\u2197',
  'nedot': '\u2250\u0338',
  'nequiv': '\u2262',
  'nesear': '\u2928',
  'nesim': '\u2242\u0338',
  'nexist': '\u2204',
  'nexists': '\u2204',
  'nfr': '\u{1d52b}',
  'ngE': '\u2267\u0338',
  'nge': '\u2271',
  'ngeq': '\u2271',
  'ngeqq': '\u2267\u0338',
  'ngeqslant': '\u2a7e\u0338',
  'nges': '\u2a7e\u0338',
  'ngsim': '\u2275',
  'ngt': '\u226f',
  'ngtr': '\u226f',
  'nhArr': '\u21ce',
  'nharr': '\u21ae',
  'nhpar': '\u2af2',
  'ni': '\u220b',
  'nis': '\u22fc',
  'nisd': '\u22fa',
  'niv': '\u220b',
  'njcy': '\u045a',
  'nlArr': '\u21cd',
  'nlE': '\u2266\u0338',
  'nlarr': '\u219a',
  'nldr': '\u2025',
  'nle': '\u2270',
  'nleftarrow': '\u219a',
  'nleftrightarrow': '\u21ae',
  'nleq': '\u2270',
  'nleqq': '\u2266\u0338',
  'nleqslant': '\u2a7d\u0338',
  'nles': '\u2a7d\u0338',
  'nless': '\u226e',
  'nlsim': '\u2274',
  'nlt': '\u226e',
  'nltri': '\u22ea',
  'nltrie': '\u22ec',
  'nmid': '\u2224',
  'nopf': '\u{1d55f}',
  'not': '\u00ac',
  'notin': '\u2209',
  'notinE': '\u22f9\u0338',
  'notindot': '\u22f5\u0338',
  'notinva': '\u2209',
  'notinvb': '\u22f7',
  'notinvc': '\u22f6',
  'notni': '\u220c',
  'notniva': '\u220c',
  'notnivb': '\u22fe',
  'notnivc': '\u22fd',
  'npar': '\u2226',
  'nparallel': '\u2226',
  'nparsl': '\u2afd\u20e5',
  'npart': '\u2202\u0338',
  'npolint': '\u2a14',
  'npr': '\u2280',
  'nprcue': '\u22e0',
  'npre': '\u2aaf\u0338',
  'nprec': '\u2280',
  'npreceq': '\u2aaf\u0338',
  'nrArr': '\u21cf',
  'nrarr': '\u219b',
  'nrarrc': '\u2933\u0338',
  'nrarrw': '\u219d\u0338',
  'nrightarrow': '\u219b',
  'nrtri': '\u22eb',
  'nrtrie': '\u22ed',
  'nsc': '\u2281',
  'nsccue': '\u22e1',
  'nsce': '\u2ab0\u0338',
  'nscr': '\u{1d4c3}',
  'nshortmid': '\u2224',
  'nshortparallel': '\u2226',
  'nsim': '\u2241',
  'nsime': '\u2244',
  'nsimeq': '\u2244',
  'nsmid': '\u2224',
  'nspar': '\u2226',
  'nsqsube': '\u22e2',
  'nsqsupe': '\u22e3',
  'nsub': '\u2284',
  'nsubE': '\u2ac5\u0338',
  'nsube': '\u2288',
  'nsubset': '\u2282\u20d2',
  'nsubseteq': '\u2288',
  'nsubseteqq': '\u2ac5\u0338',
  'nsucc': '\u2281',
  'nsucceq': '\u2ab0\u0338',
  'nsup': '\u2285',
  'nsupE': '\u2ac6\u0338',
  'nsupe': '\u2289',
  'nsupset': '\u2283\u20d2',
  'nsupseteq': '\u2289',
  'nsupseteqq': '\u2ac6\u0338',
  'ntgl': '\u2279',
  'ntilde': '\u00f1',
  'ntlg': '\u2278',
  'ntriangleleft': '\u22ea',
  'ntrianglelefteq': '\u22ec',
  'ntriangleright': '\u22eb',
  'ntrianglerighteq': '\u22ed',
  'nu': '\u03bd',
  'num': '#',
  'numero': '\u2116',
  'numsp': '\u2007',
  'nvDash': '\u22ad',
  'nvHarr': '\u2904',
  'nvap': '\u224d\u20d2',
  'nvdash': '\u22ac',
  'nvge': '\u2265\u20d2',
  'nvgt': '>\u20d2',
  'nvinfin': '\u29de',
  'nvlArr': '\u2902',
  'nvle': '\u2264\u20d2',
  'nvlt': '<\u20d2',
  'nvltrie': '\u22b4\u20d2',
  'nvrArr': '\u2903',
  'nvrtrie': '\u22b5\u20d2',
  'nvsim': '\u223c\u20d2',
  'nwArr': '\u21d6',
  'nwarhk': '\u2923',
  'nwarr': '\u2196',
  'nwarrow': '\u2196',
  'nwnear': '\u2927',
  'oS': '\u24c8',
  'oacute': '\u00f3',
  'oast': '\u229b',
  'ocir': '\u229a',
  'ocirc': '\u00f4',
  'ocy': '\u043e',
  'odash': '\u229d',
  'odblac': '\u0151',
  'odiv': '\u2a38',
  'odot': '\u2299',
  'odsold': '\u29bc',
  'oelig': '\u0153',
  'ofcir': '\u29bf',
  'ofr': '\u{1d52c}',
  'ogon': '\u02db',
  'ograve': '\u00f2',
  'ogt': '\u29c1',
  'ohbar': '\u29b5',
  'ohm': '\u03a9',
  'oint': '\u222e',
  'olarr': '\u21ba',
  'olcir': '\u29be',
  'olcross': '\u29bb',
  'oline': '\u203e',
  'olt': '\u29c0',
  'omacr': '\u014d',
  'omega': '\u03c9',
  'omicron': '\u03bf',
  'omid': '\u29b6',
  'ominus': '\u2296',
  'oopf': '\u{1d560}',
  'opar': '\u29b7',
  'operp': '\u29b9',
  'oplus': '\u2295',
  'or': '\u2228',
  'orarr': '\u21bb',
  'ord': '\u2a5d',
  'order': '\u2134',
  'orderof': '\u2134',
  'ordf': '\u00aa',
  'ordm': '\u00ba',
  'origof': '\u22b6',
  'oror': '\u2a56',
  'orslope': '\u2a57',
  'orv': '\u2a5b',
  'oscr': '\u2134',
  'oslash': '\u00f8',
  'osol': '\u2298',
  'otilde': '\u00f5',
  'otimes': '\u2297',
  'otimesas': '\u2a36',
  'ouml': '\u00f6',
  'ovbar': '\u233d',
  'par': '\u2225',
  'para': '\u00b6',
  'parallel': '\u2225',
  'parsim': '\u2af3',
  'parsl': '\u2afd',
  'part': '\u2202',
  'pcy': '\u043f',
  'percnt': '%',
  'period': '.',
  'permil': '\u2030',
  'perp': '\u22a5',
  'pertenk': '\u2031',
  'pfr': '\u{1d52d}',
  'phi': '\u03c6',
  'phiv': '\u03d5',
  'phmmat': '\u2133',
  'phone': '\u260e',
  'pi': '\u03c0',
  'pitchfork': '\u22d4',
  'piv': '\u03d6',
  'planck': '\u210f',
  'planckh': '\u210e',
  'plankv': '\u210f',
  'plus': '+',
  'plusacir': '\u2a23',
  'plusb': '\u229e',
  'pluscir': '\u2a22',
  'plusdo': '\u2214',
  'plusdu': '\u2a25',
  'pluse': '\u2a72',
  'plusmn': '\u00b1',
  'plussim': '\u2a26',
  'plustwo': '\u2a27',
  'pm': '\u00b1',
  'pointint': '\u2a15',
  'popf': '\u{1d561}',
  'pound': '\u00a3',
  'pr': '\u227a',
  'prE': '\u2ab3',
  'prap': '\u2ab7',
  'prcue': '\u227c',
  'pre': '\u2aaf',
  'prec': '\u227a',
  'precapprox': '\u2ab7',
  'preccurlyeq': '\u227c',
  'preceq': '\u2aaf',
  'precnapprox': '\u2ab9',
  'precneqq': '\u2ab5',
  'precnsim': '\u22e8',
  'precsim': '\u227e',
  'prime': '\u2032',
  'primes': '\u2119',
  'prnE': '\u2ab5',
  'prnap': '\u2ab9',
  'prnsim': '\u22e8',
  'prod': '\u220f',
  'profalar': '\u232e',
  'profline': '\u2312',
  'profsurf': '\u2313',
  'prop': '\u221d',
  'propto': '\u221d',
  'prsim': '\u227e',
  'prurel': '\u22b0',
  'pscr': '\u{1d4c5}',
  'psi': '\u03c8',
  'puncsp': '\u2008',
  'qfr': '\u{1d52e}',
  'qint': '\u2a0c',
  'qopf': '\u{1d562}',
  'qprime': '\u2057',
  'qscr': '\u{1d4c6}',
  'quaternions': '\u210d',
  'quatint': '\u2a16',
  'quest': '?',
  'questeq': '\u225f',
  'quot': '"',
  'rAarr': '\u21db',
  'rArr': '\u21d2',
  'rAtail': '\u291c',
  'rBarr': '\u290f',
  'rHar': '\u2964',
  'race': '\u223d\u0331',
  'racute': '\u0155',
  'radic': '\u221a',
  'raemptyv': '\u29b3',
  'rang': '\u27e9',
  'rangd': '\u2992',
  'range': '\u29a5',
  'rangle': '\u27e9',
  'raquo': '\u00bb',
  'rarr': '\u2192',
  'rarrap': '\u2975',
  'rarrb': '\u21e5',
  'rarrbfs': '\u2920',
  'rarrc': '\u2933',
  'rarrfs': '\u291e',
  'rarrhk': '\u21aa',
  'rarrlp': '\u21ac',
  'rarrpl': '\u2945',
  'rarrsim': '\u2974',
  'rarrtl': '\u21a3',
  'rarrw': '\u219d',
  'ratail': '\u291a',
  'ratio': '\u2236',
  'rationals': '\u211a',
  'rbarr': '\u290d',
  'rbbrk': '\u2773',
  'rbrace': '}',
  'rbrack': ']',
  'rbrke': '\u298c',
  'rbrksld': '\u298e',
  'rbrkslu': '\u2990',
  'rcaron': '\u0159',
  'rcedil': '\u0157',
  'rceil': '\u2309',
  'rcub': '}',
  'rcy': '\u0440',
  'rdca': '\u2937',
  'rdldhar': '\u2969',
  'rdquo': '\u201d',
  'rdquor': '\u201d',
  'rdsh': '\u21b3',
  'real': '\u211c',
  'realine': '\u211b',
  'realpart': '\u211c',
  'reals': '\u211d',
  'rect': '\u25ad',
  'reg': '\u00ae',
  'rfisht': '\u297d',
  'rfloor': '\u230b',
  'rfr': '\u{1d52f}',
  'rhard': '\u21c1',
  'rharu': '\u21c0',
  'rharul': '\u296c',
  'rho': '\u03c1',
  'rhov': '\u03f1',
  'rightarrow': '\u2192',
  'rightarrowtail': '\u21a3',
  'rightharpoondown': '\u21c1',
  'rightharpoonup': '\u21c0',
  'rightleftarrows': '\u21c4',
  'rightleftharpoons': '\u21cc',
  'rightrightarrows': '\u21c9',
  'rightsquigarrow': '\u219d',
  'rightthreetimes': '\u22cc',
  'ring': '\u02da',
  'risingdotseq': '\u2253',
  'rlarr': '\u21c4',
  'rlhar': '\u21cc',
  'rlm': '\u200f',
  'rmoust': '\u23b1',
  'rmoustache': '\u23b1',
  'rnmid': '\u2aee',
  'roang': '\u27ed',
  'roarr': '\u21fe',
  'robrk': '\u27e7',
  'ropar': '\u2986',
  'ropf': '\u{1d563}',
  'roplus': '\u2a2e',
  'rotimes': '\u2a35',
  'rpar': ')',
  'rpargt': '\u2994',
  'rppolint': '\u2a12',
  'rrarr': '\u21c9',
  'rsaquo': '\u203a',
  'rscr': '\u{1d4c7}',
  'rsh': '\u21b1',
  'rsqb': ']',
  'rsquo': '\u2019',
  'rsquor': '\u2019',
  'rthree': '\u22cc',
  'rtimes': '\u22ca',
  'rtri': '\u25b9',
  'rtrie': '\u22b5',
  'rtrif': '\u25b8',
  'rtriltri': '\u29ce',
  'ruluhar': '\u2968',
  'rx': '\u211e',
  'sacute': '\u015b',
  'sbquo': '\u201a',
  'sc': '\u227b',
  'scE': '\u2ab4',
  'scap': '\u2ab8',
  'scaron': '\u0161',
  'sccue': '\u227d',
  'sce': '\u2ab0',
  'scedil': '\u015f',
  'scirc': '\u015d',
  'scnE': '\u2ab6',
  'scnap': '\u2aba',
  'scnsim': '\u22e9',
  'scpolint': '\u2a13',
  'scsim': '\u227f',
  'scy': '\u0441',
  'sdot': '\u22c5',
  'sdotb': '\u22a1',
  'sdote': '\u2a66',
  'seArr': '\u21d8',
  'searhk': '\u2925',
  'searr': '\u2198',
  'searrow': '\u2198',
  'sect': '\u00a7',
  'semi': ';',
  'seswar': '\u2929',
  'setminus': '\u2216',
  'setmn': '\u2216',
  'sext': '\u2736',
  'sfr': '\u{1d530}',
  'sfrown': '\u2322',
  'sharp': '\u266f',
  'shchcy': '\u0449',
  'shcy': '\u0448',
  'shortmid': '\u2223',
  'shortparallel': '\u2225',
  'shy': '\u00ad',
  'sigma': '\u03c3',
  'sigmaf': '\u03c2',
  'sigmav': '\u03c2',
  'sim': '\u223c',
  'simdot': '\u2a6a',
  'sime': '\u2243',
  'simeq': '\u2243',
  'simg': '\u2a9e',
  'simgE': '\u2aa0',
  'siml': '\u2a9d',
  'simlE': '\u2a9f',
  'simne': '\u2246',
  'simplus': '\u2a24',
  'simrarr': '\u2972',
  'slarr': '\u2190',
  'smallsetminus': '\u2216',
  'smashp': '\u2a33',
  'smeparsl': '\u29e4',
  'smid': '\u2223',
  'smile': '\u2323',
  'smt': '\u2aaa',
  'smte': '\u2aac',
  'smtes': '\u2aac\ufe00',
  'softcy': '\u044c',
  'sol': '/',
  'solb': '\u29c4',
  'solbar': '\u233f',
  'sopf': '\u{1d564}',
  'spades': '\u2660',
  'spadesuit': '\u2660',
  'spar': '\u2225',
  'sqcap': '\u2293',
  'sqcaps': '\u2293\ufe00',
  'sqcup': '\u2294',
  'sqcups': '\u2294\ufe00',
  'sqsub': '\u228f',
  'sqsube': '\u2291',
  'sqsubset': '\u228f',
  'sqsubseteq': '\u2291',
  'sqsup': '\u2290',
  'sqsupe': '\u2292',
  'sqsupset': '\u2290',
  'sqsupseteq': '\u2292',
  'squ': '\u25a1',
  'square': '\u25a1',
  'squarf': '\u25aa',
  'squf': '\u25aa',
  'srarr': '\u2192',
  'sscr': '\u{1d4c8}',
  'ssetmn': '\u2216',
  'ssmile': '\u2323',
  'sstarf': '\u22c6',
  'star': '\u2606',
  'starf': '\u2605',
  'straightepsilon': '\u03f5',
  'straightphi': '\u03d5',
  'strns': '\u00af',
  'sub': '\u2282',
  'subE': '\u2ac5',
  'subdot': '\u2abd',
  'sube': '\u2286',
  'subedot': '\u2ac3',
  'submult': '\u2ac1',
  'subnE': '\u2acb',
  'subne': '\u228a',
  'subplus': '\u2abf',
  'subrarr': '\u2979',
  'subset': '\u2282',
  'subseteq': '\u2286',
  'subseteqq': '\u2ac5',
  'subsetneq': '\u228a',
  'subsetneqq': '\u2acb',
  'subsim': '\u2ac7',
  'subsub': '\u2ad5',
  'subsup': '\u2ad3',
  'succ': '\u227b',
  'succapprox': '\u2ab8',
  'succcurlyeq': '\u227d',
  'succeq': '\u2ab0',
  'succnapprox': '\u2aba',
  'succneqq': '\u2ab6',
  'succnsim': '\u22e9',
  'succsim': '\u227f',
  'sum': '\u2211',
  'sung': '\u266a',
  'sup': '\u2283',
  'sup1': '\u00b9',
  'sup2': '\u00b2',
  'sup3': '\u00b3',
  'supE': '\u2ac6',
  'supdot': '\u2abe',
  'supdsub': '\u2ad8',
  'supe': '\u2287',
  'supedot': '\u2ac4',
  'suphsol': '\u27c9',
  'suphsub': '\u2ad7',
  'suplarr': '\u297b',
  'supmult': '\u2ac2',
  'supnE': '\u2acc',
  'supne': '\u228b',
  'supplus': '\u2ac0',
  'supset': '\u2283',
  'supseteq': '\u2287',
  'supseteqq': '\u2ac6',
  'supsetneq': '\u228b',
  'supsetneqq': '\u2acc',
  'supsim': '\u2ac8',
  'supsub': '\u2ad4',
  'supsup': '\u2ad6',
  'swArr': '\u21d9',
  'swarhk': '\u2926',
  'swarr': '\u2199',
  'swarrow': '\u2199',
  'swnwar': '\u292a',
  'szlig': '\u00df',
  'target': '\u2316',
  'tau': '\u03c4',
  'tbrk': '\u23b4',
  'tcaron': '\u0165',
  'tcedil': '\u0163',
  'tcy': '\u0442',
  'tdot': '\u20db',
  'telrec': '\u2315',
  'tfr': '\u{1d531}',
  'there4': '\u2234',
  'therefore': '\u2234',
  'theta': '\u03b8',
  'thetasym': '\u03d1',
  'thetav': '\u03d1',
  'thickapprox': '\u2248',
  'thicksim': '\u223c',
  'thinsp': '\u2009',
  'thkap': '\u2248',
  'thksim': '\u223c',
  'thorn': '\u00fe',
  'tilde': '\u02dc',
  'times': '\u00d7',
  'timesb': '\u22a0',
  'timesbar': '\u2a31',
  'timesd': '\u2a30',
  'tint': '\u222d',
  'toea': '\u2928',
  'top': '\u22a4',
  'topbot': '\u2336',
  'topcir': '\u2af1',
  'topf': '\u{1d565}',
  'topfork': '\u2ada',
  'tosa': '\u2929',
  'tprime': '\u2034',
  'trade': '\u2122',
  'triangle': '\u25b5',
  'triangledown': '\u25bf',
  'triangleleft': '\u25c3',
  'trianglelefteq': '\u22b4',
  'triangleq': '\u225c',
  'triangleright': '\u25b9',
  'trianglerighteq': '\u22b5',
  'tridot': '\u25ec',
  'trie': '\u225c',
  'triminus': '\u2a3a',
  'triplus': '\u2a39',
  'trisb': '\u29cd',
  'tritime': '\u2a3b',
  'trpezium': '\u23e2',
  'tscr': '\u{1d4c9}',
  'tscy': '\u0446',
  'tshcy': '\u045b',
  'tstrok': '\u0167',
  'twixt': '\u226c',
  'twoheadleftarrow': '\u219e',
  'twoheadrightarrow': '\u21a0',
  'uArr': '\u21d1',
  'uHar': '\u2963',
  'uacute': '\u00fa',
  'uarr': '\u2191',
  'ubrcy': '\u045e',
  'ubreve': '\u016d',
  'ucirc': '\u00fb',
  'ucy': '\u0443',
  'udarr': '\u21c5',
  'udblac': '\u0171',
  'udhar': '\u296e',
  'ufisht': '\u297e',
  'ufr': '\u{1d532}',
  'ugrave': '\u00f9',
  'uharl': '\u21bf',
  'uharr': '\u21be',
  'uhblk': '\u2580',
  'ulcorn': '\u231c',
  'ulcorner': '\u231c',
  'ulcrop': '\u230f',
  'ultri': '\u25f8',
  'umacr': '\u016b',
  'uml': '\u00a8',
  'uogon': '\u0173',
  'uopf': '\u{1d566}',
  'uparrow': '\u2191',
  'updownarrow': '\u2195',
  'upharpoonleft': '\u21bf',
  'upharpoonright': '\u21be',
  'uplus': '\u228e',
  'upsi': '\u03c5',
  'upsih': '\u03d2',
  'upsilon': '\u03c5',
  'upuparrows': '\u21c8',
  'urcorn': '\u231d',
  'urcorner': '\u231d',
  'urcrop': '\u230e',
  'uring': '\u016f',
  'urtri': '\u25f9',
  'uscr': '\u{1d4ca}',
  'utdot': '\u22f0',
  'utilde': '\u0169',
  'utri': '\u25b5',
  'utrif': '\u25b4',
  'uuarr': '\u21c8',
  'uuml': '\u00fc',
  'uwangle': '\u29a7',
  'vArr': '\u21d5',
  'vBar': '\u2ae8',
  'vBarv': '\u2ae9',
  'vDash': '\u22a8',
  'vangrt': '\u299c',
  'varepsilon': '\u03f5',
  'varkappa': '\u03f0',
  'varnothing': '\u2205',
  'varphi': '\u03d5',
  'varpi': '\u03d6',
  'varpropto': '\u221d',
  'varr': '\u2195',
  'varrho': '\u03f1',
  'varsigma': '\u03c2',
  'varsubsetneq': '\u228a\ufe00',
  'varsubsetneqq': '\u2acb\ufe00',
  'varsupsetneq': '\u228b\ufe00',
  'varsupsetneqq': '\u2acc\ufe00',
  'vartheta': '\u03d1',
  'vartriangleleft': '\u22b2',
  'vartriangleright': '\u22b3',
  'vcy': '\u0432',
  'vdash': '\u22a2',
  'vee': '\u2228',
  'veebar': '\u22bb',
  'veeeq': '\u225a',
  'vellip': '\u22ee',
  'verbar': '|',
  'vert': '|',
  'vfr': '\u{1d533}',
  'vltri': '\u22b2',
  'vnsub': '\u2282\u20d2',
  'vnsup': '\u2283\u20d2',
  'vopf': '\u{1d567}',
  'vprop': '\u221d',
  'vrtri': '\u22b3',
  'vscr': '\u{1d4cb}',
  'vsubnE': '\u2acb\ufe00',
  'vsubne': '\u228a\ufe00',
  'vsupnE': '\u2acc\ufe00',
  'vsupne': '\u228b\ufe00',
  'vzigzag': '\u299a',
  'wcirc': '\u0175',
  'wedbar': '\u2a5f',
  'wedge': '\u2227',
  'wedgeq': '\u2259',
  'weierp': '\u2118',
  'wfr': '\u{1d534}',
  'wopf': '\u{1d568}',
  'wp': '\u2118',
  'wr': '\u2240',
  'wreath': '\u2240',
  'wscr': '\u{1d4cc}',
  'xcap': '\u22c2',
  'xcirc': '\u25ef',
  'xcup': '\u22c3',
  'xdtri': '\u25bd',
  'xfr': '\u{1d535}',
  'xhArr': '\u27fa',
  'xharr': '\u27f7',
  'xi': '\u03be',
  'xlArr': '\u27f8',
  'xlarr': '\u27f5',
  'xmap': '\u27fc',
  'xnis': '\u22fb',
  'xodot': '\u2a00',
  'xopf': '\u{1d569}',
  'xoplus': '\u2a01',
  'xotime': '\u2a02',
  'xrArr': '\u27f9',
  'xrarr': '\u27f6',
  'xscr': '\u{1d4cd}',
  'xsqcup': '\u2a06',
  'xuplus': '\u2a04',
  'xutri': '\u25b3',
  'xvee': '\u22c1',
  'xwedge': '\u22c0',
  'yacute': '\u00fd',
  'yacy': '\u044f',
  'ycirc': '\u0177',
  'ycy': '\u044b',
  'yen': '\u00a5',
  'yfr': '\u{1d536}',
  'yicy': '\u0457',
  'yopf': '\u{1d56a}',
  'yscr': '\u{1d4ce}',
  'yucy': '\u044e',
  'yuml': '\u00ff',
  'zacute': '\u017a',
  'zcaron': '\u017e',
  'zcy': '\u0437',
  'zdot': '\u017c',
  'zeetrf': '\u2128',
  'zeta': '\u03b6',
  'zfr': '\u{1d537}',
  'zhcy': '\u0436',
  'zigrarr': '\u21dd',
  'zopf': '\u{1d56b}',
  'zscr': '\u{1d4cf}',
  'zwj': '\u200d',
  'zwnj': '\u200c',
};
