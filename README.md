# mylang

An experimental statically checked, interpreted language implemented in Zig.
The custom bytecode VM is the primary runtime while we develop the language's
semantics and test whether agents can write and repair correct code more reliably.
The implementation follows [the revision 3 plan](docs/plan.md) and
[interpreter-first roadmap](docs/experiments/interpreter-first.md). The working
language name and `.my` extension are provisional.

The optional [incremental QBE native backend](docs/experiments/incremental-qbe.md)
builds executables with `mylang build`, reusing individual native function objects
while checking the frontend fresh. It supports the current typed operations, managed collections, resources,
and embedding APIs on Linux x86-64; persistent frontend caching remains future work.

Typed VM host-library calls now execute through explicit registrations. The
[board-validation trial](experiments/board_trial/README.md) runs on the VM and
matches a standalone Zig baseline against 87 fixed oracle cases and 60 transformed
cases. Three exploratory agent maintenance blocks have since completed; see
[the audit](docs/audits/feature-completeness-2026-09-07.md). These do not establish
a comparative productivity advantage.
Expensive geometry can remain in Zig/C/Rust behind explicit typed wrappers.
QBE is the only native backend. LLVM and a custom native backend remain future
work.

New application code uses [Python-style syntax](docs/python-syntax.md): `def`,
indented blocks, ordinary assignments, `list[T]`, strings, dictionaries, and
tracing GC. Static types and checked results remain explicit. See the
[GC example](examples/gc-default/main.my) and [schematic entry](src/schematic/guest/main.my).

Current supported features and restrictions are indexed in the
[current language reference](docs/current-language.md). Run `mylang --features`
for a machine-readable manifest tied to the installed executable.

## Toolchain

Use **Zig `0.17.0-dev.1683+5ceec001b`**, the exact snapshot used by Guardian.
The user selected this snapshot in place of the plan's original preference for
a released toolchain. `.zigversion`, the package manifest, and the build guard
pin the version; CI installs the manifest's version and verifies it exactly.

On the development machine it is installed at:

```sh
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig version
```

The build targets the native host and depends on the sibling `../guardian-zig`
checkout for compiler quality checks. The CLI
uses this snapshot's `std.process.Init` and `std.Io` APIs. Do not substitute
Zig 0.15 APIs or update the compiler version as part of a language feature.

## Build a native application

`zig build` also compiles the vendored QBE release (`vendor/qbe`, version pinned in
`.qbeversion`) into `zig-out/bin/qbe`, so only the pinned Zig toolchain has to be
installed:

```sh
zig-out/bin/mylang build examples/factorial.my -o /tmp/factorial --report
/tmp/factorial
```

To compile and execute without keeping a final binary, use:

```sh
zig-out/bin/mylang build examples/factorial.my --run
```

Add `--project` for a module entry or `--library` for a shared library. The compiler
runs the native build directly; Python is not needed for application builds.
`--qbe` and `--zig` select tool paths; otherwise QBE is taken from beside the
`mylang` executable, then `PATH`, so builds work from any working directory. See
the [QBE build guide](docs/experiments/incremental-qbe.md) for the vendored
toolchain, cache behavior, providers, and embedding.

## Run guest tests

```sh
zig-out/bin/mylang test path/to/main.my --filter '*test_*'
zig-out/bin/mylang test path/to/main.my --cases cases.json --json
```

Exported `test_` functions run as native QBE code with typed assertions and fresh
execution state. Passed tests with unchanged semantic dependencies can be reused;
`--force` reruns them. Python is not required. See the
[guest test workflow](docs/experiments/guest-tests.md) for fixtures, budgets, and
result-cache behavior.

## GC-default application preview

Managed lists allocate and grow with no allocator parameters and no ownership
annotations. The schematic guest uses them throughout its application model. See
[managed memory](docs/managed-memory.md) and [the runnable example](examples/gc-default/main.my).
[Managed arenas](docs/arenas.md) are the one way to control when they are freed.

## Real schematic pilot

