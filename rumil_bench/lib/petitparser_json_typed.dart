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
      .map<JsonValue>((String s) => JsonNumber(double.parse(s)));

  final jsonStringContent = (char('\\') & any() | char('"').neg()).star();

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
