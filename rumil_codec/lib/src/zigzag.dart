/// ZigZag encoding for signed integers.
///
/// Maps signed integers to unsigned for efficient Varint encoding:
/// `0 → 0, -1 → 1, 1 → 2, -2 → 3, 2 → 4, ...`
library;

abstract final class ZigZag {
  static int encode(int n) => (n << 1) ^ (n >> 63);
  static int decode(int n) => (n >>> 1) ^ -(n & 1);
}
