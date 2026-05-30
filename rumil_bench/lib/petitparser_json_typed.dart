/// Petitparser JSON parser that builds typed JsonValue AST — same output
/// as Rumil's parseJson, for fair comparison of parser overhead vs AST cost.
library;

import 'package:petitparser/petitparser.dart';
import 'package:rumil_parsers/rumil_parsers.dart';

final Parser<JsonValue> petitJsonTyped = _buildTypedJsonParser();

Parser<JsonValue> _buildTypedJsonParser() {
  final jsonValue = undefined<JsonValue>();

  final jsonNull = string('null').map<JsonValue>((_) => const JsonNull());

  final jsonBool =
      string('true').map<JsonValue>((_) => const JsonBool(true)) |
      string('false').map<JsonValue>((_) => const JsonBool(false));

  final jsonNumber = (char('-').optional() &
          digit().plus() &
          (char('.') & digit().plus()).optional() &
          (pattern('eE') & pattern('+-').optional() & digit().plus())
              .optional())
      .flatten()
      .trim()
      .map<JsonValue>((String s) {
        if (!s.contains('.') && !s.contains('e') && !s.contains('E')) {
          final i = int.tryParse(s);
          if (i != null) return JsonInt(i);
        }
        return JsonDouble(double.parse(s));
      });

  // Decode escape sequences (like rumil does) so the produced JsonValue is
  // genuinely output-equal on inputs containing escapes — required for a fair
  // engine-vs-engine comparison, not just on escape-free inputs.
  final escape =
      (char('\\') &
              (char('"').map((_) => '"') |
                  char('\\').map((_) => '\\') |
                  char('/').map((_) => '/') |
                  char('b').map((_) => '\b') |
                  char('f').map((_) => '\f') |
                  char('n').map((_) => '\n') |
                  char('r').map((_) => '\r') |
                  char('t').map((_) => '\t') |
                  (char('u') & pattern('0-9a-fA-F').times(4).flatten()).map(
                    (dynamic v) => String.fromCharCode(
                      int.parse((v as List)[1] as String, radix: 16),
                    ),
                  )))
          .map<String>((dynamic v) => (v as List)[1] as String);

  final jsonStringContent =
      (escape | char('"').neg().map<String>((dynamic c) => c as String)).star();

  final jsonStringRaw = (char('"') & jsonStringContent & char('"')).map<String>(
    (List<dynamic> seq) => (seq[1] as List<dynamic>).join(),
  );

  final jsonStringValue = jsonStringRaw.map<JsonValue>(
    (String s) => JsonString(s),
  );

  final jsonArray =
      char('[').trim() &
      jsonValue
          .starSeparated<dynamic>(char(',').trim())
          .map<dynamic>((SeparatedList<JsonValue, dynamic> sl) => sl.elements) &
      char(']').trim();

  final jsonMember = jsonStringRaw.trim() & char(':').trim() & jsonValue;

  final jsonObject =
      char('{').trim() &
      jsonMember
          .starSeparated<dynamic>(char(',').trim())
          .map<dynamic>(
            (SeparatedList<dynamic, dynamic> sl) =>
                sl.elements.map((dynamic m) {
                  final parts = m as List<dynamic>;
                  return MapEntry<String, JsonValue>(
                    parts[0] as String,
                    parts[2] as JsonValue,
                  );
                }),
          ) &
      char('}').trim();

  final jsonArrayValue = jsonArray.map<JsonValue>(
    (List<dynamic> l) => JsonArray((l[1] as Iterable<JsonValue>).toList()),
  );

  final jsonObjectValue = jsonObject.map<JsonValue>(
    (List<dynamic> l) => JsonObject(
      Map<String, JsonValue>.fromEntries(
        l[1] as Iterable<MapEntry<String, JsonValue>>,
      ),
    ),
  );

  jsonValue.set(
    (jsonNull |
            jsonBool |
            jsonNumber |
            jsonStringValue.trim() |
            jsonArrayValue |
            jsonObjectValue)
        .cast<JsonValue>(),
  );

  return jsonValue.end();
}
