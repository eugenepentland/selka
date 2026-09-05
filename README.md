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
All 133 tests pass in Debug and ReleaseFast.

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
Borrowing and slices are in progress: a [memory/lease backend](docs/experiments/borrowing.md)
is tested, while guest syntax, static checking, and VM integration remain pending. Approximate
matching, borrowing, ownership, effects, modules, native execution, and the other
pending tracks are not yet complete.

See [implemented semantics](docs/semantics.md) and [verification/progress](docs/progress.md).
