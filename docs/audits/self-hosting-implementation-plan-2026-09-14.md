# Agent-simple language and self-hosting implementation plan — 14 September 2026

## 1. Purpose

This plan turns the language-simplicity recommendations into an implementation order
that ends with a self-hosted compiler. The intended result is:

- ordinary compiler development happens in `.my` files;
- a small edit reparses, rechecks, lowers, and emits only the affected declarations;
- the default language surface is small, familiar, and predictable for AI agents;
- performance and systems features are explicit escape hatches rather than concepts
  every program must carry; and
- Zig, Guardian, C, and QBE remain part of the bootstrap or runtime boundary, but are
  no longer in the routine frontend edit/test loop.

This document complements the [language simplicity
audit](language-simplicity-2026-09-14.md) and its [implementation
plan](simplification-plan-2026-09-14.md). That plan remains the source of truth for
its W1–W9 surface-cleanup work. This plan decides which of that work must land before
self-hosting, adds the missing incremental and bootstrap contracts, and defines the
order in which the compiler should move out of Zig.

It is deliberately not a plan to rewrite everything in mylang. The C runtime, vendored
QBE backend, platform startup code, and a thin stage-0 launcher can stay in their
current implementation languages until replacing one of them solves a measured
problem.

## 2. Outcomes and success criteria

Self-hosting is viable when the new compiler is the easiest implementation in which
to change the language, not merely when it can compile one copy of itself.

### Required outcomes

1. **One obvious default.** Common operations have one canonical spelling. The
   formatter produces that spelling and stale aliases are rejected with a direct
   replacement diagnostic.
2. **Local reasoning.** Name binding, mutation, effects, and errors can be understood
   from the current declaration and explicit imports. No hidden capture, ambient
   capability, implicit conversion, overload search, or compile-time I/O is needed.
3. **A complete program boundary.** A compiler-sized command can read arguments, write
   diagnostics to stderr, inspect an explicitly granted environment, access files,
   and return a checked exit result.
4. **A sufficient bootstrap subset.** The language can express a lexer, parser,
   resolver, type checker, typed IR, diagnostic renderer, and QBE emitter without
   host-only data-structure helpers.
5. **Incremental by construction.** Declaration identities and dependency edges are
   stable. A private body edit does not invalidate unrelated declarations or callers
   whose imported interface has not changed.
6. **A reproducible trust chain.** The Zig compiler can build stage 1; stage 1 can
   build stage 2; stage 2 can build stage 3; and stages 2 and 3 produce equivalent
   compiler artifacts from clean inputs.
7. **A faster routine loop.** Editing and testing the self-hosted frontend requires no
   Zig rebuild and no Guardian run. Guardian remains a blocking gate for the Zig code
   that is still changed.

### Measurements to record

Before the port starts, add a versioned reference workload and record cold and warm
median/p95 timings on one named machine. The initial budgets should be treated as
guardrails, not marketing claims:

- a private function-body edit reparses one changed module and rechecks only the
  changed declaration plus real semantic dependants;
- unchanged modules, declarations, generic specializations, and object fragments are
  reported as reused;
- the warm edit/check loop for the compiler project is at most 500 ms p95 on the
  reference machine, or no slower than the measured Zig-hosted incremental baseline
  if that baseline is already above 500 ms;
- an unchanged check performs no QBE, assembler, or linker work;
- a single-function implementation edit emits at most that function's object fragment
  and unavoidable link metadata; and
- a full clean self-bootstrap has a recorded time and peak-memory ceiling so either
  can be ratcheted rather than guessed about.

Every timing report must also assert the expected reuse counts. A fast cache that
silently returns stale results is a correctness failure.

## 3. Design decisions to freeze first

These decisions define `bootstrap-v1`. Resolve and document them before writing the
self-hosted parser; otherwise the port will encode moving semantics.

### D1. Keep function-scoped locals with sound definite assignment

Adopt function-scoped locals, like Python, but make definite assignment sound.
An assignment anywhere in a function body refers to one binding from its first
assignment to the end of the body. A local is definitely assigned after a
potentially zero-iteration `for`/`while` loop or after a `match` only when every
continuing path assigns it. Payload and loop bindings remain scoped to their own
block.

Why:

