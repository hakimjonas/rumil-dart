/// HCL (HashiCorp Configuration Language) AST types.
library;

import '_equality.dart';

// ---------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------

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

/// HCL object (map with `=` or `:` assignment).
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

/// HCL reference: a bare identifier used as a variable reference.
final class HclReference extends HclValue {
  /// The identifier name.
  final String path;

  /// Creates a reference.
  const HclReference(this.path);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HclReference && other.path == path;
  @override
  int get hashCode => path.hashCode;
}

// ---------------------------------------------------------------------------
// Expression nodes
// ---------------------------------------------------------------------------

/// Unary operator: `-x` or `!x`.
final class HclUnaryOp extends HclValue {
  /// The operator (`"-"` or `"!"`).
  final String op;

  /// The operand.
  final HclValue operand;

  /// Creates a unary operation.
  const HclUnaryOp(this.op, this.operand);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclUnaryOp && other.op == op && other.operand == operand;
  @override
  int get hashCode => Object.hash(op, operand);
}

/// Binary operator: `a + b`, `a == b`, `a && b`, etc.
final class HclBinaryOp extends HclValue {
  /// The operator (e.g. `"+"`, `"=="`, `"&&"`).
  final String op;

  /// The left operand.
  final HclValue left;

  /// The right operand.
  final HclValue right;

  /// Creates a binary operation.
  const HclBinaryOp(this.op, this.left, this.right);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclBinaryOp &&
          other.op == op &&
          other.left == left &&
          other.right == right;
  @override
  int get hashCode => Object.hash(op, left, right);
}

/// Conditional (ternary): `condition ? then_ : else_`.
final class HclConditional extends HclValue {
  /// The condition expression.
  final HclValue condition;

  /// The then branch.
  final HclValue then_;

  /// The else branch.
  final HclValue else_;

  /// Creates a conditional expression.
  const HclConditional(this.condition, this.then_, this.else_);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclConditional &&
          other.condition == condition &&
          other.then_ == then_ &&
          other.else_ == else_;
  @override
  int get hashCode => Object.hash(condition, then_, else_);
}

/// Function call: `name(args...)`.
final class HclFunctionCall extends HclValue {
  /// The function name.
  final String name;

  /// The arguments.
  final List<HclValue> args;

  /// Whether the final argument uses `...` expansion.
  final bool expandFinal;

  /// Creates a function call.
  const HclFunctionCall(this.name, this.args, this.expandFinal);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclFunctionCall &&
          other.name == name &&
          listEquals(args, other.args) &&
          other.expandFinal == expandFinal;
  @override
  int get hashCode => Object.hash(name, listHash(args), expandFinal);
}

/// Index access: `collection[index]`.
final class HclIndex extends HclValue {
  /// The collection being indexed.
  final HclValue collection;

  /// The index expression.
  final HclValue index;

  /// Creates an index access.
  const HclIndex(this.collection, this.index);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclIndex &&
          other.collection == collection &&
          other.index == index;
  @override
  int get hashCode => Object.hash(collection, index);
}

/// Attribute access: `object.name`.
final class HclGetAttr extends HclValue {
  /// The object being accessed.
  final HclValue object;

  /// The attribute name.
  final String name;

  /// Creates an attribute access.
  const HclGetAttr(this.object, this.name);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclGetAttr && other.object == object && other.name == name;
  @override
  int get hashCode => Object.hash(object, name);
}

/// Attribute splat: `object.*.attr1.attr2`.
final class HclAttrSplat extends HclValue {
  /// The object being splatted.
  final HclValue object;

  /// The attribute chain after `.*`.
  final List<String> attrs;

  /// Creates an attribute splat.
  const HclAttrSplat(this.object, this.attrs);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclAttrSplat &&
          other.object == object &&
          listEquals(attrs, other.attrs);
  @override
  int get hashCode => Object.hash(object, listHash(attrs));
}

