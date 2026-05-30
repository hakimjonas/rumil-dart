/// CPU profiler for the JSON parse hot path.
///
/// Connects to the VM service, runs a tight loop of large-doc parses while
/// sampling the CPU, then reports functions by EXCLUSIVE self-time (ticks
/// where that function was on top of the stack). This finds where cycles go
/// per parser step — the dispatch cost — as opposed to allocation.
///
/// Run:  dart run --observe bin/profile_cpu.dart [parse|native|petit]
library;

import 'dart:developer' as developer;
import 'dart:io';

import 'package:petitparser_examples/json.dart' show JsonDefinition;
import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:vm_service/vm_service.dart' as vms;
import 'package:vm_service/vm_service_io.dart';

import 'package:rumil_bench/json_data.dart';

final String _large = jsonLarge();
final _petit = JsonDefinition().build();

JsonValue _force(Result<ParseError, JsonValue> r) => switch (r) {
  Success<ParseError, JsonValue>(:final value) => value,
  Partial<ParseError, JsonValue>(:final value) => value,
  Failure() => throw StateError('parse failed'),
};

void _work(String mode, int iters) {
  switch (mode) {
    case 'native':
      for (var i = 0; i < iters; i++) {
        jsonToNative(_force(parseJson(_large)));
      }
    case 'petit':
      for (var i = 0; i < iters; i++) {
        _petit.parse(_large);
      }
    default:
      for (var i = 0; i < iters; i++) {
        _force(parseJson(_large));
      }
  }
}

Future<void> main(List<String> args) async {
  final mode = args.isNotEmpty ? args.first : 'parse';

  final info = await developer.Service.getInfo();
  final uri = info.serverUri;
  if (uri == null) {
    stderr.writeln('Run with: dart run --observe bin/profile_cpu.dart [mode]');
    exit(2);
  }
  final wsUri = uri.replace(scheme: 'ws', path: '${uri.path}ws').toString();
  final service = await vmServiceConnectUri(wsUri);
  final vm = await service.getVM();
  final isolateId = vm.isolates!.first.id!;

  // Warm up (let JIT tier up), then clear samples and run the measured window.
  _work(mode, 50);
  await service.clearCpuSamples(isolateId);

  final sw = Stopwatch()..start();
  _work(mode, 500);
  sw.stop();

  // Fetch all samples since the clear. Use a wide-but-sane window (1 hour).
  final samples = await service.getCpuSamples(isolateId, 0, 3600 * 1000000);
  final functions = samples.functions ?? <vms.ProfileFunction>[];
  stderr.writeln('DIAG: sampleCount=${samples.sampleCount} '
      'samples.list=${samples.samples?.length} functions=${functions.length}');

  // Exclusive self-time: count ticks where a function is the TOP frame.
  final selfTicks = <String, int>{};
  var total = 0;
  for (final s in samples.samples ?? <vms.CpuSample>[]) {
    final stack = s.stack ?? <int>[];
    if (stack.isEmpty) continue;
    total++;
    final name = _frameName(functions[stack.first]);
    selfTicks[name] = (selfTicks[name] ?? 0) + 1;
  }

  final sorted = selfTicks.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  print('=== CPU self-time: mode=$mode, ${sw.elapsedMilliseconds}ms, '
      '$total samples ===');
  print('  self%   ticks  function');
  for (final e in sorted.take(30)) {
    final pct = (100.0 * e.value / total).toStringAsFixed(1).padLeft(5);
    print('  $pct%  ${e.value.toString().padLeft(6)}  ${e.key}');
  }
  await service.dispose();
  exit(0);
}

String _frameName(vms.ProfileFunction fn) {
  final f = fn.function;
  String owner = '';
  String name = '?';
  if (f is vms.FuncRef) {
    name = f.name ?? '?';
    final scriptUri = f.location?.script?.uri;
    if (scriptUri != null) owner = scriptUri.split('/').last;
  } else if (f is vms.NativeFunction) {
    name = f.name ?? 'native';
  }
  return owner.isEmpty ? name : '$owner:$name';
}