- the surface stays Python-like for agent-written code;
- path merging is explicit and local to the enclosing function;
- incremental name-resolution dependencies stay inside the function body; and
- agents get a direct repair: predeclare the value before the loop or match when it
  is read afterward.

Record the rejected block-scope alternative in D1 and keep the diagnostic and
formatter-facing examples aligned with the implemented rule.

### D2. Rename value-only `class` declarations to `record`

Use `record` as the canonical declaration keyword before the bootstrap grammar is
frozen. The current type has value semantics, no inheritance, and no methods; calling
it `class` creates expectations the language intentionally does not meet.

Migration:

1. teach the parser and formatter `record`;
2. mechanically migrate the repository and installed examples;
3. accept `class` for one compatibility window with a structured replacement
   diagnostic;
4. remove it from formatter output immediately; and
5. reject it after the window and add a stale-spelling scan.

Before committing to the rename, run the existing agent idiom harness on equivalent
`class` and `record` tasks. Reverse this decision only if the measured repair burden
of `record` is materially worse. Do not add class-like behavior merely to justify the
old spelling.

### D3. Keep the default managed and value-oriented

The compiler should be writable with managed lists, dictionaries, strings, records,
tagged unions, results, options, and explicit loops. Fixed arrays, bytes, arenas,
effect ceilings, typed C calls, and provider APIs remain opt-in escape hatches.

Do not add a second general allocation model, stored references, ownership syntax, or
general pointers for the compiler port. If a compiler workload is slow, profile it
first; optimize a bounded representation or phase rather than changing the default
memory model.

### D4. Add mutation through a narrow managed `Cell[T]`

Add a managed cell rather than closures or stored references. `Cell[T]` is an
identity-bearing managed builtin, not a value record: copying a cell value shares its
one slot, while copying an ordinary record continues to copy its fields. Its familiar
surface should be ordinary construction plus an explicit `.value` read or assignment:

```text
cursor = Cell(value=0)
cursor.value = cursor.value + 1
```

Its public model must stay this small:

- construct a cell with an initial value;
- read its value;
- replace its value;
- permit it only for managed, storable values;
- do not give it pointer arithmetic, address-taking, implicit dereference, identity
  comparison, FFI layout, or wire encoding; and
- make mutation explicit at the call site.

Use it for scanner/parser cursors and explicit shared state passed among top-level
functions. Do not use it as a back door to capturing lambdas.

### D5. Lambdas are noncapturing only

Add expression-bodied, contextually typed `lambda` syntax for the existing
noncapturing function-value model. A lambda may use its parameters and module
constants, but may not capture a local. It has no parameter defaults or statements;
its parameter and result types come from the expected callback type, and its effects
must satisfy that type's exact bound. A lambda with no expected callback type is
rejected rather than triggering open-ended inference. The capture diagnostic should
point at the captured name and recommend a top-level function or an explicit state
parameter.

This delivers concise `map`, `filter`, and sorting keys without introducing closure
environments, hidden allocation, or new invalidation edges. Capturing closures remain
outside `bootstrap-v1`.

### D6. Freeze the compiler/runtime boundary

The self-hosted compiler owns lexing through QBE text generation. The existing
runtime owns managed allocation, traps, capability plumbing, process startup, and
platform operations. QBE owns machine-code generation. A thin stage-0 Zig launcher
may continue to locate resources and invoke the compiler.

Version this boundary as `runtime-abi-v1`; do not let the port reach into arbitrary
Zig internals.

### D7. One-version feature delay

A language feature is not used by the compiler in the same release that first
implements it. It must first land in the current compiler, pass the full corpus, and
survive one compatibility release. The next compiler version may then use it.

This keeps stage 0 capable of rebuilding the compiler and prevents a feature from
being required to compile its own implementation.

## 4. Scope boundaries

### Required before the self-hosted compiler becomes primary

- canonical syntax and stale-spelling removal;
- function-scope decision and definite-assignment diagnostics;
- minimum compiler collection vocabulary;
- module/project compilation and deterministic discovery;
- program arguments, stderr, explicit environment access, and checked `main` results;
- `Cell[T]`;
- expression-bodied noncapturing lambdas over the existing function-value model;
- canonical formatting;
- stable declaration identity and interface/body dependency separation;
- per-declaration checking and per-function lowering/emission reuse;
- stable, structured diagnostics;
- a versioned runtime ABI and resource manifest;
- the self-hosted frontend, typed IR, and QBE emitter; and
- stage-2/stage-3 bootstrap and corpus parity.

