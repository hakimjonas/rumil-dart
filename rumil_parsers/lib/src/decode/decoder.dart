/// AST decoders: convert parsed values into typed Dart objects.
library;

/// Decodes a value of AST type [AST] into a Dart value of type [A].
abstract interface class AstDecoder<AST, A> {
  /// Decode [value] into type [A]. Throws [DecodeException] on type mismatch.
  A decode(AST value);
}

/// Functor map on [AstDecoder].
extension AstDecoderOps<AST, A> on AstDecoder<AST, A> {
  /// Transform the decoded value.
  AstDecoder<AST, B> map<B>(B Function(A) f) =>
      _MappedAstDecoder<AST, A, B>(this, f);
}

/// Navigates struct-like AST nodes (objects, tables, mappings).
abstract interface class AstStruct<AST> {
  /// Get the field named [name] from [value], or null if absent.
  AST? getField(AST value, String name);
}

/// Typed field accessor for struct-like AST nodes.
final class ObjectAccessor<AST> {
  final AST _value;
  final AstStruct<AST> _struct;

  /// Creates an accessor over [_value] using [_struct] for field lookup.
  const ObjectAccessor(this._value, this._struct);

  /// Extract a required field and decode it.
  A field<A>(String name, AstDecoder<AST, A> decoder) {
    final v = _struct.getField(_value, name);
    if (v == null) throw DecodeException('Missing field: $name');
    return decoder.decode(v);
  }

  /// Extract an optional field and decode it if present.
  A? optionalField<A>(String name, AstDecoder<AST, A> decoder) {
    final v = _struct.getField(_value, name);
    if (v == null) return null;
    return decoder.decode(v);
  }
}

/// Error thrown when AST decoding fails.
class DecodeException implements Exception {
  /// The error message.
  final String message;

  /// Creates a decode exception.
  const DecodeException(this.message);

  @override
  String toString() => 'DecodeException: $message';
}

// ---- Internal ----

final class _MappedAstDecoder<AST, A, B> implements AstDecoder<AST, B> {
  final AstDecoder<AST, A> _inner;
  final B Function(A) _f;
  const _MappedAstDecoder(this._inner, this._f);

  @override
  B decode(AST value) => _f(_inner.decode(value));
}