The [Straps LMX2595 SVG pilot](experiments/schematic/README.md) parses the local
Netlisp DSL and renders a schematic inside the bytecode VM. It includes a generated
SVG, reproducible inputs and independent netlist acceptance. This is a bounded
single-subcircuit application; full Netlisp evaluation remains outside its scope.

## Application development without rebuilding Zig

Use an installed `mylang` binary to check/run `.my` projects from disk. The two
pilot hosts also load disk source explicitly: `schematic-svg --project DIRECTORY`
and `board-trial --project DIRECTORY`, followed by their input paths. The directory
contains `main.my` and its imports. Each invocation reads the current source and
compiles it to VM bytecode in memory. No Zig or Guardian invocation is needed for
application edits; rebuild the host when changing the implementation or wrappers.

See the [implementation and phased development plan](docs/experiments/incremental-development.md)
for commands and acceptance. [Incremental verification](docs/experiments/verification-runtime.md)
now provides opt-in affected-suite selection, shared receipts, local agent scheduling
and combined-merge certificates. The [development host](docs/experiments/development-host.md)
reloads the schematic in one VM process. Existing production gates remain full gates;
finer semantic-query caching is conditional on measurements.

The development tools keep the ordinary read/edit/check workflow:

- [Project verification](docs/experiments/project-workflow.md) prints a compact
  receipt by default and retains complete context and command output in its report.
- [Contract fixtures](docs/experiments/contract-tests.md) exercise an application's
  actual stdin/stdout interface, with strict JSON or exact-byte expectations and
  bounded child execution. A maintained runner replaces per-task driver scripts.
- [Compiler-pinned references](docs/experiments/agent-reference.md) provide a
  concise searchable language/API reference derived from the selected executable.

Run `zig build test-agent-tools --summary all` for their implementation regressions.
These tests also belong to the default suite; they do not launch agent evaluations
or establish a development-speed improvement.

## Build and use

```sh
zig build
zig-out/bin/mylang run examples/arithmetic.my
zig-out/bin/mylang check examples/arithmetic.my
zig-out/bin/mylang dump-bytecode examples/arithmetic.my
zig build test --summary all
zig build test -Doptimize=ReleaseFast --summary all
zig build fmt-check
```

`zig build test` runs checker/VM, actual CLI, and interpreter/tooling integration
acceptance. `zig build test-interpreter` is an explicit alias. CI uses this
default suite in Debug and ReleaseFast.

QBE native compilation and parity integration remain available on demand:

```sh
zig build test-qbe --summary all
zig build test-qbe-build --summary all
zig build test-native-tests --summary all
zig build test-c-ffi --summary all
```

Guardian gates each acceptance route. `-Doptimize` selects the host compiler/VM
mode. Use a disk-backed `TMPDIR` with sufficient space for large native runs.

The example prints `7`. A successful program result is printed to stdout, not
used as the exit code. Success exits 0, source errors and guest traps exit 1,
and usage/I/O/host failures exit 2. Diagnostics go to stderr. Source files
are currently limited to 16 MiB; excessive syntax nesting is diagnosed.

## Compiler quality gate

Guardian checks the Zig compiler implementation on `zig build`, `zig build test`,
and `zig build run`. `guardian.toml` selects the strict profile and blocking builds;
violation baselines are disabled. Runtime tests use Guardian's counting runner so
an empty test selection cannot pass unnoticed. `zig build test-compile` compiles
both complete Zig test roots without executing them.

Keep this checkout beside `guardian-zig`. Guardian uses the same pinned Zig
snapshot. CI checks out both repositories and pins the Guardian revision in its
workflow. The build verifies any reused Guardian binary against its source.

```sh
zig build guardian -- all . --gate --full
zig build guardian-doctor
zig build guardian-debt
zig build guardian -- install-hook .
```

The hook command installs a blocking pre-commit gate in this checkout; repeat it
after cloning because Git hooks are local. It also configures Guardian metadata
merge handling.

