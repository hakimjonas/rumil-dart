/// YAML AST types.
library;

/// A YAML value.
sealed class YamlValue {
  const YamlValue();
}

final class YamlNull extends YamlValue {
  const YamlNull();
}

final class YamlBool extends YamlValue {
  final bool value;
  const YamlBool(this.value);
}

final class YamlInteger extends YamlValue {
  final int value;
  const YamlInteger(this.value);
}

final class YamlFloat extends YamlValue {
  final double value;
  const YamlFloat(this.value);
}

final class YamlString extends YamlValue {
  final String value;
  const YamlString(this.value);
}

final class YamlSequence extends YamlValue {
  final List<YamlValue> elements;
  const YamlSequence(this.elements);
}

final class YamlMapping extends YamlValue {
  final Map<String, YamlValue> pairs;
  const YamlMapping(this.pairs);
}

/// A YAML document (simplified: just the root value).
typedef YamlDocument = YamlValue;
