/// Delimited format parser (CSV, TSV, PSV, and any delimiter variant).
///
/// Three tiers:
/// - **Tier 1**: `parseDelimited(input, config)` — explicit config, strict
/// - **Tier 2**: `parseDelimited(input)` — auto-detect dialect
/// - **Tier 3**: `parseDelimitedRobust(input)` — per-row dialect adaptation
///
/// RFC 4180 compliant with real-world robustness extensions:
/// BOM stripping, bare quotes mid-field, ragged row handling,
/// dialect detection, and configurable delimiter/quote/escape.
library;

import 'package:rumil/rumil.dart';

import 'common.dart' as common;

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// Policy for rows that have fewer or more fields than expected.
enum RaggedRowPolicy {
  /// Throw a parse error on ragged rows.
  error,

  /// Pad short rows with empty strings, ignore extra fields.
  padWithEmpty,

  /// Keep rows as-is (no padding, no truncation).
  preserve,
}

/// Configuration for delimited format parsing.
class DelimitedConfig {
  /// Field delimiter character.
  final String delimiter;

  /// Quote character for wrapping fields.
  final String quote;

  /// Escape character within quoted fields.
  final String escape;

  /// Whether to trim whitespace from field values.
  final bool trimWhitespace;

  /// Whether to skip empty lines.
  final bool skipEmptyLines;

  /// Line ending for serialization (`\r\n` for RFC 4180, `\n` for Unix).
  final String lineEnding;

  /// Whether the first row is a header.
  final bool? hasHeader;

  /// Policy for rows with inconsistent field counts.
  final RaggedRowPolicy raggedRows;

  /// Creates a delimited format configuration.
  const DelimitedConfig({
    this.delimiter = ',',
    this.quote = '"',
    this.escape = '"',
    this.trimWhitespace = false,
    this.skipEmptyLines = false,
    this.lineEnding = '\r\n',
    this.hasHeader,
    this.raggedRows = RaggedRowPolicy.preserve,
  });

  @override
  String toString() =>
      'DelimitedConfig(delimiter: ${_charName(delimiter)}, '
      'quote: ${_charName(quote)})';
}

String _charName(String c) => switch (c) {
  '\t' => 'TAB',
  ',' => 'COMMA',
  ';' => 'SEMICOLON',
  '|' => 'PIPE',
  _ => "'$c'",
};

/// Default CSV configuration (comma-separated, double-quote).
const defaultDelimitedConfig = DelimitedConfig();

/// Default TSV configuration (tab-separated).
const defaultTsvConfig = DelimitedConfig(delimiter: '\t');

/// Backward-compatible alias for [DelimitedConfig].
typedef CsvConfig = DelimitedConfig;

/// Backward-compatible alias for [DelimitedDocument].
typedef CsvDocument = DelimitedDocument;

/// Backward-compatible alias for [defaultDelimitedConfig].
const defaultCsvConfig = defaultDelimitedConfig;

/// A delimited document: list of records, each a list of fields.
typedef DelimitedDocument = List<List<String>>;

// ---------------------------------------------------------------------------
// BOM handling
// ---------------------------------------------------------------------------

/// Strip UTF-8 BOM (\uFEFF) from the start of input if present.
String _stripBom(String input) =>
    input.startsWith('\uFEFF') ? input.substring(1) : input;

// ---------------------------------------------------------------------------
// Dialect detection
// ---------------------------------------------------------------------------

/// Auto-detect the dialect of a delimited file by sampling content.
///
/// Examines the first [sampleLines] lines to determine:
/// - Delimiter (most consistent field-count across lines)
/// - Quote character (`"` or `'`)
/// - Whether the first row is a header
DelimitedConfig detectDialect(String input, {int sampleLines = 20}) {
  final clean = _stripBom(input);
  final lines = clean
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final sample = lines.take(sampleLines).where((l) => l.isNotEmpty).toList();
  if (sample.isEmpty) return defaultDelimitedConfig;

  // Score each candidate delimiter by consistency of field count.
  const candidates = [',', '\t', ';', '|'];
  var bestDelimiter = ',';
  var bestScore = -1.0;

  for (final delim in candidates) {
    final counts = <int>[];
    for (final line in sample) {
      // Naive split (doesn't handle quoting — good enough for detection).
      counts.add(_countDelimiters(line, delim) + 1);
    }
    if (counts.isEmpty) continue;
    final mean = counts.reduce((a, b) => a + b) / counts.length;
    if (mean <= 1.0) continue; // Single field = this delimiter isn't used.
    // Score: higher mean + lower variance = better.
    final variance =
        counts.map((c) => (c - mean) * (c - mean)).reduce((a, b) => a + b) /
        counts.length;
    final score = mean / (1.0 + variance);
    if (score > bestScore) {
      bestScore = score;
      bestDelimiter = delim;
    }
  }

  // Detect quote character.
  final hasDouble = sample.any((l) => l.contains('"'));
  final hasSingle = sample.any((l) => l.contains("'"));
  final quote = hasDouble ? '"' : (hasSingle ? "'" : '"');

  // Detect header: if the first row's fields are all non-numeric strings
  // and the second row has at least one numeric field, first row is a header.
  var hasHeader = false;
  if (sample.length >= 2) {
    final row1 = sample[0].split(bestDelimiter);
    final row2 = sample[1].split(bestDelimiter);
    final row1AllStrings = row1.every((f) => double.tryParse(f.trim()) == null);
    final row2HasNumbers = row2.any((f) => double.tryParse(f.trim()) != null);
    hasHeader = row1AllStrings && row2HasNumbers;
  }

  return DelimitedConfig(
    delimiter: bestDelimiter,
    quote: quote,
    hasHeader: hasHeader,
  );
}

