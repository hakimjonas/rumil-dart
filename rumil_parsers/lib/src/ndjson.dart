/// Newline-delimited JSON (NDJSON / JSON Lines) parser.
///
/// Each line of input is parsed as a single JSON value via
/// [parseJson]. By default, every line in the input must contribute
/// either a value or an error — blank lines are rejected, matching
/// the JSON Lines spec at `jsonlines.org`. The lenient mode skips
/// blank lines for ergonomics with log files and stanza-style input.
library;

import 'package:rumil/rumil.dart';

import 'ast/json.dart';
import 'json.dart';

/// Configuration for [parseNdJson].
///
/// Defaults to strict mode (blank lines are parse errors), matching
/// the JSON Lines specification.
final class NdJsonConfig {
  /// When `true`, blank lines (lines whose only content is the line
  /// terminator) are skipped silently. When `false` (default), they
  /// produce a parse error.
  ///
  /// Lenient mode is appropriate for log-file consumers and
  /// stanza-style inputs where blank-line separation is intentional;
  /// strict mode is appropriate for canonical NDJSON streams.
  final bool lenient;

  /// Creates an NDJSON config.
  const NdJsonConfig({this.lenient = false});
}

/// Parse a newline-delimited JSON stream into a list of values.
///
/// Per-line errors are accumulated rather than aborting the stream:
/// the result is [Partial] with the values that did parse and the
/// errors for those that didn't. A successful parse with no per-line
/// errors returns [Success].
///
/// Behavior:
///
/// - Splits on `\n`. A `\r` immediately preceding `\n` is stripped, so
///   CRLF-delimited input parses identically to LF-delimited input.
/// - Strict (default): blank lines produce a parse error pointing at
///   the empty line. The trailing newline at end-of-stream is not a
///   blank line — it's a terminator on the final value. An entirely
///   empty input is [Success] with an empty list.
/// - Lenient (`NdJsonConfig(lenient: true)`): blank lines are skipped
///   silently. An input containing only blank lines is [Success] with
///   an empty list.
/// - Per-line errors carry [Location]s referenced to the original
///   input via [LineIndex], so `line:column` resolution is O(log n)
///   per error rather than O(n).
/// - The `consumed` count reflects the entire input (whether or not
///   every line parsed) so callers can detect "we read the whole
///   stream, here's what stuck."
Result<ParseError, List<JsonValue>> parseNdJson(
  String input, {
  NdJsonConfig config = const NdJsonConfig(),
}) {
  final values = <JsonValue>[];
  final errors = <ParseError>[];

  if (input.isEmpty) {
    return Success(values, 0);
  }

  // One [LineIndex] per call. Per-error location resolution becomes
  // O(log n) per error rather than O(n) per error, so a stream with
  // many bad lines doesn't degrade quadratically.
  final lineIndex = LineIndex(input);

  var offset = 0;
  while (offset < input.length) {
    final lineEnd = _findNewline(input, offset);
    final rawLine = input.substring(offset, lineEnd);
    final line =
        rawLine.endsWith('\r')
            ? rawLine.substring(0, rawLine.length - 1)
            : rawLine;

    if (line.isEmpty) {
      // Blank line. The trailing newline of the final record is not
      // a blank line — it's the closing terminator and lineEnd ==
      // input.length will break out of the loop below before this
      // branch sees it.
      final atEnd = lineEnd >= input.length;
      if (!atEnd && !config.lenient) {
        errors.add(
          CustomError(
            'blank line in NDJSON stream',
            lineIndex.locationAt(offset),
          ),
        );
      }
    } else {
      final lineResult = parseJson(line);
      switch (lineResult) {
        case Success(:final value):
          values.add(value);
        case Partial(:final value):
          values.add(value);
          for (final e in lineResult.errors) {
            errors.add(_relocate(e, lineIndex, offset));
          }
        case Failure():
          for (final e in lineResult.errors) {
            errors.add(_relocate(e, lineIndex, offset));
          }
      }
    }

    if (lineEnd >= input.length) break;
    offset = lineEnd + 1;
  }

  if (errors.isEmpty) {
    return Success(values, input.length);
  }
  return Partial.eager(values, errors, input.length);
}

/// Returns the offset of the next `\n` at or after [offset], or
/// `input.length` if no newline is found. The returned offset points
/// at the `\n` itself; the caller advances past it.
int _findNewline(String input, int offset) {
  for (var i = offset; i < input.length; i++) {
    if (input.codeUnitAt(i) == 0x0a) return i;
  }
  return input.length;
}

/// Reconstructs [error] with its [Location] shifted to refer to the
/// original input at `lineStart + originalOffset`, resolved through
/// [lineIndex] so the returned [Location] carries precomputed line
/// and column. Preserves the concrete [ParseError] subtype.
ParseError _relocate(ParseError error, LineIndex lineIndex, int lineStart) {
  final newLocation = lineIndex.locationAt(lineStart + error.location.offset);
  return switch (error) {
    Unexpected(:final found, :final expected) => Unexpected(
      found,
      expected,
      newLocation,
    ),
    EndOfInput(:final expected) => EndOfInput(expected, newLocation),
    CustomError(:final message) => CustomError(message, newLocation),
  };
}
