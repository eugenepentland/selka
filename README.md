# mylang

An experimental statically checked, interpreted language implemented in Zig.
The custom bytecode VM is the primary runtime while we develop the language's
semantics and test whether agents can write and repair correct code more reliably.
The implementation follows [the revision 3 plan](docs/plan.md) and
[interpreter-first roadmap](docs/experiments/interpreter-first.md). The working
language name and `.my` extension are provisional.

Next priorities are generic arena/reset lifetimes, diagnostic repair quality,
typed host-library calls, and a board-validation or constraint-processing trial.
Expensive geometry can remain in Zig/C/Rust behind explicit typed wrappers.
Completed C/native experiments remain available; further native compilation,
LLVM, and direct x86_64 Linux work are deferred until the design and measurements
justify them. Native feature descriptions below record the existing experiments.

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

## Build and use

```sh
zig build
zig build run -- run examples/arithmetic.my
zig-out/bin/mylang check examples/arithmetic.my
zig-out/bin/mylang dump-bytecode examples/arithmetic.my
zig build test --summary all
zig build test -Doptimize=ReleaseFast --summary all
zig build fmt-check
```

`zig build test` runs checker/VM, actual CLI, and interpreter/tooling integration
acceptance. `zig build test-interpreter` is an explicit alias. Both retain all
core tests, including inexpensive C-emission checks, without compiling guest C.
CI uses this default suite in Debug and ReleaseFast.

Native compilation/parity integration remains available on demand:

```sh
zig build test-native --summary all
zig build test-all --summary all
```

`test-native` runs the native drivers and the corpus with native execution;
`test-all` combines both suites. Guardian gates each acceptance route. Native
testing compiles guest C in its documented modes; `-Doptimize` selects the host
compiler/VM mode. Use a disk-backed `TMPDIR` with sufficient space for large native
runs. The default corpus driver needs only `--compiler`; direct native corpus
runs also require `--native --zig /path/to/zig`.

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
`src/root_test.zig` is the unit test root, and `test/integration.zig` contains the
actual CLI tests. Python acceptance drivers remain in `tests/`. There are no
frozen violations or accepted violation baselines. Guardian's local telemetry
cache is ignored.

## Current implementation

The scalar MVP (M0–M5) is implemented and audited: owned source buffers, source locations, lexer,
parser, separate untyped/typed representations, per-function instructions,
an iterative VM with typed locals, jumps, and explicit call frames, deterministic dumps, binding diagnostics, and actual-CLI tests.

The accepted subset has one `fn main() -> i64` and typed helper functions, with
local bindings, assignment,
nested blocks, branches, loops, explicit discard, and explicit returns. It supports integer and boolean values,
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
1003. Closed enums/tagged unions and exhaustive matching are also implemented
([variant semantics](docs/experiments/variants.md)); `examples/variants.my` returns
24. Complete enum-indexed tables finish A2
([table semantics](docs/experiments/tables.md)); `examples/tables.my` returns 1407.
Borrowing and slices are implemented: a [memory/lease backend](docs/experiments/borrowing.md)
and scoped source references are implemented, including static access checking and VM
cleanup. `examples/references.my` returns 23. Shared/exclusive reference parameters
also work; `examples/reference-parameters.my` returns 19. [Bounded slices](docs/experiments/slices.md),
slice parameters, and checked narrowing are implemented; `examples/slices.my` returns 13.
[Returned-reference contracts](docs/experiments/returned-references.md) complete B
([acceptance audit](docs/experiments/b-audit.md)); `examples/returned-references.my` returns 20.
Resource/capability operations and modules have subsequent implemented milestones
below. Broader native interfaces, generic contracts, and other pending roadmap work
are not yet complete.

See [implemented semantics](docs/semantics.md) and [verification/progress](docs/progress.md).


[Typed recoverable results](docs/experiments/results.md) now carry handling
obligations through bindings, helpers, and wrappers. Exhaustive matches, returns,
and explicit `acknowledge` handle them; ordinary discard and silent overwrite are
rejected. `examples/results.my` returns 7. [Explicit `try` propagation](docs/experiments/propagation.md)
checks early-return obligations and cleans up active borrows; `examples/propagation.my`
returns 20. C/D remain in progress.