/// Count occurrences of [delim] outside quoted regions in [line].
int _countDelimiters(String line, String delim) {
  final quoted = (char('"') | char("'")).flatMap(
    (q) => satisfy((c) => c != q, 'quoted').many.skipThen(char(q)),
  );
  final delimParser = char(delim).map((_) => true);
  final other = satisfy(
    (c) => c != delim && c != '"' && c != "'",
    'other',
  ).map((_) => false);
  final token = quoted.as<bool>(false) | delimParser | other;
  final result = token.many.thenSkip(eof()).run(line);
  return switch (result) {
    Success(:final value) => value.where((b) => b).length,
    _ => 0,
  };
}

// ---------------------------------------------------------------------------
// Parsing — Tier 1 (explicit config)
// ---------------------------------------------------------------------------

/// Parse delimited text with explicit or auto-detected configuration.
///
/// If [config] is omitted, the dialect is auto-detected from the input.
Result<ParseError, DelimitedDocument> parseDelimited(
  String input, [
  DelimitedConfig? config,
]) {
  final clean = _stripBom(input);
  final cfg = config ?? detectDialect(clean);
  final result = _delimitedDocument(cfg).run(clean);
  return _applyRaggedPolicy(result, cfg);
}

/// Parse delimited text and split into (headers, data rows).
///
/// If [config] is omitted, the dialect is auto-detected.
Result<ParseError, (List<String>, DelimitedDocument)> parseDelimitedWithHeaders(
  String input, [
  DelimitedConfig? config,
]) {
  final clean = _stripBom(input);
  final cfg = config ?? detectDialect(clean);
  final r = _delimitedDocument(cfg).run(clean);
  final ragged = _applyRaggedPolicy(r, cfg);
  return switch (ragged) {
    Success<ParseError, DelimitedDocument>(:final value, :final consumed) =>
      value.isEmpty
          ? Success((<String>[], <List<String>>[]), consumed)
          : Success((value.first, value.sublist(1)), consumed),
    Partial<ParseError, DelimitedDocument>(
      :final value,
      :final errorThunk,
      :final consumed,
    ) =>
      value.isEmpty
          ? Partial((<String>[], <List<String>>[]), errorThunk, consumed)
          : Partial((value.first, value.sublist(1)), errorThunk, consumed),
    Failure<ParseError, DelimitedDocument>(
      :final errorThunk,
      :final furthest,
    ) =>
      Failure(errorThunk, furthest),
  };
}

// ---------------------------------------------------------------------------
// Parsing — Tier 3 (per-row dialect adaptation)
// ---------------------------------------------------------------------------

/// Parse delimited text with per-row dialect adaptation.
///
/// For messy data where different rows may use different delimiters.
/// Uses the detected header field count as the anchor: for each row,
/// the delimiter that produces the expected field count wins.
Result<ParseError, DelimitedDocument> parseDelimitedRobust(String input) {
  final clean = _stripBom(input);
  final lines = clean
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  if (lines.isEmpty) return const Success([], 0);

  // Remove trailing empty line.
  if (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }

  if (lines.isEmpty) return const Success([], 0);

  final dialect = detectDialect(clean);
  final expectedFields = _splitLine(lines.first, dialect).length;

  final records = <List<String>>[];
  for (final line in lines) {
    if (line.isEmpty && dialect.skipEmptyLines) continue;

    // Try the detected delimiter first.
    final fields = _splitLine(line, dialect);
    if (fields.length == expectedFields) {
      records.add(fields);
      continue;
    }

    // Try other delimiters to find one that produces the right field count.
    const candidates = [',', '\t', ';', '|'];
    var found = false;
    for (final delim in candidates) {
      if (delim == dialect.delimiter) continue;
      final alt = _splitLine(
        line,
        DelimitedConfig(delimiter: delim, quote: dialect.quote),
      );
      if (alt.length == expectedFields) {
        records.add(alt);
        found = true;
        break;
      }
    }
    if (!found) {
      records.add(fields); // Fallback to detected delimiter.
    }
  }

  return Success(records, clean.length);
}

