/// Benchmark harness utilities.
library;

void bench(
  String label,
  void Function() body, {
  int warmUp = 1000,
  int iterations = 10000,
}) {
  for (var i = 0; i < warmUp; i++) {
    body();
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    body();
  }
  sw.stop();
  final usPerOp = sw.elapsedMicroseconds / iterations;
  print(
    '  $label: ${usPerOp.toStringAsFixed(2)} μs/op'
    '  ($iterations iterations, ${sw.elapsedMilliseconds} ms total)',
  );
}

void benchWithSize(
  String label,
  void Function() body,
  int inputBytes, {
  int warmUp = 100,
  int iterations = 1000,
}) {
  for (var i = 0; i < warmUp; i++) {
    body();
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    body();
  }
  sw.stop();
  final usPerOp = sw.elapsedMicroseconds / iterations;
  final totalBytes = inputBytes * iterations;
  final mbPerSec = totalBytes / (sw.elapsedMicroseconds / 1e6) / 1e6;
  print(
    '  $label: ${usPerOp.toStringAsFixed(1)} μs/op'
    '  ${mbPerSec.toStringAsFixed(1)} MB/s'
    '  (${inputBytes}B input, $iterations iter)',
  );
}
