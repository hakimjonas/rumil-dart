/// Shared iterative-walk machinery for the format serializers.
///
/// Every serializer is a depth-first walk of a value tree that emits text.
/// Written recursively, the walk grows the Dart call stack with nesting depth,
/// so a document that *parses* (the interpreter is trampolined and stack-safe
/// to arbitrary depth) could still overflow on serialization. Rewritten over an
/// explicit [SinkWalk] worklist, the walk emits byte-for-byte identical output
/// while consuming only heap — the same discipline as
/// `GreenNodeOps.toSource` and the value-layer converters in
/// `native_decoders.dart`.
///
/// ## The pattern
///
/// A serializer holds one mutually-recursive-*in-scheduling* `emit` closure:
/// running it dispatches on the node, writes that node's own literal text
/// (brackets, separators, indentation) directly to the [StringSink], and
/// schedules one `emit` step per child via [SinkWalk.pushAll]. Because the
/// worklist is a LIFO stack and [SinkWalk.pushAll] reverses, the scheduled
/// steps run front-to-back — children, separators, and the closing delimiter
/// drain in source order. No `emit` call ever calls another `emit`: descent is
/// scheduling, not recursion, so the native stack stays flat at any depth.
///
/// Output size is orthogonal to this: an indented pretty-printer still emits
/// `indent * depth` whitespace at every level (Θ(depth²) total, the same as
/// `jq` / `JSON.stringify(_, null, 2)` / `serde_json` pretty). Streaming to a
/// [StringSink] lets a consumer drain that to a file or socket so *peak memory*
/// stays bounded even though the *work* is irreducibly quadratic; only the
/// `String`-returning convenience wrappers (which buffer into a `StringBuffer`)
/// are bounded by the materialized result.
library;

/// A single scheduled unit of serializer work: emit some text and/or schedule
/// further steps. See the library doc for the discipline.
typedef SinkStep = void Function();

/// A LIFO worklist of [SinkStep]s, drained depth-first by [run].
///
/// Replaces native-stack recursion in the serializers. Steps scheduled by a
/// running step are drained before the walk returns, so a container's closing
/// delimiter (scheduled last in its [pushAll] batch) is always emitted after
/// every descendant.
final class SinkWalk {
  final List<SinkStep> _stack = [];

  /// Schedule [step] to run next (before anything already on the worklist).
  void push(SinkStep step) => _stack.add(step);

  /// Schedule [steps] to run in the given order (front-to-back).
  ///
  /// The worklist is LIFO, so the batch is pushed in reverse: the first
  /// element ends up on top and runs first.
  void pushAll(List<SinkStep> steps) {
    for (var i = steps.length - 1; i >= 0; i--) {
      _stack.add(steps[i]);
    }
  }

  /// Drain the worklist to completion.
  void run() {
    while (_stack.isNotEmpty) {
      _stack.removeLast()();
    }
  }
}
