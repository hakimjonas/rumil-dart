import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

/// Parse [source] and resolve it to native Dart values, failing the
/// test on parse errors.
Object? resolved_(String source, {HoconConfig config = const HoconConfig()}) {
  final r = parseHocon(source);
  return switch (r) {
    Success<ParseError, HoconValue>(:final value) ||
    Partial<ParseError, HoconValue>(
      :final value,
    ) => hoconToNative(resolveHocon(value, config: config)),
    Failure() => throw StateError('Expected success, got ${r.errors}'),
  };
}

/// Assert [source] fails to parse.
void parseFails_(String source) {
  final r = parseHocon(source);
  expect(r, isA<Failure<ParseError, HoconValue>>(), reason: 'source: $source');
}

Map<String, Object?> obj_(Object? v) => v as Map<String, Object?>;

void main() {
  group('HOCON: unquoted strings', () {
    test('simple word', () {
      expect(resolved_('a = hello'), {'a': 'hello'});
    });

    test('whitespace concatenation preserves inner whitespace', () {
      expect(resolved_('a = foo bar baz'), {'a': 'foo bar baz'});
      expect(resolved_('a = foo  bar'), {'a': 'foo  bar'});
    });

    test('leading and trailing whitespace trimmed', () {
      expect(resolved_('a =    foo bar    '), {'a': 'foo bar'});
    });

    test('quoted and unquoted forms are equivalent', () {
      expect(resolved_('a = "foo bar"'), {'a': 'foo bar'});
    });

    test('embedded numbers and booleans become strings', () {
      expect(resolved_('a = 10.0bar'), {'a': '10.0bar'});
      expect(resolved_('a = truefoo'), {'a': 'truefoo'});
      expect(resolved_('a = footrue'), {'a': 'footrue'});
      expect(resolved_('a = bar10.0'), {'a': 'bar10.0'});
      expect(resolved_('a = 1.2.3'), {'a': '1.2.3'});
    });

    test('unquoted string may not begin with -', () {
      parseFails_('a = -foo');
    });

    test('unquoted string may not contain forbidden characters', () {
      for (final c in [r'$', '{', '}', '[', ']', ':', '=', ',', '+']) {
        parseFails_('a = foo${c}bar');
      }
    });

    test('single slash is allowed in unquoted strings', () {
      expect(resolved_('a = 3/2'), {'a': '3/2'});
    });
  });

  group('HOCON: quoted strings', () {
    test('escapes are processed', () {
      expect(resolved_(r'a = "x\ny"'), {'a': 'x\ny'});
      expect(resolved_(r'a = "q\"q"'), {'a': 'q"q'});
      expect(resolved_(r'a = "\u0041"'), {'a': 'A'});
    });

    test('substitutions are not parsed inside quoted strings', () {
      expect(resolved_('x = 7\na = "\${x}"'), {'x': 7, 'a': r'${x}'});
    });

    test('substitution via concatenation', () {
      expect(resolved_('x = 7\na = \${x} is seven'), {
        'x': 7,
        'a': '7 is seven',
      });
      expect(resolved_('x = 7\na = \${x}" is seven"'), {
        'x': 7,
        'a': '7 is seven',
      });
    });
  });

  group('HOCON: multi-line strings', () {
    test('newlines and whitespace taken literally', () {
      expect(resolved_('a = """\nline1\n  line2"""'), {
        'a': '\nline1\n  line2',
      });
    });

    test('no escape processing', () {
      expect(resolved_(r'a = """x\ny"""'), {'a': r'x\ny'});
    });

    test('extra closing quotes are part of the string', () {
      expect(resolved_('a = """foo""""'), {'a': 'foo"'});
    });

    test('quotes inside the string', () {
      expect(resolved_('a = """he said "hi" ok"""'), {'a': 'he said "hi" ok'});
    });
  });

  group('HOCON: keys and separators', () {
    test('quoted keys', () {
      expect(resolved_('"a b" = 1'), {'a b': 1});
      expect(resolved_('"include" = 1'), {'include': 1});
    });

    test('dotted keys expand to nested objects', () {
      expect(resolved_('a.b.c = 1'), {
        'a': {
          'b': {'c': 1},
        },
      });
      expect(resolved_('a.x : 42, a.y : 43'), {
        'a': {'x': 42, 'y': 43},
      });
    });

    test('numbers in dotted keys split on the dot', () {
      expect(resolved_('3.14 : 42'), {
        '3': {'14': 42},
      });
    });

    test('empty path elements are invalid', () {
      parseFails_('a..b : 1');
      parseFails_('.a : 1');
      parseFails_('a. : 1');
    });

    test('+= appends to a previous array', () {
      expect(resolved_('a = [1]\na += 2'), {
        'a': [1, 2],
      });
    });

    test('+= can be the first mention', () {
      expect(resolved_('a += 2'), {
        'a': [2],
      });
    });

    test('include is special only at key start', () {
      // Whitespace-concatenated keys (`foo include : 42`) are a v1
      // limitation and are not supported; `include` as a VALUE and as
      // a quoted key work.
      expect(resolved_('{ foo : include }'), {'foo': 'include'});
      expect(resolved_('"include" = 1'), {'include': 1});
    });
  });

  group('HOCON: objects and arrays', () {
    test('root braces optional', () {
      expect(resolved_('a = 1'), {'a': 1});
      expect(resolved_('{a = 1}'), {'a': 1});
    });

    test('empty document is an empty object', () {
      expect(resolved_(''), <String, Object?>{});
      expect(resolved_('# just a comment'), <String, Object?>{});
    });

    test('root array is a valid document', () {
      expect(resolved_('[1, 2, 3]'), [1, 2, 3]);
    });

    test('stray closing brace without opening is invalid', () {
      parseFails_('a = 1 }');
    });

    test('commas optional with newlines', () {
      expect(resolved_('{a = 1\nb = 2}'), {'a': 1, 'b': 2});
      expect(resolved_('[1\n2\n3]'), [1, 2, 3]);
    });

    test('single trailing comma ignored', () {
      expect(resolved_('[1,2,3,]'), [1, 2, 3]);
      expect(resolved_('{a = 1, b = 2,}'), {'a': 1, 'b': 2});
    });

    test('initial or doubled commas invalid', () {
      parseFails_('[,1,2,3]');
      parseFails_('[1,,2,3]');
      parseFails_('[1,2,3,,]');
    });

    test('omitted separator before object', () {
      expect(resolved_('a { b = 1 }'), {
        'a': {'b': 1},
      });
    });

    test('non-newline whitespace inside arrays concatenates', () {
      expect(resolved_('a = [ 1 2 3 4 ]'), {
        'a': ['1 2 3 4'],
      });
      expect(resolved_('a = [ This is an unquoted string ]'), {
        'a': ['This is an unquoted string'],
      });
    });

    test('nested containers', () {
      expect(resolved_('a = [ { b = 1 }, [2, 3] ]'), {
        'a': [
          {'b': 1},
          [2, 3],
        ],
      });
    });
  });

  group('HOCON: comments', () {
    test('hash and double-slash comments', () {
      expect(resolved_('# c1\na = 1 // c2\n# c3'), {'a': 1});
    });

    test('comment inside braces', () {
      expect(resolved_('{\n  # header\n  a = 1 # trailing\n}'), {'a': 1});
    });
  });

  group('HOCON: substitutions', () {
    test('simple lookup', () {
      expect(resolved_('a = 1\nb = \${a}'), {'a': 1, 'b': 1});
    });

    test('forward reference', () {
      expect(resolved_('a = \${b}\nb = 7'), {'a': 7, 'b': 7});
    });

    test('dotted path lookup', () {
      expect(resolved_('bar : { foo : 42, baz : \${bar.foo} }'), {
        'bar': {'foo': 42, 'baz': 42},
      });
    });

    test('latest value wins', () {
      expect(
        resolved_('bar = { foo : 42 }\nbar = { foo : 43 }\nbaz = \${bar.foo}'),
        {
          'bar': {'foo': 43},
          'baz': 43,
        },
      );
    });

    test('self-reference looks back', () {
      expect(resolved_('path = "a:b:c"\npath = \${path}":d"'), {
        'path': 'a:b:c:d',
      });
    });

    test('self-reference below the assigned path', () {
      expect(
        resolved_(
          'foo : { a : { c : 1 } }\n'
          'foo : \${foo.a}\n'
          'foo : { a : 2 }',
        ),
        {
          'foo': {'a': 2, 'c': 1},
        },
      );
    });

    test('self-reference with no previous value is an error', () {
      expect(
        () => resolved_('foo : \${foo}'),
        throwsA(isA<HoconResolveException>()),
      );
    });

    test('optional self-reference disappears silently', () {
      expect(resolved_('foo : \${?foo}'), <String, Object?>{});
      expect(resolved_('a = \${?a}foo'), {'a': 'foo'});
    });

    test('undefined required substitution errors', () {
      expect(
        () => resolved_('a = \${nope}'),
        throwsA(isA<HoconResolveException>()),
      );
    });

    test('optional substitution omits the field', () {
      expect(resolved_('a = 1\nb = \${?nope}'), {'a': 1});
    });

    test('optional substitution with a previous value keeps it', () {
      expect(resolved_('a = 1\na = \${?nope}'), {'a': 1});
    });

    test('optional substitution drops the array element', () {
      expect(resolved_('a = [1, \${?nope}, 3]'), {
        'a': [1, 3],
      });
    });

    test('optional substitution in concatenation is empty', () {
      expect(resolved_('a = \${?nope}foo'), {'a': 'foo'});
      expect(resolved_('a = \${?nope}\${?nope2}'), <String, Object?>{});
    });

    test('mutual cycles are detected', () {
      expect(
        () => resolved_('a : \${b}\nb : \${a}'),
        throwsA(isA<HoconResolveException>()),
      );
      expect(
        () => resolved_('a : \${b}\nb : \${c}\nc : \${a}'),
        throwsA(isA<HoconResolveException>()),
      );
    });

    test('environment fallback', () {
      expect(
        resolved_(
          'a = \${MY_VAR}',
          config: const HoconConfig(environment: {'MY_VAR': 'hello'}),
        ),
        {'a': 'hello'},
      );
      expect(
        resolved_(
          'a = \${?MY_MISSING}',
          config: const HoconConfig(environment: {}),
        ),
        <String, Object?>{},
      );
    });

    test('hidden substitutions are never evaluated', () {
      expect(resolved_('foo : \${does-not-exist}\nfoo : 42'), {'foo': 42});
    });

    test('self-reference inside object or array is an unbreakable cycle', () {
      expect(
        () => resolved_('a : { b : \${a} }'),
        throwsA(isA<HoconResolveException>()),
      );
      expect(
        () => resolved_('a : [\${a}]'),
        throwsA(isA<HoconResolveException>()),
      );
    });
  });

  group('HOCON: concatenation', () {
    test('string + string', () {
      expect(resolved_('a = 1 2'), {'a': '1 2'});
      expect(resolved_('a = hello world'), {'a': 'hello world'});
    });

    test('substitution to string keeps whitespace significant', () {
      expect(resolved_('x = 1\ny = 2\na = \${x} \${y}'), {
        'x': 1,
        'y': 2,
        'a': '1 2',
      });
    });

    test('object concatenation merges', () {
      expect(resolved_('a : { b : 1 } { c : 2 }'), {
        'a': {'b': 1, 'c': 2},
      });
    });

    test('array concatenation', () {
      expect(resolved_('a : [1, 2] [3, 4]'), {
        'a': [1, 2, 3, 4],
      });
    });

    test('mixed kinds error', () {
      expect(
        () => resolved_('a = 1 { b = 2 }'),
        throwsA(isA<HoconResolveException>()),
      );
      expect(
        () => resolved_('a = [1] 2'),
        throwsA(isA<HoconResolveException>()),
      );
    });

    test('substitution resolving to an object merges in concat', () {
      expect(
        resolved_(
          'data-center-generic = { cluster-size = 6 }\n'
          'data-center-east = \${data-center-generic} { name = "east" }',
        ),
        {
          'data-center-generic': {'cluster-size': 6},
          'data-center-east': {'cluster-size': 6, 'name': 'east'},
        },
      );
    });

    test('substitution resolving to an array concatenates', () {
      expect(resolved_('path = [ /bin ]\npath = \${path} [ /usr/bin ]'), {
        'path': ['/bin', '/usr/bin'],
      });
    });

    test('self-referential field on non-array errors in +=', () {
      expect(
        () => resolved_('a = 1\na += 2'),
        throwsA(isA<HoconResolveException>()),
      );
    });

    test('numbers stringify as written', () {
      expect(resolved_('a = 1E5 x'), {'a': '1E5 x'});
    });
  });

  group('HOCON: duplicate keys and merging', () {
    test('later scalar wins', () {
      expect(resolved_('a = 1\na = 2'), {'a': 2});
    });

    test('objects merge', () {
      expect(resolved_('foo : { a : 42 }\nfoo : { b : 43 }'), {
        'foo': {'a': 42, 'b': 43},
      });
    });

    test('setting null prevents merge', () {
      expect(resolved_('foo : { a : 42 }\nfoo : null\nfoo : { b : 43 }'), {
        'foo': {'b': 43},
      });
    });

    test('dotted keys merge with braced objects', () {
      expect(resolved_('a { x = 1 }\na.y = 2'), {
        'a': {'x': 1, 'y': 2},
      });
    });
  });

  group('HOCON: includes', () {
    test('include merges keys in place', () {
      expect(
        resolved_(
          'include "extra.conf"\na = 1',
          config: HoconConfig(
            includeLoader: (r) => r == 'extra.conf' ? 'b = 2' : null,
          ),
        ),
        {'b': 2, 'a': 1},
      );
    });

    test('later fields override included ones', () {
      expect(
        resolved_(
          'include "extra.conf"\na = override',
          config: HoconConfig(includeLoader: (_) => 'a = original'),
        ),
        {'a': 'override'},
      );
    });

    test('missing optional include ignored', () {
      expect(
        resolved_(
          'a = 1\ninclude "nope.conf"',
          config: const HoconConfig(includeLoader: null),
        ),
        {'a': 1},
      );
    });

    test('missing required include errors', () {
      expect(
        () => resolved_(
          'include required("nope.conf")',
          config: const HoconConfig(includeLoader: null),
        ),
        throwsA(isA<HoconResolveException>()),
      );
    });

    test('required(file()) form', () {
      expect(
        resolved_(
          'include required(file("extra.conf"))',
          config: HoconConfig(
            includeLoader: (r) => r == 'extra.conf' ? 'b = 2' : null,
          ),
        ),
        {'b': 2},
      );
    });

    test('circular include errors', () {
      expect(
        () => resolved_(
          'include "self.conf"',
          config: HoconConfig(
            includeLoader:
                (r) => r == 'self.conf' ? 'include "self.conf"' : null,
          ),
        ),
        throwsA(isA<HoconResolveException>()),
      );
    });

    test('included substitutions resolve against the merged tree', () {
      expect(
        resolved_(
          'a { include "extra.conf" }\na { x : 42 }',
          config: HoconConfig(includeLoader: (_) => 'x : 10, y : \${x}'),
        ),
        {
          'a': {'x': 42, 'y': 42},
        },
      );
    });

    test('included array root is invalid', () {
      expect(
        () => resolved_(
          'include "arr.conf"',
          config: HoconConfig(includeLoader: (_) => '[1, 2]'),
        ),
        throwsA(isA<HoconResolveException>()),
      );
    });
  });

  group('HOCON: JSON compatibility', () {
    test('plain JSON parses', () {
      expect(resolved_('{"a": [1, 2, {"b": true}], "c": null, "d": 1.5}'), {
        'a': [
          1,
          2,
          {'b': true},
        ],
        'c': null,
        'd': 1.5,
      });
    });

    test('number formats match JSON', () {
      expect(resolved_('a = -0'), {'a': 0});
      expect(resolved_('a = 1e5'), {'a': 100000.0});
      expect(resolved_('a = 1.5e-3'), {'a': 0.0015});
    });
  });

  group('HOCON: round-trip through the serializer', () {
    test('resolved value serializes as valid JSON/HOCON', () {
      const source = 'a = 1\nb { c = "x\\ny" }\nd = [true, null, 2.5]';
      final r = parseHocon(source);
      final parsed = switch (r) {
        Success<ParseError, HoconValue>(:final value) => value,
        _ => throw StateError('parse failed'),
      };
      final resolved = resolveHocon(parsed);
      final text = serializeHocon(resolved);
      // The output is itself a valid HOCON document with the same data.
      final reparsed = switch (parseHocon(text)) {
        Success<ParseError, HoconValue>(:final value) => value,
        _ => throw StateError('re-parse failed'),
      };
      expect(hoconToNative(resolveHocon(reparsed)), hoconToNative(resolved));
    });
  });
}
