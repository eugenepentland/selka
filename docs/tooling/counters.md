# Run-time counters

`selka cost` counts *sites*: what emitted code may do. A build with `--counters`
records executions of emitted operations and instrumented runtime helpers. Use
[Juice, the performance proxy](juice.md) for repeatable optimized instruction
comparisons; keep semantic counters separate from ordinary executable timings.

Checked ownership is the only model. Ordinary commands below use moves, borrows,
explicit copies and direct destruction.

```bash
selka build program.selka -o program-counted --release --counters
SELKA_COUNTERS=program-counts.json ./program-counted input.txt
selka run program.selka --counters  # writes selka-counters.json
```

`--counters` works with `build`, `build --run` and `run`. Counts go to
`SELKA_COUNTERS`, or `selka-counters.json` in the guest's working directory.
Normal shutdown and reported traps write the document; forced termination does
not guarantee one. Guest output, exit status and trap reports retain their usual
meaning. A failed counts-file write produces a diagnostic on the standard streams.

Instrumentation changes execution and optimization. Use a separate build without
`--counters` for wall time, RSS and hardware performance counters. Without the
flag, counting hooks and their thread-local tables are not linked; this does not
promise identical executable bytes across different compiler revisions.

## Document and attribution

The format is `selka-counters-v1`:

| Field | Meaning |
|---|---|
| `totals` | Sums of function counters, plus `peak_live_bytes` and `live_bytes_at_exit` for instrumented managed blocks |
| `kinds` | Sums of `count`, `bytes` and `extra` over each emitted site kind |
| `functions` | Emitted functions that did work, with specializations separate; `<outside>` holds runtime work outside an emitted function |
| `sites` | Executed sites: emitted `function`, source `origin` retained through inlining, `path`, `line`, `column`, `kind`, Core-operation `detail`, `count`, `bytes`, `extra` |

Function counters charge runtime work to the emitted function running when it
happens. Worker threads accumulate local counters; the report combines them.
The managed live-byte and peak counters track the combined live blocks.

| Counter | Meaning |
|---|---|
| `calls` | Function calls |
| `allocs`, `alloc_bytes`, `frees`, `free_bytes` | Managed block allocation/free events and allocation-class bytes; large blocks use allocator-reported usable size |
| `list_grows`, `list_grow_bytes` | Small-list growth into a new block and element bytes copied |
| `reallocs`, `realloc_added_bytes`, `realloc_moves`, `realloc_moved_bytes` | Large list/buffer growth through `realloc`, positive usable-byte increase, address changes, and occupied bytes when the block moves (including its header) |
| `list_copies`, `dict_copies`, `buffer_copies`, `text_copies` and their `_bytes` | Instrumented runtime copy events and payload traffic: list elements, dictionary entries plus hashes, buffer/byte payloads and text bytes |
| `dict_grows`, `buffer_grows`, `text_grows` and their `_bytes` | Growth events that copy old contents, and copied bytes |
| `text_appends`, `text_append_bytes`, `buffer_pushes`, `buffer_appends`, `buffer_append_bytes` | Instrumented out-of-line text appends, byte pushes and byte appends |
| `blocks` | Executed basic blocks of emitted program functions: one count per entry of every emitted block, so work done in selka code (an index scan, a loop that moves no other counter) is visible. The entry block counts once per call, so a function that only runs its prologue and returns counts one block per call |
| `element_moves`, `element_move_bytes` | Whole elements shifted inside the list by the runtime helper behind a native `insert`, `remove` or `pop(index)`: `insert` moves the elements at and after the insertion point, `remove`/`pop(index)` moves the elements after the removed one and the last element into the hole, so both move `len - index` elements of the site's `count`, `stride` bytes each. Whole-list copies are `list_copy`, not element moves |
| `sort_compares` | Element comparisons the runtime's stable sort made: every comparison of the comparison sort (`i64`, `u64`, `f64`, `bool`, `str`, `bytes`, narrower integers, including its natural-run scan, insertion extension and merge), the integer insertion fallback used for at most 32 elements, and the keyed decorated sort's comparison of keys. An integer list sorted above 32 elements by the stable distribution path compares no elements |
| `elements_sorted` | The elements one sort operation processes, counted at its entry by the list's length: the plain `list.sort()`/`sorted(...)` site by the receiver's length and the keyed sort sites by the source list's length. Every path counts, so an integer list sorted above 256 elements by the radix distribution reports its elements here with `sort_compares` 0, and re-sorting a list in a loop adds its length each time |