[SPEC.md](SPEC.md) links implemented behaviors to executable regression tests.
[Versioned JSON diagnostics](docs/experiments/json-diagnostics.md) are available
with `--diagnostics=json`. Source locations, notes, VM traces and cached warnings
stay on stderr; command results keep their stdout format.

[Ownership diagnostic provenance](docs/experiments/diagnostic-provenance.md) now
shows the invalid use, the earlier transfer, and the value declaration.
Repair fixtures check these locations and execute the corrected programs.
`src/root_test.zig` is the unit test root, and `test/integration.zig` contains the
actual CLI tests. Python acceptance drivers remain in `tests/`. There are no
frozen violations or accepted violation baselines. Guardian's local telemetry
cache is ignored.

## Current implementation

The [typed VM host interface](docs/experiments/host-functions.md) supports explicit
`host fn` declarations, transitive effects and program-bound registrations. It
copies ordinary values through bounded synchronous sessions, including imported
calls and typed results. Host-enabled typed application invocation now accepts
snapshots and returns owned reports through exported guest functions.
Runtime-owned boundary values reject.

The scalar MVP (M0–M5) is implemented and audited: owned source buffers, source locations, lexer,
parser, separate untyped/typed representations, per-function instructions,
an iterative VM with typed locals, jumps, and explicit call frames, deterministic dumps, binding diagnostics, and actual-CLI tests.

The accepted subset has one `fn main() -> i64` and typed helper functions, with
local bindings, assignment,
nested blocks, branches, loops, discarded expression statements (`_ = expr`),
and typed returns.
[Unit procedures](docs/experiments/unit-procedures.md) use `-> unit`, ordinary call
statements, and bare returns or fallthrough; other values retain explicit handling.
It supports integer and boolean values,
optional local type annotations, unary `-` and `!`, binary `+`, `-`, `*`, `/`, `%`, short-circuit `&&` and `||`,
comparisons, parentheses, whitespace, and `//` comments. Active shadowing,
use outside scope, mutation of immutable bindings, and type mismatches are
rejected. Unused bindings and unnecessary `mut` produce advisory warnings.
Arithmetic traps on overflow in every host optimization mode; checking does
not evaluate arithmetic. `examples/locals.my` returns `21`.

Run supports `--max-steps=N` (default 10,000,000) and `--max-frames=N`
(default 1,024, including main) to bound execution. Calls support forward
references, mutual recursion, and boolean or integer parameters/results.
Guest traps include source locations and a bounded call trace.
`examples/sum_inline.my` returns `4950`; `examples/gcd_inline.my` returns `6`.
`examples/sum.my` and `examples/gcd.my` are the plan's exact acceptance programs.
All 47 tests pass in Debug and ReleaseFast, including from a fresh checkout.
The [acceptance audit](docs/mvp-audit.md) maps requirements to evidence.

The first post-MVP experiment is implemented:

```sh
zig build run -- discover-duplicates examples/duplicates.my --timings
```

It reports exact checked-function candidates after normalizing bound names,
with source locations and advisory explanations. Ordinary compilation does not
run it. See the [comparison contract and review](docs/experiments/duplicate-discovery.md).
All 413 tests pass in Debug and ReleaseFast.

[Post-MVP tracking](docs/experiments/roadmap.md) records the remaining experiments.
Records, complete construction, field access, preserving updates, and declarative
complete conversions are now implemented; see [A1 semantics](docs/experiments/aggregates.md).
Run `examples/records.my` (12) or `examples/conversions.my` (11).
Signed/unsigned 8/16/32/64-bit integers and checked casts are implemented
([integer semantics](docs/experiments/integers.md)). Fixed arrays, checked indexing,
`replace`, and `len` complete A1 ([array semantics](docs/experiments/arrays.md)).
Run `examples/arrays.my` (44). A2 now includes nominal scalar domains and private factories/accessors
([domain semantics](docs/experiments/domains.md)); `examples/domains.my` returns
1003. [Scalar domain equality](docs/experiments/domain-equality.md) supports `==`,
`!=` and generic equality contracts without mixing distinct IDs or units.
Closed enums/tagged unions and exhaustive matching are also implemented
([variant semantics](docs/experiments/variants.md)); `examples/variants.my` returns
24. Complete enum-indexed tables finish A2
([table semantics](docs/experiments/tables.md)); `examples/tables.my` returns 1407.
Resource/capability operations and modules have subsequent implemented milestones
below. Broader native interfaces, generic contracts, and other pending roadmap work
are not yet complete.