The [owned-buffer backend](docs/experiments/ownership.md) now supports consuming
transfers, reserved-capacity edits, growth limits, and partial-acquisition cleanup.
[Source acquisition and moves](docs/experiments/owned-buffers.md) now support buffer
results, owned wrappers, and lexical/early-return cleanup; `examples/buffers.my`
returns 21. [Buffer operations and views](docs/experiments/buffer-operations.md) now
include checked mutations, queries, slices, and returned-view helpers;
`examples/buffer-views.my` returns 19. [Transitive effect bounds](docs/experiments/effects.md)
now reject direct or indirect guest allocation under `noalloc`; `examples/effects.my`
returns 14. [Explicit allocator capabilities](docs/experiments/allocator-capabilities.md)
now flow from the entry point through helper parameters; acquisition and reserve
require them. `examples/allocator-capabilities.my` returns 3.
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

[Non-consuming field reads](docs/experiments/owned-field-reads.md) now let completion
handlers inspect error codes before transferring or retrying the owned resource.
[Partial field moves](docs/experiments/partial-fields.md) are now implemented.

[Bounded environment lookup](docs/experiments/environment.md) now uses explicit
entry grants and injected providers, preserving missing/empty distinctions and
rejecting oversized values without truncation.

[Resource reads/writes](docs/experiments/resource-io.md) now expose bounded byte
snapshots, explicit EOF, and actual write counts while retaining ownership. Borrowed slice
I/O is described below; operating-system adapters remain separate work.

[Resource permission attenuation](docs/experiments/attenuation.md) now lets helpers
receive reduced read/write/complete authority. Acquisition receives those permissions,
and copies cannot restore removed rights or increase the shared quota.

[Borrowed resource slice I/O](docs/experiments/resource-slices.md) now reads into
existing array/buffer ranges and writes exact populated ranges while enforcing
exclusive destinations, lifetime checks, and snapshot preservation.

[Typed-handle pool backend](docs/experiments/typed-pools.md) now supports nominal
ID categories, stale-handle rejection, cyclic graphs, slot reuse, retained snapshots,
and bulk clearing. [Source pools](docs/experiments/source-pools.md) now expose these
operations with allocator authority and quotas; [checked region backing](docs/experiments/region-backing.md)
also supports arena-backed pool registries.

[Arena backing and checked region reset](docs/experiments/arenas.md) now separate
buffer backing from retained snapshots, reject live borrows before reset, and reuse
backing/registries across cycles. [Source arena scopes](docs/experiments/source-arenas.md) are implemented.

[Execution-lifetime arena selection](docs/experiments/arena-execution.md) now runs
existing source programs with `run --memory=arena` or embedding option
`memory_backing = .arena`. General allocation remains the default. Explicit [source arena scopes](docs/experiments/source-arenas.md)
now reclaim backing at lexical boundaries; execution-lifetime arena backing can
accumulate until execution ends.
Pool registries now follow this selection; retained node snapshots use the parent allocator.

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

[Scalar native execution](docs/experiments/native-execution.md) is available with
`emit-c` and `python3 scripts/native.py examples/sum.my -o /tmp/native-sum`.
The pinned Zig compiles direct C branches and explicit frames. The backend now
covers all current bytecode operations, including aggregates, borrowing and
resources, with VM/native parity and allocation-failure acceptance.

[Native embedding](docs/experiments/native-embedding.md) builds a shared library
with `python3 scripts/native.py examples/sum.my --library -o /tmp/libsum.so`.
A C host supplies providers and budgets and receives a scalar result or bounded
diagnostic through `mylang_native_run_v1`; calls return without printing or exiting.
Module libraries also support [exported scalar calls](docs/experiments/native-calls.md)
by qualified name through `mylang_native_call_v1`, with checked integer/Boolean
arguments and full-width results. [Native aggregate calls](docs/experiments/native-wire.md)
copy ordinary record, array and variant trees through caller-owned buffers.
Generated Python wrappers also accept a [schema-pinned NativeClient](docs/experiments/native-bindings.md),
which calls a matching shared library without a compiler subprocess, including
declared domain codecs with typed decoder rejection errors. Source programs can
also use [declared codec operations](docs/experiments/source-codecs.md) to convert
between domain values and their typed wire representations.

[Partial record field moves](docs/experiments/partial-fields.md) use
`take_field(owner, field)` to transfer individual fields immediately while preserving
access to the remainder and enforcing result obligations and branch consistency.

