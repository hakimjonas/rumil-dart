/// Memory + wall-clock probe for the Pratt parser at increasing depths.
///
/// Spawns one child Dart process per (parser × depth) cell. The child runs
/// a single parse, then prints `maxRss=<bytes>` and `elapsedUs=<int>` and
/// exits, so each cell's resident set is measured in isolation (no
/// monotonic carry-over from earlier sub-benchmarks).
///
/// Run as:
///
///   dart run bin/probe_pratt_memory.dart
///
/// To run a single cell directly (used by the parent process):
///
///   `dart run bin/probe_pratt_memory.dart child <pratt|chainl> <depth>`
library;

import 'dart:io';

import 'package:rumil/rumil.dart';

void main(List<String> args) async {
  if (args.length == 3 && args.first == 'child') {
    _runChild(args[1], int.parse(args[2]));
    return;
  }
  await _runParent();
}

Future<void> _runParent() async {
  const depths = [1000, 10000, 100000, 1000000];
  const parsers = ['pratt', 'chainl'];

  print('=== Pratt vs chainl1 memory + wall-clock at depth ===');
  print('');
  print('  depth       parser      maxRss        time');
  print('  ----------  ----------  ------------  --------');

  final script = Platform.script.toFilePath();
  for (final depth in depths) {
    for (final parser in parsers) {
      final result = await Process.run('dart', [
        'run',
        script,
        'child',
        parser,
        '$depth',
      ]);
      final out = result.stdout as String;
      final err = result.stderr as String;
      if (result.exitCode != 0) {
        final reason = err.contains('Stack Overflow')
            ? 'StackOverflow'
            : 'failed (exit ${result.exitCode})';
        print(
          '  ${_pad('$depth', 10)}  ${_pad(parser, 10)}  '
          '${_pad(reason, 12)}  ${_pad('—', 8)}',
        );
        continue;
      }
      final rss = RegExp(r'maxRss=(\d+)').firstMatch(out)?.group(1) ?? '?';
      final us = RegExp(r'elapsedUs=(\d+)').firstMatch(out)?.group(1) ?? '?';
      print(
        '  ${_pad('$depth', 10)}  ${_pad(parser, 10)}  '
        '${_pad(_fmtBytes(int.tryParse(rss)), 12)}  '
        '${_pad(_fmtUs(int.tryParse(us)), 8)}',
      );
    }
    print('');
  }
}

void _runChild(String parser, int depth) {
  final input = List<String>.filled(depth, '1').join('+');
  final num = digit().map(int.parse);

  final Parser<ParseError, int> p;
  switch (parser) {
    case 'pratt':
      p = pratt<int>(num, [
        InfixLeft(char('+'), 10, (int a, int b) => a + b),
      ]);
    case 'chainl':
      final addOp = char('+').map((_) => (int a, int b) => a + b);
      p = num.chainl1(addOp);
    default:
      stderr.writeln('unknown parser: $parser');
      exitCode = 2;
      return;
  }

  // Warm dispatch caches without inflating peak heap (small input).
  p.run('1');

  final sw = Stopwatch()..start();
  final r = p.run(input);
  sw.stop();
  if (r is! Success<ParseError, int>) {
    stderr.writeln('parse failed: $r');
    exitCode = 1;
    return;
  }
  if (r.value != depth) {
    stderr.writeln('wrong sum: ${r.value} vs $depth');
    exitCode = 1;
    return;
  }
  print('maxRss=${ProcessInfo.maxRss}');
  print('elapsedUs=${sw.elapsedMicroseconds}');
}

String _pad(String s, int n) => s.padRight(n);

String _fmtBytes(int? bytes) {
  if (bytes == null) return '?';
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
}

String _fmtUs(int? us) {
  if (us == null) return '?';
  if (us < 1000) return '$us μs';
  if (us < 1000000) return '${(us / 1000).toStringAsFixed(1)}ms';
  return '${(us / 1000000).toStringAsFixed(2)}s';
}
