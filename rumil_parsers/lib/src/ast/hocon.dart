/// HOCON AST types.
///
/// The AST preserves the *shape of the source document* rather than the
/// resolved configuration: substitutions, value concatenations, and
/// include statements are all first-class nodes. Resolving them —
/// merging objects, concatenating values, loading includes, and looking
/// up substitution paths — is the job of `resolveHocon` in
/// `../hocon_resolve.dart`, which runs iteratively over an explicit
/// worklist.
///
/// [HoconObject] keeps its entries as an ordered list (not a map) so
/// that later assignments can look back at the value a path had before
/// it was reassigned — the mechanism behind self-referential fields
/// like `path = ${path} [ /usr/bin ]`.
library;

/// A HOCON value.
///
/// Sealed hierarchy; exhaustive `switch` is supported and recommended.
sealed class HoconValue {
  /// Base constructor.
  const HoconValue();
}

/// HOCON `null`.
final class HoconNull extends HoconValue {
  /// Creates a null value.
  const HoconNull();

  @override
  bool operator ==(Object other) => other is HoconNull;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'HoconNull()';
}

/// HOCON boolean (`true` / `false`).
final class HoconBool extends HoconValue {
  /// The boolean value.
  final bool value;

  /// Creates a boolean value.
  const HoconBool(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HoconBool && other.value == value;

  @override
  int get hashCode => Object.hash('hocon-bool', value);

  @override
  String toString() => 'HoconBool($value)';
}

/// HOCON integer. Split from [HoconDouble] at parse time so `int`
/// precision is preserved exactly (no round-trip through `double`).
final class HoconInt extends HoconValue {
  /// The integer value.
  final int value;

  /// Creates an integer value.
  const HoconInt(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HoconInt && other.value == value;

  @override
  int get hashCode => Object.hash('hocon-int', value);

  @override
  String toString() => 'HoconInt($value)';
}

/// HOCON floating-point number.
final class HoconDouble extends HoconValue {
  /// The double value.
  final double value;

  /// Creates a double value.
  const HoconDouble(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HoconDouble && other.value == value;

  @override
  int get hashCode => Object.hash('hocon-double', value);

  @override
  String toString() => 'HoconDouble($value)';
}

/// HOCON string — quoted, triple-quoted, or unquoted.
final class HoconString extends HoconValue {
  /// The decoded string content.
  final String value;

  /// Creates a string value.
  const HoconString(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HoconString && other.value == value;

  @override
  int get hashCode => Object.hash('hocon-string', value);

  @override
  String toString() => "HoconString('$value')";
}

/// HOCON array.
final class HoconArray extends HoconValue {
  /// The elements, in source order.
  final List<HoconValue> elements;

  /// Creates an array value.
  const HoconArray(this.elements);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HoconArray &&
          other.elements.length == elements.length &&
          _listsEqual(other.elements, elements);

  @override
  int get hashCode => Object.hashAll(elements);

  @override
  String toString() => 'HoconArray($elements)';
}

bool _listsEqual(List<HoconValue> a, List<HoconValue> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// HOCON object.
///
/// Entries are an ordered list so that (a) source order is preserved
/// and (b) self-referential assignments can look back at the value a
/// path had *before* the current assignment. Includes interleave with
/// assignments in source order via [HoconIncludeEntry].
final class HoconObject extends HoconValue {
  /// The entries, in source order.
  final List<HoconEntry> entries;

  /// Creates an object value.
  const HoconObject(this.entries);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HoconObject &&
          other.entries.length == entries.length &&
          _entriesEqual(other.entries, entries);

  @override
  int get hashCode => Object.hashAll(entries);

  @override
  String toString() => 'HoconObject($entries)';
}

bool _entriesEqual(List<HoconEntry> a, List<HoconEntry> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One entry of a [HoconObject]: either a key assignment or an include
/// statement. A sealed type — rather than an optional key on a single
/// class — so the resolver can dispatch exhaustively and so include
/// statements interleave with assignments in source order.
sealed class HoconEntry {
  /// Base constructor.
  const HoconEntry();
}

/// A `path = value` (or `path : value`, `path += v`) assignment.
///
/// [path] holds the dotted key split into segments: `a.b.c = 1` has
/// path `['a', 'b', 'c']`.
final class HoconAssignment extends HoconEntry {
  /// The dotted key segments.
  final List<String> path;

  /// The assigned value.
  final HoconValue value;

  /// Creates an assignment.
  const HoconAssignment(this.path, this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HoconAssignment &&
          _stringListsEqual(other.path, path) &&
          other.value == value;

  @override
  int get hashCode => Object.hash(Object.hashAll(path), value);

  @override
  String toString() => 'HoconAssignment(${path.join('.')}, $value)';
}

/// An `include "resource"` statement at object-field position.
final class HoconIncludeEntry extends HoconEntry {
  /// The include statement.
  final HoconInclude include;

  /// Creates an include entry.
  const HoconIncludeEntry(this.include);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HoconIncludeEntry && other.include == include;

  @override
  int get hashCode => include.hashCode;

  @override
  String toString() => 'HoconIncludeEntry($include)';
}

/// A substitution: `${path}` or the optional form `${?path}`.
///
/// When [optional] is true, an unresolvable path disappears instead of
/// failing: the field is omitted, the array element dropped, or the
/// substitution contributes nothing to a string concatenation.
final class HoconSubstitution extends HoconValue {
  /// The dotted path as written in the source.
  final String path;

  /// True for the `${?path}` form.
  final bool optional;

  /// Creates a substitution.
  const HoconSubstitution(this.path, {required this.optional});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HoconSubstitution &&
          other.path == path &&
          other.optional == optional;

  @override
  int get hashCode => Object.hash('hocon-sub', path, optional);

  @override
  String toString() => 'HoconSubstitution($path${optional ? ' ?' : ''})';
}

/// A value concatenation: multiple values on the same line, combined
/// at resolution time.
///
/// - all strings (or simple values) → concatenated string, with the
///   whitespace between the parts preserved (the parser folds the
///   whitespace into the string parts);
/// - all objects → merged;
/// - all arrays → concatenated;
/// - mixed → a resolution error.
final class HoconConcat extends HoconValue {
  /// The concatenated parts, in source order. Whitespace that separates
  /// parts which resolve to objects/arrays appears as whitespace-only
  /// [HoconString] parts and is ignored by those combination rules.
  final List<HoconValue> parts;

  /// Creates a concatenation.
  const HoconConcat(this.parts);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HoconConcat &&
          other.parts.length == parts.length &&
          _listsEqual(other.parts, parts);

  @override
  int get hashCode => Object.hashAll(parts);

  @override
  String toString() => 'HoconConcat($parts)';
}

/// An `include` statement: `include "r"`, `include file("r")`,
/// `include url("r")`, `include classpath("r")`, each optionally
/// wrapped in `required(...)`.
final class HoconInclude extends HoconValue {
  /// The resource name as written (the quoted string inside any
  /// `file()`/`url()`/`classpath()` wrapper).
  final String resource;

  /// True for `required(...)` — a missing resource is an error instead
  /// of being silently ignored.
  final bool required;

  /// Creates an include statement.
  const HoconInclude(this.resource, {required this.required});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HoconInclude &&
          other.resource == resource &&
          other.required == required;

  @override
  int get hashCode => Object.hash('hocon-include', resource, required);

  @override
  String toString() => 'HoconInclude($resource${required ? ' required' : ''})';
}

bool _stringListsEqual(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
