/// TOML AST types.
library;

/// A TOML value.
sealed class TomlValue {
  /// Base constructor.
  const TomlValue();
}

/// TOML string.
final class TomlString extends TomlValue {
  /// The string content.
  final String value;

  /// Creates a string value.
  const TomlString(this.value);
}

/// TOML integer.
final class TomlInteger extends TomlValue {
  /// The integer value.
  final int value;

  /// Creates an integer value.
  const TomlInteger(this.value);
}

/// TOML float.
final class TomlFloat extends TomlValue {
  /// The float value.
  final double value;

  /// Creates a float value.
  const TomlFloat(this.value);
}

/// TOML boolean.
final class TomlBool extends TomlValue {
  /// The boolean value.
  final bool value;

  /// Creates a boolean value.
  const TomlBool(this.value);
}

/// TOML offset datetime (absolute point in time).
final class TomlDateTime extends TomlValue {
  /// The datetime value (UTC).
  final DateTime value;

  /// Creates an offset datetime.
  const TomlDateTime(this.value);
}

/// TOML local datetime (no timezone).
final class TomlLocalDateTime extends TomlValue {
  /// The datetime value (local).
  final DateTime value;

  /// Creates a local datetime.
  const TomlLocalDateTime(this.value);
}

/// TOML local date.
final class TomlLocalDate extends TomlValue {
  /// The year.
  final int year;

  /// The month (1-12).
  final int month;

  /// The day (1-31).
  final int day;

  /// Creates a local date.
  const TomlLocalDate(this.year, this.month, this.day);
}

/// TOML local time.
final class TomlLocalTime extends TomlValue {
  /// The hour (0-23).
  final int hour;

  /// The minute (0-59).
  final int minute;

  /// The second (0-59).
  final int second;

  /// Sub-second precision in nanoseconds.
  final int nanosecond;

  /// Creates a local time.
  const TomlLocalTime(
    this.hour,
    this.minute,
    this.second, [
    this.nanosecond = 0,
  ]);
}

/// TOML array.
final class TomlArray extends TomlValue {
  /// The array elements.
  final List<TomlValue> elements;

  /// Creates an array value.
  const TomlArray(this.elements);
}

/// TOML table (inline or section).
final class TomlTable extends TomlValue {
  /// The key-value pairs.
  final Map<String, TomlValue> pairs;

  /// Creates a table value.
  const TomlTable(this.pairs);
}

/// A TOML document is a table at the top level.
typedef TomlDocument = Map<String, TomlValue>;
