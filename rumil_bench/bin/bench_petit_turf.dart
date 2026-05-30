/// Apples-to-apples head-to-head: rumil vs petitparser vs dart:convert.
///
/// FAIRNESS DISCIPLINE (the whole point of this file):
///  - EACH LIBRARY'S OWN IDIOMATIC PARSER on petitparser's OWN canonical
///    grammars + inputs. petit JSON = `JsonDefinition` from
///    petitparser_examples; petit CSV = `CsvDefinition`; petit typed-JSON =
///    `petitJsonTyped` (a hand grammar that builds rumil's `JsonValue`, with
///    escape decoding so its output is genuinely equal). Inputs are
///    petitparser's own benchmark constants, verbatim.
///  - SAME OUTPUT per compared pair, VERIFIED EQUAL at runtime before timing
///    (see `_verifyJson`/`_verifyCsv`), so we never time a parser doing less.
///  - TWO HONEST JSON AXES, because rumil and petit make different
///    architectural choices:
///      * to-native  : plain Map/List/num.  rumil pays parse→JsonValue THEN
///        jsonToNative (TWO passes — its PL-grade always-build-a-typed-tree
///        cost); petit `JsonDefinition` builds Map/List in ONE pass; SDK
///        `json.decode` is the baseline.
///      * to-typed   : a typed AST (rumil `JsonValue`).  rumil parseJson and
///        petit `petitJsonTyped` are BOTH one pass to the same JsonValue —
///        this isolates the parser ENGINE from the convert cost.
///    Reporting only one would mislead: to-native flatters petit (rumil does
///    2 passes), to-typed is the fair engine-vs-engine number.
///  - BOTH INPUT REGIMES: petitparser's tiny number-dense constants (per-parse
///    dispatch overhead) AND a large document (sustained throughput). The ratio
///    differs enormously; both are reported rather than cherry-picked.
///  - FAIR TIMING: every parser is warmed on every input before any timing, and
///    the run order is rotated per input, so no parser eats a cold-start cost
///    or a systematic first-runner penalty.
///
/// Run under all three Dart execution modes — they diverge by ~3×:
///   JIT : dart run bin/bench_petit_turf.dart
///   AOT : dart compile exe ... && run
///   WASM: dart compile wasm ... && deno run tool/run_wasm.mjs ...
library;

import 'dart:convert';

import 'package:petitparser_examples/csv.dart' show CsvDefinition;
import 'package:petitparser_examples/json.dart' show JsonDefinition;
import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';

import 'package:rumil_bench/petitparser_json_typed.dart';

// --- petitparser's own JSON benchmark inputs (verbatim) ---

const String jsonArray =
    '[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]';
const String jsonObject =
    '{"a": 1, "b": 2, "c": 3, "d": 4, "e": 5, "f": 6, "g": 7}';
const String jsonEvent =
    '{"type": "change", "eventPhase": 2, "bubbles": true, "cancelable": true, '
    '"timeStamp": 1484904741000, "defaultPrevented": false, "isTrusted": true, '
    '"eventType": "HTMLEvents", "altKey": false, "ctrlKey": false, '
    '"metaKey": false, "shiftKey": false, "button": 0, "buttons": 0, '
    '"clientX": 0, "clientY": 0, "screenX": 0, "screenY": 0, "detail": 0, '
    '"keyCode": 0, "charCode": 0, "which": 0, "MOUSEDOWN": 1, "MOUSEUP": 2, '
    '"MOUSEOVER": 4, "MOUSEOUT": 8, "MOUSEMOVE": 16, "MOUSEDRAG": 32, '
    '"CLICK": 64, "DBLCLICK": 128, "KEYDOWN": 256, "KEYUP": 512, '
    '"KEYPRESS": 1024, "DRAGDROP": 2048, "FOCUS": 4096, "BLUR": 8192, '
    '"SELECT": 16384, "CHANGE": 32768}';
const String jsonNested =
    '{"items":{"item":[{"id":"0001","type":"donut","name":"Cake",'
    '"ppu":0.55,"batters":{"batter":[{"id":"1001","type":"Regular"},'
    '{"id":"1002","type":"Chocolate"},{"id":"1003","type":"Blueberry"},'
    '{"id":"1004","type":"Devils Food"}]},"topping":[{"id":"5001",'
    '"type":"None"},{"id":"5002","type":"Glazed"},{"id":"5005",'
    '"type":"Sugar"},{"id":"5007","type":"Powdered Sugar"},{"id":"5006",'
    '"type":"Chocolate with Sprinkles"},{"id":"5003","type":"Chocolate"},'
    '{"id":"5004","type":"Maple"}]}]}}';

/// Large document: the donut fixture in a 100-element array (sustained
/// throughput, not per-parse setup).
String largeJson() => '[${List.filled(100, jsonNested).join(',')}]';

/// A plain CSV document (unquoted simple fields) — the subset rumil's and
/// petit's CSV grammars treat identically, verified at runtime. Quoting/escape
/// semantics differ between the two grammars, so we benchmark only the common
/// subset rather than paper over a real semantic divergence.
String csvDoc(int rows) =>
    List.generate(
      rows,
      (i) => 'field$i,value$i,123$i,plain$i,col$i',
    ).join('\n');

