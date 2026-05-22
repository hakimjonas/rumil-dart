// Generic Deno runner for any rumil_bench Wasm target.
//
// Usage:
//   deno run --allow-read tool/run_wasm.mjs <bench>.wasm [args...]
//
// `dart compile wasm <bench>.dart -o <bench>.wasm` emits two files:
// the `.wasm` module and a `.mjs` companion with `compile()` and
// `instantiate()` helpers. This script imports the companion at the
// matching path next to the `.wasm` argument, compiles the bytes,
// instantiates without imports, and forwards remaining argv to the
// Dart `main`.
//
// Path-agnostic: works for any output location. The dynamic
// `import(...)` resolves the `.mjs` companion at the same path as the
// `.wasm` argument.

const wasmPath = Deno.args[0];
if (!wasmPath || !wasmPath.endsWith('.wasm')) {
  console.error(
    'usage: deno run --allow-read tool/run_wasm.mjs <bench>.wasm [args...]',
  );
  Deno.exit(2);
}
const dartArgs = Deno.args.slice(1);

const mjsPath = wasmPath.replace(/\.wasm$/, '.mjs');
const mjsUrl = new URL(mjsPath, `file://${Deno.cwd()}/`).href;

const { compile } = await import(mjsUrl);
const bytes = await Deno.readFile(wasmPath);
const app = await compile(bytes);
const instance = await app.instantiate({});
instance.invokeMain(...dartArgs);