/// Split a single line into fields using simple quoting rules.
List<String> _splitLine(String line, DelimitedConfig config) {
  final delim = config.delimiter;
  final quote = config.quote;

  final escaped = string('$quote$quote').as<String>(quote);
  final quotedContent =
      (escaped | satisfy((c) => c != quote, 'quoted char')).many.capture;
  final quotedField = char(quote).skipThen(quotedContent).thenSkip(char(quote));
  final unquotedField =
      satisfy((c) => c != delim && c != quote, 'field char').many.capture;
  final field = quotedField | unquotedField;
  final row = field.sepBy(char(delim));

  final result = row.thenSkip(eof()).run(line);
  return switch (result) {
    Success(:final value) => value,
    Partial(:final value) => value,
    Failure() => [line],
  };
}

// ---------------------------------------------------------------------------
// Backward compatibility (CSV/TSV aliases)
// ---------------------------------------------------------------------------

/// Parse CSV from [input].
Result<ParseError, DelimitedDocument> parseCsv(
  String input, [
  DelimitedConfig config = defaultDelimitedConfig,
]) => parseDelimited(input, config);

/// Parse TSV from [input].
Result<ParseError, DelimitedDocument> parseTsv(String input) =>
    parseDelimited(input, defaultTsvConfig);

/// Parse CSV and split into (headers, data rows).
Result<ParseError, (List<String>, DelimitedDocument)> parseCsvWithHeaders(
  String input, [
  DelimitedConfig config = defaultDelimitedConfig,
]) => parseDelimitedWithHeaders(input, config);

// ---------------------------------------------------------------------------
// Ragged row handling
// ---------------------------------------------------------------------------

Result<ParseError, DelimitedDocument> _applyRaggedPolicy(
  Result<ParseError, DelimitedDocument> result,
  DelimitedConfig config,
) {
  if (config.raggedRows == RaggedRowPolicy.preserve) return result;
  return switch (result) {
    Success<ParseError, DelimitedDocument>(:final value, :final consumed) =>
      Success(_normalizeRows(value, config), consumed),
    Partial<ParseError, DelimitedDocument>(
      :final value,
      :final errorThunk,
      :final consumed,
    ) =>
      Partial(_normalizeRows(value, config), errorThunk, consumed),
    Failure() => result,
  };
}

DelimitedDocument _normalizeRows(
  DelimitedDocument rows,
  DelimitedConfig config,
) {
  if (rows.isEmpty) return rows;
  final expectedLen = rows.first.length;
  return [
    for (final row in rows)
      if (row.length == expectedLen)
        row
      else if (row.length < expectedLen &&
          config.raggedRows == RaggedRowPolicy.padWithEmpty)
        [...row, for (var i = row.length; i < expectedLen; i++) '']
      else if (config.raggedRows == RaggedRowPolicy.error)
        throw FormatException('Expected $expectedLen fields, got ${row.length}')
      else
        row, // preserve
  ];
}

// ---------------------------------------------------------------------------
// Internal parsers (combinator-based, Tier 1)
// ---------------------------------------------------------------------------

Parser<ParseError, DelimitedDocument> _delimitedDocument(
  DelimitedConfig config,
) => _delimitedRecord(config)
    .sepBy(common.newline())
    .map((records) {
      var result = records;
      // Trailing newline produces an empty record — remove it per RFC 4180.
      if (result.length > 1 &&
          result.last.length == 1 &&
          result.last[0].isEmpty) {
        result = result.sublist(0, result.length - 1);
      }
      if (config.skipEmptyLines) {
        result =
            result
                .where((r) => r.isNotEmpty && !r.every((f) => f.isEmpty))
                .toList();
      }
      return result;
    })
    .thenSkip(eof());

Parser<ParseError, List<String>> _delimitedRecord(DelimitedConfig config) =>
    _delimitedField(config).sepBy(char(config.delimiter));

Parser<ParseError, String> _delimitedField(DelimitedConfig config) {
  final quoted = _quotedField(config);
  final unquoted = _unquotedField(config);

  return (quoted | unquoted).map(
    (field) => config.trimWhitespace ? field.trim() : field,
  );
}

Parser<ParseError, String> _quotedField(DelimitedConfig config) {
  final escapedQuote = string(
    '${config.escape}${config.quote}',
  ).as(config.quote);
  final regularChar = satisfy((c) => c != config.quote, 'field char');

  return char(config.quote)
      .skipThen((escapedQuote | regularChar).many)
      .map((chars) => chars.join())
      .thenSkip(char(config.quote));
}

Parser<ParseError, String> _unquotedField(DelimitedConfig config) {
  final normalChar = satisfy(
    (c) => c != config.delimiter && c != '\n' && c != '\r' && c != config.quote,
    'unquoted field char',
  );

  // Allow quote chars mid-field (real-world: bare quotes like 37.8"N).
  final midQuote = char(config.quote);

  return normalChar.flatMap(
        (first) =>
            (normalChar | midQuote).many.map((rest) => [first, ...rest].join()),
      ) |
      succeed<ParseError, String>(''); // empty field
}
