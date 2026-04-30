import 'package:rumil_tokens/rumil_tokens.dart';

void main() {
  const source = '''
void main() {
  final x = 42;
  // greeting
  print("hello \$x");
}
''';

  final tokens = tokenize(source, dart);

  for (final token in tokens) {
    final kind = switch (token) {
      Keyword() => 'keyword',
      TypeName() => 'type',
      StringLit() => 'string',
      NumberLit() => 'number',
      Comment() => 'comment',
      Annotation() => 'annotation',
      Punctuation() => 'punct',
      Operator() => 'op',
      Variable() => 'var',
      Identifier() => 'ident',
      Whitespace() => 'ws',
      Plain() => 'plain',
    };
    if (token is! Whitespace) {
      print('$kind: ${token.text}');
    }
  }
}