### Useful, but not allowed to block the port

- every Python collection convenience rather than the measured compiler minimum;
- methods on records;
- tuples;
- record equality;
- additional native targets;
- a second backend;
- a package registry;
- an optimizing IR;
- capturing closures;
- exceptions;
- overloads or operator overloading;
- inheritance or a dynamic object model;
- general pointers or stored references;
- unrestricted compile-time execution, reflection, or compile-time I/O; and
- threads or a second allocation model.

The second list is not a post-bootstrap promise. Each item still needs evidence that
it improves agent development or solves a measured constraint.

## 5. Workstreams

The workstreams are ordered by dependency. Within a wave, keep changes independently
mergeable and avoid mixing a language semantic change with the self-host port that
first consumes it.

### Wave 0 — Reconcile the baseline and freeze `bootstrap-v1`

Deliverables:

1. Reconcile the branches/worktrees mentioned by the current handoff. Update the
   W1–W9 plan so each item is marked landed, superseded, or still pending against one
   known commit.
2. Write short ADRs for D1–D7. The ADRs record the rule, rejected alternative, and
   compatibility consequence; they are not open-ended design documents.
3. Add `docs/bootstrap-v1.md` containing the exact syntax, builtins, standard-library
   calls, effects, and capabilities the compiler may use.
4. Add `selfhost/README.md` with the stage model and the rule that compiler code stays
   inside `bootstrap-v1`.
5. Inventory the Zig compiler by pipeline stage and create a parity checklist. Count
   constructs and tests, not just source lines.
6. Capture clean/warm timing, memory, diagnostic, and output baselines for the current
   compiler and representative projects.

Exit criteria:

- there is one green baseline commit;
- no unresolved language-semantic choice changes the bootstrap grammar or type model;
- every proposed bootstrap feature is either already implemented or assigned to Wave
  1/2; and
- the compiler project has a machine-readable build manifest and reference benchmark.

### Wave 1 — Finish the simple default surface

Execute the required parts of the existing simplification plan in this dependency
order:

1. W1 correctness fixes: `len`, lexical shadowing, and authoritative source scanning.
2. W2 one-spelling cleanup and stale-spelling rejection.
3. W3 minimum compiler collection vocabulary.
4. W4 only the prelude operations demonstrated by real compiler code.
5. W5 expression-bodied noncapturing lambdas over the existing callback model.
6. W9 one canonical run/build/test command shape.
7. W7 docs and W8 agent-idiom probes continuously, not as cleanup at the end.

Minimum collection operations to prove with lexer/parser/checker prototypes:

- list: append, pop, clear/truncate, extend, indexed get/set, length, and iteration;
- dictionary: get, set, membership, remove, keys, values/items, and iteration;
- string/bytes: length, indexed access, slicing, find/prefix/suffix checks, split/join,
  integer formatting/parsing, and an efficient builder path; and
- sorting: a deterministic built-in order and an explicit noncapturing key function
  if measured compiler code needs one.

Do not implement the whole desired Python vocabulary on speculation. First write a
small lexer and parser workload using only proposed public APIs. Each missing operation
becomes an issue with the source workaround and its cost. That evidence decides the
minimum set.

The efficient text-builder escape hatch should live in the standard library or as a
compiler-known managed type. The obvious string operations remain the default; the
builder is introduced only where repeated concatenation is measured.

Exit criteria:

- the lexer/parser prototypes contain no host calls or accidental quadratic text
  construction;
- each common operation has one formatter-produced spelling;
- aliases scheduled for removal have migrated repository-wide;
- idiom probes show that agents select the canonical form and repair rejected forms;
  and
- the feature/doc/spec gates describe the same surface.

### Wave 2 — Complete the program boundary

The self-hosted compiler must behave like an ordinary command-line tool without
ambient host access.

#### Arguments

Reserve compiler flags before `--` and pass everything after `--` to the guest:

```console
mylang run compiler.my -- check project/main.my --diagnostics=json
```

