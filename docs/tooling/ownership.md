# Ownership

Checked ownership is the only memory model. Managed assignments move,
ordinary parameters borrow, `mut` parameters borrow exclusively, and `copy(value)`
creates independent storage. The checker rejects use after a move, overlapping
mutation, invalidated views and escaping resources before native code runs.
See [value semantics](../value-semantics.md).

## What the pass decides

- **Moves and borrows.** Stores and owned returns transfer their source owner.
  Read-only calls borrow, so the caller can keep using the value after the call.
  Managed values include lists, dictionaries, sets, text, bytes, byte buffers and
  aggregates containing them. Immortal literals need no heap destruction.
- **Cleanup.** The compiler destroys owned storage after its last use on each
  path, including early return and checked error propagation. Owned children
  are destroyed with their parent. Borrowed storage is never freed by a borrower.
- **Copies.** Explicit `copy(value)` duplicates owned storage. Optimized builds can
  remove a copy when the result can take ownership of a dead source. The program's
  independent values stay unchanged.
- **Stack storage.** Bounded, nonescaping temporary lists with unmanaged elements
  can use stack storage. The compiler proves that direct helper calls only read
  or forward the list, without retaining it beyond the call. Element storage is
  limited to 4 KiB per list and promoted lists to 8 KiB per function. Lists with
  unproved bounds or escape behavior retain managed storage.

Collection growth and explicit copies can still allocate. `@noalloc` is checked
on ownership-expanded Core before optimization and fails builds with
`E_NOALLOC_ALLOCATES` when a site may allocate. Plain `check` validates source
ownership; `build` also checks lowering, allocation contracts and runtime support.
An unsupported shape is diagnosed without a reference-counting fallback.

## Seeing it

`selka build --stats` reports static ownership and optimization decisions.
`selka cost FILE.selka --json` reports per-function sites, `selka dump-ir FILE.selka`
prints Core IR, and `--emit-llvm PATH` saves the emitted native-code input.
These describe emitted functions, including functions later inlined; they do
not count executions. Use [runtime counters](counters.md) for executed work.

```selka
# doc: expect 21
func fill(n: int) -> int[]:
    mut output: int[] = []
    for index in range(n):
        append(mut output, index * index)
    return output

func main() -> int:
    const squares = fill(10)
    mut copied = copy(squares)
    append(mut copied, 1)
    return len(squares) + len(copied)
```

```bash
selka build fill.selka -o fill --release --stats
selka cost fill.selka --json
selka dump-ir fill.selka
```

The copy keeps `squares` independently usable after `copied` changes. The
parameter-dependent allocation in `fill` does not satisfy a fixed stack bound.

## Checked ownership commands

Plain `build`, `run`, `run-project`, `check`, `check-project`, `check-module`,
`check-session`, `dump-ir`, `test` and `doctest` use checked ownership. Persistent
checks validate ownership after cached source checks; directory test workers and
property trials use the same contract. Source and native cache identities bind
the ownership semantics and runtime ABI. Development builds can reuse unchanged
module units; release builds emit one whole-program LLVM unit.

`--experimental-zero-rc` and `--experimental-single-owner` are rejected with
exit status 2 because reference counting was removed. Arguments after
`--` belong to the guest program and are preserved.

Optional providers such as `Clock?` can be borrowed through read-only parameters.
Pass `None`, an existing optional parameter or `Some(clock)` directly to a call.
Keep providers outside returned application state and thread them through calls
that need them. Text and byte views borrow a named owner; the checker keeps that
owner alive and rejects invalidating it while a view remains in use.

## Retired

Reference counting, copy-on-write, `.snapshot()` and the hybrid single-owner
mode were retired on 17 October 2026. Checked ownership is the only model. The old back end's ownership
analysis, `--explain-ownership`, counting RC runtime selectors and tracing
collector remain retired. Historical experiment commands and measurements retain
their original meaning.
