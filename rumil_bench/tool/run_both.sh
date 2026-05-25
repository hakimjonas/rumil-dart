#!/usr/bin/env bash
# Compile a rumil_bench binary to both AOT and Wasm and run each in
# turn. Useful for changes whose effect varies across runtimes (e.g.
# tight loops where dart2wasm's optimizer behaves differently from
# AOT).
#
# Usage:
#   tool/run_both.sh <bench_file>
#
# Example:
#   tool/run_both.sh bin/bench_line_index.dart
#
# Requires `deno` on PATH for the Wasm pass.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <bench_file>" >&2
  exit 2
fi

BENCH="$1"
if [[ ! -f "$BENCH" ]]; then
  echo "no such file: $BENCH" >&2
  exit 2
fi

BASENAME=$(basename "$BENCH" .dart)
TMP_AOT="/tmp/${BASENAME}.aot"
TMP_WASM="/tmp/${BASENAME}.wasm"

echo "=== AOT ==="
dart compile exe "$BENCH" -o "$TMP_AOT" >/dev/null
"$TMP_AOT"

echo
echo "=== WASM ==="
dart compile wasm "$BENCH" -o "$TMP_WASM" >/dev/null
deno run --allow-read tool/run_wasm.mjs "$TMP_WASM"
