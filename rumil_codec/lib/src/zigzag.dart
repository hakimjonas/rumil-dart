/// ZigZag encoding for signed integers.
///
/// Maps signed integers to unsigned for efficient Varint encoding:
/// `0 → 0, -1 → 1, 1 → 2, -2 → 3, 2 → 4, ...`
library;

/// ZigZag signed-to-unsigned mapping.
abstract final class ZigZag {
  /// Encode signed [n] to unsigned: `0→0, -1→1, 1→2, -2→3, ...`.
  static int encode(int n) => (n << 1) ^ (n >> 63);

  /// Decode unsigned [n] back to signed.
  static int decode(int n) => (n >>> 1) ^ -(n & 1);
}