Arguments are input data, not authority, so keep the default boundary familiar: an
entry point may take `args: list[str]` as its first parameter, followed by capability
parameters. The list contains only guest arguments—values after `--` for `mylang run`,
or OS arguments after `argv[0]` for an installed binary. It never contains a synthetic
program name. Values are validated Unicode strings. Invalid platform bytes produce a
stable host-boundary error before guest execution; a raw-bytes API can be added later
if a real tool needs it.

#### Output

Add one `eprint` spelling under the existing `output` effect, with the same `sep`,
`end`, and default newline behavior as `print`. Diagnostics go to stderr;
machine-readable program output can remain on stdout. Test byte-exact behavior and
broken-pipe handling.

#### Environment

Use the existing explicit `Environment` capability as the normal public API. Add only
the operations the compiler needs, with deterministic absence and invalid-text
behavior. Do not introduce an ambient global environment map.

#### Exit values

Permit both:

```text
# doc: not-mylang
def main(args: list[str], fs: Filesystem) -> int:
    ...

def main(args: list[str], fs: Filesystem) -> Result[int, str]:
    ...
```

For the result form, `Ok(code)` exits with that code and `Err(message)` prints one
canonical diagnostic to stderr and exits 1. Preserve the existing distinction between
guest results, guest traps, source errors, and host/usage failures.

Exit criteria:

- one `.my` program can implement `check`, `build`, and diagnostics modes using only
  documented public APIs;
- `run`, `build --run`, installed executables, and guest tests agree on argv, stderr,
  capabilities, and exit codes; and
- all boundary behavior has native tests, documentation examples, and structured
  diagnostics.

### Wave 3 — Make incremental compilation a language/tooling contract

Build the incremental model in the Zig compiler before depending on it in the port.
The self-hosted implementation should reproduce a proven contract, not invent a new
one while chasing semantic parity.

#### Stable identities

Introduce stable identifiers for:

- package/module;
- top-level declaration;
- exported interface item;
- type and nominal template;
- function body;
- generic specialization; and
- emitted function/data fragment.

An identifier must not contain a source byte offset. Use module identity plus the
declaration's canonical name/kind and a disambiguator that survives edits elsewhere in
the file. Store source spans as replaceable diagnostic data attached to identities.

#### Query boundaries

Use explicit query stages:

1. load and hash source;
2. lex/parse module;
3. collect declarations and imports;
4. resolve exported interface;
5. check one declaration body;
6. instantiate one generic specialization;
7. lower one checked function or constant;
8. emit one QBE/data fragment; and
9. link the requested product.

Each query records its input fingerprints and dependency identities. Cache entries
include the compiler build identity, bootstrap-language version, target, runtime ABI,
effects/capabilities contract, and relevant flags.

#### Interface versus implementation

An exported-interface fingerprint includes only information a dependant can observe:

- canonical name and kind;
- explicit parameter and return types;
- explicit generic parameters and constraints;
- effects and capability requirements;
- record fields or union variants that are exported;
- constant value only when it is part of type checking or emitted semantics; and
- layout/ABI facts only when the boundary exposes them.

It excludes function bodies, diagnostic spans, comments, formatting, private
declarations, and local names. A body edit with an unchanged interface rechecks and
re-emits that body but does not recheck callers.

Require explicit signatures and effects on exported declarations. Inference may stay
inside a private declaration; it must not make public interface hashes depend on
implementation details.

#### Generic cache keys

Keep template checking separate from specialization. A specialization key contains:

- template identity and checked-template fingerprint;
- canonical concrete type/value arguments;
- observed provider/constraint shape;
- target/runtime ABI where layout or code generation depends on it; and
- compiler build identity.

Changing an unrelated instantiation must not invalidate existing specializations.

#### Diagnostics and observability

Preserve diagnostic codes, causal relationships, declaration identities, and sort
order across warm and cold checks. Recompute spans without changing semantic identity.
Add an `--explain-invalidation` report and extend `--report` with per-stage hit/miss
counts and the first changed dependency for every miss.

#### Correctness strategy

For every incremental scenario, compare a warm result with a clean rebuild:

- accepted/rejected status;
- diagnostic JSON after removing explicitly unstable timing fields;
- typed-interface manifest;
- QBE or normalized object manifest; and
- executed behavior where applicable.

