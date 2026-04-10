# Rumil Showcase: Lambé

What Rumil does 10x better than anything else in the Dart ecosystem: left-recursive grammars that just work, stack-safe to 10M+ operations, type-safe sealed ADT, compiling to both AOT native and WebAssembly. No other Dart parser library can do this.

## The Arda Ecosystem

| Name | Tolkien | Programming |
|------|---------|-------------|
| **Eru** | The One, creator | The Monad, cast-free GADT interpreter |
| **Valar** | Protectors, guardians | Validation, error handling |
| **Aulë** | Smith, craftsman | Builder, code generation |
| **Rúmil** | Scholar, invented writing | Parser combinators |
| **Sarati** | The script he created | Serialization, codecs |
| **Lambé** | Tongue, language | Query DSL |

## Priority

1. **Lambé** (`lam`) — the real tool. Exercises the full stack, has real users, good timing.
2. **Rumil Playground** — the learning companion. Smaller scope, educational reach.
3. **Reactive Formula Graph** — parked. Interesting but narrow. Revisit later.

---

## 1. Lambé — A Universal Query Language for Structured Data

**Package**: `lambe` | **CLI**: `lam` | **Library**: `import 'package:lambe/lambe.dart'`

### Concept

A typed, composable query language for structured data — JSON, YAML, TOML, and beyond. A **Dart-native query DSL** that works as a library you import *and* a CLI tool you run. Same code compiles to AOT native (fast CLI binary) and WebAssembly (browser playground, embeddable in agents).

The grammar is naturally left-recursive, which means it *requires* Warth to parse correctly — the strongest possible proof that Rumil's differentiator matters in practice.

### Who needs this (without knowing it yet)

**Platform engineers / SREs / DevOps**
The person who battles JSON API responses, YAML k8s manifests, TOML configs, and Terraform state files every day. They switch between `jq`, `yq`, and `grep` hacks. They hate the fragmentation, they hate jq's cryptic syntax (`.[].foo // empty`), and they especially hate that nothing handles all their formats with one consistent language.

What they want:
```bash
# Clean syntax. Any format.
lam '.users | filter(.age > 30) | map(.name)' data.json
lam '.database.host' config.toml
lam '.spec.containers[0].image' deployment.yaml
lam '.version' pubspec.yaml
```

**Dart/Flutter developers**
Every Flutter developer deals with JSON API responses. Every Dart developer has a pubspec.yaml. Currently they write 15-line null-check accessor chains or manual deserialization code. Lambé as a library changes that:

```dart
import 'package:lambe/lambe.dart';

// In a test — no manual deserialization
final count = query('.users | filter(.active) | length', response.body);
expect(count, greaterThan(0));

// In a build script — works on YAML directly
final version = query('.version', pubspecContent, format: Format.yaml);

// In app code — query nested API responses
final cities = query('.data.results | map(.address.city) | unique', json);
```

**AI tools / agent frameworks**
This is the timing play. Every AI CLI tool (Claude Code, Copilot, aider, Cursor) constantly reads and extracts values from structured files. Currently they either:
- Shell out to `jq` and hope the syntax is right
- Write throwaway inline code
- Read the entire file into context (wasteful)

Lambé as an **MCP tool** or library that any AI agent can call:
```
User: "What k8s services have more than 2 replicas?"
Agent → lam '.items | filter(.spec.replicas > 2) | map(.metadata.name)' services.yaml
```

Why this works for AI:
- **Clean, predictable syntax** — LLMs generate it more reliably than jq's edge cases
- **Multi-format** — agents don't want to care whether a file is JSON or YAML
- **Library + CLI** — embed in an agent's Dart runtime OR shell out from any language
- **Wasm-embeddable** — run inside a browser-based agent without spawning a subprocess
- **Precise errors** — when a query fails, the error points to the exact position, which an agent can use to self-correct

The AI-tool market is exploding and structured data extraction is a primitive every agent needs. This market barely exists yet.

### What makes it 10x (technically)

