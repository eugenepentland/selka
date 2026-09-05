# mylang

An experimental systems language compiler and bytecode VM written in Zig.
The implementation follows [the revision 2 plan](docs/plan.md). The working
language name and `.my` extension are provisional.

## Toolchain

Use **Zig `0.17.0-dev.1683+5ceec001b`**, the exact snapshot used by Guardian.
The user selected this snapshot in place of the plan's original preference for
a released toolchain. `.zigversion`, the package manifest, and the build guard
pin the version; CI installs the manifest's version and verifies it exactly.

On the development machine it is installed at:

```sh
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig version
```

The build targets the native host and has no package dependencies. The CLI
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

The example prints `7`. A successful program result is printed to stdout, not
used as the exit code. Success exits 0, source errors and guest traps exit 1,
and usage/I/O/host failures exit 2. Diagnostics go to stderr. Source files
are currently limited to 16 MiB; excessive syntax nesting is diagnosed.

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
The full resource/effect system, modules, full-language native execution, and the other
pending tracks are not yet complete.

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
backing/registries across cycles. Guest arena scopes remain pending.

[Execution-lifetime arena selection](docs/experiments/arena-execution.md) now runs
existing source programs with `run --memory=arena` or embedding option
`memory_backing = .arena`. General allocation remains the default. Nested source
arena scopes remain pending; arena backing can accumulate until execution ends.
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
413 Zig/core-and-CLI tests.

[Scalar native execution](docs/experiments/native-execution.md) is available with
`emit-c` and `python3 scripts/native.py examples/sum.my -o /tmp/native-sum`.
The pinned Zig compiles direct C branches and explicit frames. Native tests execute
23 scalar fixtures across -O0/-O2 with undefined-behavior checks; aggregate/resource/
borrowing operations are explicitly unsupported by this backend.

[Partial record field moves](docs/experiments/partial-fields.md) use
`take_field(owner, field)` to transfer individual fields immediately while preserving
access to the remainder and enforcing result obligations and branch consistency.

Source [pools and nominal handles](docs/experiments/source-pools.md) now support
cyclic graphs, snapshot reads, checked IDs, and shared execution quotas. Run
`zig build run -- run examples/pools.my` for the graph fixture (result `52`).
Source arena scopes and generics remain pending.
