# Run-time counters

`mylang cost` counts *sites*: what emitted code may do. A build with `--counters`
records executions of emitted operations and instrumented runtime helpers. Use
[Juice, the performance proxy](juice.md) for repeatable optimized instruction
comparisons; keep semantic counters separate from ordinary executable timings.

On this development revision, checked ownership is selected with
`--experimental-zero-rc`. The examples below select it explicitly. Default
promotion and retirement of the experimental selectors are separate changes;
these examples do not claim either has happened.

```bash
mylang build program.my -o program-counted --release --experimental-zero-rc --counters
MYLANG_COUNTERS=program-counts.json ./program-counted input.txt
mylang run program.my --experimental-zero-rc --counters  # writes mylang-counters.json
```

`--counters` works with `build`, `build --run` and `run`. Counts go to
`MYLANG_COUNTERS`, or `mylang-counters.json` in the guest's working directory.
Normal shutdown and reported traps write the document; forced termination does
not guarantee one. Guest output, exit status and trap reports retain their usual
meaning. A failed counts-file write produces a diagnostic on the standard streams.

Instrumentation changes execution and optimization. Use a separate build without
`--counters` for wall time, RSS and hardware performance counters. Without the
flag, counting hooks and their thread-local tables are not linked; this does not
promise identical executable bytes across different compiler revisions.

## Document and attribution

The format is `mylang-counters-v1`:

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
| `runtime_retains`, `runtime_releases` | Legacy runtime memory-reference-count updates; zero for checked ownership |
| `shared_retains`, `shared_releases` | Legacy shared memory-reference-count updates; zero for checked ownership |
| `share_marks`, `share_bytes` | Legacy shared-block publication events and allocated bytes marked; zero for checked ownership |

Explicit `.copy()` creates independent storage. Checked ownership has no COW
sharing: copy counters measure explicit copies and any copies introduced by
lowering/runtime helpers. Historical RC documents can include COW copies too.
A copy count alone does not identify an avoidable copy; inspect its source and
ownership contract. Allocation, growth and copy counters describe different
operations and can overlap; do not add all their byte columns as a single metric.

## Site kinds and direct destruction

| Kind | `count` | `bytes` | `extra` |
|---|---|---|---|
| `retain` | Legacy inline memory-count increments | Data bytes of the shared block, not bytes actually copied | |
| `release` | Legacy inline memory-count decrements | | |
| `release_unique` | Direct destruction of uniquely owned storage, including a transferred box's empty shell | | |
| `unique_test` | Legacy `is_unique` tests | | Tests that found the block unique |
| `list_copy`, `dict_copy`, `buffer_copy`, `text_copy` | Runtime copies attributed to this emitted site | Bytes copied | |
| `record_copy` | Emitted `memcpy`/`memmove` of a record, union or array over four words | Bytes copied | |
| `list_push` | List pushes | Element bytes written | Bytes moved by growth attributed to the push |
| `element_load`, `element_store` | Whole aggregates of four words or less read/written in a list | Element bytes | |
| `bounds_check` | Emitted list/text/byte index, pop or substring checks | | |
| `overflow_check` | Emitted integer overflow checks, including negation and `MIN // -1` | | |
| `division_check` | Emitted zero-divisor checks | | |
| `shift_check` | Emitted shift-amount checks | | |
| `other_check` | Other emitted conditional traps: casts, float conversions, missing keys, fact verification and similar checks | | |

`release_unique` is **not an RC event**. It can be positive in a correct zero-RC
run. Core IR also spells its cleanup operation `release`; with checked ownership
that operation emits direct `myl_core_drop_owned` cleanup. A textual search for
`release` cannot distinguish direct destruction from an RC decrement. Task
pending-work counters and the instrumentation's event counters are not memory
reference counts either.

For a checked run, inspect `kinds.retain.count`, `kinds.release.count` and
`kinds.unique_test.count`, plus `totals.runtime_retains`, `runtime_releases`,
`shared_retains`, `shared_releases`, `share_marks` and `share_bytes`: all must be
zero. Preserve the schema fields rather than treating missing data as zero.
Zero events only describe executed paths; establish the selected ABI separately
from emitted LLVM, runtime layout/preprocessing and linked symbols. Normal exit
with `live_bytes_at_exit == 0` is useful cleanup evidence, not a complete ownership
soundness proof. A fatal trap can retain live blocks because it ends the process.

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
mylang build program.my -o program --release --experimental-zero-rc
perf stat -e instructions:u -x, ./program input.txt > /dev/null
mylang build program.my -o program-counted --release --experimental-zero-rc --counters
MYLANG_COUNTERS=counts.json ./program-counted input.txt > /dev/null
```

For example, `kinds.bounds_check.count` divided by the ordinary build's retired
instructions is a ratio of semantic check executions to optimized instructions.
It is not the fraction of machine instructions implementing bounds checks.

## Counts beside the static cost

`mylang cost ENTRY.my --counters FILE.json` appends per-function dynamic rows to
the [static cost report](cost.md). Match source, compiler and ownership/optimization
mode to the counted run. The reader accepts historical v1 documents; it does not
prove that a file came from the current source or compiler.

```bash
mylang build program.my -o program-counted --release --experimental-zero-rc --counters
MYLANG_COUNTERS=counts.json ./program-counted
mylang cost program.my --experimental-zero-rc --counters counts.json
mylang cost program.my --experimental-zero-rc --counters counts.json --json
```

The current cost summary combines `release` and `release_unique` into its
`releases` field (`run.rc.releases` in JSON). That historical label therefore
includes direct drops and **must not be used as an RC-event total**. Its `runtime`
field combines runtime retains/releases and does not include all shared-event
fields. Use the raw v1 fields listed above for an RC audit. Summary allocation
bytes cover `alloc_bytes`, with `realloc` traffic separately available in raw
counters. The text also lists checks by kind; JSON has a `checks` object beside
`run`.

## Comparing historical reports

The 12 October 2026 closeout corrected list-copy instrumentation for recursive,
descriptor-driven owned copies. Those paths bypass the ordinary list-copy helper;
list payload traffic is now counted without charging recursive box shells as list
copies or counting the ordinary helper twice. An increased list-copy total across
that change can be a telemetry correction, even when allocation/free bytes and
managed peak are unchanged. See the [before/after counter evidence](../../experiments/memory-closeout-20261012/A09/raw/counters/README.md).

Keep original reports tied to their compiler/source hashes and mode. Do not
reinterpret old RC events as direct drops, relabel old binaries as a new default,
or infer RSS improvements from their managed-byte columns. The v1 legacy RC
fields remain useful for reading historical documents and as explicit zero-event
columns in checked runs.