- **The grammar requires left recursion.** Property chains (`a.b.c`), indexing (`a[0].b`), and pipeline operators (`data | filter | map`) are left-recursive by nature. This grammar cannot be parsed correctly by PetitParser or any other Dart parser library without manual refactoring into right-recursive form — which changes associativity and breaks semantics.
- **Multi-format input.** rumil_parsers already has JSON, TOML, and YAML parsers. Same query, any format. No other Dart tool does this.
- **Expression evaluation.** Computed fields use rumil_expressions: `users | map(.price * .quantity)`. The expression evaluator is already built and battle-tested.
- **Dual-platform.** `dart compile exe` for a standalone CLI binary (no runtime needed). `dart compile wasm` for browser playground. Same code, both targets.
- **Exercises the entire Rumil stack.** rumil (parser), rumil_parsers (input formats), rumil_expressions (computed fields). This is the integration showcase.

### Language design

```bash
# Property access — left-recursive
.name
.users[0].address.city
.config.database.host

# Pipeline — left-recursive chaining
. | keys
.users | length
.users | filter(.age > 30) | map(.name) | sort

# Filtering with boolean logic
.users | filter(.active == true && .age >= 18)
.items | filter(.price * .quantity > 100)

# Mapping / projection
.users | map({name: .name, email: .email})
.users | map(.salary * 1.1)

# Aggregation
.scores | sum
.scores | avg
.items | map(.price) | max

# Indexing and slicing
.users[0]
.users[-1]
.users[1:3]

# Conditional
.users | map(if .age > 65 then "senior" else "active")

# String interpolation
.users | map("\(.name) is \(.age) years old")

# Multi-format — same query, any input
echo '{"users": [...]}' | lam '.users | filter(.age > 30)'
cat config.toml | lam '.database.host'
cat data.yaml | lam '.items | map(.price) | sum'
```

### Grammar (naturally left-recursive)

```
expr     → expr '|' pipe_op          # pipeline
         | expr '.' ident            # property access
         | expr '[' index ']'        # indexing
         | expr '[' expr ':' expr ']' # slicing
         | atom

pipe_op  → 'filter' '(' expr ')'
         | 'map' '(' expr ')'
         | 'sort'
         | 'reverse'
         | 'keys'
         | 'values'
         | 'length'
         | 'sum' | 'avg' | 'min' | 'max'
         | 'first' | 'last'
         | 'flatten'
         | 'unique'
         | 'group_by' '(' expr ')'
         | 'sort_by' '(' expr ')'

atom     → '.' ident?                # current value / field
         | number | string | bool | null
         | '(' expr ')'
         | '{' pair (',' pair)* '}'  # object construction
         | '[' expr (',' expr)* ']'  # array construction
         | 'if' expr 'then' expr 'else' expr
```

This grammar is left-recursive in three productions (pipeline, property access, indexing). With Warth, it parses naturally. Without Warth, you'd need to manually refactor all three, losing the clean correspondence between syntax and semantics.

### Surfaces

Lambé has four delivery surfaces, each reaching a different persona:

| Surface | Persona | How |
|---------|---------|-----|
| **CLI binary** | Platform engineers, DevOps | `dart compile exe` → standalone `lam` binary, zero dependencies |
| **Dart library** | Flutter/Dart developers | `import 'package:lambe/lambe.dart'` in tests, build scripts, apps |
| **MCP tool** | AI agents, LLM frameworks | Structured data extraction primitive for tool-use |
| **Browser playground** | Everyone | dart2wasm web UI, try queries live, shareable URLs |

### Inside-out implementation plan

Each ring is self-contained and shippable. Build from the core outward.