/// Full splat: `object[*].attr[0]...`.
final class HclFullSplat extends HclValue {
  /// The object being splatted.
  final HclValue object;

  /// The accessor chain after `[*]`.
  final List<HclPostfixOp> accessors;

  /// Creates a full splat.
  const HclFullSplat(this.object, this.accessors);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclFullSplat &&
          other.object == object &&
          listEquals(accessors, other.accessors);
  @override
  int get hashCode => Object.hash(object, listHash(accessors));
}

/// For-tuple: `[for k, v in coll : body if cond]`.
final class HclForTuple extends HclValue {
  /// The key variable (null if single-variable form).
  final String? keyVar;

  /// The value variable.
  final String valueVar;

  /// The collection expression.
  final HclValue collection;

  /// The body expression.
  final HclValue body;

  /// Optional filter condition.
  final HclValue? condition;

  /// Creates a for-tuple expression.
  const HclForTuple(
    this.keyVar,
    this.valueVar,
    this.collection,
    this.body,
    this.condition,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclForTuple &&
          other.keyVar == keyVar &&
          other.valueVar == valueVar &&
          other.collection == collection &&
          other.body == body &&
          other.condition == condition;
  @override
  int get hashCode =>
      Object.hash(keyVar, valueVar, collection, body, condition);
}

/// For-object: `{for k, v in coll : keyExpr => valExpr... if cond}`.
final class HclForObject extends HclValue {
  /// The key variable (null if single-variable form).
  final String? keyVar;

  /// The value variable.
  final String valueVar;

  /// The collection expression.
  final HclValue collection;

  /// The key expression.
  final HclValue keyExpr;

  /// The value expression.
  final HclValue valueExpr;

  /// Whether the result is grouped (`...` suffix).
  final bool grouping;

  /// Optional filter condition.
  final HclValue? condition;

  /// Creates a for-object expression.
  const HclForObject(
    this.keyVar,
    this.valueVar,
    this.collection,
    this.keyExpr,
    this.valueExpr,
    this.grouping,
    this.condition,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclForObject &&
          other.keyVar == keyVar &&
          other.valueVar == valueVar &&
          other.collection == collection &&
          other.keyExpr == keyExpr &&
          other.valueExpr == valueExpr &&
          other.grouping == grouping &&
          other.condition == condition;
  @override
  int get hashCode => Object.hash(
    keyVar,
    valueVar,
    collection,
    keyExpr,
    valueExpr,
    grouping,
    condition,
  );
}

/// Parenthesized expression (preserved for round-trip fidelity).
final class HclParenExpr extends HclValue {
  /// The inner expression.
  final HclValue inner;

  /// Creates a parenthesized expression.
  const HclParenExpr(this.inner);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HclParenExpr && other.inner == inner;
  @override
  int get hashCode => inner.hashCode;
}

/// String template: `"literal${expr}literal"`.
final class HclTemplate extends HclValue {
  /// The template parts.
  final List<HclTemplatePart> parts;

  /// Creates a template.
  const HclTemplate(this.parts);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclTemplate && listEquals(parts, other.parts);
  @override
  int get hashCode => listHash(parts);
}

/// Heredoc string: `<<MARKER` or `<<-MARKER`.
final class HclHeredoc extends HclValue {
  /// The delimiter marker.
  final String marker;

  /// Whether indent-stripping is enabled (`<<-`).
  final bool indented;

  /// The template parts within the heredoc body.
  final List<HclTemplatePart> parts;

  /// Creates a heredoc.
  const HclHeredoc(this.marker, this.indented, this.parts);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclHeredoc &&
          other.marker == marker &&
          other.indented == indented &&
          listEquals(parts, other.parts);
  @override
  int get hashCode => Object.hash(marker, indented, listHash(parts));
}

// ---------------------------------------------------------------------------
// Template parts
// ---------------------------------------------------------------------------

/// A part of a string template or heredoc body.
sealed class HclTemplatePart {
  /// Base constructor.
  const HclTemplatePart();
}

/// Literal text within a template.
final class HclTemplateLiteral extends HclTemplatePart {
  /// The literal text.
  final String value;

