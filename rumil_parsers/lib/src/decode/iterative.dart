/// Shared iterative driver for composite (nesting) AST decoders.
///
/// A composite decoder — list-of, map-of, nullable-of — decodes its children
/// by calling the child decoder's `.decode`, so a chain composed N levels deep
/// (`jsonListOf(jsonListOf(... jsonInt))`) recurses N native frames and
/// overflows the Dart call stack on a matching deeply-nested value. This
/// driver drains the composition over an explicit worklist instead, so the
/// nesting is bounded by heap, not by stack — the same discipline as the
/// value-layer converters in `native_decoders.dart` and the serializers in
/// `sink_walk.dart`.
///
/// ## The erasure boundary
///
/// The driver is generic over the AST type but *erased* in the decoded type:
/// it threads results as `Object?`. Each composite decoder implements
/// [IterativeDecoder] with one [IterativeDecoder.expand] method that (a)
/// shape-checks the value, (b) lists its children as `(childDecoder,
/// childValue)` pairs, and (c) returns a reassembler that rebuilds this node's
/// *typed* result from the child results. The single `as`/reified cast to the
/// node's element type lives inside that typed class — the one principled
/// boundary, exactly as in the interpreter cleanup (`80ff0d5`): a cast to a
/// concrete reified type (`r[i] as A`, `result as List<A>`), never a `dynamic`
/// widening.
///
/// ## The un-trampolinable boundary
///
/// A decoder that is *not* an [IterativeDecoder] — a primitive leaf, a `.map`
/// (which wraps an opaque `B Function(A)`), or a `fromJsonObject` /
/// `fromYamlMapping` / `fromTomlTable` object decoder (whose user build
/// callback calls `accessor.field(...)` → `.decode` synchronously) — is
/// decoded by calling `.decode` directly. Those user-callback frames run on
/// the native stack and cannot be trampolined without a breaking change to the
/// public `AstDecoder.decode` signature, so they are left as a documented
/// host-recursion boundary. In practice they are shallow: a struct decoder
/// recurses once per *schema* level, not once per *value* level, and the deep
/// axis (list/map/nullable nesting) is exactly what this driver makes safe.
library;

import 'decoder.dart';

/// Rebuilds a composite node's typed result from its children's decoded
/// results (supplied in [IterativeDecoder.expand]'s child order). The reified
/// cast to the node's element type is confined to the implementing class.
typedef Reassemble = Object? Function(List<Object?> childResults);

/// A composite decoder that decomposes into child decode steps so the
/// [decodeIterative] driver can drain it without native-stack recursion.
abstract interface class IterativeDecoder<AST> {
  /// Decompose decoding [value] with this composite into the children to
  /// decode and a reassembler for the typed result.
  ///
  /// Throws [DecodeException] on a shape mismatch, identically to the
  /// equivalent recursive `decode`.
  (List<(AstDecoder<AST, Object?>, AST)>, Reassemble) expand(AST value);
}

/// Decode [rootValue] with [root] over an explicit worklist.
///
/// Composite nodes (those implementing [IterativeDecoder]) are expanded and
/// reassembled iteratively; every other decoder is invoked directly (see the
/// library doc on the un-trampolinable boundary). Returns the erased result;
/// the caller confines the cast back to its declared type.
Object? decodeIterative<AST>(AstDecoder<AST, Object?> root, AST rootValue) {
  final out = <Object?>[null];
  final stack = <void Function()>[];

  // Mutually recursive *in scheduling* only: every task body runs in the
  // drain loop below, so there is no native-stack recursion. A composite's
  // reassemble step is scheduled before its children, so (LIFO) the children
  // fully drain before the parent reassembles.
  late final void Function(
    AstDecoder<AST, Object?>,
    AST,
    void Function(Object?),
  )
  schedule;
  schedule = (decoder, value, sink) {
    stack.add(() {
      if (decoder is IterativeDecoder<AST>) {
        final composite = decoder as IterativeDecoder<AST>;
        final (children, reassemble) = composite.expand(value);
        final results = List<Object?>.filled(children.length, null);
        stack.add(() => sink(reassemble(results)));
        for (var i = children.length - 1; i >= 0; i--) {
          final idx = i;
          final (childDecoder, childValue) = children[idx];
          schedule(childDecoder, childValue, (r) => results[idx] = r);
        }
      } else {
        sink(decoder.decode(value));
      }
    });
  };

  schedule(root, rootValue, (v) => out[0] = v);
  while (stack.isNotEmpty) {
    stack.removeLast()();
  }
  return out[0];
}