```
        ┌───────────────────────────────────────────────────┐
        │            Ring 7: Horizon                        │
        │   HCL/Terraform · user functions · streaming ·    │
        │   shell completion                                │
        │  ┌───────────────────────────────────────────┐    │
        │  │         Ring 6: Ecosystem                 │    │
        │  │   MCP server · browser playground ·       │    │
        │  │   watch mode · lambe_test matchers        │    │
        │  │  ┌───────────────────────────────────┐    │    │
        │  │  │      Ring 5: Interactive           │    │    │
        │  │  │   REPL + tab completion ·          │    │    │
        │  │  │   object/array construction ·      │    │    │
        │  │  │   conditionals · interpolation     │    │    │
        │  │  │  ┌───────────────────────────┐     │    │    │
        │  │  │  │   Ring 4: Power tools     │     │    │    │
        │  │  │  │  --schema · --to yaml ·   │     │    │    │
        │  │  │  │  --assert · slicing       │     │    │    │
        │  │  │  │  ┌───────────────────┐    │     │    │    │
        │  │  │  │  │ Ring 3: Formats   │    │     │    │    │
        │  │  │  │  │ YAML · TOML ·     │    │     │    │    │
        │  │  │  │  │ auto-detect ·     │    │     │    │    │
        │  │  │  │  │ arithmetic ·      │    │     │    │    │
        │  │  │  │  │ aggregation       │    │     │    │    │
        │  │  │  │  │ ┌───────────┐     │    │     │    │    │
        │  │  │  │  │ │ Ring 2:   │     │    │     │    │    │
        │  │  │  │  │ │ Pipeline  │     │    │     │    │    │
        │  │  │  │  │ │ filter ·  │     │    │     │    │    │
        │  │  │  │  │ │ map ·     │     │    │     │    │    │
        │  │  │  │  │ │ sort ·    │     │    │     │    │    │
        │  │  │  │  │ │ keys ·    │     │    │     │    │    │
        │  │  │  │  │ │ values ·  │     │    │     │    │    │
        │  │  │  │  │ │ length    │     │    │     │    │    │
        │  │  │  │  │ │ ┌───┐     │     │    │     │    │    │
        │  │  │  │  │ │ │ 1 │     │     │    │     │    │    │
        │  │  │  │  │ │ │ 0 │     │     │    │     │    │    │
        │  │  │  │  │ │ └───┘     │     │    │     │    │    │
        │  │  │  │  │ └───────────┘     │    │     │    │    │
        │  │  │  │  └───────────────────┘    │     │    │    │
        │  │  │  └───────────────────────────┘     │    │    │
        │  │  └───────────────────────────────────┘    │    │
        │  └───────────────────────────────────────────┘    │
        └───────────────────────────────────────────────────┘
```

**Ring 0 — The core** (pure logic, no I/O)
- Query AST: sealed `Expr` hierarchy (PropertyAccess, Index, Pipeline, Filter, Map, ...)
- Query parser: left-recursive grammar via Rumil's `rule()` + `chainl1`
- Evaluator: walk the AST over `Object?` values (maps, lists, primitives)
- This is the engine. Everything else wraps it.

**Ring 1 — First shippable** (library + CLI)
- JSON input via `dart:convert` (not even rumil_parsers yet — keep it simple)
- Library API: `Object? query(String expr, String data)`
- CLI: `lam '.users[0].name' data.json`
- Precise error messages with source locations
- *Ship this. Get feedback.*

**Ring 2 — Useful** (pipeline operations)
- filter, map, sort, reverse, keys, values, length, first, last
- Comparison operators (`>`, `<`, `==`, `!=`, `&&`, `||`) in filter predicates
- Pretty-printed JSON output
- *This is where Lambé becomes genuinely useful day-to-day.*

**Ring 3 — Multi-format** (the differentiator)
- YAML and TOML input via rumil_parsers
- Auto-detection by file extension or content sniffing
- Arithmetic in map/filter: `.price * .quantity`
- Aggregation: sum, avg, min, max
- *This is where it stops being "jq but Dart" and becomes its own thing.*

**Ring 4 — Power tools**
- `--schema` for structure inference
- `--to yaml/toml/json` for format conversion (nearly free)
- `--assert` for CI/CD validation
- Slicing `[1:3]`, negative indexing `[-1]`
- *Each of these is small but high-delight.*

**Ring 5 — Interactive**
- REPL with tab completion on field names
- Object/array construction: `map({name: .name, total: .price * .qty})`
- Conditionals: `if .age > 65 then "senior" else "active"`
- String interpolation: `"\(.name) is \(.age)"`
- *The REPL changes the tool from "I know what I want" to "I'm exploring."*

**Ring 6 — Ecosystem integration**
- MCP server (AI agent tool-use)
- Browser playground (dart2wasm)
- `--watch` mode
- `lambe_test` package (test matchers for Dart)
- *This is where the three personas fully converge.*

**Ring 7 — Horizon** (stretch goals)
- User-defined functions: `def adults: filter(.age >= 18)`
- Streaming / JSONL for large files
- Shell completion (bash, zsh, fish)
- HCL/Terraform parsing (big effort, huge payoff for DevOps persona)

### Sequencing

Rings 0-2 are the focused sprint. A working `lam` command with JSON + pipeline ops. That's the thing you hand to your colleague and say "try this instead of jq." Everything after that is guided by what he actually reaches for.

### Architecture

