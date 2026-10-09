# Ownership

Collections and records are values ([value semantics](../value-semantics.md)): an
assignment, an argument, a store or a return behaves as if it copied. The compiler
makes that cheap with one-count reference counting and copy-on-write, planned per
function by the new core's ownership pass (`src/core/own.zig`). It runs in every
build, debug and release, after the release facts when there are any, and it never
refuses a program: what it cannot prove it answers the conservative way.

## What the pass decides

- **Moves and borrows.** Every managed value (a list, dictionary, set, string, byte
  buffer, or a record or enum holding one) is owned, borrowed or immortal. A call
  borrows its arguments; the last use of an owned value that consumes it (a store, a
  return, an update) moves it; any other consuming use takes a `retain` first, and a
  value that dies without one is released where it dies, on every path, including
  early returns and `try` propagation.
- **Copy-on-write.** Each in-place update of a list (`append`, an element write,
  `pop`) takes one of three forms: in place with no test when the list is provably
  unique (fresh from a constructor, a copy or another update, and never shared);
  in place after a uniqueness test when it is owned but may be shared; or on a copy
  when it is borrowed or used again after the update.
- **Cleanup.** A `retain x … release x` pair in one block with only reads between
  them is dropped.

Whether a copy happened never changes what a program prints: only how much it
allocates. A release build built with `--verify-facts` asserts at run time that every
list the pass updated in place without a test really was unique.

## Seeing it

`mylang build --stats` prints what the passes did, the ownership plan included:
updates in place without a test, updates behind a uniqueness test, updates on a
copy, retains and releases emitted, pairs elided, and lists placed on the stack.

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
```

`copy.append(1)` is the one update on a copy: `squares` is read after it. For the
counts of one function, put it in a file of its own; `mylang dump-ir FILE.my`
prints the Core IR before the passes and `--emit-llvm PATH` the emitted code with
every `retain`, `release` and copy.

## Retired

The old back end's ownership analysis read its bytecode and is gone with it, and so
are its reports: `--explain-ownership` (refused; use `--stats`), the counting RC
runtimes `--rc-runtime=stats` and `--rc-runtime=sites` with `MYLANG_RC_COUNTS` and
`MYLANG_RC_SITES`, and the tracing collector they were compared against.
