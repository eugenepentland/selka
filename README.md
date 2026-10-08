# mylang

An experimental statically checked, compiled language implemented in Zig.
Programs are compiled to native code. The design goal is for mylang to be the
fastest language for AI agents to develop in: the default path is the easy path —
Python-like syntax, static types, incremental compilation and testing — with
opt-in escape hatches for performance when a measurement calls for them. That goal
is still a hypothesis; [the plan](docs/plan.md) tracks the application evidence that
would confirm it. The working language name and `.my` extension are provisional.

## Start here

- **Writing mylang?** Read [the one-page primer](docs/primer.md): the language
  for a Python programmer, every example checked by `mylang doctest`. The user
  guides also ship inside the compiler, so they are there outside this
  repository: `mylang docs` lists them, and `mylang docs primer` (or `syntax`,
  `io`, `errors`, `tests`, `build`, ...) prints one.
- **Commands:** `mylang --help` starts with the everyday ones. `run`, `build`
  and `test` make a debug build, one LLVM unit per module so an edit recompiles
  only what changed; add `--release` for the optimized whole-program build you
  ship or time.
- **Working in a large project:** `mylang context ENTRY.my --symbol=module::name`
  answers one bounded question about a declaration (`--at=FILE:LINE:COLUMN`
  about a position), `mylang tests-for ENTRY.my module::name` lists the tests
  that reach it, `mylang list-interfaces ENTRY.my` prints every module's public
  surface, and `mylang test ENTRY.my --affected --against REF` runs only the
  tests an edit since `REF` can change.
- **All documentation:** [docs/README.md](docs/README.md) indexes the user guides
  first and keeps the compiler's internal records (audits, experiments,
  proposals, handoffs) apart.

## Status

The compiler's back end is the new core (`src/core/`, designed in
[docs/design](docs/design/new-core-ir.md)): the checked program becomes Core IR,
then LLVM text, which the pinned Zig toolchain's clang compiles and links with the
core C runtime into a Linux x86-64 executable. A debug build emits one unit per
source module, and unit objects are kept in a content-keyed per-user store, so an
edit recompiles only the units whose text changed and an unchanged build replays
without starting a process; `--release` builds the whole program as one optimized
unit ([native builds](docs/tooling/native-build.md)). The front end reuses checked
bodies, symbolic generic templates and concrete specializations across processes
([the caches guide](docs/tooling/caches.md)). `mylang run` is that build followed by
running the result, and `mylang test` builds and runs each test as its own process.

