/// Format parser benchmarks: CSV, TOML, XML throughput.
library;

import 'package:rumil_parsers/rumil_parsers.dart';

import 'package:rumil_bench/format_data.dart';
import 'package:rumil_bench/harness.dart';

void main() {
  final csvS = csvSmall();
  final csvL = csvLarge();
  final tomlS = tomlSmall();
  final tomlL = tomlLarge();
  final xmlS = xmlSmall();
  final xmlL = xmlLarge();

  print('=== Format parser benchmarks ===');

  print('');
  print('CSV (100 rows, ${csvS.length} bytes):');
  benchWithSize(
    'csv',
    () => parseCsv(csvS),
    csvS.length,
    warmUp: 200,
    iterations: 2000,
  );

  print('CSV (1000 rows, ${csvL.length} bytes):');
  benchWithSize(
    'csv',
    () => parseCsv(csvL),
    csvL.length,
    warmUp: 50,
    iterations: 500,
  );

  print('');
  print('TOML (config, ${tomlS.length} bytes):');
  benchWithSize(
    'toml',
    () => parseToml(tomlS),
    tomlS.length,
    warmUp: 200,
    iterations: 2000,
  );

  print('TOML (50 services, ${tomlL.length} bytes):');
  benchWithSize(
    'toml',
    () => parseToml(tomlL),
    tomlL.length,
    warmUp: 50,
    iterations: 500,
  );

  print('');
  print('XML (20 elements, ${xmlS.length} bytes):');
  benchWithSize(
    'xml',
    () => parseXml(xmlS),
    xmlS.length,
    warmUp: 200,
    iterations: 2000,
  );

  print('XML (200 elements, ${xmlL.length} bytes):');
  benchWithSize(
    'xml',
    () => parseXml(xmlL),
    xmlL.length,
    warmUp: 50,
    iterations: 500,
  );
}
