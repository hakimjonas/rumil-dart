/// Format-specific string escaping utilities.
library;

/// Escape a string for JSON (RFC 8259 §7).
///
/// Handles `\b`, `\f`, `\t`, `\n`, `\r`, `\"`, `\\`, and all control
/// characters below U+0020 via `\u00xx`.
String escapeJson(String s) => _escapeQuoted(s, escapeSlash: false);

/// Escape a string for TOML basic strings (TOML v1.0.0 §basic-string).
///
/// Same control character handling as JSON.
String escapeToml(String s) => _escapeQuoted(s, escapeSlash: false);

/// Escape a string for YAML double-quoted strings (YAML 1.2 §7.3.1).
///
/// Same control character handling as JSON.
String escapeYaml(String s) => _escapeQuoted(s, escapeSlash: false);

/// Escape a string for HCL double-quoted strings.
///
/// Same control character handling as JSON, plus `${` → `$${` and `%{` → `%%{`
/// to prevent template interpolation.
String escapeHcl(String s) => _escapeQuoted(
  s,
  escapeSlash: false,
).replaceAll(r'${', r'$${').replaceAll('%{', '%%{');

/// Escape text content for XML.
String escapeXmlText(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// Escape attribute values for XML.
String escapeXmlAttr(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Shared codeunit-level escaping for JSON, TOML, and YAML quoted strings.
String _escapeQuoted(String s, {required bool escapeSlash}) {
  final buffer = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    switch (c) {
      case 0x08:
        buffer.write(r'\b');
      case 0x09:
        buffer.write(r'\t');
      case 0x0A:
        buffer.write(r'\n');
      case 0x0C:
        buffer.write(r'\f');
      case 0x0D:
        buffer.write(r'\r');
      case 0x22:
        buffer.write(r'\"');
      case 0x2F when escapeSlash:
        buffer.write(r'\/');
      case 0x5C:
        buffer.write(r'\\');
      default:
        if (c < 0x20) {
          buffer.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
        } else {
          buffer.writeCharCode(c);
        }
    }
  }
  return buffer.toString();
}
