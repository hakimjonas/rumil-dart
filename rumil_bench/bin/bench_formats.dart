/// Format parser benchmarks: all 7 rumil_parsers formats.
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
  final yamlS = yamlSmall();
  final yamlL = yamlLarge();
  final hclS = hclSmall();
  final hclL = hclLarge();
  final protoS = protoSmall();
  final protoL = protoLarge();

  print('=== Format parser benchmarks ===');

  print('');
  print('--- JSON ---');
  final jsonS = '{"name":"Alice","age":30,"items":[1,2,3],"nested":{"x":1}}';
  benchWithSize(
    'json-small ',
    () => parseJson(jsonS),
    jsonS.length,
    warmUp: 200,
    iterations: 10000,
  );

  print('');
  print('--- Delimited (CSV) ---');
  benchWithSize(
    'csv-100    ',
    () => parseDelimited(csvS),
    csvS.length,
    warmUp: 200,
    iterations: 2000,
  );
  benchWithSize(
    'csv-1000   ',
    () => parseDelimited(csvL),
    csvL.length,
    warmUp: 50,
    iterations: 500,
  );

  print('');
  print('--- TOML ---');
  benchWithSize(
    'toml-config',
    () => parseToml(tomlS),
    tomlS.length,
    warmUp: 200,
    iterations: 2000,
  );
  benchWithSize(
    'toml-50svc ',
    () => parseToml(tomlL),
    tomlL.length,
    warmUp: 50,
    iterations: 500,
  );

  print('');
  print('--- XML ---');
  benchWithSize(
    'xml-20elem ',
    () => parseXml(xmlS),
    xmlS.length,
    warmUp: 200,
    iterations: 2000,
  );
  benchWithSize(
    'xml-200elem',
    () => parseXml(xmlL),
    xmlL.length,
    warmUp: 50,
    iterations: 500,
  );

  print('');
  print('--- YAML ---');
  benchWithSize(
    'yaml-config',
    () => parseYaml(yamlS),
    yamlS.length,
    warmUp: 200,
    iterations: 2000,
  );
  benchWithSize(
    'yaml-100svc',
    () => parseYaml(yamlL),
    yamlL.length,
    warmUp: 50,
    iterations: 500,
  );

  print('');
  print('--- HCL ---');
  benchWithSize(
    'hcl-config ',
    () => parseHcl(hclS),
    hclS.length,
    warmUp: 200,
    iterations: 2000,
  );
  benchWithSize(
    'hcl-50res  ',
    () => parseHcl(hclL),
    hclL.length,
    warmUp: 50,
    iterations: 500,
  );

  print('');
  print('--- Proto3 ---');
  benchWithSize(
    'proto-small',
    () => parseProto(protoS),
    protoS.length,
    warmUp: 200,
    iterations: 2000,
  );
  benchWithSize(
    'proto-50msg',
    () => parseProto(protoL),
    protoL.length,
    warmUp: 50,
    iterations: 500,
  );
}
