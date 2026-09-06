import 'dart:convert';
import 'dart:io';

import 'package:rumil_grammars/rumil_grammars.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('rumil_grammars_cli-');
  });

  tearDown(() {
    workspace.deleteSync(recursive: true);
  });

  test('writes a deterministic grammar.json from an IR document', () {
    final irFile = File('${workspace.path}/grammar.ir.json')
      ..writeAsStringSync(jsonEncode(grammarToJson(_grammar())));
    final out = Directory('${workspace.path}/parser');

    final first = _run(['--input', irFile.path, '--out', out.path]);
    expect(first.exitCode, 0, reason: first.stderr.toString());
    final content = File('${out.path}/grammar.json').readAsStringSync();
    expect(content, startsWith('{\n  "name": "cli_test"'));

    final second = _run(['--input', irFile.path, '--out', out.path]);
    expect(second.exitCode, 0);
    expect(
      File('${out.path}/grammar.json').readAsStringSync(),
      content,
      reason: 'emission must be byte-identical across runs',
    );
  });

  test('exits non-zero and reports validation problems', () {
    final irFile = File('${workspace.path}/broken.ir.json')..writeAsStringSync(
      jsonEncode(
        grammarToJson(
          const Grammar(
            name: 'broken',
            rules: {'start': Rule('start', Ref('nowhere'))},
          ),
        ),
      ),
    );
    final result = _run([
      '--input',
      irFile.path,
      '--out',
      '${workspace.path}/out',
    ]);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('nowhere'));
    expect(File('${workspace.path}/out/grammar.json').existsSync(), isFalse);
  });

  test('fails with usage when arguments are missing', () {
    final result = _run(const []);
    expect(result.exitCode, 2);
    expect(result.stderr, contains('--input'));
  });
}

Grammar _grammar() => const Grammar(
  name: 'cli_test',
  rules: {
    'source_file': Rule('source_file', ZeroOrMore(Ref('word'))),
    'word': Rule.token('word', Pattern(r'\w+')),
  },
  extras: [Pattern(r'\s')],
);

ProcessResult _run(List<String> arguments) => Process.runSync(
  Platform.resolvedExecutable,
  ['run', 'bin/rumil_grammars.dart', ...arguments],
  workingDirectory: Directory.current.path,
);
