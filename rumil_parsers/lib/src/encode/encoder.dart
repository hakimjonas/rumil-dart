/// AST encoders: convert typed Dart objects into AST values.
library;

/// Encodes a Dart value of type [A] into an AST value of type [AST].
abstract interface class AstEncoder<A, AST> {
  /// Encode [value] into an AST node.
  AST encode(A value);
}

/// Contravariant map on [AstEncoder].
extension AstEncoderOps<A, AST> on AstEncoder<A, AST> {
  /// Adapt the encoder to accept a different input type.
  AstEncoder<B, AST> contramap<B>(A Function(B) f) =>
      _ContramappedAstEncoder<A, B, AST>(this, f);
}

/// Builds an AST object (JSON Object, TOML Table, etc.) from named fields.
final class ObjectBuilder<AST> {
  /// Creates an empty object builder.
  ObjectBuilder();

  /// The accumulated (name, value) pairs.
  final List<(String, AST)> entries = [];

  /// Add a field with [name] encoded via [encoder].
  void field<A>(String name, A value, AstEncoder<A, AST> encoder) {
    entries.add((name, encoder.encode(value)));
  }

  /// Add a field only if [value] is not null.
  void optionalField<A>(String name, A? value, AstEncoder<A, AST> encoder) {
    if (value != null) entries.add((name, encoder.encode(value)));
  }
}

// ---- Internal ----

final class _ContramappedAstEncoder<A, B, AST> implements AstEncoder<B, AST> {
  final AstEncoder<A, AST> _inner;
  final A Function(B) _f;
  const _ContramappedAstEncoder(this._inner, this._f);

  @override
  AST encode(B value) => _inner.encode(_f(value));
}