Source [pools and nominal handles](docs/experiments/source-pools.md) now support
cyclic graphs, snapshot reads, checked IDs, and shared execution quotas. Run
`zig build run -- run examples/pools.my` for the graph fixture (result `52`).
Source arena scopes and pure generic specialization are implemented.
[Concrete generic records and arrays](docs/experiments/generic-concrete.md) now
support fixed data schemas alongside symbolic parameters; broader generic
contracts remain pending. [Generic aggregate updates](docs/experiments/generic-updates.md)
preserve record, array and enum-table snapshots.
[Generic enum/union construction and matching](docs/experiments/generic-variants.md)
now retain exact payload types and exhaustive cases.
[Concrete generic results](docs/experiments/generic-results.md) now enforce transfers,
acknowledgement, propagation and obligations across control-flow paths.
[Generic partial fields](docs/experiments/generic-fields.md) now track remaining
result obligations and reject mismatched field moves across those paths.
[Concrete owned generic values](docs/experiments/generic-owned.md) now preserve
transfers, implicit cleanup and transitive resource cleanup effects.
[Generic buffer/pool operations](docs/experiments/generic-runtime.md) now check
explicit allocator authority, mutation contracts and allocation effects.
[Generic provider operations](docs/experiments/generic-providers.md) now retain
capability, result, permission and effect contracts.
[Generic local views](docs/experiments/generic-local-views.md) now support concrete
array/buffer ranges and slices returned from declared whole-array inputs, with
ownership/access checks before instantiation. The VM example
`examples/generic-local-views.my` returns `22`.

[Lexical arenas](docs/experiments/source-arenas.md) use `arena heap as scratch { ... }`
with conservative escape checks and cleanup across returns/errors.
`zig build run -- run examples/arenas.my` returns `50`.

[Typed arena reset](docs/experiments/arena-reset.md) reclaims unused chunks inside
a scope while preserving its allocator. `zig build run -- run examples/arena-reset.my`
returns `3` after exercising guarded reset and reuse.

Module header discovery is available with `zig build run -- list-modules examples/modules/main.my`.
It reports bounded import graphs and cycles. `list-interfaces` on the same entry
parses module bodies and checks explicit exports and signature visibility; full body checking/execution is available through `check-project`/`run-project`. See [module discovery](docs/experiments/module-discovery.md)
and [module interfaces](docs/experiments/module-interfaces.md).

`zig build run -- run-project examples/modules/main.my` now returns 12 through a
shared domain factory. `check-project` validates all imported bodies with nominal
types, private boundaries, ownership, borrowing, and effects. See
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

Scalar module projects support `emit-project-c` and `scripts/native.py --project`.
Try the [module-native example](docs/experiments/module-native.md); resource
operations still require broader native implementation.

Native code now supports [nominal scalar domains](docs/experiments/native-domains.md),
including `examples/modules/domain_main.my` (12), while preserving checked private
construction and explicit accessors. Native resources remain pending.

Native [closed enums](docs/experiments/native-enums.md) now support construction,
equality, calls, mutation, and exhaustive matches in single-file and module programs.
Try `examples/native-enums.my` with the native builder.

`eval-project` provides [restricted evaluation](docs/experiments/restricted-evaluation.md)
for effect-free, parameter-free project entry points, with explicit step, frame,
and VM-memory budgets. This is the compile-time evaluator foundation; schema
generation and finer incremental compilation remain pending.

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
qualified identities, field/variant structure, integer bounds, borrowing contracts,
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

Native [packed unions and results](docs/experiments/native-variants.md) support
nested scalar payloads, matching, transfers, acknowledgement, and propagation
within a 127-bit layout. [Native aggregates](docs/experiments/native-aggregates.md)
add records, arrays, tables, conversions/updates, and boxed variants beyond this
limit. [Native borrowing and slices](docs/experiments/native-references.md) now support
scoped loans, parameters, returned views, and snapshot-preserving writes.
[Native owned buffers](docs/experiments/native-buffers.md) add root allocators,
mutation, growth, and borrowed views with VM/native and cleanup acceptance.
[Native lexical arenas](docs/experiments/native-arenas.md)
now support chunk backing, checked reset, and scope/return cleanup.
[Native pools](docs/experiments/native-pools.md) add generation-checked handles,
snapshots, operations, and shared quotas on root/arena storage.
[Native clock/random providers](docs/experiments/native-providers.md) use explicit
C adapters selected with the native builder’s `--provider` option.
[Native environment lookup](docs/experiments/native-environment.md) extends that
interface with bounded bytes, missing/empty distinctions, and independent snapshots.
[Native resource lifecycle providers](docs/experiments/native-resources.md) add
filesystem/network acquisition, retryable completion, and ownership cleanup.
Native array/slice resource I/O now supports partial transfers, EOF, snapshots,
and failure cleanup through explicit provider adapters.

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

Native builds support `--report` for emission/C build timings and publication
status. Failed builds preserve the last executable; byte-identical successful
builds preserve its timestamp. See [native publication](docs/experiments/native-build-publication.md).
