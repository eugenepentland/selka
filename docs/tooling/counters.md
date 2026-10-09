# Run-time counters

For repeatable before/after comparisons with optimized machine instruction
counts, short workload scenarios and source explanations, use
[Juice, the performance proxy](juice.md). It keeps these semantic counters
separate from measurements of the ordinary optimized executable.

`selka cost` counts *sites*: what the emitted code may do. A counting build
counts what a run actually does. `--counters` on `selka build`, `build --run`
or `run` emits a counter at every count update, uniqueness test, copy, list
push and check (bounds, overflow, division, shift and other conditional traps)
the core emits, charges every allocation, free, growth and runtime copy to
the emitted function that was running, and makes the program write the counts
as JSON when it exits — or when a trap ends it.

```bash
selka build program.selka -o program --release --counters
SELKA_COUNTERS=program-counts.json ./program input.txt
selka run program.selka --counters        # writes selka-counters.json
```

The counts go to the path in `SELKA_COUNTERS`, else to `selka-counters.json`
in the program's working directory. The program's own output, exit status and
trap reports are those of the ordinary build; it writes to its standard streams
only if the counts file cannot be written. A counting build runs slower and its
timings mean nothing. Without `--counters`, the emitted LLVM, the runtime object
and the executable are byte for byte what they were before counting existed.

## The document

One `selka-counters-v1` object:

| Field | Meaning |
|---|---|
| `totals` | Program-wide sums of every function counter below, plus `peak_live_bytes` and `live_bytes_at_exit` (bytes in managed blocks, by allocation class) |
| `kinds` | Per site kind, the sums of `count`, `bytes` and `extra` over every site |
| `functions` | One row per emitted function (Core name, specializations separate) that did anything; `<outside>` holds what ran outside every emitted function |
| `sites` | One row per site that executed: `function` (the emitted function), `origin` (the source function, which an inlined body keeps), `path`, `line`, `column`, `kind`, `detail` (the Core operation that emitted it), `count`, `bytes`, `extra` |

Function counters, charged to the emitted function running when the runtime did
the work:

| Counter | Meaning |
|---|---|
| `calls` | Calls of the function |
| `allocs`, `alloc_bytes`, `frees`, `free_bytes` | Managed blocks, by their allocation class's size (a large block by its usable size) |
| `list_grows`, `list_grow_bytes` | Small lists moved to the next size class, and the element bytes copied |
| `reallocs`, `realloc_added_bytes`, `realloc_moves`, `realloc_moved_bytes` | Large lists grown with `realloc`; of those, the ones whose block moved and the bytes in use when it moved (an upper bound: the C library may move pages without copying them) |
| `list_copies`, `dict_copies`, `buffer_copies`, `text_copies` and their `_bytes` | Copy-on-write and value copies the runtime made: list elements, dictionary entries plus their hashes, buffer bytes, text bytes (`str_from_view`) |
| `runtime_retains`, `runtime_releases` | Count updates the runtime made itself: a copy's children, a freed block's children, out-of-line releases |
| `dict_grows`, `buffer_grows`, `text_grows` and their `_bytes` | Growth that copied the old contents |
| `text_appends`, `text_append_bytes`, `buffer_pushes`, `buffer_appends`, `buffer_append_bytes` | Out-of-line text appends, byte pushes and byte appends (`append_range`, number spellings) |

Site kinds:

| Kind | `count` | `bytes` | `extra` |
|---|---|---|---|
| `retain` | Inline count increments of one block: each makes a second owner of a value that stays live | Data bytes of the shared block (elements times stride, text length, entries times key and value size, a box's value): what a copy would move instead | |
| `release` | Inline count decrements of one block | | |
| `release_unique` | Frees of a block ownership proved unique | | |
| `unique_test` | `is_unique` tests | | Tests that found the block unique |
| `list_copy`, `dict_copy`, `buffer_copy`, `text_copy` | Copies made for this Core instruction | Bytes copied | |
| `record_copy` | `memcpy`/`memmove` of a record, union or array over four words | Bytes copied | |
| `list_push` | Pushes into a list | Element bytes written | Bytes the growths this push caused moved (a small list's copy into the next class, a large list's bytes in use when `realloc` moved it) |
| `element_load`, `element_store` | Whole aggregates of four words or less read from or written into a list | Element bytes | |
| `bounds_check` | Executions of a list, text or byte index check, a pop's empty-list or index check, or a substring's bounds check | | |
| `overflow_check` | Executions of an integer overflow check (arithmetic, negation, `MIN // -1`) | | |
| `division_check` | Executions of a zero-divisor check | | |
| `shift_check` | Executions of a shift-amount check | | |
| `other_check` | Executions of any other conditional trap: casts, float conversions, missing keys, fact verification (`--verify-facts`), … | | |

A `record_copy`'s detail names the operation: `list_get` (an element copied out),
`list_set` (a value copied into an element), `list_set.old` (the old element
copied out to release its fields), `record_set` (a copy made before a field
store), `ret` (a return through `sret`), `jump`/`branch` (a value moved into a
phi's slot), and so on.

The counts are of the core's emitted operations, before LLVM optimizes them: a
copy LLVM later removes is still counted, and nothing LLVM adds is. Dictionary
side tables, text scratch and other `malloc`s outside managed blocks are not in
the memory counters.

A check site counts how often the emitted code reached that check. A check the
core's own passes removed (a fact proved the index in range, say) is never
emitted and never counted. A check LLVM removes or hoists later is still counted
at every execution, so the check counts are an upper bound on the checks the
optimized program runs. The counter's own load and store in a loop also keep
LLVM from hoisting the check, which is one more reason a counting build's timing
means nothing. Checks inside runtime functions (a text search, a byte-buffer
range test in C) are not counted.

### Per instruction retired

The counters are executions of the counting build, and a counting build runs
more instructions than the ordinary one. To state them per instruction, count
the ordinary build's instructions with `perf stat` and divide:

```bash
selka build program.selka -o program --release
perf stat -e instructions:u -x, ./program > /dev/null
selka build program.selka -o program-counted --release --counters
SELKA_COUNTERS=counts.json ./program-counted > /dev/null
```

`kinds.bounds_check.count` ÷ instructions is then the bounds checks per
instruction the program reached, and likewise for `retain`, `release`,
`unique_test` and the other check kinds.

## Counts beside the static cost

`selka cost ENTRY.selka --counters FILE.json` prints the ordinary
[cost report](cost.md) and then one line per reported function with what the run
in `FILE.json` did there: calls, inline retains and releases, the runtime's own
count updates, uniqueness tests and how many found the block shared, copies and
the bytes they moved, the bytes growth moved, managed allocations, and the checks
it executed by kind (`checks: bounds N, overflow N, division N, shift N, other
N`; a `checks` object beside each row's `run` with `--json`). Build the counting
run from the same source and mode as the report.

```bash
selka build program.selka -o program --release --counters
SELKA_COUNTERS=counts.json ./program
selka cost program.selka --counters counts.json
selka cost program.selka --counters counts.json --json   # `counters` after the static members
```