On missing or corrupt cache data, fall back to recomputation. Never recover by trusting
a partially decoded entry.

Exit criteria:

- the invalidation matrix covers whitespace, comments, private bodies, exported
  signatures, effects, constants, record/union shape, imports, generic templates,
  specialization arguments, runtime ABI, and compiler version;
- each matrix case asserts both reuse and clean-build equivalence;
- the reference compiler-shaped project meets the recorded warm-edit budget; and
- incremental rules are documented as public tooling behavior rather than incidental
  implementation details.

**Status: complete (2026-09-15).** The Zig incremental contract landed: stable content-derived identities
for all seven identity kinds, per-declaration interface fingerprints, the nine-stage query model,
`--explain-invalidation` plus per-stage `--report` counts, the six-dimension cache-key contract,
generic-specialization keys, and the clean/warm invalidation matrix. See
[Wave 3 completion](wave3-incremental-2026-09-15.md) and the public
[incremental contract](../experiments/incremental-contract.md). Generic/nominal reuse remains
conservative, explicit effect ceilings on exported declarations remain a follow-up, and the runtime
ABI key is still the `runtime-abi-v0-unfrozen` placeholder until Wave 4.

### Wave 4 — Freeze `runtime-abi-v1`

Document and test the narrow interface available to generated QBE:

- process entry and `main` result mapping;
- managed object headers, allocation, roots, and collection/string operations;
- trap codes and source-stack metadata;
- capability handles and provider calls;
- result/option/record/union representation;
- scalar sizes, alignment, and calling convention;
- constant/data emission and module initialization;
- runtime archive/resource discovery; and
- version negotiation and mismatch diagnostics.

Publish a machine-readable ABI manifest beside the installed runtime archive. Include
its content hash in every relevant code-generation cache key. Treat any incompatible
change as a new ABI version; do not silently couple stage 1 to the Zig source tree.

Keep the first self-hosted emitter simple: generate one deterministic QBE module for a
clean build. Per-function fragments and finer linking reuse may then be enabled through
the already-defined Wave 3 cache boundary. Do not add another backend during the port.

Exit criteria:

- generated code uses only documented symbols and layouts;
- ABI conformance tests can run without importing Zig compiler modules;
- a compiler installation can find QBE, headers/objects, and the runtime archive from
  its manifest rather than repository-relative assumptions; and
- ABI mismatch fails early with an actionable diagnostic.

### Wave 5 — Build the self-hosted compiler vertically

Create the compiler under `selfhost/` with small modules and no dependency on Zig
compiler internals. Prefer end-to-end vertical slices over implementing every parser
feature before any checked program can run.

Suggested module shape:

```text
selfhost/
  README.md
  main.my
  source.my
  token.my
  lexer.my
  syntax.my
  parser.my
  symbol.my
  resolve.my
  types.my
  effects.my
  check.my
  ir.my
  lower.my
  qbe.my
  diagnostic.my
  project.my
  cache.my
  tests/
```

This is a responsibility map, not a requirement for one large file per noun. Split
modules when their public interface is stable and the split improves invalidation or
navigation; do not recreate the Zig file layout mechanically.

#### Slice 5.1 — Driver, source, lexer, and diagnostics

- load a deterministic module graph;
- represent source without retaining unnecessary substrings;
- tokenize every `bootstrap-v1` construct;
- report invalid bytes/tokens and delimiter/indentation failures through the stable
  JSON diagnostic schema; and
- differentially compare tokens and diagnostics with the Zig compiler.

#### Slice 5.2 — Parser and syntax representation

- parse declarations, types, statements, and expressions used by one small compiler
  module;
- add syntax recovery at the same explicit boundaries as stage 0;
- separate semantic identity from source spans from the beginning; and
- compare a normalized syntax manifest rather than internal memory layout.

#### Slice 5.3 — Declarations, imports, and name resolution

- collect top-level declarations before checking bodies;
- resolve imports deterministically;
- enforce function scope, definite assignment, and shadowing rules;
- assign stable module/declaration identities; and
- emit an exported-interface manifest suitable for differential tests.

#### Slice 5.4 — Types, generics, effects, and capabilities

- implement only the types and constraints used by `bootstrap-v1` first;
- check one declaration at a time;
- keep exported signatures explicit;
- implement options/results, records/unions, collections, `Cell[T]`, and required
  generic specializations; and
