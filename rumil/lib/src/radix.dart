/// Radix tree (compressed trie) for O(m) string matching.
///
/// Matches one of many string alternatives in time proportional to the
/// matched string length, independent of the number of alternatives.
library;

import 'dart:math' as math;

/// A node in a radix tree (compressed trie).
///
/// Use [RadixNode.fromStrings] to build a tree, then [matchAtOrNull]
/// or [matchAt] to match against input.
final class RadixNode {
  final String matched;
  final bool _isTerminal;
  final int _bitMask;
  final List<String?> _prefixes;
  final List<RadixNode?> _children;

  const RadixNode._(
    this.matched,
    this._isTerminal,
    this._bitMask,
    this._prefixes,
    this._children,
  );

  /// Match at [offset] in [input]. Returns end position, or -1 if no match.
  int matchAt(String input, int offset) {
    final result = matchAtOrNull(input, offset);
    return result == null ? -1 : offset + result.length;
  }

  /// Match at [offset] in [input]. Returns the matched string, or null.
  String? matchAtOrNull(String input, int offset) {
    var node = this;
    String? currentMatch;

    while (true) {
      final validMatch = node._isTerminal ? node.matched : currentMatch;

      if (offset >= input.length) return validMatch;

      final c = input.codeUnitAt(offset);
      final idx = c & node._bitMask;

      if (idx >= node._prefixes.length) return validMatch;

      final prefix = node._prefixes[idx];
      if (prefix == null) return validMatch;

      final prefixLen = prefix.length;
      if (offset + prefixLen > input.length) return validMatch;

      // Check prefix match
      var matches = true;
      for (var i = 0; i < prefixLen; i++) {
        if (input.codeUnitAt(offset + i) != prefix.codeUnitAt(i)) {
          matches = false;
          break;
        }
      }
      if (!matches) return validMatch;

      final child = node._children[idx];
      if (child == null) {
        return node.matched.isEmpty ? prefix : node.matched + prefix;
      }

      currentMatch = validMatch;
      offset += prefixLen;
      node = child;
    }
  }

  /// Build a radix tree from a list of strings.
  static RadixNode fromStrings(List<String> strings) {
    final list = strings.toSet().where((s) => s.isNotEmpty).toList();
    if (list.isEmpty) {
      return const RadixNode._('', false, 0, [], []);
    }
    return _buildNode('', list);
  }

  static RadixNode _buildNode(String matched, List<String> strings) {
    final empty = strings.where((s) => s.isEmpty).toList();
    final nonEmpty = strings.where((s) => s.isNotEmpty).toList();
    final isTerminal = empty.isNotEmpty;

    if (nonEmpty.isEmpty) {
      return RadixNode._(matched, true, 0, const [], const []);
    }

    // Group by first character
    final grouped = <int, List<String>>{};
    for (final s in nonEmpty) {
      final c = s.codeUnitAt(0);
      (grouped[c] ??= []).add(s);
    }

    final chars = grouped.keys.toSet();
    final bitMask = _computeBitMask(chars);
    final arraySize = bitMask + 1;

    final prefixes = List<String?>.filled(arraySize, null);
    final children = List<RadixNode?>.filled(arraySize, null);

    for (final entry in grouped.entries) {
      final idx = entry.key & bitMask;
      final strs = entry.value;

      final commonPrefix = strs.reduce(_commonPrefixOf);
      final remaining =
          strs.map((s) => s.substring(commonPrefix.length)).toList();

      prefixes[idx] = commonPrefix;

      if (remaining.every((s) => s.isEmpty)) {
        children[idx] = null;
      } else {
        children[idx] = _buildNode(matched + commonPrefix, remaining);
      }
    }

    return RadixNode._(matched, isTerminal, bitMask, prefixes, children);
  }

  static int _computeBitMask(Set<int> chars) {
    var mask = 0;
    var bits = 0;
    while (bits < 16 && _hasCollision(chars, mask)) {
      bits += 1;
      mask = (1 << bits) - 1;
    }
    return mask;
  }

  static bool _hasCollision(Set<int> chars, int mask) {
    final masked = chars.map((c) => c & mask).toSet();
    return masked.length != chars.length;
  }

  static String _commonPrefixOf(String a, String b) {
    final len = math.min(a.length, b.length);
    var i = 0;
    while (i < len && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    return a.substring(0, i);
  }
}