Memory is one-count reference counting with copy-on-write: lists, dictionaries,
sets, strings and records are values, released when their last owner goes away.
Stage S5 of the new core (2026-10) retired the old back end: QBE, the bytecode IR,
the QBE-to-LLVM adapter, the tracing collector, two-count reference counting,
`with arena()` regions (now a plain block that warns `W_ARENA_RETIRED`), host
functions (`host def`, `mylang invoke`) and the host applications built on them
([removed features](docs/legacy/README.md)). C interop is `extern def` with
`--link FILE.c` ([direct C imports](docs/c-ffi.md)).
[The plan](docs/plan.md#1-project-direction) records the earlier direction.

The language reads like Python: `def`, `record`, indented blocks, ordinary
assignments, `list[T]`, strings, dictionaries, and automatic memory management
(reference counting with copy-on-write) — with static types and checked results
kept explicit. [The language guide](docs/python-syntax.md) covers it; see the
[managed-memory example](examples/gc-default/main.my).

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

`zig build` installs `zig-out/bin/mylang`; the only other tool a build needs is the
pinned Zig toolchain, whose clang compiles the emitted LLVM:

```sh
zig-out/bin/mylang build examples/factorial.my -o /tmp/factorial --report
/tmp/factorial
```

To compile and execute without keeping a final binary, use:

```sh
zig-out/bin/mylang build examples/factorial.my --run
```

A module header or import makes the entry a project; the nearest `mylang.json`
supplies its import policy and limits. `--zig` selects the toolchain (else `ZIG`,
`MYLANG_ZIG`, then `PATH`). `--report` prints one `cache-report-v1` line saying what
the caches served; `--release` builds the optimized whole-program unit. Python is
not needed. See [native builds](docs/tooling/native-build.md) for the pipeline, the
caches, `--verify-cache` and `--no-cache`.

## Run guest tests

```sh
zig-out/bin/mylang test path/to/main.my --filter '*test_*'
zig-out/bin/mylang test path/to/main.my --cases cases.json --json
```

Exported `test_` functions run as native code, each test in a fresh process under
step, frame, byte and time budgets. Passed tests whose program (keyed by its Core
IR) and settings are unchanged replay their receipts; `--force` reruns them, and
`--affected --against REF` runs only the tests an edit can reach. See
[guest tests](docs/tooling/guest-tests.md).

## Managed-memory application preview

Managed lists allocate and grow with no allocator parameters and no ownership
annotations; the runtime counts and releases them. See
[managed collections](docs/managed-memory.md) and
[the runnable example](examples/gc-default/main.my).

## Real schematic pilot

The [Straps LMX2595 SVG pilot](experiments/schematic/README.md) (a record: its
`schematic-svg` host application was retired in S5) parsed the local Netlisp DSL
and rendered a schematic from a natively built guest. It includes a generated
SVG, reproducible inputs and independent netlist acceptance. This is a bounded
single-subcircuit application; full Netlisp evaluation remains outside its scope.

## Application development without rebuilding Zig

Use an installed `mylang` binary to check, run and test `.my` projects from disk.
Each invocation reads the current source and builds it natively, reusing the
units that did not change. No Zig or Guardian invocation is needed for application
edits.

See the [implementation and phased development plan](docs/experiments/incremental-development.md)
for commands and acceptance. [Incremental verification](docs/experiments/verification-runtime.md)
now provides opt-in affected-suite selection, shared receipts, local agent scheduling
and combined-merge certificates. The [development host](docs/experiments/development-host.md)
reloads the schematic in one host process. Existing production gates remain full gates;
finer semantic-query caching is conditional on measurements.

The development tools keep the ordinary read/edit/check workflow:

- [Project verification](docs/experiments/project-workflow.md) prints a compact
  receipt by default and retains complete context and command output in its report.
- [Contract fixtures](docs/experiments/contract-tests.md) exercise an application's
  actual stdin/stdout interface, with strict JSON or exact-byte expectations and
  bounded child execution. A maintained runner replaces per-task driver scripts.
- The compiler-derived surface is what the installed binary reports about itself:
  `mylang --features`, `mylang list-declarations`, `mylang list-interfaces` and
  `mylang schema-project`. The [compiler-pinned reference
  page](docs/experiments/agent-reference.md) is a historical design record — its
  `scripts/reference.py` generator was removed with the Zig-native tooling fold.
  [The compiler-derived reference](docs/reference.md) documents the in-binary
  reference engine that replaces it.
- [Focused context](docs/tooling/agent-context.md) answers one bounded
  `agent-context-v1` question about one declaration — its contract with a fact
  status per field, the types it names, its dependencies, its static test
  reachability and, optionally, how an API baseline changed — inside a byte
  budget that reports what it dropped: `mylang context app/main.my --symbol
  'model::validate'`.

Run `zig build test-agent-tools --summary all` for their implementation regressions.
These tests also belong to the default suite; they do not launch agent evaluations
or establish a development-speed improvement.

## Build and use

```sh
zig build
zig-out/bin/mylang run examples/arithmetic.my --print-result
zig-out/bin/mylang check examples/arithmetic.my
zig-out/bin/mylang dump-ir examples/arithmetic.my
zig build test --summary all
zig build test -Doptimize=ReleaseFast --summary all
zig build fmt-check
```

`zig build test` runs the checker, actual CLI, and runtime/tooling integration
acceptance. CI uses this default suite in Debug and ReleaseFast.

Building and using mylang needs only the pinned Zig: `zig build` runs no Python,
and the installed compiler's `check`, `build`, `run`, `test`, `fmt`, `docs`,
`index-project`, `context` and `packages` run none either, `--release` included
(`USE-WITHOUT-PYTHON-1` and the `PACKAGES-*` tests check them under an empty
`PATH`). Python 3 is used only by some `zig build test` drivers,
developer scripts and experiments.

While iterating, `-Dtest-filter=SUBSTRING` narrows the Zig suites to the tests
whose name contains that text: `zig build test-core -Dtest-filter=…` for the new
core's tests, `zig build test-units -Dtest-filter=…` for `src/root_test.zig` and
`zig build test-cli -Dtest-filter=…` for `test/integration.zig`; none of them runs
the Python drivers. A filter that
selects nothing fails rather than reporting a green run, so narrow one root at a
time. `-Dtest-filter` applies to `zig build test` and `test-compile` too.

The language suite runs on its own too:

```sh
zig build test-core --summary all
zig build test-lang --summary all
zig build test-docs --summary all
```

Guardian gates each acceptance route. `-Doptimize` selects the host compiler's
mode. Use a disk-backed `TMPDIR` with sufficient space for large native runs.

The example prints `7` and exits `7`. `def main() -> int`'s return value is the
process exit status, the way a Python or Go program returns an exit code,
truncated to the low 8 bits (POSIX `waitpid` semantics: status = value & 0xFF),
for `mylang run`, `run-project`, and a native executable from `mylang build`.
`--print-result` prints the value to stdout as before and is now orthogonal to
the status — you can print it and also exit with it. A source or check error
exits 1, a runtime trap exits 1 (the trap outranks the return, because the
program never reached it), and usage/I/O/host failures exit 2. Diagnostics go to
stderr. Source files are currently limited to 16 MiB; excessive syntax nesting
is diagnosed.

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
merge handling. Also run `sh scripts/setup-git.sh` once per clone: it registers
the `SPEC.md` merge driver (`scripts/merge_spec.py`), which merges spec bullets by
tag so parallel branches that append to one section no longer conflict.

[SPEC.md](SPEC.md) links implemented behaviors to executable regression tests.
[Versioned JSON diagnostics](docs/experiments/json-diagnostics.md) are available
with `--diagnostics=json`. Source locations, notes, guest stack traces and cached
warnings stay on stderr; command results keep their stdout format.

[Ownership diagnostic provenance](docs/experiments/diagnostic-provenance.md) now
shows the invalid use, the earlier transfer, and the value declaration.
Repair fixtures check these locations and execute the corrected programs.
`src/root_test.zig` is the unit test root, and `test/integration.zig` contains the
actual CLI tests. Python acceptance drivers remain in `tests/`. There are no
frozen violations or accepted violation baselines. Guardian's local telemetry
cache is ignored.

## Current implementation

The [typed host interface](docs/experiments/host-functions.md) (`host def`,
registered providers and typed invocation) was retired in S5 (2026-10); the
paragraphs below are the implementation history, and
[current-language.md](docs/current-language.md) is the current surface.

The scalar MVP (M0–M5) is implemented and audited: owned source buffers, source locations, lexer,
parser, separate untyped/typed representations, per-function instructions with
typed locals, jumps and explicit call frames, deterministic dumps, binding
diagnostics, and actual-CLI tests.

The accepted subset has one `def main() -> int` and typed helper functions, with
local bindings, assignment,
nested blocks, branches, loops, discarded expression statements (`_ = expr`),
and typed returns.
[Unit procedures](docs/functions.md#unit-procedures) omit the return annotation, ordinary call
statements, and bare returns or fallthrough; other values retain explicit handling.
It supports integer and boolean values,
optional local type annotations, unary `-` and `not`, binary `+`, `-`, `*`, `/`, `%`, short-circuit `and` and `or`,
comparisons, parentheses, whitespace, and `#` comments. Active shadowing,
use outside scope, mutation of immutable bindings, and type mismatches are
rejected. Unused bindings produce advisory warnings.
Arithmetic traps on overflow in every host optimization mode; checking does
not evaluate arithmetic. `examples/locals.my` returns `21`.

Run supports `--max-steps=N` and `--max-frames=N` (unbounded unless given; a test
defaults to 1,000,000 steps and 1,024 frames) to bound execution. Calls support forward
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

See [the language reference](docs/current-language.md) and [verification/progress](docs/progress.md); [historical checkpoints](docs/legacy/semantics.md) record what each milestone implemented.


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

[Managed arenas](docs/managed-memory.md#retired-arenas), which freed a phase of work's allocations in one
step, were retired in S5: `with arena():` now runs as an ordinary block and warns
`W_ARENA_RETIRED`; `mylang fix` removes them.

[Approximate discovery](docs/experiments/approximate-discovery.md) is available with
`discover-duplicates --approximate`. It reports canonical edits between near matches
and explicitly flags an incomplete search when work or output limits are reached.

[Static quality reports](docs/experiments/quality-reports.md) are available with
`report-quality`. They show resolved calls, reachability from main, binding counts,
and structural metrics with configurable review thresholds. Runtime coverage is
explicitly unmeasured.

[Canonical formatting](docs/experiments/formatter.md) is available with `fmt`
(stdout) and `fmt --check`, which is nonzero when the input differs from the
canonical layout. Formatting preserves token spellings, literal values and
comments, and accepts syntactically valid code without requiring completed type
checking.

[Project verification](docs/experiments/verification-driver.md) is a Python
workflow runner for this repository's own `verify.json` manifest
(`python3 scripts/verify.py verify.json`), not part of the compiler: nothing a
mylang user builds, runs or tests goes through it. Filters select explicit steps
and their dependencies; reports distinguish selected success from full-manifest
success.

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
records, unions, results and enum templates, preserving argument
identity, ownership and typed host contracts.
`examples/nominal-instances.my` returns `16`.
[Symbolic nominal bodies](docs/experiments/nominal-bodies.md) now check `Box<T>`
fields, variant payloads, result propagation and ownership before calls,
then specialize the discovered concrete types.
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
zig-out/bin/mylang index-project examples/modules/main.my
zig-out/bin/mylang context examples/modules/main.my --symbol=shared.units::Distance.make
zig-out/bin/mylang tests-for examples/modules/main.my shared.units::Distance.make
```

Indexes carry source/compiler receipts, and failed bodies expose unchecked
partial declarations.
[Larger-project measurements](docs/experiments/large-project-checking.md) justified
retaining 256 parsed modules within the existing memory budget. Per-function
checked-body reuse, symbolic-template reuse, concrete-specialization reuse and
receipt-first native-test selection are now implemented with conservative
fallbacks; see [the caches guide](docs/tooling/caches.md) and
[guest tests](docs/tooling/guest-tests.md).

Module header discovery is available with `zig build run -- list-modules examples/modules/main.my`.
It reports bounded import graphs and cycles. `list-interfaces` on the same entry
parses module bodies and checks explicit exports and signature visibility; full body checking/execution is available through `check-project`/`run-project`. See [module discovery](docs/experiments/module-discovery.md)
and [module interfaces](docs/experiments/module-interfaces.md).

`zig build run -- run-project examples/modules/main.my` now returns 12 through a
shared domain factory. `check-project` validates all imported bodies with nominal
types, private boundaries, ownership, and effects. See
[module execution](docs/experiments/module-execution.md) for scope and remaining work.

A discovered entry-anchored `mylang.json` makes its import policy required for
ordinary `check`, `build`, `run`, project variants and native-test preparation
before any cached success; `check-policy <entry.my> --policy=<rules.json>` remains
available for explicit inspection and exits 3 for a separate policy failure. See
[import policy](docs/tooling/import-policy.md).

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

`eval-project`, which ran a project entry point in the compiler's own process,
was removed on 2026-09-14 along with the interpreter it needed; so were its
evaluation reports and its persistent evaluation cache. Run a program with
`mylang run`, which builds it natively and executes it. Checked schemas and exact
successful-check caching are implemented below; per-function checked-body,
symbolic-template and concrete-specialization reuse run by default through the
shared semantic cache.

`input-module` validates [typed JSON input manifests](docs/experiments/input-manifests.md)
and emits ordinary exported functions. The example at `examples/input-values/`
evaluates to 64. `schema-project --inputs=examples/input-values/inputs.json`
supplies the declared module in memory, checking it in place of the file on disk
without writing one.

Repeat `--inputs` for multiple declared modules (up to 16 manifests and 8 MiB combined).
Conflicting module bindings reject; flag order does not change the rendered schema.

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

Ordinary typed values have a bounded JSON representation derived from the checked
declarations. It supports integer/boolean values, records, arrays, enum tables,
enums, unions, and results. Duplicate/unknown keys and invalid values reject;
opaque types require future explicit codecs. The `check-value-project` command
that validated a standalone value document was removed on 2026-09-14; the
representation is now reached through `schema-project` and through
`mylang test --cases`, which carries a test's arguments and expected result in it.
See [typed JSON boundaries](docs/typed-json.md) and the
[wire contract, limits, and remaining integration](docs/experiments/typed-json.md).

Standalone Python *data* bindings were generated by `scripts/bindings.py` before
the `invoke-project` removal; the generator and its runtime were dropped with that
command, and the checked schema still carries the contracts they used. See the
[Python bindings design record](docs/experiments/python-bindings.md) for the
historical format.

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

[Direct C imports](docs/c-ffi.md) support `extern def` scalar calls with repeatable
`--link FILE.c` on `build`, `run` and `test`.
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
records those contracts while preserving opaque backing. See
[the example](examples/domain-codecs/main.my) and inspect the contracts with:

```sh
zig-out/bin/mylang schema-project examples/domain-codecs/main.my
```

The commands that executed a declared codec — `check-value-project` and
`invoke-project` — were removed on 2026-09-14 with the interpreter they ran on,
and so were the generated Python call wrappers built over `invoke-project`.
Declared codec contracts are still checked and still rendered in the schema.
Standalone Python *data* bindings remain independent of the compiler and are
described above.

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
`check`, `clear`, or `quit` lines on stdin; each reply reports status, syntax
reuse, successful-verdict reuse and per-function checked-body reuse as JSON.
Exact successful snapshots skip semantic checking and replay their warnings; a
changed snapshot reuses unchanged checked bodies through the shared semantic
cache and rechecks the rest. Files and `--inputs` manifests are loaded afresh on
every check. See [persistent checking sessions](docs/experiments/check-session.md).

Automatic project watching is not part of the folded toolchain. The former
`scripts/watch.py` driver was dropped; `mylang check-session` remains the
persistent checking interface and `mylang test --filter` reuses cached results.

Native builds support `--report` for what the caches served (`cache-report-v1`).
A failed build preserves the last executable.

When a program is not fast enough, the [performance page](docs/performance.md) is
the front door: what ordinary managed code costs, that `mylang build` and
`mylang run` make a debug build by default and `--release` the optimized one, how to raise the `--max-steps` and
`--max-frames` budgets each trap now names, why a fixed `[N]T` belongs on the wire
rather than in a hot loop, and how to measure with `--timings`, `--report` and the
system timer.

The [owner/generic maintenance calibration](docs/experiments/direct-agent-maintenance-20260907.md) records two fresh agents completing three sequential stages each, with preserved command and grading evidence. It establishes feasibility on small tasks, not a language productivity advantage.