- preserve effect/capability errors and their causal diagnostics.

#### Slice 5.5 — Typed IR and lowering

- define a compact, backend-independent typed IR;
- lower one checked declaration independently;
- make all implicit cleanup/rooting operations visible in IR or its verified metadata;
- normalize IR for stage-0/stage-1 differential comparisons; and
- attach deterministic source evidence without using spans as instruction identity.

#### Slice 5.6 — QBE generation and native execution

- emit deterministic QBE against `runtime-abi-v1`;
- compile and run scalar programs first, then records/unions, collections/managed
  values, generics, effects/capabilities, and compiler-sized programs;
- compare native output, stderr, exit status, traps, and normalized QBE with stage 0;
  and
- integrate per-function/data-fragment reuse only after clean emission is correct.

#### Slice 5.7 — Project mode and incremental store

- reproduce deterministic module discovery and source limits;
- persist the Wave 3 identities, fingerprints, dependencies, and artifacts;
- make `check`, `build`, `run`, `test`, formatting, and diagnostic modes usable by an
  agent without a Zig rebuild; and
- run the complete invalidation matrix against both implementations.

At the end of every slice, port at least one real compiler module to the newly working
path. This prevents a toy grammar or IR from accumulating separately from the program
it must compile.

### Wave 6 — Bootstrap and establish trust

Name the stages consistently:

- **stage 0:** archived Zig-built compiler capable of `bootstrap-v1`;
- **stage 1:** compiler executable built from `.my` source by stage 0;
- **stage 2:** compiler executable built from the same source by stage 1; and
- **stage 3:** compiler executable built from the same source by stage 2.

Run each stage from a clean directory with declared inputs only. Capture compiler
version, source tree hash, target, runtime ABI hash, QBE version, assembler/linker
identity, flags, and environment allowlist in a bootstrap manifest.

Compare stage 2 and stage 3 at progressively stronger levels:

1. normalized public-interface manifests;
2. normalized typed IR;
3. normalized QBE;
4. linked artifacts after removing or controlling nondeterministic metadata; and
5. behavior and diagnostics over the complete corpus.

The required reproducibility claim is normalized semantic equivalence. Byte-for-byte
executables are preferable and should be pursued once timestamps, build IDs, paths,
and toolchain metadata are controlled, but those packaging details must not block a
semantically stable bootstrap.

Preserve a small, reproducible stage-0 source/binary bundle and instructions for
rebuilding it. A self-hosted compiler without a maintained seed is difficult to trust
or recover.

Exit criteria:

- stage 2 and stage 3 match at the normalized QBE level and pass the same corpus;
- a clean bootstrap does not read undeclared files or network state;
- failure injection proves corrupt/missing caches rebuild safely;
- the archived stage-0 bundle builds stage 1 on the supported amd64 Linux target; and
- the full process stays within recorded time and memory ceilings.

### Wave 7 — Switch the primary implementation

Use a bounded dual-run period, not an indefinite two-compiler era.

1. Run stage 0 and the self-hosted compiler on every language corpus case for two
   consecutive release candidates.
2. Classify every difference as a bug, intentional spec change, or explicitly
   irrelevant representation detail.
3. Make the self-hosted executable the default for `check`, `build`, `run`, `test`,
   and formatting.
4. Freeze the Zig frontend. It becomes stage-0 bootstrap material and receives only
   security, bootstrap, or critical compatibility fixes.
5. Implement all new language features in the self-hosted compiler first. Do not keep
   feature parity in two active frontends.
6. Keep the C runtime, QBE, and thin launcher independently versioned behind their
   frozen interfaces.

Rollback means selecting the archived stage-0 compiler and known runtime ABI; it does
not mean continuing to develop both frontends.

Exit criteria:

- routine frontend work changes only `.my` compiler sources and tests;
- the documented inner loop invokes no Zig build or Guardian gate;
- differential mismatches are zero across the acceptance corpus;
- stage-2/stage-3 and incremental-equivalence checks are blocking release gates; and
- stage 0 and bootstrap instructions have been exercised from a clean environment.

## 6. Dependency and merge order

