# Ownership

Managed values have one owner. Assigning, inserting or returning an owner can
move it; ordinary parameters borrow, and `mut` parameters borrow exclusively for
the call and write their final values back. Use `.copy()` when two independent
values must remain usable. The compiler checks these rules before lowering and
rejects unsupported ownership shapes. Ownership and lifetime names do not appear
in source syntax.

## Source rules

A list, dictionary, set, string, byte buffer, or record or enum containing one can
own managed storage. A use after a move is an error. Borrowed parameters and
selected managed fields or elements do not become owners because they are used
for the last time; copy them when an independent owner must escape. Copies
recursively duplicate managed children. Resources cannot be copied.

`try` can transfer the successful payload of an owned Result. Matching a fresh
producing expression can transfer its payload, including an immediate whole-field
pattern. Matching a named value, field or index borrows its payload. Arbitrary
partial record moves remain unsupported; explicit copies make independence clear.

Text and byte `.borrow(start, end)` create read-only local ranges without managed
allocation. Their owner must remain valid through their last use. Mutating,
replacing or moving that owner while a view is live, or storing or escaping the
view, is rejected. A view's `.copy()` materializes independent storage.

Mutable children passed together use exclusivity at the root container, including
children selected by different constant indices. Explicitly copying child owners
and writing them back after the call can be a local migration when the callee
cannot observe a root alias. Evaluate each index once and preserve source argument
order. The compiler does not promise general disjoint-path analysis.

Resources stay anchored to a live provider. A dependent returned owner must have
one unambiguous provider input. An owner escaping a local provider or an ambiguous
provider choice is rejected. Early returns and propagated errors still run scoped
cleanup. `parallel.map` borrows inputs and joins before returning an independent,
ordered output; callbacks must copy borrowed input they return as owned data.
Detached tasks, escaping task handles and general captured closures are outside
this contract.

## Storage and cleanup

The compiler schedules direct destruction on all exits and replacements. The
selected guest runtime has no reference-count field or count-based uniqueness
checks. Dynamic allocation, growth, explicit independent copies and direct freeing
remain ordinary operations. A task's pending-work counter is synchronization.

Optimized builds can place bounded temporary unmanaged-element lists on the
stack, including across proven borrowing readers. Current budgets cap each
promoted list at 4 KiB of elements and total promoted storage at 8 KiB per function,
including headers and alignment. These budgets do not bound other stack storage.
Bounded constructor inlining can also construct suitable fresh lists in the
caller. Unknown bounds, managed children or escaping results keep heap storage.

Repeated replacement can reuse a suitable list's storage when its previous owner
is consumed. This optimization does not turn an earlier alias into an independent
snapshot. Preserve a snapshot explicitly with `.copy()` before a consuming use.
Optimization and facts verification preserve the checked source contract in
release, unoptimized debug and optimized debug builds.

## Inspecting a program

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
    mut copy = squares.copy()
    copy.append(1)
    return len(squares) + len(copy)
```

`mylang build fill.my -o fill --release --stats` describes the current compiler's
static allocation and ownership decisions. `mylang cost fill.my --json` reports
static costs per function, `mylang dump-ir fill.my` shows Core IR, and
`mylang build fill.my -o fill --emit-llvm fill.ll` saves emitted LLVM. These reports
are not runtime event counts. A static cleanup site can be reported using an older
`release` label while representing direct destruction rather than counting RC.

Allocation analysis follows the same ownership mode as execution. Borrowed local
views are nonallocating. Independent text encoding, buffer reversal and explicit
`.copy()` may allocate and violate a `noalloc` ceiling. Invalid source ownership
is diagnosed before allocation analysis lowers a helper, including unused helpers.

## Commands, artifacts and package boundary

Ordinary build, run, run-project, check, check-project, check-module, check-session,
lint, dump-ir, cost, coverage, test and doctest commands select checked ownership.
Persistent checks validate each request. Tests apply the same source rules to
properties, providers and directory workers. Cached successes cannot bypass
ownership checking. `check` validates source contracts; a native build also
qualifies backend and runtime support. `dump-ir` displays intermediate Core for
diagnosis; its successful output alone does not prove the backend can emit or run
that program. There is no fallback after an ownership error.

Guest LLVM uses the `mylang-zero-rc-v2` ABI marker with `kind` at header offset zero.
Lowering, optimization, emission, native artifacts and test receipts bind their
selected compiler/runtime identities. Old RC artifacts cannot be interpreted as
this ABI. Eager source checking is retained even when safe metadata or compiled
stages are reused.

`--counters` and `MYLANG_COUNTERS` distinguish managed allocations/direct frees
from RC events. Managed peak live bytes differ from cumulative allocation traffic
and process RSS. Provider buffers, task stacks and other native storage can fall
outside managed counters. Removing RC alone proves no particular RSS saving.

The compiler's Zig allocator is separate from guest memory management. The
installed test-index and cache-plan components require their own qualified owned
compiler pin, source and protocol checks. A default guest command change alone
does not prove those installed components RC-free; the closeout report records
the exact package qualification and any remaining boundary. Historical immutable
bootstrap seed inputs remain historical artifacts.