See [implemented semantics](docs/semantics.md) and [verification/progress](docs/progress.md).


[Typed recoverable results](docs/experiments/results.md) now carry handling
obligations through bindings, helpers, and wrappers. Exhaustive matches and
returns handle them; a silently overwritten obligation is rejected.
`examples/results.my` returns 7. [Postfix `?` propagation](docs/experiments/propagation.md)
checks early-return obligations; `examples/propagation.my` returns 20.

[Transitive effect bounds](docs/experiments/effects.md)
now reject direct or indirect managed allocation under `noalloc`.
[Clock and randomness capabilities](docs/experiments/external-capabilities.md) now
require injected host providers and contribute distinct transitive effects. The
CLI checks their example but cannot run it without providers. Further capability
operations and their current limits are described below.

The [external resource backend](docs/experiments/external-resources.md) now tracks
fallible completion separately from fallback release, with scoped ownership moves
and reverse cleanup. [Source resource acquisition/completion](docs/experiments/source-resources.md) now
connects those rules to nominal types, explicit filesystem/network grants, owned
error results, and transitive cleanup effects. Providers remain injected; the CLI
checks the example but denies execution without providers.

[Bounded environment lookup](docs/experiments/environment.md) now uses explicit
entry grants and injected providers, preserving missing/empty distinctions and
rejecting oversized values without truncation.

[Resource reads/writes](docs/experiments/resource-io.md) now expose bounded byte
snapshots, explicit EOF, and actual write counts while retaining ownership.
Operating-system adapters remain separate work.

[Managed arenas](docs/arenas.md) provide the language's only manual-memory control:
`with arena() as scratch:` frees everything a phase of work allocated in one step,
and `scratch.escape(value)` copies a result out.
`zig build run -- run-project examples/arena-managed/main.my` returns `38`.

[Approximate discovery](docs/experiments/approximate-discovery.md) is available with
`discover-duplicates --approximate`. It reports canonical edits between near matches
and explicitly flags an incomplete search when work or output limits are reached.

[Static quality reports](docs/experiments/quality-reports.md) are available with
`report-quality`. They show resolved calls, reachability from main, binding counts,
and structural metrics with configurable review thresholds. Runtime coverage is
explicitly unmeasured.

[Canonical formatting](docs/experiments/formatter.md) is available with `fmt`
(stdout) and `fmt --check`. It preserves token spellings and comments, and accepts
syntactically valid code without requiring completed type checking.

[Project verification](docs/experiments/verification-driver.md) uses
`python3 scripts/verify.py verify.json`. Filters select explicit steps and their
dependencies; reports distinguish selected success from full-manifest success.
The eight Python driver tests also run under `zig build test`, alongside the
core/CLI suites and the interpreter/tooling integration drivers.

Source programs use [declared codec operations](docs/experiments/source-codecs.md)
to convert between domain values and their typed wire representations.