final _petitJson = JsonDefinition().build();
final _petitCsv = CsvDefinition().build();

// ---- rumil entry points ----

JsonValue _rumilParse(String x) => switch (parseJson(x)) {
  Success<ParseError, JsonValue>(:final value) => value,
  Partial<ParseError, JsonValue>(:final value) => value,
  Failure() => throw StateError('rumil JSON parse failed'),
};

Object? _rumilJsonNative(String x) => jsonToNative(_rumilParse(x));

List<List<String>> _rumilCsv(String x) => switch (parseCsv(x)) {
  Success<ParseError, DelimitedDocument>(:final value) => value,
  Partial<ParseError, DelimitedDocument>(:final value) => value,
  Failure() => throw StateError('rumil CSV parse failed'),
};

// ---- correctness gates ----

void _verifyJson(String name, String input) {
  // to-native: rumil(2-pass) == petit JsonDefinition == json.decode
  final rn = json.encode(_rumilJsonNative(input));
  final pn = json.encode(_petitJson.parse(input).value);
  final sn = json.encode(json.decode(input));
  if (rn != pn || rn != sn) {
    throw StateError('to-native mismatch on "$name"');
  }
  // to-typed: rumil parseJson == petitJsonTyped (compare via toString of the
  // JsonValue, which both produce).
  final rt = _rumilParse(input).toString();
  final pt = (petitJsonTyped.parse(input).value).toString();
  if (rt != pt) {
    throw StateError('to-typed mismatch on "$name":\n  rumil: $rt\n  petit: $pt');
  }
}

void _verifyCsv(String name, String input) {
  final r = _rumilCsv(input).toString();
  final p = (_petitCsv.parse(input).value).toString();
  if (r != p) {
    throw StateError('CSV mismatch on "$name":\n  rumil: $r\n  petit: $p');
  }
}

/// μs/op over [iters] (no internal warmup; global warmup done in [main]).
double _time(void Function() body, int iters) {
  final sw = Stopwatch()..start();
  for (var i = 0; i < iters; i++) {
    body();
  }
  sw.stop();
  return sw.elapsedMicroseconds / iters;
}

void main() {
  final jsonInputs = <String, String>{
    'array16': jsonArray,
    'object7': jsonObject,
    'event(636B)': jsonEvent,
    'donut(477B)': jsonNested,
    'large(~48KB)': largeJson(),
  };
  final csvInputs = <String, String>{
    'csv-10': csvDoc(10),
    'csv-1000': csvDoc(1000),
  };

  for (final e in jsonInputs.entries) {
    _verifyJson(e.key, e.value);
  }
  for (final e in csvInputs.entries) {
    _verifyCsv(e.key, e.value);
  }

  // Warm every parser on every input before timing anything.
  for (var w = 0; w < 1000; w++) {
    for (final x in jsonInputs.values) {
      _rumilParse(x);
      _rumilJsonNative(x);
      _petitJson.parse(x);
      petitJsonTyped.parse(x);
      json.decode(x);
    }
    for (final x in csvInputs.values) {
      _rumilCsv(x);
      _petitCsv.parse(x);
    }
  }

  print('output equality verified (to-native and to-typed); all parsers warmed');
  print('');
  print('=== JSON to-typed (engine vs engine: both build a typed JsonValue) ===');
  print('rumil-parse = parseJson(x)            petit-typed = petitJsonTyped');
  _runMatrix(jsonInputs, [
    ('rumil-parse', (x) => _rumilParse(x)),
    ('petit-typed', (x) => petitJsonTyped.parse(x)),
  ]);

  print('=== JSON to-native (plain Map/List; rumil pays 2 passes) ===');
  print('rumil-native = jsonToNative(parseJson(x))   petit = JsonDefinition');
  _runMatrix(jsonInputs, [
    ('rumil-nativ', (x) => _rumilJsonNative(x)),
    ('petit-nativ', (x) => _petitJson.parse(x)),
    ('sdk-decode ', (x) => json.decode(x)),
  ]);

  print('=== CSV (both build List<List<String>>) ===');
  _runMatrix(csvInputs, [
    ('rumil', (x) => _rumilCsv(x)),
    ('petit', (x) => _petitCsv.parse(x)),
  ]);
}

void _runMatrix(
  Map<String, String> inputs,
  List<(String, void Function(String))> runners,
) {
  var rot = 0;
  for (final MapEntry(key: name, value: input) in inputs.entries) {
    final iters = input.length > 5000 ? 1000 : 50000;
    print('$name (${input.length} B):');
    final results = <(String, double)>[];
    for (var k = 0; k < runners.length; k++) {
      final (label, fn) = runners[(rot + k) % runners.length];
      results.add((label, _time(() => fn(input), iters)));
    }
    rot++;
    for (final (label, _) in runners) {
      final us = results.firstWhere((r) => r.$1 == label).$2;
      print('  $label: ${us.toStringAsFixed(2)} μs/op');
    }
    print('');
  }
}
