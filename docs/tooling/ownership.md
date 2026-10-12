# Ownership

Collections and records are values ([value semantics](../value-semantics.md)): an
assignment, an argument, a store or a return behaves as if it copied. The compiler
makes that cheap with one-count reference counting and copy-on-write, planned per
function by the new core's ownership pass (`src/core/own.zig`). It runs in every
build, debug and release, after the release facts when there are any, and it never
refuses a program: what it cannot prove it answers the conservative way.

## What the pass decides

- **Moves and borrows.** Every managed value (a list, dictionary, set, string, byte
  buffer, or a record or enum holding one) is owned, borrowed or immortal. Ordinary
  parameters normally borrow their arguments; `mut` parameters take ownership and
  return their final values. Optimized builds can also infer that an ordinary list
  parameter takes one owner, as described below. The last use of an owned value
  that consumes it (a store, a return, an update) moves it; any other consuming use
  takes a `retain` first. A value that dies without a consuming last use is released
  where it dies, on every path, including early returns and `try` propagation.
- **Copy-on-write.** Each in-place update of a list (`append`, an element write,
  `pop`) takes one of three forms: in place with no test when the list is provably
  unique (fresh from a constructor, a copy or another update, and never shared);
  in place after a uniqueness test when it is owned but may be shared; or on a copy
  when it is borrowed or used again after the update.
- **Cleanup.** A `retain x … release x` pair in one block with only reads between
  them is dropped.
- **Stack storage.** Optimized builds can keep bounded temporary lists on the
  stack, including across direct internal helper calls. The compiler must prove
  that each helper only reads the list or forwards it to another proven reader,
  without retaining, returning, storing or mutating it. This proof needs no
  annotations and works even when the helper is not inlined. Lists with managed
  children, unknown bounds or unproved uses keep ordinary managed storage.
  Element storage is limited to 4 KiB per list; promoted lists together use at
  most 8 KiB per function, including headers and alignment. This limit covers
  promoted lists, not other stack storage.
- **Caller storage for constructors.** A small function that creates and returns
  a bounded list can be inlined into its caller before the storage decision.
  Ordinary `values = make_values(n)` syntax can therefore construct directly in
  the caller's stack frame. The initial policy accepts one fresh list with
  unmanaged elements, ordinary unmanaged arguments, one return, no calls, and a
  straight fill or a recognized counted loop. It limits each constructor to
  100 body instructions, 128 instruction slots and 20 blocks, and adds at most
  256 instructions to a caller. The same list and frame budgets apply. Escaping
  results and snapshots kept across mutation retain managed storage. This is
  bounded constructor inlining; opaque or uninlined builders do not gain a hidden
  destination-passing ABI.
- **Repeated list replacement.** In an expression such as
  `values = append_batch(values, n)`, the compiler can pass the old list's owner
  to an ordinary helper that updates and returns it. If the caller still needs
  the old value, it retains an owner first, so snapshots and repeated arguments
  remain independent. The callee still checks uniqueness before reusing a shared
  block. This initial inference applies to internal leaf helpers returning an
  unmanaged-element list through updates, aliases and phis, with at most 4096
  instructions. It excludes `mut` parameters, calls, recursion, explicit counting,
  the entry point, and any module whose type catalog contains a function value
  type, including callbacks. No new source annotation is needed: the inferred
  consuming convention is separate from `mut` and does not write back to the
  caller's variable except through the ordinary returned value.

Whether a copy happened never changes what a program prints: only how much it
allocates. A release build built with `--verify-facts` checks optimization
assumptions at run time, including unique ownership before untested heap updates
and available capacity before pushes into stack lists.

## Seeing it

`mylang build --stats` prints what the passes did, the ownership plan included:
updates in place without a test, updates behind a uniqueness test, updates on a
copy, retains and releases emitted, pairs elided, and lists placed on the stack.
These are static compiler decisions across emitted functions, including functions
whose calls were all inlined. They are not counts of operations executed by a run.

Save this program as `fill.my`:

```mylang
# doc: expect 21
func fill(n: int) -> int[]:
    mut out: int[] = []
    for i in range(n):
        out.append(i * i)
    return out


func main() -> int:
    const squares = fill(10)
    mut copy = squares
    copy.append(1)
    return len(squares) + len(copy)
```

```console
$ mylang build fill.my -o fill --release --stats
mylang-core: inlined 0 calls, unswitched 0 loops, versioned 0 loops, proved 5 checks, vectorized 0 loops
mylang-core: ownership: 1 updates in place, 0 tested, 1 copied; 0 retains, 2 releases (0 pairs elided); 0 lists on the stack
mylang-core: cost: 0 checks kept; 4 allocation sites (0 unresolved calls); 1 unknown loops
```

Measured on 2026-10-10; the final LLVM remarks and compilation-timing line is omitted.

`copy.append(1)` is the update on a copy: `squares` is read after it. `fill` has a
parameter-dependent bound, so it does not qualify for the bounded constructor
inlining policy. `mylang cost FILE.my --json` reports static counts per function;
`mylang dump-ir FILE.my` prints the Core IR before the passes and
`--emit-llvm PATH` saves the emitted code with its reference-count operations,
copies and stack allocations.

## Experimental zero RC

`--experimental-zero-rc` selects source moves, explicit copies, checked borrows
and direct destruction. It applies to `build`, `run`, `run-project`, `check`,
`check-project`, `check-module`, `check-session`, `dump-ir`, `test` and `doctest`.
Persistent checks validate each request, including after cached checks. Documentation
examples pass the selection into both checking and execution. Tests use the same checked source ownership rules, including
directory workers and property trials. Local, shared and indexed-property test
receipts distinguish ownership modes; an ordinary RC success cannot satisfy a
zero-RC request. `check` validates source ownership,
while `build` also checks backend and runtime support. Unsupported operations
fail compilation without an RC fallback. See the
[supported features and measurements](../../experiments/zero-rc-final-20261011/README.md).

The runtime ABI is separate from ordinary RC builds: `kind` is at offset zero,
there is no count member, and emitted LLVM starts with `mylang-zero-rc-v2`.
Lowering, optimization and emission cache identities include ownership mode.
Native cache identities include the runtime ABI. Ownership checking stays eager;
zero-RC builds do not use deferred source/body loading. Release builds still
emit one whole-program LLVM unit, while development builds can reuse emitted
module units. `--report` distinguishes whole-build replay from stage reuse.

`--counters` and `MYLANG_COUNTERS` report managed allocations and direct frees
separately from RC. Removing RC does not imply zero heap allocations or reduced
process RSS; raw provider buffers, task stacks and other native storage are
outside the managed-block counters.

## Retired

The old back end's ownership analysis read its bytecode and is gone with it, and so
are its reports: `--explain-ownership` (refused; use `--stats`), the counting RC
runtimes `--rc-runtime=stats` and `--rc-runtime=sites` with `MYLANG_RC_COUNTS` and
`MYLANG_RC_SITES`, and the tracing collector they were compared against.