Pure generic specialization is implemented.
[Concrete generic records and arrays](docs/experiments/generic-concrete.md) now
support fixed data schemas alongside symbolic parameters; broader generic
contracts remain pending. [Generic aggregate updates](docs/experiments/generic-updates.md)
preserve record, array and enum-table snapshots.
[Generic enum/union construction and matching](docs/experiments/generic-variants.md)
now retain exact payload types and exhaustive cases.
[Concrete generic results](docs/experiments/generic-results.md) now enforce transfers,
handling, propagation and obligations across control-flow paths.
[Generic provider operations](docs/experiments/generic-providers.md) now retain
capability, result and effect contracts.
[Generic fixed arrays](docs/experiments/generic-arrays.md) now support `[N]T`
construction, nested substitution and nominal-ID membership.
`examples/generic-arrays.my` returns `3`.
[Nominal template syntax and interfaces](docs/experiments/nominal-type-syntax.md)
now retain declarations and nested applications. [Declaration checking](docs/experiments/nominal-template-checks.md)
validates unused template fields, identities and argument requirements.
[Finite layout checking](docs/experiments/nominal-layouts.md) now distinguishes
stored recursion from finite nesting and phantom arguments.
[Concrete nominal instances](docs/experiments/nominal-instances.md) now execute
records, unions, results and enum templates on the VM, preserving argument
identity, ownership and typed host contracts.
`examples/nominal-instances.my` returns `16`.
[Symbolic nominal bodies](docs/experiments/nominal-bodies.md) now check `Box<T>`
fields, variant payloads, result propagation and ownership before calls,
then specialize the discovered concrete types for the VM.
`examples/nominal-bodies.my` returns `7`.
[Generic provider contracts](docs/experiments/nominal-providers.md) now support
resource/environment result wrappers and fully substituted byte-array inputs.
Generic functions can also call codecs for concrete domains while preserving
factory/accessor privacy. The [board trial](experiments/board_trial/README.md)
now uses one optional `Slot<T>` union and one membership helper for distinct IDs.
[Structural generic constraints](docs/experiments/structural-constraints.md) now
support named fields and public domain operations. [Public generic tooling](docs/experiments/generic-public-tooling.md)
exposes symbolic templates separately from concrete callable exports.
`examples/structural-constraints.my` returns `12`. Guest-source JSON encoding and
decoding were removed with the explicit storage tier; typed JSON remains available
at the CLI and host boundary.

[Compiler navigation](docs/experiments/navigation-client.md) finds qualified
symbols, callers, references, types, effects and bounded source context:

```sh
zig-out/bin/mylang index-project src/schematic/guest/main.my
python3 scripts/navigate.py --compiler zig-out/bin/mylang \
  --entry src/schematic/guest/main.my --symbol layout::build --relation context \
  --cache-dir /tmp/mylang-navigation
```

Indexes carry source/compiler receipts, and failed bodies expose unchecked
partial declarations. The optional bounded cache supports equivalent worktrees.
[Larger-project measurements](docs/experiments/large-project-checking.md) justified
retaining 256 parsed modules within the existing memory budget; semantic reuse
below module/project granularity remains conditional on demonstrated cost.

Module header discovery is available with `zig build run -- list-modules examples/modules/main.my`.
It reports bounded import graphs and cycles. `list-interfaces` on the same entry
parses module bodies and checks explicit exports and signature visibility; full body checking/execution is available through `check-project`/`run-project`. See [module discovery](docs/experiments/module-discovery.md)
and [module interfaces](docs/experiments/module-interfaces.md).

`zig build run -- run-project examples/modules/main.my` now returns 12 through a
shared domain factory. `check-project` validates all imported bodies with nominal
types, private boundaries, ownership, and effects. See
[module execution](docs/experiments/module-execution.md) for scope and remaining work.

Optional dependency policy is available through `check-policy <entry.my> --policy=<rules.json>`.
It checks the language first and exits 3 for a separate policy failure. See
[import policy](docs/experiments/import-policy.md); ordinary project commands do not load it.

Cross-file discovery is available through `discover-project-duplicates <entry.my>`,
with the same exact/approximate options as single-file discovery. Try
`zig build run -- discover-project-duplicates examples/module-duplicates/main.my --approximate`.
See [module duplicate discovery](docs/experiments/module-duplicates.md).

`report-project-quality <entry.my>` reports resolved calls and structural metrics
with separate main/export reachability. Exported interfaces and their private helpers
are accounted for explicitly; see [module quality reports](docs/experiments/module-quality.md).