```
lambe/
├── lib/
│   ├── src/
│   │   ├── ast.dart          # Query AST (sealed classes)
│   │   ├── parser.dart       # Query parser (left-recursive grammar via Rumil)
│   │   ├── evaluator.dart    # Query evaluator over dynamic values
│   │   ├── pipeline.dart     # Pipeline operations (filter, map, sort, ...)
│   │   ├── input.dart        # Multi-format input (JSON/TOML/YAML detection)
│   │   └── output.dart       # Output formatting (JSON, raw, table)
│   └── lambe.dart            # Library API: query(expr, data, {format})
├── bin/
│   └── lam.dart              # CLI entry point
├── tool/
│   └── mcp_server.dart       # MCP server wrapper (Ring 6)
├── web/                       # Browser playground (Ring 6)
│   ├── index.html
│   ├── main.dart
│   └── style.css
├── pubspec.yaml
└── test/
    ├── parser_test.dart
    ├── evaluator_test.dart
    └── integration_test.dart
```

### Dependencies

- rumil (core parser — query grammar)
- rumil_parsers (JSON/TOML/YAML input parsing — Ring 3+)
- rumil_expressions (arithmetic in filter/map — or custom evaluator)
- args (CLI argument parsing)
- package:web (browser playground — Ring 6)

### Effort estimate

- Rings 0-1: Medium — query AST + parser + evaluator + CLI. Core is ~500-800 LOC.
- Ring 2: Small — pipeline operations are straightforward.
- Ring 3: Small — plug in rumil_parsers, add arithmetic.
- Ring 4: Small — each power tool is a focused feature.
- Ring 5: Medium — REPL with tab completion is real work.
- Ring 6: Medium — MCP server + web UI.
- Ring 7: Large — HCL parsing alone is a significant parser.

### Risks and mitigations

- **Scope creep toward full jq compatibility.** Resist. The goal is a focused tool that works perfectly, not a complete but buggy jq clone. Design a cleaner syntax and own it.
- **Evaluator type safety.** The evaluator operates on dynamic JSON values (maps, lists, primitives). Less clean than the parser. Mitigated by keeping a clear boundary: the parser/AST is fully typed sealed classes, the evaluator works with `Object?` because JSON is untyped by nature.
- **jq syntax expectations.** Users who know jq will expect jq syntax. Explicitly position Lambé as "jq-inspired but cleaner" — document the differences, provide a migration guide.
- **Platform engineer adoption.** They don't care about Dart. They care that the binary is fast, handles their formats, and doesn't require a runtime. AOT compilation handles this — the binary is self-contained.

### Why Dart?

The inevitable question: "Why not build this in Rust?"

The Rust ecosystem doesn't need this. It has jaq, jql, xq, yq — all Rust, all good. That market is served.

The honest answer isn't "Dart is better than Rust for this." It's three things:

1. **Dart's parser libraries don't support left recursion or stack-safe deep recursion.** PetitParser and others exist and do good work, but Lambé's grammar (property chains, pipeline operators, nested indexing) is naturally left-recursive. Rumil brings something new to the Dart table — and Lambé proves it matters in practice.

2. **dart2wasm is where Dart is heading.** Building a non-trivial tool that compiles to both AOT native and WasmGC and works well is a direct demonstration of the platform's readiness. The query parser's sealed class dispatch compiles to WasmGC `br_on_cast` — this is the future the Dart team is investing in.

3. **The library integration is Dart-exclusive.** A Rust query tool can't give a Flutter developer `query('.users | filter(.active)', response.body)` without FFI pain. A Dart library can. That's 1M+ developers who get a query DSL with zero friction.

Context: this work draws on experience building compilers with left recursion in Rust (Fungal) and developing parser combinator libraries in Scala. The choice of Dart is deliberate — not because Dart is better at parsing than Rust, but because Dart is where these ideas can have the most impact as a published ecosystem contribution.

### The story it tells

"I've been building parser combinators and compilers across Rust, Scala, and Dart. I published in Dart first because the existing parser libraries don't handle left recursion, and I wanted to prove that Dart's sealed classes and Wasm compilation are ready for serious language work. Lambé is the tool that proves the library handles real workloads. It compiles to a standalone CLI binary *and* runs in the browser via WebAssembly. Here's the parser combinator library, here's the query tool, and here's the MCP server that lets AI agents use it."

Theory → library → tool → ecosystem integration.

---

## 2. Rumil Playground — Interactive Grammar Learning Tool

