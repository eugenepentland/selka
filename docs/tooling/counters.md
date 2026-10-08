# Run-time counters

`mylang cost` counts *sites*: what the emitted code may do. A counting build
counts what a run actually does. `--counters` on `mylang build`, `build --run`
or `run` emits a counter at every count update, uniqueness test, copy and list
push the core emits, charges every allocation, free, growth and runtime copy to
the emitted function that was running, and makes the program write the counts
as JSON when it exits — or when a trap ends it.

```bash
mylang build program.my -o program --release --counters
MYLANG_COUNTERS=program-counts.json ./program input.txt
mylang run program.my --counters        # writes mylang-counters.json
```

The counts go to the path in `MYLANG_COUNTERS`, else to `mylang-counters.json`
in the program's working directory. The program's own output, exit status and
trap reports are those of the ordinary build; it writes to its standard streams
only if the counts file cannot be written. A counting build runs slower and its
timings mean nothing. Without `--counters`, the emitted LLVM, the runtime object
and the executable are byte for byte what they were before counting existed.

## The document

One `mylang-counters-v1` object:

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
| `text_appends`, `text_append_bytes`, `buffer_pushes` | Out-of-line text appends and byte pushes |

Site kinds:

| Kind | `count` | `bytes` | `extra` |
|---|---|---|---|
| `retain`, `release` | Inline count updates of one block | | |
| `release_unique` | Frees of a block ownership proved unique | | |
| `unique_test` | `is_unique` tests | | Tests that found the block unique |
| `list_copy`, `dict_copy`, `buffer_copy`, `text_copy` | Copies made for this Core instruction | Bytes copied | |
| `record_copy` | `memcpy`/`memmove` of a record, union or array over four words | Bytes copied | |
| `list_push` | Pushes into a heap list | Element bytes written | |
| `element_load`, `element_store` | Whole aggregates of four words or less read from or written into a list | Element bytes | |

A `record_copy`'s detail names the operation: `list_get` (an element copied out),
`list_set` (a value copied into an element), `list_set.old` (the old element
copied out to release its fields), `record_set` (a copy made before a field
store), `ret` (a return through `sret`), `jump`/`branch` (a value moved into a
phi's slot), and so on.

The counts are of the core's emitted operations, before LLVM optimizes them: a
copy LLVM later removes is still counted, and nothing LLVM adds is. Dictionary
side tables, text scratch and other `malloc`s outside managed blocks are not in
the memory counters.
