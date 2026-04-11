/// Code generator for [AstSerializable]-annotated classes.
library;

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:rumil_codec/rumil_codec.dart';
import 'package:source_gen/source_gen.dart';

/// Generates `AstEncoder<T, JsonValue>` for `@AstSerializable` classes.
class AstEncoderGenerator extends GeneratorForAnnotation<AstSerializable> {
  /// Creates the AST encoder generator.
  const AstEncoderGenerator();

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@astSerializable can only be applied to classes.',
        element: element,
      );
    }

    final name = element.displayName;
    final formats = _readFormats(annotation);
    final buffer = StringBuffer();

    for (final format in formats) {
      if (element.isSealed) {
        buffer.writeln(_generateSumEncoder(element, name, format));
      } else {
        buffer.writeln(_generateProductEncoder(element, name, format));
      }
    }

    return buffer.toString();
  }

  List<String> _readFormats(ConstantReader annotation) {
    final formatsField = annotation.read('formats');
    if (formatsField.isNull ||
        formatsField.isList && formatsField.listValue.isEmpty) {
      return ['json'];
    }
    return formatsField.listValue
        .map((obj) => obj.getField('_name')?.toStringValue() ?? 'json')
        .toList();
  }

  String _generateProductEncoder(
    ClassElement element,
    String name,
    String format,
  ) {
    final suffix = _capitalize(format);
    final codecName = '_\$$name${suffix}Encoder';
    final astType = _astTypeName(format);
    final fields = _instanceFields(element);

    final fieldLines = fields
        .map((FieldElement f) {
          final encoder = _encoderForType(f.type, format);
          return "    b.field('${f.displayName}', value.${f.displayName}, $encoder);";
        })
        .join('\n');

    return '''
class $codecName implements AstEncoder<$name, $astType> {
  const $codecName();

  @override
  $astType encode($name value) {
    final b = ObjectBuilder<$astType>();
$fieldLines
    return ${_objectConstructor(format)}(
      Map.fromEntries(b.entries.map((e) => MapEntry(e.\$1, e.\$2))),
    );
  }
}

const ${_lowerFirst(name)}${suffix}Encoder = $codecName();
''';
  }

  String _generateSumEncoder(ClassElement element, String name, String format) {
    final suffix = _capitalize(format);
    final codecName = '_\$$name${suffix}Encoder';
    final astType = _astTypeName(format);
    final subtypes = _leafSubclasses(element);

    final cases = subtypes
        .map((ClassElement sub) {
          final subName = sub.displayName;
          final fields = _allInstanceFields(sub);
          final fieldLines = fields
              .map((FieldElement f) {
                final encoder = _encoderForType(f.type, format);
                return "      b.field('${f.displayName}', value.${f.displayName}, $encoder);";
              })
              .join('\n');

          return '''
      case $subName():
        b.field('type', '$subName', ${format}StringEncoder);
$fieldLines''';
        })
        .join('\n');

    return '''
class $codecName implements AstEncoder<$name, $astType> {
  const $codecName();

  @override
  $astType encode($name value) {
    final b = ObjectBuilder<$astType>();
    switch (value) {
$cases
    }
    return ${_objectConstructor(format)}(
      Map.fromEntries(b.entries.map((e) => MapEntry(e.\$1, e.\$2))),
    );
  }
}

const ${_lowerFirst(name)}${suffix}Encoder = $codecName();
''';
  }

  List<FieldElement> _instanceFields(ClassElement element) =>
      element.fields
          .where((FieldElement f) => !f.isStatic && f.isOriginDeclaration)
          .toList();

  List<FieldElement> _allInstanceFields(ClassElement element) {
    final fields = <FieldElement>[];
    var current = element;
    while (true) {
      fields.insertAll(0, _instanceFields(current));
      final superEl = current.supertype?.element;
      if (superEl is! ClassElement || superEl.library.isDartCore) break;
      current = superEl;
    }
    return fields;
  }

  List<ClassElement> _leafSubclasses(ClassElement sealed) {
    final leaves = <ClassElement>[];
    for (final child in _directChildren(sealed)) {
      if (child.isSealed) {
        leaves.addAll(_leafSubclasses(child));
      } else {
        leaves.add(child);
      }
    }
    return leaves;
  }

  List<ClassElement> _directChildren(ClassElement parent) =>
      parent.library.classes
          .where(
            (ClassElement c) =>
                c.supertype?.element == parent ||
                c.interfaces.any((InterfaceType i) => i.element == parent),
          )
          .toList();

  String _encoderForType(DartType type, String format) {
    if (type.isDartCoreInt) return '${format}IntEncoder';
    if (type.isDartCoreDouble) return '${format}DoubleEncoder';
    if (type.isDartCoreBool) return '${format}BoolEncoder';
    if (type.isDartCoreString) return '${format}StringEncoder';

    if (type is InterfaceType) {
      final name = type.element.displayName;

      if (name == 'List') {
        final elementType = type.typeArguments.first;
        return '${format}ListEncoder(${_encoderForType(elementType, format)})';
      }

      if (name == 'Map' && type.typeArguments.first.isDartCoreString) {
        final valueType = type.typeArguments[1];
        return '${format}MapEncoder(${_encoderForType(valueType, format)})';
      }

      if (type.nullabilitySuffix == NullabilitySuffix.question) {
        return '${format}NullableEncoder(${_lowerFirst(name)}${_capitalize(format)}Encoder)';
      }

      return '${_lowerFirst(name)}${_capitalize(format)}Encoder';
    }

    return '/* unknown type: $type */';
  }

  String _astTypeName(String format) => switch (format) {
    'json' => 'JsonValue',
    'yaml' => 'YamlValue',
    'toml' => 'TomlValue',
    'xml' => 'XmlNode',
    _ => 'JsonValue',
  };

  String _objectConstructor(String format) => switch (format) {
    'json' => 'JsonObject',
    'yaml' => 'YamlMapping',
    'toml' => 'TomlTable',
    _ => 'JsonObject',
  };

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  static String _lowerFirst(String s) =>
      s.isEmpty ? s : '${s[0].toLowerCase()}${s.substring(1)}';
}