  /// Creates a template literal.
  const HclTemplateLiteral(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclTemplateLiteral && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// Interpolation within a template: `${expr}` or `${~ expr ~}`.
final class HclTemplateInterpolation extends HclTemplatePart {
  /// The interpolated expression.
  final HclValue expr;

  /// Whether leading whitespace is stripped (`~` before expr).
  final bool stripBefore;

  /// Whether trailing whitespace is stripped (`~` after expr).
  final bool stripAfter;

  /// Creates a template interpolation.
  const HclTemplateInterpolation(
    this.expr, {
    this.stripBefore = false,
    this.stripAfter = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclTemplateInterpolation &&
          other.expr == expr &&
          other.stripBefore == stripBefore &&
          other.stripAfter == stripAfter;
  @override
  int get hashCode => Object.hash(expr, stripBefore, stripAfter);
}

/// Template if directive: `%{if cond}...%{else}...%{endif}`.
final class HclTemplateIf extends HclTemplatePart {
  /// The condition expression.
  final HclValue condition;

  /// The then branch parts.
  final List<HclTemplatePart> thenBranch;

  /// The else branch parts (null if no else).
  final List<HclTemplatePart>? elseBranch;

  /// Creates a template if directive.
  const HclTemplateIf(this.condition, this.thenBranch, this.elseBranch);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclTemplateIf &&
          other.condition == condition &&
          listEquals(thenBranch, other.thenBranch) &&
          ((elseBranch == null && other.elseBranch == null) ||
              (elseBranch != null &&
                  other.elseBranch != null &&
                  listEquals(elseBranch!, other.elseBranch!)));
  @override
  int get hashCode =>
      Object.hash(condition, listHash(thenBranch), elseBranch?.length);
}

/// Template for directive: `%{for x in list}...%{endfor}`.
final class HclTemplateFor extends HclTemplatePart {
  /// The key variable (null if single-variable form).
  final String? keyVar;

  /// The value variable.
  final String valueVar;

  /// The collection expression.
  final HclValue collection;

  /// The body parts.
  final List<HclTemplatePart> body;

  /// Creates a template for directive.
  const HclTemplateFor(this.keyVar, this.valueVar, this.collection, this.body);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclTemplateFor &&
          other.keyVar == keyVar &&
          other.valueVar == valueVar &&
          other.collection == collection &&
          listEquals(body, other.body);
  @override
  int get hashCode => Object.hash(keyVar, valueVar, collection, listHash(body));
}

// ---------------------------------------------------------------------------
// Postfix operators (used in splat chains)
// ---------------------------------------------------------------------------

/// A postfix operation in a splat accessor chain.
sealed class HclPostfixOp {
  /// Base constructor.
  const HclPostfixOp();
}

/// Attribute access in a splat chain: `.name`.
final class HclPostfixGetAttr extends HclPostfixOp {
  /// The attribute name.
  final String name;

  /// Creates a postfix attribute access.
  const HclPostfixGetAttr(this.name);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclPostfixGetAttr && other.name == name;
  @override
  int get hashCode => name.hashCode;
}

/// Index access in a splat chain: `[index]`.
final class HclPostfixIndex extends HclPostfixOp {
  /// The index expression.
  final HclValue index;

  /// Creates a postfix index access.
  const HclPostfixIndex(this.index);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HclPostfixIndex && other.index == index;
  @override
  int get hashCode => index.hashCode;
}

// ---------------------------------------------------------------------------
// Document
// ---------------------------------------------------------------------------

/// An HCL document. List of pairs because HCL allows multiple
/// blocks with the same type name.
typedef HclDocument = List<(String, HclValue)>;
