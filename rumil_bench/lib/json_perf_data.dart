/// JSON workloads tuned to exercise the rumil_parsers 0.8.0 perf
/// changes (capture-based number/string parsing, JsonInt/JsonDouble
/// split, `_lex` cleanup). Sibling to `json_data.dart`'s realistic
/// shapes; these are deliberately unbalanced to surface specific
/// code paths.
library;

/// 50k-element list of integers. Exercises the JsonInt fast track in
/// `_jsonNumber`: every token takes the `int.tryParse` success path,
/// no float fall-through.
String intHeavyJson() {
  final buf = StringBuffer('[');
  for (var i = 0; i < 50000; i++) {
    if (i > 0) buf.write(',');
    buf.write(i);
  }
  buf.write(']');
  return buf.toString();
}

/// 50k-element list of floats with a fractional part. Exercises the
/// JsonDouble path; the int.tryParse short-circuit never fires.
String floatHeavyJson() {
  final buf = StringBuffer('[');
  for (var i = 0; i < 50000; i++) {
    if (i > 0) buf.write(',');
    buf.write('${i + 0.1}');
  }
  buf.write(']');
  return buf.toString();
}

/// 50k records with int / string / bool fields. Roughly the shape of
/// an API-response listing: exercises every parser path (numbers,
/// strings, bools, the firstCharChoice dispatch, object construction)
/// in proportion to a realistic mixed workload.
String mixedJson() {
  final buf = StringBuffer('[');
  for (var i = 0; i < 50000; i++) {
    if (i > 0) buf.write(',');
    buf.write('{"id":');
    buf.write(i);
    buf.write(',"name":"user_');
    buf.write(i);
    buf.write('","active":');
    buf.write(i % 5 != 0);
    buf.write(',"score":');
    buf.write(i % 100);
    buf.write('}');
  }
  buf.write(']');
  return buf.toString();
}
