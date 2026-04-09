/// Petitparser JSON parser for fair comparison with Rumil.
library;

import 'package:petitparser/petitparser.dart';

final Parser<dynamic> petitJson = _buildJsonParser();

Parser<dynamic> _buildJsonParser() {
  final jsonValue = undefined<dynamic>();

  final jsonNull = string('null').map<dynamic>((_) => null);

  final jsonBool =
      string('true').map<dynamic>((_) => true) |
      string('false').map<dynamic>((_) => false);

  final jsonNumber = (char('-').optional() &
          digit().plus() &
          (char('.') & digit().plus()).optional() &
          (pattern('eE') & pattern('+-').optional() & digit().plus())
              .optional())
      .flatten()
      .trim()
      .map<dynamic>(num.parse);

  final jsonStringContent = (char('\\') & any() | char('"').neg()).star();

  final jsonString = (char('"') & jsonStringContent & char('"')).map<dynamic>(
    (List<dynamic> seq) => (seq[1] as List<dynamic>).join(),
  );

  final jsonArray =
      char('[').trim() &
      jsonValue
          .starSeparated<dynamic>(char(',').trim())
          .map<dynamic>((SeparatedList<dynamic, dynamic> sl) => sl.elements) &
      char(']').trim();

  final jsonMember = jsonString.trim() & char(':').trim() & jsonValue;

  final jsonObject =
      char('{').trim() &
      jsonMember
          .starSeparated<dynamic>(char(',').trim())
          .map<dynamic>(
            (SeparatedList<dynamic, dynamic> sl) =>
                Map<String, dynamic>.fromEntries(
                  sl.elements.map((dynamic m) {
                    final parts = m as List<dynamic>;
                    return MapEntry<String, dynamic>(
                      parts[0] as String,
                      parts[2],
                    );
                  }),
                ),
          ) &
      char('}').trim();

  jsonValue.set(
    jsonNull |
        jsonBool |
        jsonNumber |
        jsonString.trim() |
        jsonArray.map<dynamic>((List<dynamic> l) => l[1]) |
        jsonObject.map<dynamic>((List<dynamic> l) => l[1]),
  );

  return jsonValue.end();
}
