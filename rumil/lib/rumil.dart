/// Rumil — a parser combinator library for Dart.
///
/// Features:
/// - Native left-recursion via Warth seed-growth algorithm
/// - Stack-safe trampolining for arbitrary FlatMap depth
/// - Lazy error construction (2.6x speedup on error-heavy workloads)
/// - Sealed ADT with exhaustive pattern matching
/// - Zero external runtime dependencies
library;

export 'src/errors.dart';
export 'src/extensions.dart';
export 'src/interpreter.dart' show run;
export 'src/location.dart';
export 'src/memo.dart' show MemoKey;
export 'src/parser.dart';
export 'src/primitives.dart';
export 'src/result.dart';
export 'src/state.dart' show ParserState, Snapshot;