| Order | Deliverable | Depends on | May proceed in parallel with |
| --- | --- | --- | --- |
| 0 | Baseline reconciliation and ADRs | Current green tree | Benchmark capture |
| 1 | `bootstrap-v1` and compiler API probe | ADRs | Inventory/parity checklist |
| 2 | Canonical syntax and minimum collections | API probe | Program-boundary work |
| 3 | Arguments/stderr/environment/`main Result` | Runtime semantics | `Cell[T]` |
| 4 | Incremental identities and query contract | Frozen semantics | Runtime ABI documentation |
| 5 | `runtime-abi-v1` conformance suite | Program boundary | Lexer prototype |
| 6 | Self-host lexer/parser/diagnostics | Bootstrap subset | Incremental test harness |
| 7 | Resolver/checker/interface manifests | Stable identities | IR design |
| 8 | Typed IR/lowering/QBE emitter | Runtime ABI, checker | Cache persistence |
| 9 | Project mode and incremental store | Query contract, emitter | Corpus expansion |
| 10 | Stage bootstrap and dual-run | Complete vertical compiler | Reproducibility work |
| 11 | Primary-implementation switch | Parity and bootstrap gates | Stage-0 archival |

One change should have one semantic owner. In particular, do not simultaneously
modify a rule in Zig and independently infer it in the self-hosted port. Land and
specify the rule in stage 0, then port its tests and implementation.

## 7. Test and acceptance matrix

Every behavior change needs the repository's normal SPEC tag, feature metadata,
documentation example, positive test, negative/diagnostic test, and native execution
coverage. In addition, self-hosting work uses these layers:

| Layer | What it proves |
| --- | --- |
| Unit | Local lexer/parser/checker/lowering invariants |
| Golden manifest | Stable tokens, syntax, interfaces, typed IR, QBE, diagnostics |
| Differential | Stage 0 and stage 1 agree on accepted programs and errors |
| Clean vs warm | Incremental results equal clean rebuilds |
| Native corpus | stdout, stderr, exit, traps, and resource behavior agree |
| Agent idiom | The canonical spelling is chosen and diagnostics lead to repair |
| Bootstrap | Stage 2 and stage 3 are semantically reproducible |
| Performance | Reuse counts, latency, and memory remain within ratchets |

Golden files must represent public or normalized contracts, not incidental arena
addresses, hash-table order, byte offsets used as IDs, or private struct layouts.

## 8. Development and gate cadence

### While foundational work is still in Zig

- use the smallest relevant Zig/unit/native test during iteration;
- rebuild the installed compiler only when the changed Zig code requires it;
- run the full documented gate before merging a completed work item; and
- because that gate exercises Guardian, append and commit the required concrete
  Guardian feedback entry after the task.

### While writing the self-hosted frontend

The intended inner loop is:

```console
mylang check selfhost
mylang test selfhost/tests --filter <area>
mylang build selfhost/main.my -o .mylang-cache/selfhost/mylang-next
```

Focused differential and incremental-equivalence tests should run from that loop. It
must not rebuild Zig or run Guardian when no Zig implementation file changed.

### Integration and release

Run the full existing gate for any remaining Zig/runtime changes, plus:

- all self-host unit/native tests;
- stage-0/stage-1 differential corpus;
- clean/warm incremental equivalence and invalidation matrix;
- stage-2/stage-3 bootstrap comparison;
- agent idiom suite; and
- benchmark/memory ratchets.

The release gate may be thorough. The inner loop must stay narrow; do not move release
checks into every `.my` edit.

## 9. Risks and controls

### Moving language during the port

Control: freeze `bootstrap-v1`, use the one-version feature delay, and accept only
critical semantic fixes until stage 1 is complete.

### Maintaining two compilers indefinitely

Control: use a time-bounded dual-run phase, freeze the Zig frontend at switchover, and
never require new features to land in both implementations.

### Renaming `class` creates churn without benefit

Control: run the agent idiom probe first, provide a formatter-driven migration and one
compatibility window, and make the replacement diagnostic mechanically actionable.

### Managed code is too slow for a compiler

Control: measure allocations and hot phases on the self-host workload. Use builders,
fixed arrays, bytes, effect ceilings, or phase-local managed arenas only at measured
hotspots. Do not introduce general references or a second default memory model.

### Cache invalidation is unsound

