/// Spanned token: a [Token] paired with byte offsets into the source.
library;

import 'token.dart';

/// A [Token] with byte offsets into the original source string.
///
/// The interval `[start, end)` is half-open. `source.substring(start, end)`
/// reconstructs the token's text:
///
/// ```dart
/// final spans = tokenizeSpans(source, grammar);
/// for (final s in spans) {
///   assert(source.substring(s.start, s.end) == s.token.text);
/// }
/// ```
///
/// Callers needing line/column can construct a `Location(source, offset)`
/// from `rumil`.
extension type const Spanned<T extends Token>._((T, int, int) _) {
  /// Creates a spanned token covering the half-open interval `[start, end)`.
  const Spanned.of(T token, int start, int end) : this._((token, start, end));

  /// The classified token.
  T get token => _.$1;

  /// Byte offset of the first character of [token] in the original source.
  int get start => _.$2;

  /// Byte offset one past the last character of [token] in the original source.
  int get end => _.$3;

  /// Length of the span in code units: `end - start`.
  int get length => _.$3 - _.$2;
}