### Concept

A browser-based interactive tool where users explore parser combinators, write grammars, test them against input, and watch the parsing process unfold. Part demo, part teaching tool.

The key moment: you write a left-recursive grammar (`expr → expr + term | term`) and it *just works*. Toggle Warth off and see it fail. No other Dart parser library — and very few parser tools in any language — can demonstrate this live in the browser.

To be a *real* learning tool (not just a sandbox people visit once), it needs structured progression — exercises that build up from "match a digit" to "handle left recursion." Think Rustlings for parser combinators.

Open question: should this be a Flutter app (web + mobile + desktop) or a plain dart2wasm web app? Flutter gives reach. Plain web gives simplicity and faster iteration.

### What makes it 10x

- **Left recursion toggle**: ON shows correct parsing via Warth seed-growth, OFF shows the failure mode. Immediate, visceral demonstration of the algorithm.
- **Sealed ADT visualization**: The parse result is a tree of Dart sealed class subtypes, rendered as collapsible nodes. Shows Dart 3.x patterns in action.
- **Source-mapped errors**: Parse errors highlight the exact position in the input (line, column, offset). Demonstrates Rumil's typed error system.
- **Wasm-native**: The parser runs as WebAssembly in the browser — directly relevant to Dart's platform future.
- **Educational reach**: Teaching tools get shared. People remember the thing that made them understand parser combinators for the first time.

### Features (v0.1 → v1.0)

**v0.1 — Expression evaluator playground**
- Single-page web app
- Input box for expressions (`2 + 3 * (x - 1)`)
- Variable sliders (adjust `x`, see result update live)
- AST tree visualization (sealed Expr subtypes as nodes)
- Error panel with source-highlighted parse errors
- Uses rumil_expressions directly

**v0.2 — Grammar examples + learning path**
- Pre-built grammars: arithmetic, JSON, CSV, left-recursive chains
- Editable test input per grammar
- Side-by-side: input → AST tree → evaluated result
- Structured exercises with progression (not just a sandbox)
- "What is left recursion?" explainer with live demo

**v0.3 — Step-through visualization**
- Parsing steps shown as an animation
- Memo table filling visualized
- Seed-growth algorithm: watch the seed get planted, grow, reach fixpoint
- Comparison mode: Warth ON vs OFF for left-recursive rules

**v1.0 — User-defined grammars**
- BNF-like notation that Rumil itself parses (meta-circular)
- Users define their own grammar rules, test against input
- Shareable URLs (grammar + input encoded in hash fragment)
- Example library: arithmetic, JSON, CSS selectors, SQL WHERE clauses

### Effort estimate

- v0.1: Small — a weekend.
- v0.2: Medium — content creation (exercises) is the real work, not code.
- v0.3: Large — instrumenting the interpreter for step-through events.
- v1.0: Large — meta-circular grammar parser is a project in itself.

### Risks

- Without structured content, it's a tech demo people visit once. The curriculum is the product, not the UI.
- Step-through visualization (v0.3) requires modifying or wrapping the interpreter. Could be intrusive.
- dart2wasm DOM interop is evolving — `package:web` API may shift.

### Relationship to Lambé

The Playground becomes the "learn how Lambé's parser works" page. Lambé Ring 6 (browser playground) and the Playground could share infrastructure or even be tabs on the same site.

---

## 3. Reactive Formula Graph (parked)

A visual node graph where each node is a named expression. Nodes reference each other by name. Change a value and see propagation through the dependency topology.

Interesting but exercises only rumil_expressions (not the full stack). Less urgency, less clear audience. Worth revisiting as either:
- A Playground example (v0.2)
- A standalone demo once Lambé and the Playground exist
- A Flutter showcase if the portfolio needs a visual piece

---

## Overall sequencing

```
NOW:     Lambé Rings 0-2 (core query + JSON + pipeline + CLI)
         ↓ proves Rumil handles real workloads
THEN:    Lambé Ring 3 (multi-format — the differentiator)
         ↓ becomes genuinely useful
NEXT:    Playground v0.1 (expression evaluator, AST tree)
         ↓ educational companion, Wasm showcase
LATER:   Lambé Rings 4-6 (power tools, REPL, MCP, browser)
         Playground v0.2 (learning path, exercises)
SOMEDAY: Lambé Ring 7, Formula Graph, Playground v0.3+
```
