/// TOML AST types.
library;

/// A TOML value.
sealed class TomlValue {
  const TomlValue();
}

final class TomlString extends TomlValue {
  final String value;
  const TomlString(this.value);
}

final class TomlInteger extends TomlValue {
  final int value;
  const TomlInteger(this.value);
}

final class TomlFloat extends TomlValue {
  final double value;
  const TomlFloat(this.value);
}

final class TomlBool extends TomlValue {
  final bool value;
  const TomlBool(this.value);
}

final class TomlDateTime extends TomlValue {
  final DateTime value;
  const TomlDateTime(this.value);
}

final class TomlLocalDateTime extends TomlValue {
  final DateTime value;
  const TomlLocalDateTime(this.value);
}

final class TomlLocalDate extends TomlValue {
  final int year, month, day;
  const TomlLocalDate(this.year, this.month, this.day);
}

final class TomlLocalTime extends TomlValue {
  final int hour, minute, second;
  final int nanosecond;
  const TomlLocalTime(
    this.hour,
    this.minute,
    this.second, [
    this.nanosecond = 0,
  ]);
}

final class TomlArray extends TomlValue {
  final List<TomlValue> elements;
  const TomlArray(this.elements);
}

final class TomlTable extends TomlValue {
  final Map<String, TomlValue> pairs;
  const TomlTable(this.pairs);
}

/// A TOML document is a table at the top level.
typedef TomlDocument = Map<String, TomlValue>;
