/// HOCON spec conformance tests.
///
/// Transcribes the normative examples from the official HOCON
/// specification (lightbend/config, `HOCON.md`) and runs them through
/// the full parse → resolve → native pipeline. Each test names the spec
/// section it comes from.
///
/// The Akka `reference.conf` smoke test at the bottom exercises the
/// parser against a large real-world HOCON document.
library;

import 'dart:io';

import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

/// Parse + resolve [source] to native Dart values.
Object? resolve_(String source, {HoconConfig config = const HoconConfig()}) {
  final r = parseHocon(source);
  return switch (r) {
    Success<ParseError, HoconValue>(:final value) ||
    Partial<ParseError, HoconValue>(
      :final value,
    ) => hoconToNative(resolveHocon(value, config: config)),
    Failure() => throw StateError('Expected success, got \${r.errors}'),
  };
}

void main() {
  group('spec: key-value separator', () {
    // "The `=` character can be used anywhere JSON allows `:` ... If a
    // key is followed by `{`, the `:` or `=` may be omitted."
    test('`=` and `:` are interchangeable', () {
      expect(resolve_('a = 1'), {'a': 1});
      expect(resolve_('a : 1'), {'a': 1});
    });

    test('separator omitted before `{`', () {
      expect(resolve_('"foo" {}'), {'foo': <String, Object?>{}});
    });
  });

  group('spec: commas', () {
    // "[1,2,3,] and [1,2,3] are the same array. [1\\n2\\n3] and
    // [1,2,3] are the same array."
    test('trailing comma is the same array', () {
      expect(resolve_('[1,2,3,]'), [1, 2, 3]);
    });

    test('newlines are separators', () {
      expect(resolve_('[1\n2\n3]'), [1, 2, 3]);
    });

    test('two trailing commas invalid', () {
      final r = parseHocon('[1,2,3,,]');
      expect(r, isA<Failure<ParseError, HoconValue>>());
    });

    test('initial comma invalid', () {
      final r = parseHocon('[,1,2,3]');
      expect(r, isA<Failure<ParseError, HoconValue>>());
    });

    test('doubled comma invalid', () {
      final r = parseHocon('[1,,2,3]');
      expect(r, isA<Failure<ParseError, HoconValue>>());
    });

    test('same comma rules apply to object fields', () {
      expect(resolve_('{a = 1, b = 2,}'), {'a': 1, 'b': 2});
      final r = parseHocon('{a = 1,, b = 2}');
      expect(r, isA<Failure<ParseError, HoconValue>>());
    });
  });

  group('spec: unquoted strings', () {
    // "`truefoo` parses as the boolean token `true` followed by the
    // unquoted string `foo`. However, `footrue` parses as the unquoted
    // string `footrue`."
    test('initial keyword splits, embedded does not', () {
      // `truefoo` = boolean `true` + unquoted `foo`, value-concatenated
      // to the string "truefoo".
      expect(resolve_('a = truefoo'), {'a': 'truefoo'});
      expect(resolve_('a = footrue'), {'a': 'footrue'});
    });

    // "`10.0bar` is the number `10.0` then the unquoted string `bar`"
    test('initial number splits, embedded does not', () {
      expect(resolve_('a = 10.0bar'), {'a': '10.0bar'});
      expect(resolve_('a = bar10.0'), {'a': 'bar10.0'});
    });

    test('unquoted may not begin with a digit or hyphen', () {
      expect(
        parseHocon('a = 1foo'),
        isNot(isA<Failure<ParseError, HoconValue>>()),
      );
      // `-foo` cannot start a number (no digits follow) or an unquoted
      // string (hyphen is a number-starter).
      expect(parseHocon('a = -foo'), isA<Failure<ParseError, HoconValue>>());
    });
  });

  group('spec: multi-line strings', () {
    // "any sequence of at least three quotes ends the multi-line
    // string, and any \"extra\" quotes are part of the string"
    test('extra quotes are content', () {
      expect(resolve_('a = """foo""""'), {'a': 'foo"'});
    });

    test('newlines taken literally', () {
      expect(resolve_('a = """x\ny"""'), {'a': 'x\ny'});
    });
  });

  group('spec: value concatenation', () {
    // "As long as simple values are separated only by non-newline
    // whitespace, the whitespace between them is preserved"
    test('whitespace between simple values is preserved', () {
      expect(resolve_('a = hello world'), {'a': 'hello world'});
      expect(resolve_('a = foo bar baz'), {'a': 'foo bar baz'});
    });

    test('leading/trailing whitespace discarded', () {
      expect(resolve_('a =    foo bar baz    '), {'a': 'foo bar baz'});
    });

    // "`foo bar` ... and quoted string \"foo bar\" would result in the
    // same in-memory representation, seven characters."
    test('unquoted concat equals quoted form', () {
      expect(resolve_('a = foo bar'), {'a': 'foo bar'});
      expect(resolve_('a = "foo bar"'), {'a': 'foo bar'});
    });

    test('arrays without commas or newlines concat inside an element', () {
      // "this is an array with one element, the string \"1 2 3 4\""
      expect(resolve_('a = [ 1 2 3 4 ]'), {
        'a': ['1 2 3 4'],
      });
      // "an array of one element, the array [ 1, 2, 3, 4 ]"
      expect(resolve_('a = [ [ 1, 2 ] [ 3, 4 ] ]'), {
        'a': [
          [1, 2, 3, 4],
        ],
      });
      // "an array of two arrays"
      expect(resolve_('a = [ [ 1, 2 ]\n  [ 3, 4 ] ]'), {
        'a': [
          [1, 2],
          [3, 4],
        ],
      });
    });

    test('object concatenation merges', () {
      // "a : { b : 1 } { c : 2 }" equals "a : { b : 1, c : 2 }"
      expect(resolve_('a : { b : 1 } { c : 2 }'), {
        'a': {'b': 1, 'c': 2},
      });
    });

    test('array concatenation', () {
      expect(resolve_('a : [ 1, 2 ] [ 3, 4 ]'), {
        'a': [1, 2, 3, 4],
      });
    });

    test('substitution to array concatenates (inheritance of lists)', () {
      expect(resolve_('path = [ /bin ]\npath = \${path} [ /usr/bin ]'), {
        'path': ['/bin', '/usr/bin'],
      });
    });
  });

  group('spec: path expressions', () {
    // "`10.0foo` is a number then unquoted string `foo` and should be
    // the two-element path with `10` and `0foo` as the elements."
    test('numbers split on the dot in keys', () {
      expect(resolve_('3.14 : 42'), {
        '3': {'14': 42},
      });
    });

    // "Because path expressions work like value concatenations, you can
    // have whitespace in keys: `a b c : 42` is equivalent to
    // `\"a b c\" : 42`." — v1 does not support whitespace-concatenated
    // key elements; quoted keys cover the practical case.
    test('quoted keys with whitespace', () {
      expect(resolve_('"a b c" : 42'), {'a b c': 42});
    });

    test('dotted keys expand and merge', () {
      // "a.x : 42, a.y : 43 is equivalent to a { x : 42, y : 43 }"
      expect(resolve_('a.x : 42, a.y : 43'), {
        'a': {'x': 42, 'y': 43},
      });
    });

    test('empty path element must be quoted', () {
      expect(resolve_('a."".b = 1'), {
        'a': {
          '': {'b': 1},
        },
      });
      expect(parseHocon('a..b = 1'), isA<Failure<ParseError, HoconValue>>());
    });
  });

  group('spec: substitutions', () {
    test('substitution looks forward', () {
      expect(resolve_('a = \${b}\nb = 7'), {'a': 7, 'b': 7});
    });

    test('latest-assigned value wins', () {
      // "If a key has been specified more than once, the substitution
      // will always evaluate to its latest-assigned value."
      expect(
        resolve_(
          'bar : { foo : 42 }\n'
          'bar : { foo : 43 }\n'
          'baz : \${bar.foo}',
        ),
        {
          'bar': {'foo': 43},
          'baz': 43,
        },
      );
    });

    test('self-referential field looks back', () {
      // "path : \"a:b:c\"\npath : \${path}\":d\"" → "a:b:c:d"
      expect(resolve_('path = "a:b:c"\npath = \${path}":d"'), {
        'path': 'a:b:c:d',
      });
    });

    test('in isolation a self-reference is an error', () {
      expect(
        () => resolve_('foo : \${foo}'),
        throwsA(isA<HoconResolveException>()),
      );
    });

    test('merged self-reference resolves to the overridden value', () {
      // "foo : { a : 1 }" then "foo : \${foo}" → { a : 1 }
      expect(resolve_('foo : { a : 1 }\nfoo : \${foo}'), {
        'foo': {'a': 1},
      });
    });

    test('self-reference below the assigned path', () {
      // "foo : { a : { c : 1 } } / foo : \${foo.a} / foo : { a : 2 }"
      // final merge = { a : 2, c : 1 }
      expect(
        resolve_(
          'foo : { a : { c : 1 } }\n'
          'foo : \${foo.a}\n'
          'foo : { a : 2 }',
        ),
        {
          'foo': {'a': 2, 'c': 1},
        },
      );
    });

    test('hidden substitution is never evaluated', () {
      // "foo : \${does-not-exist} / foo : 42" → foo is 42, no error.
      expect(resolve_('foo : \${does-not-exist}\nfoo : 42'), {'foo': 42});
    });

    test('hidden self-reference must be ignored', () {
      // "foo : \${foo}, foo : 42" → foo is 42, no error.
      expect(resolve_('foo : \${foo}\nfoo : 42'), {'foo': 42});
    });

    test('optional self-reference does not create a cycle', () {
      // "foo : \${?foo} // this field just disappears silently"
      expect(resolve_('foo : \${?foo}'), <String, Object?>{});
      // "a = \${?a}foo" — a is "foo", not "foofoo".
      expect(resolve_('a = \${?a}foo'), {'a': 'foo'});
    });

    test('optional substitution rules', () {
      // undefined field omitted; previous value remains when overriding
      expect(resolve_('a = 1\nb = \${?nope}'), {'a': 1});
      expect(resolve_('a = 1\na = \${?nope}'), {'a': 1});
      // array element dropped
      expect(resolve_('a = [1, \${?nope}, 3]'), {
        'a': [1, 3],
      });
      // empty in string concatenation; all-optional concat omits field
      expect(resolve_('a = \${?nope}foo'), {'a': 'foo'});
      expect(resolve_('foo : \${?bar}\${?baz}'), <String, Object?>{});
    });

    test('mutually-referring objects look forward', () {
      // "bar.a should end up as 4; foo.c should end up as 3"
      expect(
        resolve_(
          'bar : { a : \${foo.d}, b : 1 }\n'
          'bar.b = 3\n'
          'foo : { c : \${bar.b}, d : 2 }\n'
          'foo.d = 4',
        ),
        {
          'bar': {'a': 4, 'b': 3},
          'foo': {'c': 3, 'd': 4},
        },
      );
    });

    test('object may refer to paths within itself', () {
      // "bar : { foo : 42, baz : \${bar.foo} }" → baz is 42
      expect(resolve_('bar : { foo : 42, baz : \${bar.foo} }'), {
        'bar': {'foo': 42, 'baz': 42},
      });
      // "bar.baz would be 43 in: ..." with a later override of bar.foo
      expect(
        resolve_(
          'bar : { foo : 42, baz : \${bar.foo} }\n'
          'bar : { foo : 43 }',
        ),
        {
          'bar': {'foo': 43, 'baz': 43},
        },
      );
    });

    test('multi-step loops are invalid', () {
      expect(
        () => resolve_('a : \${b}\nb : \${c}\nc : \${a}'),
        throwsA(isA<HoconResolveException>()),
      );
    });

    test('unbreakable cycles error', () {
      // "a : { b : \${a} }" and "a : [\${a}]" are unbreakable cycles.
      expect(
        () => resolve_('a : { b : \${a} }'),
        throwsA(isA<HoconResolveException>()),
      );
      expect(
        () => resolve_('a : [\${a}]'),
        throwsA(isA<HoconResolveException>()),
      );
    });

    test('environment variable fallback', () {
      // "Implementations may try to resolve [missing substitutions] by
      // looking at system environment variables."
      expect(
        resolve_(
          'home = \${HOME}',
          config: const HoconConfig(environment: {'HOME': '/root'}),
        ),
        {'home': '/root'},
      );
      // "{ \"HOME\" : null }" hides the variable from external lookup:
      // the substitution resolves to the config's null and never
      // consults the environment. A lone substitution preserves its
      // type, so `home` is null, not the string "null".
      expect(
        resolve_(
          'HOME = null\nhome = \${HOME}',
          config: const HoconConfig(environment: {'HOME': '/root'}),
        ),
        {'HOME': null, 'home': null},
      );
    });
  });

  group('spec: += separator', () {
    // "a += b becomes a = \${?a} [b]"
    test('appends to a previous array', () {
      expect(resolve_('a = [1]\na += 2'), {
        'a': [1, 2],
      });
    });

    test('first mention needs no prior definition', () {
      expect(resolve_('a += 2'), {
        'a': [2],
      });
    });

    test('non-array previous value errors', () {
      // "If the previous value was not an array, an error will result"
      expect(
        () => resolve_('a = 1\na += 2'),
        throwsA(isA<HoconResolveException>()),
      );
    });
  });

  group('spec: includes', () {
    test('keys merge like duplicate keys', () {
      expect(
        resolve_(
          'include "extra.conf"\na = override',
          config: HoconConfig(includeLoader: (_) => 'a = original'),
        ),
        {'a': 'override'},
      );
    });

    test('missing optional include silently ignored', () {
      expect(
        resolve_(
          'a = 1\ninclude "missing.conf"',
          config: const HoconConfig(includeLoader: null),
        ),
        {'a': 1},
      );
    });

    test('missing required include errors', () {
      expect(
        () => resolve_(
          'include required("missing.conf")',
          config: const HoconConfig(includeLoader: null),
        ),
        throwsA(isA<HoconResolveException>()),
      );
    });

    test('required(file()) form', () {
      expect(
        resolve_(
          'include required(file("extra.conf"))',
          config: HoconConfig(
            includeLoader: (r) => r == 'extra.conf' ? 'b = 2' : null,
          ),
        ),
        {'b': 2},
      );
    });

    test('circular include detected', () {
      expect(
        () => resolve_(
          'include "self.conf"',
          config: HoconConfig(
            includeLoader:
                (r) => r == 'self.conf' ? 'include "self.conf"' : null,
          ),
        ),
        throwsA(isA<HoconResolveException>()),
      );
    });

    test('substitution fixup for included files', () {
      // "foo.conf might look like { x : 10, y : \${x} } ... if you
      // include \"foo.conf\" in an object at key `a` ... it must be
      // fixed up to be \${a.x}". With a.x redefined, y follows 42.
      expect(
        resolve_(
          'a { include "foo.conf" }\na { x : 42 }',
          config: HoconConfig(includeLoader: (_) => 'x : 10, y : \${x}'),
        ),
        {
          'a': {'x': 42, 'y': 42},
        },
      );
    });

    test('array root in included file invalid', () {
      expect(
        () => resolve_(
          'include "arr.conf"',
          config: HoconConfig(includeLoader: (_) => '[1, 2]'),
        ),
        throwsA(isA<HoconResolveException>()),
      );
    });
  });

  group('spec: duplicate keys and object merging', () {
    test('later value overrides, objects merge', () {
      expect(resolve_('foo : { "a" : 42 }\nfoo : { "b" : 43 }'), {
        'foo': {'a': 42, 'b': 43},
      });
    });

    test('intermediate null prevents merge', () {
      // "The intermediate setting of \"foo\" to null prevents the
      // object merge."
      expect(resolve_('foo : { a : 42 }\nfoo : null\nfoo : { b : 43 }'), {
        'foo': {'b': 43},
      });
    });
  });

  group('spec: root handling', () {
    test('empty file is an empty object', () {
      // "if the file does not begin with a square bracket or curly
      // brace, it is parsed as if it were enclosed with {}"
      expect(resolve_(''), <String, Object?>{});
    });

    test('unbalanced braces invalid', () {
      // "A HOCON file is invalid if it omits the opening { but still
      // has a closing }"
      expect(parseHocon('a = 1 }'), isA<Failure<ParseError, HoconValue>>());
    });
  });

  group('smoke: Akka reference.conf', () {
    // A large real-world HOCON document: nested braces, dotted keys,
    // comments, substitutions (self-referential optional + list
    // lookup), quoted strings with escapes, and an include stub.
    final source =
        File('test/conformance/akka_reference.conf').readAsStringSync();
    final config = HoconConfig(
      // The shipped reference.conf does `include "version"`; supply the
      // generated version file's content so akka.version resolves.
      includeLoader: (r) => r == 'version' ? 'akka.version = "2.9.0"' : null,
    );

    late final Object? resolved;
    setUpAll(() {
      final r = parseHocon(source);
      final ast = switch (r) {
        Success<ParseError, HoconValue>(:final value) => value,
        Partial<ParseError, HoconValue>(:final value) => value,
        Failure() =>
          throw StateError('reference.conf failed to parse: \${r.errors}'),
      };
      resolved = hoconToNative(resolveHocon(ast, config: config));
    });

    test('parses and resolves', () {
      expect(resolved, isA<Map<String, Object?>>());
    });

    test('version arrives through the include and merges', () {
      final akka = (resolved as Map)['akka'] as Map;
      expect(akka['version'], '2.9.0');
    });

    test('scalars survive', () {
      final akka = (resolved as Map)['akka'] as Map;
      expect(akka['home'], '');
      expect(akka['loglevel'], 'INFO');
      expect(akka['stdout-loglevel'], 'WARNING');
    });

    test('optional self-referential list append', () {
      final akka = (resolved as Map)['akka'] as Map;
      expect(akka['library-extensions'], [
        r'akka.serialization.SerializationExtension$',
      ]);
    });

    test('substitution to a list deep in the tree', () {
      final akka = (resolved as Map)['akka'] as Map;
      final protobuf = akka['serialization'] as Map;
      final proto = protobuf['protobuf'] as Map;
      expect(proto['allowed-classes'], [
        'com.google.protobuf.GeneratedMessage',
        'com.google.protobuf.GeneratedMessageV3',
        'scalapb.GeneratedMessageCompanion',
        'akka.protobufv3.internal.GeneratedMessageV3',
      ]);
    });
  });
}
