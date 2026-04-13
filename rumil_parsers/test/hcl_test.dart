import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

HclDocument doc_(Result<ParseError, HclDocument> r) => switch (r) {
  Success<ParseError, HclDocument>(:final value) => value,
  Partial<ParseError, HclDocument>(:final value) => value,
  Failure() => throw StateError('Expected success, got ${r.errors}'),
};

HclValue _get(HclDocument doc, String key) =>
    doc.firstWhere((e) => e.$1 == key).$2;

void main() {
  group('HCL attributes', () {
    test('string', () {
      final d = doc_(parseHcl('name = "Alice"\n'));
      expect(_get(d, 'name'), const HclString('Alice'));
    });

    test('number', () {
      final d = doc_(parseHcl('port = 8080\n'));
      expect(_get(d, 'port'), const HclNumber(8080));
    });

    test('bool', () {
      final d = doc_(parseHcl('enabled = true\n'));
      expect(_get(d, 'enabled'), const HclBool(true));
    });

    test('null', () {
      final d = doc_(parseHcl('value = null\n'));
      expect(_get(d, 'value'), const HclNull());
    });

    test('list', () {
      final d = doc_(parseHcl('ports = [80, 443]\n'));
      final list = _get(d, 'ports') as HclList;
      expect(list.elements.length, 2);
    });

    test('object', () {
      final d = doc_(parseHcl('tags = { Name = "web" }\n'));
      final obj = _get(d, 'tags') as HclObject;
      expect(obj.fields['Name'], const HclString('web'));
    });

    test('reference', () {
      final d = doc_(parseHcl('value = aws_instance.web.id\n'));
      expect(
        _get(d, 'value'),
        const HclGetAttr(HclGetAttr(HclReference('aws_instance'), 'web'), 'id'),
      );
    });

    test('multiple attributes', () {
      final d = doc_(parseHcl('name = "test"\nport = 8080\n'));
      expect(_get(d, 'name'), const HclString('test'));
      expect(_get(d, 'port'), const HclNumber(8080));
    });
  });

  group('HCL blocks', () {
    test('simple block', () {
      final d = doc_(
        parseHcl('resource "aws_instance" "web" {\n  ami = "abc"\n}\n'),
      );
      final block = _get(d, 'resource') as HclBlock;
      expect(block.type, 'resource');
      expect(block.labels, ['aws_instance', 'web']);
      expect(block.body['ami'], const HclString('abc'));
    });

    test('block with no labels', () {
      final d = doc_(parseHcl('locals {\n  x = 1\n}\n'));
      final block = _get(d, 'locals') as HclBlock;
      expect(block.labels, isEmpty);
      expect(block.body['x'], const HclNumber(1));
    });

    test('nested blocks', () {
      final d = doc_(
        parseHcl(
          'terraform {\n  backend "s3" {\n    bucket = "state"\n  }\n}\n',
        ),
      );
      final tf = _get(d, 'terraform') as HclBlock;
      final backend = tf.body['backend'] as HclBlock;
      expect(backend.labels, ['s3']);
      expect(backend.body['bucket'], const HclString('state'));
    });

    test('multiple blocks with same type', () {
      final d = doc_(
        parseHcl('''
resource "aws_instance" "web" { ami = "abc" }
resource "aws_s3_bucket" "data" { bucket = "my-bucket" }
'''),
      );
      final resources = d.where((e) => e.$1 == 'resource').toList();
      expect(resources.length, 2);
      final web = resources[0].$2 as HclBlock;
      expect(web.labels, ['aws_instance', 'web']);
      final s3 = resources[1].$2 as HclBlock;
      expect(s3.labels, ['aws_s3_bucket', 'data']);
    });
  });

  group('HCL comments', () {
    test('hash comment', () {
      final d = doc_(parseHcl('# comment\nname = "test"\n'));
      expect(_get(d, 'name'), const HclString('test'));
    });

    test('slash comment', () {
      final d = doc_(parseHcl('// comment\nname = "test"\n'));
      expect(_get(d, 'name'), const HclString('test'));
    });

    test('block comment', () {
      final d = doc_(parseHcl('/* comment */\nname = "test"\n'));
      expect(_get(d, 'name'), const HclString('test'));
    });
  });

  group('HCL escape sequences', () {
    test('newline', () {
      final d = doc_(parseHcl('v = "a\\nb"\n'));
      expect((_get(d, 'v') as HclString).value, 'a\nb');
    });

    test('carriage return', () {
      final d = doc_(parseHcl('v = "a\\rb"\n'));
      expect((_get(d, 'v') as HclString).value, 'a\rb');
    });

    test('tab', () {
      final d = doc_(parseHcl('v = "a\\tb"\n'));
      expect((_get(d, 'v') as HclString).value, 'a\tb');
    });

    test('backslash', () {
      final d = doc_(parseHcl('v = "a\\\\b"\n'));
      expect((_get(d, 'v') as HclString).value, r'a\b');
    });

    test('quote', () {
      final d = doc_(parseHcl('v = "a\\"b"\n'));
      expect((_get(d, 'v') as HclString).value, 'a"b');
    });

    test('unicode 4-digit', () {
      final d = doc_(parseHcl('v = "\\u0041"\n'));
      expect((_get(d, 'v') as HclString).value, 'A');
    });

    test('unicode 8-digit', () {
      final d = doc_(parseHcl('v = "\\U0001F600"\n'));
      expect((_get(d, 'v') as HclString).value, '\u{1F600}');
    });

    test('invalid escape fails', () {
      final result = parseHcl('v = "\\x"\n');
      expect(result, isA<Failure<ParseError, HclDocument>>());
    });
  });

  group('HCL scientific notation', () {
    test('integer exponent', () {
      final d = doc_(parseHcl('v = 1e10\n'));
      expect((_get(d, 'v') as HclNumber).value, 1e10);
    });

    test('float exponent', () {
      final d = doc_(parseHcl('v = 1.5e3\n'));
      expect((_get(d, 'v') as HclNumber).value, 1.5e3);
    });

    test('negative exponent', () {
      final d = doc_(parseHcl('v = 1.5e-3\n'));
      expect((_get(d, 'v') as HclNumber).value, 1.5e-3);
    });

    test('positive exponent sign', () {
      final d = doc_(parseHcl('v = 1.5E+3\n'));
      expect((_get(d, 'v') as HclNumber).value, 1.5e3);
    });

    test('negative number with exponent', () {
      final d = doc_(parseHcl('v = -1e10\n'));
      final unary = _get(d, 'v') as HclUnaryOp;
      expect(unary.op, '-');
      expect((unary.operand as HclNumber).value, 1e10);
    });
  });

  group('HCL heredoc', () {
    test('basic', () {
      final d = doc_(parseHcl('v = <<EOF\nhello\nEOF\n'));
      expect((_get(d, 'v') as HclString).value, 'hello');
    });

    test('multi-line', () {
      final d = doc_(parseHcl('v = <<EOF\nline1\nline2\nline3\nEOF\n'));
      expect((_get(d, 'v') as HclString).value, 'line1\nline2\nline3');
    });

    test('empty', () {
      final d = doc_(parseHcl('v = <<EOF\nEOF\n'));
      expect((_get(d, 'v') as HclString).value, '');
    });

    test('blank lines', () {
      final d = doc_(parseHcl('v = <<EOF\nfoo\n\nbar\nEOF\n'));
      expect((_get(d, 'v') as HclString).value, 'foo\n\nbar');
    });

    test('indented flush', () {
      final d = doc_(parseHcl('v = <<-EOF\n    foo\n    bar\n  EOF\n'));
      expect((_get(d, 'v') as HclString).value, '  foo\n  bar');
    });

    test('indented flush no indent', () {
      final d = doc_(parseHcl('v = <<-EOF\nfoo\nbar\nEOF\n'));
      expect((_get(d, 'v') as HclString).value, 'foo\nbar');
    });

    test('as attribute value in block', () {
      final d = doc_(
        parseHcl('resource "a" "b" {\n  desc = <<EOF\nhello\nEOF\n}\n'),
      );
      final block = _get(d, 'resource') as HclBlock;
      expect((block.body['desc'] as HclString).value, 'hello');
    });
  });

  group('HCL operators', () {
    test('addition', () {
      final d = doc_(parseHcl('v = 1 + 2\n'));
      final op = _get(d, 'v') as HclBinaryOp;
      expect(op.op, '+');
      expect(op.left, const HclNumber(1));
      expect(op.right, const HclNumber(2));
    });

    test('precedence: multiply before add', () {
      final d = doc_(parseHcl('v = 1 + 2 * 3\n'));
      final add = _get(d, 'v') as HclBinaryOp;
      expect(add.op, '+');
      expect(add.left, const HclNumber(1));
      final mul = add.right as HclBinaryOp;
      expect(mul.op, '*');
    });

    test('comparison', () {
      final d = doc_(parseHcl('v = 1 <= 2\n'));
      final op = _get(d, 'v') as HclBinaryOp;
      expect(op.op, '<=');
    });

    test('equality', () {
      final d = doc_(parseHcl('v = "a" == "b"\n'));
      final op = _get(d, 'v') as HclBinaryOp;
      expect(op.op, '==');
    });

    test('logical and', () {
      final d = doc_(parseHcl('v = true && false\n'));
      final op = _get(d, 'v') as HclBinaryOp;
      expect(op.op, '&&');
    });

    test('logical or', () {
      final d = doc_(parseHcl('v = true || false\n'));
      final op = _get(d, 'v') as HclBinaryOp;
      expect(op.op, '||');
    });

    test('unary negation', () {
      final d = doc_(parseHcl('v = -x\n'));
      final op = _get(d, 'v') as HclUnaryOp;
      expect(op.op, '-');
      expect(op.operand, const HclReference('x'));
    });

    test('unary not', () {
      final d = doc_(parseHcl('v = !enabled\n'));
      final op = _get(d, 'v') as HclUnaryOp;
      expect(op.op, '!');
      expect(op.operand, const HclReference('enabled'));
    });
  });

  group('HCL conditional', () {
    test('ternary', () {
      final d = doc_(parseHcl('v = true ? "a" : "b"\n'));
      final cond = _get(d, 'v') as HclConditional;
      expect(cond.condition, const HclBool(true));
      expect(cond.then_, const HclString('a'));
      expect(cond.else_, const HclString('b'));
    });

    test('ternary with references', () {
      final d = doc_(parseHcl('v = var.enabled ? "yes" : "no"\n'));
      final cond = _get(d, 'v') as HclConditional;
      expect(cond.condition, const HclGetAttr(HclReference('var'), 'enabled'));
    });
  });

  group('HCL function calls', () {
    test('no args', () {
      final d = doc_(parseHcl('v = timestamp()\n'));
      final fc = _get(d, 'v') as HclFunctionCall;
      expect(fc.name, 'timestamp');
      expect(fc.args, isEmpty);
      expect(fc.expandFinal, false);
    });

    test('with args', () {
      final d = doc_(parseHcl('v = cidrsubnet(x, 8, 0)\n'));
      final fc = _get(d, 'v') as HclFunctionCall;
      expect(fc.name, 'cidrsubnet');
      expect(fc.args.length, 3);
    });

    test('expansion', () {
      final d = doc_(parseHcl('v = concat(list...)\n'));
      final fc = _get(d, 'v') as HclFunctionCall;
      expect(fc.name, 'concat');
      expect(fc.expandFinal, true);
    });

    test('nested call', () {
      final d = doc_(parseHcl('v = upper(lower("X"))\n'));
      final outer = _get(d, 'v') as HclFunctionCall;
      expect(outer.name, 'upper');
      final inner = outer.args.first as HclFunctionCall;
      expect(inner.name, 'lower');
    });
  });

  group('HCL index and splat', () {
    test('index access', () {
      final d = doc_(parseHcl('v = list[0]\n'));
      final idx = _get(d, 'v') as HclIndex;
      expect(idx.collection, const HclReference('list'));
      expect(idx.index, const HclNumber(0));
    });

    test('chained access', () {
      final d = doc_(parseHcl('v = a.b.c[0].d\n'));
      final ga = _get(d, 'v') as HclGetAttr;
      expect(ga.name, 'd');
      final idx = ga.object as HclIndex;
      expect(idx.index, const HclNumber(0));
    });

    test('full splat', () {
      final d = doc_(parseHcl('v = foo.bar[*].baz\n'));
      final splat = _get(d, 'v') as HclFullSplat;
      expect(splat.object, const HclGetAttr(HclReference('foo'), 'bar'));
      expect(splat.accessors, [const HclPostfixGetAttr('baz')]);
    });

    test('attr splat', () {
      final d = doc_(parseHcl('v = foo.bar.*.baz\n'));
      final splat = _get(d, 'v') as HclAttrSplat;
      expect(splat.attrs, ['baz']);
    });

    test('expression in index', () {
      final d = doc_(parseHcl('v = var.list[count.index]\n'));
      final idx = _get(d, 'v') as HclIndex;
      expect(idx.index, const HclGetAttr(HclReference('count'), 'index'));
    });

    test('function call then index', () {
      final d = doc_(parseHcl('v = foo(a, b)[0]\n'));
      final idx = _get(d, 'v') as HclIndex;
      expect(idx.collection, isA<HclFunctionCall>());
    });
  });

  group('HCL for expressions', () {
    test('for-tuple basic', () {
      final d = doc_(parseHcl('v = [for s in list : s]\n'));
      final ft = _get(d, 'v') as HclForTuple;
      expect(ft.keyVar, isNull);
      expect(ft.valueVar, 's');
      expect(ft.body, const HclReference('s'));
      expect(ft.condition, isNull);
    });

    test('for-tuple with key', () {
      final d = doc_(parseHcl('v = [for k, v in map : v]\n'));
      final ft = _get(d, 'v') as HclForTuple;
      expect(ft.keyVar, 'k');
      expect(ft.valueVar, 'v');
    });

    test('for-tuple with condition', () {
      final d = doc_(parseHcl('v = [for s in list : s if s != ""]\n'));
      final ft = _get(d, 'v') as HclForTuple;
      expect(ft.condition, isA<HclBinaryOp>());
    });

    test('for-object basic', () {
      final d = doc_(parseHcl('v = {for k, v in map : k => v}\n'));
      final fo = _get(d, 'v') as HclForObject;
      expect(fo.keyVar, 'k');
      expect(fo.valueVar, 'v');
      expect(fo.grouping, false);
      expect(fo.condition, isNull);
    });

    test('for-object with grouping', () {
      final d = doc_(parseHcl('v = {for k, v in map : k => v...}\n'));
      final fo = _get(d, 'v') as HclForObject;
      expect(fo.grouping, true);
    });

    test('for-object with condition', () {
      final d = doc_(parseHcl('v = {for k, v in map : k => v if v != ""}\n'));
      final fo = _get(d, 'v') as HclForObject;
      expect(fo.condition, isA<HclBinaryOp>());
    });

    test('for-tuple with function call', () {
      final d = doc_(parseHcl('v = [for s in list : upper(s)]\n'));
      final ft = _get(d, 'v') as HclForTuple;
      expect(ft.body, isA<HclFunctionCall>());
    });
  });

  group('HCL parenthesized expressions', () {
    test('simple parens', () {
      final d = doc_(parseHcl('v = (1 + 2)\n'));
      final paren = _get(d, 'v') as HclParenExpr;
      expect(paren.inner, isA<HclBinaryOp>());
    });

    test('parens override precedence', () {
      final d = doc_(parseHcl('v = (1 + 2) * 3\n'));
      final mul = _get(d, 'v') as HclBinaryOp;
      expect(mul.op, '*');
      expect(mul.left, isA<HclParenExpr>());
    });
  });

  group('HCL string templates', () {
    test('interpolation parsed', () {
      final d = doc_(
        parseHcl(
          r'name = "hello-${var.env}"'
          '\n',
        ),
      );
      final tmpl = _get(d, 'name') as HclTemplate;
      expect(tmpl.parts.length, 2);
      expect(tmpl.parts[0], const HclTemplateLiteral('hello-'));
      expect(tmpl.parts[1], isA<HclTemplateInterpolation>());
      final interp = tmpl.parts[1] as HclTemplateInterpolation;
      expect(interp.expr, const HclGetAttr(HclReference('var'), 'env'));
    });

    test('pure literal stays HclString', () {
      final d = doc_(parseHcl('v = "hello"\n'));
      expect(_get(d, 'v'), const HclString('hello'));
    });

    test('multiple interpolations', () {
      final d = doc_(
        parseHcl(
          r'v = "${a}-${b}"'
          '\n',
        ),
      );
      final tmpl = _get(d, 'v') as HclTemplate;
      expect(tmpl.parts.length, 3);
      expect(tmpl.parts[0], isA<HclTemplateInterpolation>());
      expect(tmpl.parts[1], const HclTemplateLiteral('-'));
      expect(tmpl.parts[2], isA<HclTemplateInterpolation>());
    });

    test('escaped dollar produces literal', () {
      final d = doc_(
        parseHcl(
          r'v = "$${literal}"'
          '\n',
        ),
      );
      expect(_get(d, 'v'), const HclString(r'${literal}'));
    });

    test('function call in interpolation', () {
      final d = doc_(
        parseHcl(
          r'v = "count: ${length(list)}"'
          '\n',
        ),
      );
      final tmpl = _get(d, 'v') as HclTemplate;
      final interp = tmpl.parts[1] as HclTemplateInterpolation;
      expect(interp.expr, isA<HclFunctionCall>());
    });

    test('strip markers', () {
      final d = doc_(
        parseHcl(
          r'v = "${~ expr ~}"'
          '\n',
        ),
      );
      final tmpl = _get(d, 'v') as HclTemplate;
      final interp = tmpl.parts[0] as HclTemplateInterpolation;
      expect(interp.stripBefore, true);
      expect(interp.stripAfter, true);
    });
  });

  group('HCL template directives', () {
    test('if directive', () {
      final d = doc_(
        parseHcl(
          r'v = "%{if enabled}yes%{endif}"'
          '\n',
        ),
      );
      final tmpl = _get(d, 'v') as HclTemplate;
      expect(tmpl.parts.length, 1);
      final ifDir = tmpl.parts[0] as HclTemplateIf;
      expect(ifDir.condition, const HclReference('enabled'));
      expect(ifDir.thenBranch.length, 1);
      expect(ifDir.elseBranch, isNull);
    });

    test('if-else directive', () {
      final d = doc_(
        parseHcl(
          r'v = "%{if enabled}yes%{else}no%{endif}"'
          '\n',
        ),
      );
      final tmpl = _get(d, 'v') as HclTemplate;
      final ifDir = tmpl.parts[0] as HclTemplateIf;
      expect(ifDir.thenBranch.length, 1);
      expect(ifDir.elseBranch, isNotNull);
      expect(ifDir.elseBranch!.length, 1);
    });

    test('for directive', () {
      final d = doc_(
        parseHcl(
          r'v = "%{for x in list}${x} %{endfor}"'
          '\n',
        ),
      );
      final tmpl = _get(d, 'v') as HclTemplate;
      final forDir = tmpl.parts[0] as HclTemplateFor;
      expect(forDir.keyVar, isNull);
      expect(forDir.valueVar, 'x');
      expect(forDir.body.length, 2); // interpolation + space
    });

    test('for directive with key', () {
      final d = doc_(
        parseHcl(
          r'v = "%{for k, v in map}${k}=${v} %{endfor}"'
          '\n',
        ),
      );
      final tmpl = _get(d, 'v') as HclTemplate;
      final forDir = tmpl.parts[0] as HclTemplateFor;
      expect(forDir.keyVar, 'k');
      expect(forDir.valueVar, 'v');
    });
  });

  group('HCL real-world', () {
    test('terraform variable', () {
      final d = doc_(
        parseHcl('''
variable "region" {
  type    = "string"
  default = "us-east-1"
}
'''),
      );
      final v = _get(d, 'variable') as HclBlock;
      expect(v.labels, ['region']);
      expect(v.body['default'], const HclString('us-east-1'));
    });

    test('terraform resource', () {
      final d = doc_(
        parseHcl('''
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
}
'''),
      );
      final r = _get(d, 'resource') as HclBlock;
      expect(r.labels, ['aws_instance', 'web']);
    });
  });

  group('HCL native decoder', () {
    test('attributes', () {
      final d = doc_(parseHcl('name = "test"\nport = 8080\n'));
      final native = hclDocToNative(d);
      expect(native['name'], 'test');
      expect(native['port'], 8080);
    });

    test('blocks include _type and _labels', () {
      final d = doc_(
        parseHcl('resource "aws_instance" "web" {\n  ami = "abc"\n}\n'),
      );
      final native = hclDocToNative(d);
      final res = native['resource'] as Map;
      expect(res['_type'], 'resource');
      expect(res['_labels'], ['aws_instance', 'web']);
      expect(res['ami'], 'abc');
    });

    test('multiple blocks grouped into list', () {
      final d = doc_(
        parseHcl('''
resource "a" "b" { x = 1 }
resource "c" "d" { x = 2 }
'''),
      );
      final native = hclDocToNative(d);
      expect(native['resource'], isA<List<Object?>>());
      expect((native['resource'] as List).length, 2);
    });
  });

  group('HCL round-trip', () {
    test('attributes', () {
      const input = 'name = "test"\nport = 8080\n';
      final doc = doc_(parseHcl(input));
      final serialized = serializeHcl(doc);
      final reparsed = doc_(parseHcl(serialized));
      expect(reparsed, doc);
    });

    test('block', () {
      const input = 'resource "aws_instance" "web" {\n  ami = "abc"\n}\n';
      final doc = doc_(parseHcl(input));
      final serialized = serializeHcl(doc);
      final reparsed = doc_(parseHcl(serialized));
      expect(reparsed, doc);
    });
  });

  group('HCL serializer', () {
    test('attributes', () {
      final doc = <(String, HclValue)>[
        ('name', const HclString('test')),
        ('port', const HclNumber(8080)),
      ];
      final s = serializeHcl(doc);
      expect(s, contains('name = "test"'));
      expect(s, contains('port = 8080'));
    });

    test('block', () {
      final doc = <(String, HclValue)>[
        (
          'resource',
          const HclBlock(
            'resource',
            ['aws_instance', 'web'],
            {'ami': HclString('abc')},
          ),
        ),
      ];
      final s = serializeHcl(doc);
      expect(s, contains('resource "aws_instance" "web" {'));
      expect(s, contains('ami = "abc"'));
    });
  });
}
