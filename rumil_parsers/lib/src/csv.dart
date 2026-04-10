/// RFC 4180 compliant CSV/TSV parser.
library;

import 'package:rumil/rumil.dart';

import 'common.dart' as common;

/// CSV configuration.
class CsvConfig {
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

  /// Creates a CSV configuration.
  const CsvConfig({
    this.delimiter = ',',
    this.quote = '"',
    this.escape = '"',
    this.trimWhitespace = false,
    this.skipEmptyLines = false,
    this.lineEnding = '\r\n',
  });
}

/// Default CSV configuration (comma-separated, double-quote).
const defaultCsvConfig = CsvConfig();

/// Default TSV configuration (tab-separated).
const defaultTsvConfig = CsvConfig(delimiter: '\t');

/// A CSV document: list of records, each a list of fields.
typedef CsvDocument = List<List<String>>;

/// Parse CSV from [input].
Result<ParseError, CsvDocument> parseCsv(
  String input, [
  CsvConfig config = defaultCsvConfig,
]) => _csvDocument(config).run(input);

/// Parse TSV from [input].
Result<ParseError, CsvDocument> parseTsv(String input) =>
    parseCsv(input, defaultTsvConfig);

/// Parse CSV and split into (headers, data rows).
Result<ParseError, (List<String>, CsvDocument)> parseCsvWithHeaders(
  String input, [
  CsvConfig config = defaultCsvConfig,
]) {
  final r = parseCsv(input, config);
  return switch (r) {
    Success<ParseError, CsvDocument>(:final value, :final consumed) =>
      value.isEmpty
          ? Success((<String>[], <List<String>>[]), consumed)
          : Success((value.first, value.sublist(1)), consumed),
    Partial<ParseError, CsvDocument>(
      :final value,
      :final errorThunk,
      :final consumed,
    ) =>
      value.isEmpty
          ? Partial((<String>[], <List<String>>[]), errorThunk, consumed)
          : Partial((value.first, value.sublist(1)), errorThunk, consumed),
    Failure<ParseError, CsvDocument>(:final errorThunk, :final furthest) =>
      Failure(errorThunk, furthest),
  };
}

// ---- Internal parsers ----

Parser<ParseError, CsvDocument> _csvDocument(CsvConfig config) =>
    _csvRecord(config)
        .sepBy(common.newline())
        .map(
          (records) =>
              config.skipEmptyLines
                  ? records
                      .where((r) => r.isNotEmpty && !r.every((f) => f.isEmpty))
                      .toList()
                  : records,
        )
        .thenSkip(eof());

Parser<ParseError, List<String>> _csvRecord(CsvConfig config) =>
    _csvField(config).sepBy(char(config.delimiter));

Parser<ParseError, String> _csvField(CsvConfig config) {
  final quoted = _quotedField(config);
  final unquoted = _unquotedField(config);

  return (quoted | unquoted).map(
    (field) => config.trimWhitespace ? field.trim() : field,
  );
}

Parser<ParseError, String> _quotedField(CsvConfig config) {
  final escapedQuote = string(
    '${config.escape}${config.quote}',
  ).as(config.quote);
  final regularChar = satisfy((c) => c != config.quote, 'field char');

  return char(config.quote)
      .skipThen((escapedQuote | regularChar).many)
      .map((chars) => chars.join())
      .thenSkip(char(config.quote));
}

Parser<ParseError, String> _unquotedField(CsvConfig config) => satisfy(
  (c) => c != config.delimiter && c != '\n' && c != '\r' && c != config.quote,
  'unquoted field char',
).many.map((chars) => chars.join());
