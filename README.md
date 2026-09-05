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
are currently limited to 16 MiB; excessive expression nesting is diagnosed.

## Current implementation

M0 through M2 are implemented: owned source buffers, source locations, lexer,
parser, separate untyped/typed representations, per-function instructions,
an iterative expression VM with typed locals, deterministic dumps, binding diagnostics, and actual-CLI tests.

The accepted subset is one `fn main() -> i64` with local bindings, assignment,
nested blocks, and explicit returns. It supports integer and boolean values,
optional local type annotations, unary `-` and `!`, binary `+`, `-`, `*`,
comparisons, parentheses, whitespace, and `//` comments. Active shadowing,
use outside scope, mutation of immutable bindings, and type mismatches are
rejected. Unused bindings and unnecessary `mut` produce advisory warnings.
Arithmetic traps on overflow in every host optimization mode; checking does
not evaluate arithmetic. `examples/locals.my` returns `21`.

Division/remainder, discard, branches, loops, and helper calls are the next MVP
milestones; they are not implemented yet. Ownership, modules, native guest
code, and the later quality contracts remain post-MVP experiments.

See [implemented semantics](docs/semantics.md) and [verification/progress](docs/progress.md).