Control: clean/warm equivalence is mandatory, cache corruption falls back to a rebuild,
and `--explain-invalidation` makes misses auditable. Prefer conservative recomputation
to questionable reuse.

### Runtime ABI drifts under generated code

Control: versioned manifest, conformance suite, cache key inclusion, and an early
mismatch diagnostic.

### Differential tests lock in accidental internals

Control: compare normalized semantic artifacts and external behavior. Internal data
structures are deliberately free to differ.

### Bootstrap is reproducible only inside the repository

Control: run from clean directories with declared inputs, archive stage 0, and test
resource discovery without source-tree-relative paths.

## 10. First implementation backlog

These are the first independently reviewable work items. Each should land green before
the next item that consumes it.

1. **Reconciliation report.** Record the baseline commit and W1–W9 landed/pending
   state; remove stale handoff claims.
2. **Scope ADR.** Ratify function scope and add the zero-iteration predeclaration diagnostic.
3. **Record ADR and probe.** Compare `record`/`class`, decide, then implement the
   migration separately.
4. **Bootstrap contract.** Add `docs/bootstrap-v1.md` and a checker/lint mode that
   rejects compiler-source features outside it.
5. **Compiler-shaped API probe.** Implement a small lexer/parser using public
   collections; turn workarounds into a minimal API list.
6. **Boundary split.** Implement the `--` delimiter and guest `list[str]` arguments first, then
   stderr, environment operations, and `main -> Result[int, str]` as separate changes.
7. **Managed cell.** Implement `Cell[T]`, escape/storage restrictions, diagnostics,
   native tests, and docs without closures.
8. **Incremental IDs.** Remove span-based identity from one vertical path and expose
   its identities in a debug manifest.
9. **Interface hash.** Separate one module's exported interface from function bodies
   and prove a private body edit does not recheck a caller.
10. **Invalidation harness.** Add the clean/warm matrix and `--explain-invalidation`
    before broad cache reuse.
11. **Runtime ABI manifest.** Extract and test the symbols/layouts needed by a scalar
    generated program, then expand by feature.
12. **Self-host slice 1.** Land source loading, lexer, diagnostic JSON, and differential
    token/error tests.
13. **Self-host slice 2.** Parse and resolve a small multi-module program with stable
    declaration identities.
14. **First native vertical slice.** Check, lower, emit, link, and run the smallest
    scalar program through the self-hosted compiler.

After item 14, plan the remaining self-host work from observed module size, invalidation
edges, diagnostics, and missing language vocabulary. Do not estimate the whole port
from lexer progress alone.

## 11. Start and switch gates

### Start writing the production self-hosted compiler only when

- `bootstrap-v1` is frozen;
- the function-scope and record decisions are closed;
- the compiler-shaped API probe needs no undocumented host helper;
- the program boundary can support a real compiler CLI;
- stable declaration identity and interface hashing work in one end-to-end Zig path;
  and
- `runtime-abi-v1` has at least a scalar conformance slice.

Prototypes may precede this gate. Production modules that will become stage 1 should
not.

### Make the self-hosted compiler primary only when

- it implements the whole frozen subset and compiles its own source;
- all required project commands and stable diagnostics are available;
- stage 0 and stage 1 agree across the acceptance corpus;
- stage 2 and stage 3 have normalized QBE equivalence;
- clean and warm results agree across the invalidation matrix;
- the reference edit loop meets the recorded latency and memory ratchets;
- the stage-0 recovery bundle has been rebuilt from clean inputs; and
- there is no unresolved category of fallback to Zig frontend internals.

## 12. Recommended sequencing decision

Do not begin by translating the existing Zig parser file-for-file. First spend the
small, bounded amount of Zig work needed to freeze the language, complete the compiler
boundary, and prove the incremental/runtime contracts. Then build the self-hosted
compiler as vertical slices and stop adding language features to Zig.

That sequence deliberately accepts a short final period of Zig/Guardian friction in
exchange for avoiding years of dual implementation. Once the first native vertical
slice works, the port itself becomes the main language-usability study: any construct
that repeatedly causes verbose, fragile, or surprising compiler code is evidence for
a focused language improvement, while the frozen bootstrap and one-version delay keep
those improvements from destabilizing the compiler that must implement them.