The managed block events counted as `allocs` are also what the `testing` module
measures: `testing.allocations(work, n)` reads one counter over one workload, and
the runtime updates it only while that measurement is active
([how work grows](guest-tests.md#how-work-grows)). The event, and the flag it
reads, exist only in the runtime variant that a program linking a `testing`
counter reader compiles: an ordinary program's allocation path is unchanged, and
the flag read costs three instructions per managed allocation only in a program
that opted into the module. A block reused from a thread's list free list by the
inline list fast path is not an `allocs` event in either reading.

Explicit `copy(value)` creates independent storage. Checked ownership has no COW
sharing: copy counters measure explicit copies and any copies introduced by
lowering/runtime helpers. Historical RC documents can include COW copies too.
A copy count alone does not identify an avoidable copy; inspect its source and
ownership contract. Allocation, growth and copy counters describe different
operations and can overlap; do not add all their byte columns as a single metric.

## Site kinds and direct destruction

| Kind | `count` | `bytes` | `extra` |
|---|---|---|---|
| `list_copy`, `dict_copy`, `buffer_copy`, `text_copy` | Runtime copies attributed to this emitted site | Bytes copied | |
| `record_copy` | Emitted `memcpy`/`memmove` of a record, union or array over four words | Bytes copied | |
| `list_push` | List pushes | Element bytes written | Bytes moved by growth attributed to the push |
| `element_load`, `element_store` | Whole aggregates of four words or less read/written in a list | Element bytes | |
| `bounds_check` | Emitted list/text/byte index, pop or substring checks | | |
| `overflow_check` | Emitted integer overflow checks, including negation and `MIN // -1` | | |
| `division_check` | Emitted zero-divisor checks | | |
| `shift_check` | Emitted shift-amount checks | | |
| `other_check` | Other emitted conditional traps: casts, float conversions, missing keys, fact verification and similar checks | | |
| `blocks` | Entries of this emitted block, one site per block, charged to its source function | | |
| `element_moves` | Elements one native `insert`/`remove`/`pop(index)` shifted, at the site of the operation | Element bytes shifted | |
| `sort_compares` | Element comparisons of one stable sort, plain or keyed, at the site of the sort operation | | |
| `elements_sorted` | Elements one sort processed, at the site of the sort operation | | |

A `blocks` site is at its block's first instruction (the function's span for an
empty block) with detail `block`, and each block entry adds one to both the
site's `count` and its emitted function's `blocks` total. Blocks are counted
before LLVM optimization, one per block the emitter writes: loop headers, bodies,
latches and exits, but not the cold trap blocks an individual check creates. An
`element_moves` site is at the `insert`/`remove`/`pop(index)` operation with
detail `list_rotate`. A `sort_compares` site is at the sort operation, with
detail `list_sort`, `sort_keyed` or `sort_keyed_record`, and its `count` is that
sort's comparisons. An `elements_sorted` site is at the same sort operation with
the same detail, and its `count` is the length the sort started from: the
emitter reads it before the call, so the runtime's choice of algorithm cannot
hide a sort. A 300-element integer list sorted twice therefore has 600
`elements_sorted` and 0 `sort_compares`, because the runtime distributes those
integers by radix instead of comparing them.

Only the runtime rotation behind the native list `insert`, `remove` and
`pop(index)` is counted as element moves. `list.reverse` swaps pairs without a
rotation, and the guest-code shift loops of the standard library's
`lists.insert` and `lists.pop_at` copy elements with `list_get`/`list_set`, so
they move no `element_moves` today; their work shows up in `blocks` (and in
their copies) until wave 2's compiler-side list homes give those helpers the
native path.

The Core IR cleanup operation is `drop`. It directly destroys owned storage and
has no reference-count event kind. Runtime `frees` and `free_bytes` measure
managed destruction; static `selka cost` reports `ownership.drops` sites and
`ownership.stack_lists` promotions. Task pending-work counts and instrumentation
event counts are separate from the retired memory reference counts.

Normal exit with `live_bytes_at_exit == 0` is useful cleanup evidence. A fatal
trap can retain live blocks because it ends the process. Establish the runtime
ABI from emitted LLVM, layout and linked symbols as well as executed counters.

A `record_copy`'s detail identifies the operation: `list_get` (element extraction),
`list_set` (element storage), `list_set.old` (old storage copied for cleanup),
`record_set` (copy before a field store), `ret` (return through `sret`), or
`jump`/`branch` (transfer into a phi's slot), for example. These operations can copy
unmanaged stack data without allocating a managed block.

Site counts describe emitted operations before LLVM optimization: a copy LLVM
removes is still counted, and a copy LLVM introduces is not. Checks removed by
Core facts are neither emitted nor counted. Instrumentation can prevent LLVM
from removing or hoisting a check, so the recorded executions are not an exact
instruction count for the uninstrumented guest. Internal runtime checks such as
a C byte-buffer range check are not emitted check sites.

## Traffic, live memory and RSS

`alloc_bytes` is cumulative allocation traffic, not maximum residency. Large
`realloc` growth is recorded separately in `realloc_added_bytes`; report both,
or explicitly label a derived sum. `free_bytes` is the accumulated freed block
size. `peak_live_bytes` is the maximum simultaneous accounted managed storage;
`live_bytes_at_exit` is the final accounted amount. A difference between two
peaks is not allocation traffic or cumulative bytes saved.

Managed block sizes include the block header, rounded class/usable size and
spare capacity. They exclude allocator chunks or free-list storage retained after
blocks are freed, dictionary side tables, text scratch, provider buffers, task
stacks, counting tables and other native allocations. Thus lower managed traffic
or peak does not establish lower process RSS. A `realloc` address change also
only estimates copying: the allocator or OS can move pages without copying bytes.

Measure uninstrumented guest wall time and process RSS separately with identical
inputs, worker counts, affinity and compiler/guest modes. Record exact source and
binary hashes, warmups and all samples. For compilation, distinguish a largest
child's RSS high-water mark from simultaneous process-tree memory; a sampled tree
can miss short-lived children, and shared pages may be counted more than once.
State which metric the measurement tool actually reports.

## Per instruction retired

Use the same compiler, mode and inputs for the counted and ordinary binaries:

```bash
selka build program.selka -o program --release
perf stat -e instructions:u -x, ./program input.txt > /dev/null
selka build program.selka -o program-counted --release --counters
SELKA_COUNTERS=counts.json ./program-counted input.txt > /dev/null
```

For example, `kinds.bounds_check.count` divided by the ordinary build's retired
instructions is a ratio of semantic check executions to optimized instructions.
It is not the fraction of machine instructions implementing bounds checks.

## Counts beside the static cost

`selka cost ENTRY.selka --counters FILE.json` appends per-function dynamic rows to
the [static cost report](cost.md). Match source, compiler and ownership/optimization
mode to the counted run. The reader accepts historical v1 documents; it does not
prove that a file came from the current source or compiler.

```bash
selka build program.selka -o program-counted --release --counters
SELKA_COUNTERS=counts.json ./program-counted
selka cost program.selka --counters counts.json
selka cost program.selka --counters counts.json --json
```

The current cost summary reports calls, copies, growth, allocations and checks.
It has no `rc` or uniqueness-counter summary. Summary allocation bytes cover
`alloc_bytes`, with `realloc` traffic separately available in raw counters.
The text lists checks by kind; JSON has a `checks` object beside `run`.

## Comparing historical reports

The 12 October 2026 closeout corrected list-copy instrumentation for recursive,
descriptor-driven owned copies. Those paths bypass the ordinary list-copy helper;
list payload traffic is now counted without charging recursive box shells as list
copies or counting the ordinary helper twice. An increased list-copy total across
that change can be a telemetry correction, even when allocation/free bytes and
managed peak are unchanged. See the [before/after counter evidence](../../experiments/memory-closeout-20261012/A09/raw/counters/README.md).

Reference counting was removed on 17 October 2026. New runtime reports omit the
former `runtime_retains`, `runtime_releases`, `shared_retains`, `shared_releases`,
`share_marks` and `share_bytes` totals, and the `retain`, `release`,
`release_unique` and `unique_test` site kinds. Allocation/free counters remain.
The historical `release_unique` site counted direct destruction, not an RC
update; the historical cost `run.rc.releases` summary combined both kinds.

Keep original reports tied to their compiler/source hashes and mode. Do not
reinterpret old RC events as direct drops, relabel old binaries as the new
model, or infer RSS improvements from managed-byte columns. Old v1 documents
remain historical evidence; their obsolete fields are not emitted by the
current runtime.
