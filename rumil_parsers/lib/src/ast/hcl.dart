/// HCL (HashiCorp Configuration Language) AST types.
library;

import '_equality.dart';

/// An HCL value.
sealed class HclValue {
  /// Base constructor.
  const HclValue();
}

/// HCL string.
final class HclString extends HclValue {
  /// The string content.
  final String value;

  /// Creates a string value.
  const HclString(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HclString && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// HCL number.
final class HclNumber extends HclValue {
  /// The numeric value.
  final num value;

  /// Creates a number value.
  const HclNumber(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HclNumber && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// HCL boolean.
final class HclBool extends HclValue {
  /// The boolean value.
  final bool value;

  /// Creates a boolean value.
  const HclBool(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HclBool && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// HCL null.
final class HclNull extends HclValue {
  /// Creates a null value.
  const HclNull();

  @override
  bool operator ==(Object other) => identical(this, other) || other is HclNull;
  @override
  int get hashCode => 0;
}

/// HCL list (tuple).
final class HclList extends HclValue {
  /// The list elements.
  final List<HclValue> elements;

  /// Creates a list value.
  const HclList(this.elements);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclList && listEquals(elements, other.elements);
  @override
  int get hashCode => listHash(elements);
}

/// HCL object (map with `=` assignment).
final class HclObject extends HclValue {
  /// The key-value pairs.
  final Map<String, HclValue> fields;

  /// Creates an object value.
  const HclObject(this.fields);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclObject && mapEquals(fields, other.fields);
  @override
  int get hashCode => mapHash(fields);
}

/// HCL block: `type "label" { body }`.
final class HclBlock extends HclValue {
  /// The block type (e.g. `resource`, `variable`).
  final String type;

  /// The block labels (e.g. `"aws_instance"`, `"web"`).
  final List<String> labels;

  /// The block body (attributes and nested blocks).
  final Map<String, HclValue> body;

  /// Creates a block.
  const HclBlock(this.type, this.labels, this.body);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclBlock &&
          other.type == type &&
          listEquals(labels, other.labels) &&
          mapEquals(body, other.body);
  @override
  int get hashCode => Object.hash(type, listHash(labels), mapHash(body));
}

/// HCL reference: `aws_instance.web.public_ip`.
final class HclReference extends HclValue {
  /// The dotted reference path.
  final String path;

  /// Creates a reference.
  const HclReference(this.path);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HclReference && other.path == path;
  @override
  int get hashCode => path.hashCode;
}

/// An HCL document. List of pairs because HCL allows multiple
/// blocks with the same type name.
typedef HclDocument = List<(String, HclValue)>;
