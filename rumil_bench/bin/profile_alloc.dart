/// Allocation profiler for the JSON parse hot path.
///
/// Connects to the VM service, resets the allocation profile, parses a large
/// JSON document a fixed number of times, then dumps the top classes by total
/// bytes and instance count allocated during that window. This turns "we think
/// it allocates a Result per step" into a measured per-class breakdown.
///
/// Run:  dart run --observe --pause-isolates-on-exit bin/profile_alloc.dart
/// (the script auto-discovers the service URI from the VM).
///
/// Modes (first arg): `parse` (rumil parseJson → JsonValue, default),
/// `native` (rumil jsonToNative∘parseJson), `petit` (petitparser JsonDefinition).
library;

import 'dart:developer' as developer;
import 'dart:io';

import 'package:petitparser_examples/json.dart' show JsonDefinition;
import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:vm_service/vm_service.dart' as vms;
import 'package:vm_service/vm_service_io.dart';

const String _donut =
    '{"items":{"item":[{"id":"0001","type":"donut","name":"Cake",'
    '"ppu":0.55,"batters":{"batter":[{"id":"1001","type":"Regular"},'
    '{"id":"1002","type":"Chocolate"},{"id":"1003","type":"Blueberry"},'
    '{"id":"1004","type":"Devils Food"}]},"topping":[{"id":"5001",'
    '"type":"None"},{"id":"5002","type":"Glazed"},{"id":"5005",'
    '"type":"Sugar"},{"id":"5007","type":"Powdered Sugar"},{"id":"5006",'
    '"type":"Chocolate with Sprinkles"},{"id":"5003","type":"Chocolate"},'
    '{"id":"5004","type":"Maple"}]}]}}';

final String _large = '[${List.filled(100, _donut).join(',')}]';
final _petit = JsonDefinition().build();

const int _runs = 2000;

void _work(String mode) {
  switch (mode) {
    case 'native':
      for (var i = 0; i < _runs; i++) {
        jsonToNative(_force(parseJson(_large)));
      }
    case 'petit':
      for (var i = 0; i < _runs; i++) {
        _petit.parse(_large);
      }
    default: // parse
      for (var i = 0; i < _runs; i++) {
        _force(parseJson(_large));
      }
  }
}

JsonValue _force(Result<ParseError, JsonValue> r) => switch (r) {
  Success<ParseError, JsonValue>(:final value) => value,
  Partial<ParseError, JsonValue>(:final value) => value,
  Failure() => throw StateError('parse failed'),
};

Future<void> main(List<String> args) async {
  final mode = args.isNotEmpty ? args.first : 'parse';

  final info = await developer.Service.getInfo();
  final uri = info.serverUri;
  if (uri == null) {
    stderr.writeln('Run with: dart run --observe bin/profile_alloc.dart [mode]');
    exit(2);
  }
  final wsUri = uri
      .replace(scheme: 'ws', path: '${uri.path}ws')
      .toString();
  final service = await vmServiceConnectUri(wsUri);
  final vm = await service.getVM();
  final isolateId = vm.isolates!.first.id!;

  // Warm, then reset allocation accounting so we measure only the timed window.
  _work(mode);
  await service.getAllocationProfile(isolateId, reset: true);

  _work(mode);

  final profile = await service.getAllocationProfile(isolateId);
  final members = profile.members ?? [];
  // Sort by bytes accumulated since the reset.
  final scored = members
      .map((m) => (m, _accumBytes(m), _accumCount(m)))
      .where((t) => t.$2 > 0)
      .toList()
    ..sort((a, b) => b.$2.compareTo(a.$2));

  print('=== Allocation profile: mode=$mode, $_runs parses of ${_large.length}B ===');
  print('class                                bytes        count');
  var totBytes = 0, totCount = 0;
  for (final (m, bytes, count) in scored.take(25)) {
    totBytes += bytes;
    totCount += count;
    final name = (m.classRef?.name ?? '?').padRight(34);
    print('$name ${_pad(bytes, 12)} ${_pad(count, 12)}');
  }
  print('--- top-25 total: ${_pad(totBytes, 0)} bytes, $totCount instances ---');
  await service.dispose();
  exit(0);
}

int _accumBytes(vms.ClassHeapStats s) =>
    (s.accumulatedSize ?? s.bytesCurrent ?? 0);
int _accumCount(vms.ClassHeapStats s) =>
    (s.instancesAccumulated ?? s.instancesCurrent ?? 0);

String _pad(int n, int w) => n.toString().padLeft(w);
