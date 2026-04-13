/// Delimited format serializer (CSV/TSV/DSV).
library;

import '../delimited.dart';

/// Serialize a [CsvDocument] to a CSV string.
String serializeCsv(
  List<List<String>> records, {
  CsvConfig config = defaultCsvConfig,
}) => records
    .map(
      (row) =>
          row.map((field) => _csvField(field, config)).join(config.delimiter),
    )
    .join(config.lineEnding);

/// Serialize with headers as the first row.
String serializeCsvWithHeaders(
  List<String> headers,
  List<List<String>> rows, {
  CsvConfig config = defaultCsvConfig,
}) => serializeCsv([headers, ...rows], config: config);

String _csvField(String field, CsvConfig config) {
  if (field.contains(config.delimiter) ||
      field.contains('"') ||
      field.contains('\n') ||
      field.contains('\r')) {
    return '"${field.replaceAll('"', '""')}"';
  }
  return field;
}