`fmt-module <file.my>` formats a module draft without resolving imports.
`fmt-project <entry.my> --check` checks formatting across its reachable graph.
Neither command writes source files; see [module formatting](docs/experiments/module-formatting.md).

`list-declarations <file.my>` prints a parse-only `declarations-v1` JSON listing of
top-level declarations with their kinds, exports and original byte ranges. It resolves
no imports and checks nothing; see [declaration listing](docs/experiments/list-declarations.md).

`eval-project` provides [restricted evaluation](docs/experiments/restricted-evaluation.md)
for effect-free, parameter-free project entry points, with explicit step, frame,
and VM-memory budgets. Checked schemas and exact successful-check caching are
implemented below; finer semantic reuse remains measurement-driven.

Use `eval-project --evaluation-report` for a JSON [dependency receipt](docs/experiments/evaluation-reports.md)
containing the exact result, source/import hashes, budgets, and running compiler identity.

`eval-project --evaluation-request` computes the same request identity after checking
eligibility, without executing the entry or claiming a result.

`python3 scripts/evaluate.py examples/modules/main.my --cache-dir .mylang-cache`
provides [persistent evaluation reuse](docs/experiments/evaluation-cache.md). Hits
still check the current project and explicitly report that VM execution was skipped.

Add `--compare-to path.json` to the evaluation cache driver to explain changes against
a saved request, evaluation report, or cache entry (`--max-changes` bounds the output).

`input-module` validates [typed JSON input manifests](docs/experiments/input-manifests.md)
and emits ordinary exported functions. The example at `examples/input-values/`
evaluates to 64. `eval-project --inputs=examples/input-values/inputs.json` generates
the declared module in memory; the cache driver also accepts `--inputs` and reads it
fresh on every lookup.

Repeat `--inputs` for multiple declared modules (up to 16 manifests and 8 MiB combined).
Conflicting module bindings reject; flag order does not change the request identity.

Public schemas can now be derived from checked module contracts:

```sh
zig-out/bin/mylang schema-project examples/schema/main.my
```

The deterministic JSON graph includes exported types and function signatures,
qualified identities, field/variant structure, integer bounds,
and inferred effects. Private declarations remain excluded; domains and runtime
owners/capabilities retain opaque reconstruction boundaries. This establishes
[schema derivation](docs/experiments/schemas.md). Ordinary serialization and Python
data bindings, domain codecs, Python callable wrappers, and generation receipt/cache
integration are implemented as described below.

Ordinary typed values now have a bounded JSON codec:

```sh
zig-out/bin/mylang check-value-project examples/schema/main.my \
  --value=examples/schema/message-value.json
```

The command checks source and data, materializes owned compiler values, and writes
canonical `typed-json-v1`. It supports integer/boolean values, records, arrays,
enum tables, enums, unions, and results. Duplicate/unknown keys and invalid values
reject; opaque types require future explicit codecs. See the
[wire contract, limits, and remaining integration](docs/experiments/typed-json.md).

Generate standalone Python data bindings from the checked public schema:

```sh
mkdir -p zig-out/bindings
python3 scripts/bindings.py examples/schema/main.my \
  --output zig-out/bindings/message_bindings.py
PYTHONPATH=zig-out/bindings python3 examples/schema/use_bindings.py
```

The module provides annotated nominal records/enums/variant classes and compatible
bounded typed JSON codecs using only Python's standard library. Generation reports
unsupported opaque types explicitly and preserves existing output on failure. See
[Python bindings](docs/experiments/python-bindings.md) for naming, constructors,
wire parity, limits, and remaining foreign-function/domain integration.

Binding generation now supports `--cache-dir=.mylang-cache/bindings`. It always checks
the current project, validates cached artifact identities, and reports whether actual
generation ran. Identical output preserves its modification time with or without a
cache, avoiding unnecessary downstream rebuild triggers. See
[binding artifact reuse](docs/experiments/binding-cache.md) for request identities,
corruption handling, and the remaining frontend incremental work.

