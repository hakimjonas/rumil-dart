# Final Review

## What's actually done and correct

| Item | Status | Notes |
|------|--------|-------|
| `==`/`hashCode` on all AST classes | Done, correct | Shared `_equality.dart` helpers for list/map. All 37 classes covered. |
| AstBuilder tests expanded | Done | Nested, empty, TOML null, unsupported type, JSON/YAML native round-trips |
| JSON round-trip uses structural == | Done | `expect(_json(serialized), ast)` |
| YAML round-trip tests | Done | Flat mapping + block sequence |
| Proto structural round-trip | Done | Message + enum |
| TOML `_serializeTable` documented | Done | Comment on line 64-66 |
| CSV lineEnding configurable | Done | `CsvConfig.lineEnding` field |
| `@AstSerializable` annotation | Done | In rumil_codec annotation.dart |
| `AstEncoderGenerator` | Done | In rumil_codec_builder |
| build.yaml registration | Done | `ast_encoder` builder registered |
| Escape functions fixed | Done | Shared `_escapeQuoted`, codeunit-level |
| AstBuilder variable shadowing | Done | Renamed to `entryValue` |
| TOML key escaping | Done | `_quoteTomlKey` |
| TOML map + nullable encoders | Done | `tomlMapEncoder`, `tomlNullableEncoder` |
| XML native decoder | Done | `xmlToNative` |

## What's NOT done

### 1. No tests for `@AstSerializable` codegen

The `AstEncoderGenerator` exists and is registered in `build.yaml`. But:
- No `@astSerializable` annotation on any class in `example/example.dart`
- No `.ast.g.dart` generated file
- No test in `test/codegen_test.dart` that exercises the AST encoder
- The generator has NEVER BEEN RUN. It compiles, but nobody has verified it produces correct output.

The session claimed "9 tests" in rumil_codec_builder. Those are the original 9 binary codec tests. Zero AST encoder tests.

**This means item 8 is only half done.** The generator code exists but is unverified. It could have bugs in field introspection, type mapping, sealed class handling — we don't know because it's never executed.

### 2. `_serializeTable` doc is minimal

The comment says what the code does (iterates twice) but not WHY this ordering matters or that it matches the Scala implementation. Minor but the spec asked for explicit documentation.

## Verdict

Items 1-7: properly done. Item 8 (the biggest one): code exists but is **untested and unverified**. Write a prompt telling the other session to add `@astSerializable` classes to the example, run build_runner, verify the generated code, and add tests that encode→serialize→parse round-trip.
