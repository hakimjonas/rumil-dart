/// Benchmark 1: Rumil vs petitparser — JSON parsing.
///
/// Three comparisons for fairness:
/// - petitparser (raw): returns dynamic — baseline parse cost
/// - petitparser (typed): builds JsonValue AST — parse + AST construction
/// - Rumil: builds JsonValue AST — total cost
///
/// The real parser overhead is Rumil vs petitparser-typed.
/// The difference between petitparser-raw and petitparser-typed is the AST
/// construction cost that any typed parser pays.
library;

import 'package:rumil_parsers/rumil_parsers.dart';

import 'package:rumil_bench/harness.dart';
import 'package:rumil_bench/json_data.dart';
import 'package:rumil_bench/petitparser_json.dart';
import 'package:rumil_bench/petitparser_json_typed.dart';

void main() {
  final small = jsonSmall();
  final medium = jsonMedium();
  final large = jsonLarge();

  print('=== Rumil vs petitparser: JSON parsing ===');
  print('');
  print('petit-raw  = petitparser returning raw dynamic');
  print(
    'petit-typed = petitparser building JsonValue AST (same output as Rumil)',
  );
  print('rumil      = Rumil building JsonValue AST');
  print('');

  print('Small (${small.length} bytes):');
  benchWithSize(
    'petit-raw  ',
    () => petitJson.parse(small),
    small.length,
    iterations: 100000,
  );
  benchWithSize(
    'petit-typed',
    () => petitJsonTyped.parse(small),
    small.length,
    iterations: 100000,
  );
  benchWithSize(
    'rumil      ',
    () => parseJson(small),
    small.length,
    iterations: 100000,
  );

  print('');
  print('Medium (${medium.length} bytes):');
  benchWithSize(
    'petit-raw  ',
    () => petitJson.parse(medium),
    medium.length,
    iterations: 1000,
  );
  benchWithSize(
    'petit-typed',
    () => petitJsonTyped.parse(medium),
    medium.length,
    iterations: 1000,
  );
  benchWithSize(
    'rumil      ',
    () => parseJson(medium),
    medium.length,
    iterations: 1000,
  );

  print('');
  print('Large (${large.length} bytes):');
  benchWithSize(
    'petit-raw  ',
    () => petitJson.parse(large),
    large.length,
    iterations: 100,
  );
  benchWithSize(
    'petit-typed',
    () => petitJsonTyped.parse(large),
    large.length,
    iterations: 100,
  );
  benchWithSize(
    'rumil      ',
    () => parseJson(large),
    large.length,
    iterations: 100,
  );
}