Use `schema-project --schema-report` to include hashes and byte counts for every loaded
module, resolved imports, and the actual compiler image behind a checked schema.
Binding generation includes fresh source receipts even when its public schema is
unchanged and an artifact is reused. See
[schema source receipts](docs/experiments/schema-receipts.md) for identity and snapshot
semantics, integrity checks, and remaining frontend incremental work.

Typed JSON errors now include a nested JSON pointer where typed validation can identify
one. Located embedding APIs retain the failure path independently of parsed documents;
large paths are bounded and explicitly marked as truncated. See
[codec diagnostics](docs/experiments/codec-diagnostics.md) for path semantics and limits.

[Direct C imports](docs/c-ffi.md) support `extern fn` scalar calls through QBE,
with repeatable `--link`, `--link-library`, and `--library-path` build/test options.
See [the libc example](examples/c-ffi/main.my).

The [ordinary application corpus](examples/corpus/README.md) adds a multi-module
invoice calculator and packet decoder, tested against independent Python oracles.
Its review records intentional duplicate policies, changed-rule diagnostics, and
integration with formatting, dependency policy, schemas, and data bindings.

[Typed embedding calls](docs/experiments/typed-invocation.md) can invoke exported
effect-free functions and checked domain factories with owned argument copies and
typed results. Explicit domain codecs and Python wrappers build on this API as
described below.

Domains can now declare [explicit codec contracts](docs/experiments/domain-codecs.md)
linking an ordinary wire type to checked public decoder/encoder methods. The schema
records those contracts while preserving opaque backing. [Executed JSON codecs](docs/experiments/domain-json.md)
now use them with shared budgets; Python calls also use these contracts. See [the example](examples/domain-codecs/main.my).

Try a declared domain codec with:

```sh
zig-out/bin/mylang check-value-project examples/domain-codecs/main.my --value=examples/domain-codecs/value.json
```

[invoke-project](docs/experiments/checked-calls.md) now calls exported functions from
a schema-pinned typed-call-v1 request with named JSON arguments. Domain codecs and
the target share operation budgets. This supplies the call boundary for generated
Python wrappers described below.

Generated Python bindings also expose `Client`, `CALLS`, and nominal domain wire
objects for exported effect-free calls. Calls use the selected compiler and project
through the schema-pinned JSON protocol; standalone data codecs remain independent
of the compiler. See [generated Python calls](docs/experiments/python-calls.md) for
usage, budgets, error handling, and unsupported boundaries.

Schema generation, JSON calls, and Python binding generation accept repeated
`--inputs` manifests. Generated clients accept `inputs=(path, ...)` and reread the
values on each invocation. See [call inputs](docs/experiments/call-inputs.md) for
schema invalidation and source receipt behavior.

Long-lived Zig embedding hosts can reuse unchanged module parse tables through
`syntax_cache.Cache` and `interfaces.buildWithCache`. Returned syntax belongs to
each fresh project; all semantic checking still runs. See
[incremental module syntax](docs/experiments/incremental-syntax.md) for limits,
observations, and the remaining incremental-compilation work.

Use `mylang check-session path/to/main.my` for a persistent checking process. Send
`check`, `clear`, or `quit` lines on stdin; each reply reports status, parse reuse
and successful-verdict reuse as JSON. Exact successful snapshots skip semantic
checking and replay their warnings; changed snapshots are checked afresh. Files and `--inputs` manifests are loaded afresh on every check. See
[persistent checking sessions](docs/experiments/check-session.md).

Automatic project checking: `python3 scripts/watch.py examples/modules/main.my`
reuses one compiler session and rechecks source/manifest content changes. See
[watch behavior and bounds](docs/experiments/watch.md).

Native builds support `--report` for emission and link timings and publication
status. Failed builds preserve the last executable; byte-identical successful
builds preserve its timestamp.

The [owner/generic maintenance calibration](docs/experiments/direct-agent-maintenance-20260907.md) records two fresh agents completing three sequential stages each, with preserved command and grading evidence. It establishes feasibility on small tasks, not a language productivity advantage.
