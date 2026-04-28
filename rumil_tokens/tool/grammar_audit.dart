// Diagnostic probe: dumps the token stream produced by each built-in
// grammar for a fixed set of inputs.
//
// Run: dart run tool/grammar_audit.dart

import 'package:rumil_tokens/rumil_tokens.dart';

void dump(String label, String src, LangGrammar g) {
  print('--- $label ---');
  print('  source: ${src.replaceAll("\n", r"\n")}');
  for (final t in tokenize(src, g)) {
    if (t is Whitespace) continue;
    print('  ${t.runtimeType.toString().padRight(12)} ${t.text}');
  }
  print('');
}

void main() {
  dump('dart raw string', r"final r = r'no\escape';", dart);
  dump('dart interp \$var', r'final s = "hi $name";', dart);
  dump('dart interp \${expr}', r'final s = "hi ${name.x}";', dart);
  dump('dart negative num', 'final n = -42;', dart);
  dump('dart records', 'final r = (1, "x");', dart);
  dump('dart triple-single raw', r"final r = r'''no\escape''';", dart);

  dump('scala s-string', r'val s = s"hi $name"', scala);
  dump('scala f-string', r'val f = f"$x%.2f"', scala);
  dump('scala backtick ident', 'val `type` = 1', scala);
  dump('scala symbol literal', "val s = 'sym", scala);

  dump('yaml block |', 'text: |\n  hello\n  world\n', yaml);
  dump('yaml block >', 'text: >\n  folded\n  lines\n', yaml);
  dump('yaml anchor/ref', 'foo: &a 1\nbar: *a\n', yaml);
  dump('yaml doc sep', '---\nkey: value\n', yaml);
  dump('yaml plain scalar', 'key: value\n', yaml);
  dump('yaml flow seq', '[1, 2, 3]\n', yaml);
  dump('yaml flow map', '{a: 1}\n', yaml);

  dump('json hex', '{"n": 0xFF}', json);
  dump('json negative num', '{"n": -1}', json);
  dump('json line-comment', '{"a": 1} // c', json);
  dump('json exponent', '{"n": 1e10}', json);

  dump('sh variable', r'echo $HOME', shell);
  dump('sh var braces', r'echo ${HOME}', shell);
  dump('sh command sub', r'echo $(ls)', shell);
  dump('sh backtick sub', 'echo `ls`', shell);
  dump('sh heredoc', 'cat <<EOF\nbody\nEOF\n', shell);
  dump('sh fn def', 'greet() { echo hi; }', shell);
  dump('sh test brackets', '[ -f "x" ]', shell);
  dump('sh arithmetic', r'x=$((1+2))', shell);
}
