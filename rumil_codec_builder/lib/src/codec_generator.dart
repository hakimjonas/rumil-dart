/// Code generator for [BinarySerializable]-annotated classes.
library;

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:rumil_codec/rumil_codec.dart';
import 'package:source_gen/source_gen.dart';

/// Generates `BinaryCodec<T>` for `@BinarySerializable` classes.
class CodecGenerator extends GeneratorForAnnotation<BinarySerializable> {
  /// Creates the binary codec generator.
  const CodecGenerator();

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is ClassElement && element.isSealed) {
      return _generateSumCodec(element);
    }
    if (element is ClassElement) {
      return _generateProductCodec(element);
    }
    throw InvalidGenerationSourceError(
      '@binarySerializable can only be applied to classes.',
      element: element,
    );
  }

  String _generateProductCodec(ClassElement element) {
    final name = element.displayName;
    final codecName = '_\$${name}Codec';
    final fields = _instanceFields(element);

    final writeLines = fields
        .map((FieldElement f) {
          final codec = _codecForType(f.type);
          return '    $codec.write(writer, value.${f.displayName});';
        })
        .join('\n');

    final readArgs = fields
        .map((FieldElement f) {
          final codec = _codecForType(f.type);
          return '$codec.read(reader)';
        })
        .join(', ');

    return '''
class $codecName implements BinaryCodec<$name> {
  const $codecName();

  @override
  void write(ByteWriter writer, $name value) {
$writeLines
  }

  @override
  $name read(ByteReader reader) => $name($readArgs);
}

const ${_lowerFirst(name)}Codec = $codecName();
''';
  }

  String _generateSumCodec(ClassElement element) {
    final name = element.displayName;
    final codecName = '_\$${name}Codec';
    final subtypes = _leafSubclasses(element);

    final writeCases = <String>[];
    final readCases = <String>[];

    for (var i = 0; i < subtypes.length; i++) {
      final sub = subtypes[i];
      final subName = sub.displayName;
      final fields = _allInstanceFields(sub);

      final fieldWrites = fields
          .map((FieldElement f) {
            final codec = _codecForType(f.type);
            return '        $codec.write(writer, value.${f.displayName});';
          })
          .join('\n');

      writeCases.add('''
      case $subName():
        Varint.write(writer, $i);
$fieldWrites''');

      final fieldReads = fields
          .map((FieldElement f) {
            final codec = _codecForType(f.type);
            return '$codec.read(reader)';
          })
          .join(', ');

      readCases.add('      $i => $subName($fieldReads)');
    }

    return '''
class $codecName implements BinaryCodec<$name> {
  const $codecName();

  @override
  void write(ByteWriter writer, $name value) {
    switch (value) {
${writeCases.join('\n')}
    }
  }

  @override
  $name read(ByteReader reader) {
    final ordinal = Varint.read(reader);
    return switch (ordinal) {
${readCases.join(',\n')},
      _ => throw InvalidOrdinal(ordinal, ${subtypes.length - 1}, reader.offset),
    };
  }
}

const ${_lowerFirst(name)}Codec = $codecName();
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

  String _codecForType(DartType type) {
    if (type.isDartCoreInt) return 'intCodec';
    if (type.isDartCoreDouble) return 'doubleCodec';
    if (type.isDartCoreBool) return 'boolCodec';
    if (type.isDartCoreString) return 'stringCodec';

    if (type is InterfaceType) {
      final name = type.element.displayName;

      if (name == 'Uint8List') return 'bytesCodec';

      if (name == 'List') {
        final elementType = type.typeArguments.first;
        return 'listOf(${_codecForType(elementType)})';
      }

      if (name == 'Set') {
        final elementType = type.typeArguments.first;
        return 'setOf(${_codecForType(elementType)})';
      }

      if (name == 'Map') {
        final keyType = type.typeArguments[0];
        final valueType = type.typeArguments[1];
        return 'mapOf(${_codecForType(keyType)}, ${_codecForType(valueType)})';
      }

      if (type.nullabilitySuffix == NullabilitySuffix.question) {
        return 'nullableOf(${_lowerFirst(name)}Codec)';
      }

      return '${_lowerFirst(name)}Codec';
    }

    return '/* unknown type: $type */';
  }

  static String _lowerFirst(String s) =>
      s.isEmpty ? s : '${s[0].toLowerCase()}${s.substring(1)}';
}
