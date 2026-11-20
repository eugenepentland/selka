# Canonical syntax implementation — 2026-09-21

This implements the seven changes identified in
[the syntax and performance audit](canonical-syntax-performance-2026-09-21.md).
The intended rule is that ordinary source expressions select the efficient
implementation; callers do not need a special helper spelling to avoid a copy.

| Operation | Canonical source | Implementation |
| --- | --- | --- |
| Sort in place | `values.sort()` | Stable bottom-up native merge sort, `O(n log n)` time and `O(n)` scratch. |
| Sorted copy | `sorted(values)` | Copy once, then use the same native sort; concrete standard-library wrappers delegate. |
| Parse floating text | `float(text)` | `strings.to_float` delegates to the same parser, including whitespace, underscores and special values. |
| Parse a byte range | `raw[start:end].parse_int()` / `.parse_float()` | Immediate immutable slices and views lower to the existing range parser before effect checking. |
| Format text | `f"x={x}; y={y}!"` | Render holes once in source order and join the pieces once; a single piece returns its rendered text directly. |
| Text extrema | `min(words)` / `max(words)` | Compare stored Unicode scalar values directly, without temporary encodings. |
| Build a known-size list | `[f(x) for x in values]`, `list(range(n))` | Reserve the unfiltered result capacity; filtered comprehensions retain incremental growth. |
| Traverse a dictionary | `mapping.keys()`, `.values()`, `.items()` | Live typed views, with the same meaning when bound or passed to another function. |
| Snapshot a dictionary projection | `list(mapping.items())` | Independent shallow list; items contain `key` and `value` fields. |

## Source changes

Dictionary projection methods now return `DictKeys[K, V]`, `DictValues[K, V]`
and `DictItems[K, V]` respectively. An item is a `DictItem[K, V]` value record.
`for key, value in items` works for both a retained items view and its snapshot.
Use `list(mapping.keys())[index]` where the previous code indexed a projection,
and `list(mapping.values())` where it expected a values snapshot.

Views retain their mapping and observe subsequent value changes. Changing the
mapping's size during iteration traps, matching direct dictionary iteration.
Creating or iterating a view needs no managed allocation; making a snapshot does.
Values and items read entries directly by position, avoiding the dictionary's
linear key search and keeping traversal and snapshot creation linear.

Float sorting now places NaNs after ordered numbers. Equal values, including
signed zeros, retain their input order. This replaces the previous inconsistent
treatment of NaNs as tied with every value.

## Deliberate limits

Compatibility wrappers remain accepted. The changes consolidate their
implementations rather than remove every alternative public spelling.
`sort.sort_by_key` retains its recursive merge because replacing it with the
prelude's bottom-up merge changes callback evaluation and trap order. Keyed
`sorted` keeps its existing comparison order and now reuses one scratch list.

The native sort's scratch buffer uses C allocation, outside the managed heap's
`noalloc` effect accounting, and remains subject to the process memory ceiling.
Formatting can still allocate rendered scalar/aggregate holes and a temporary
piece list; the one-allocation claim concerns the final joined string.
Retained byte intermediates and mutable byte-buffer slices keep their existing
semantics and allocation behavior. Preallocation can report an allocation
failure earlier than incremental list growth.

The audit's original sources, IR and evidence are preserved in
[`experiments/syntax-canonicalization-20260921`](../../experiments/syntax-canonicalization-20260921/).
Follow-up evidence records compiler identity and generated calls; it is not a
claim that every workload has a measured wall-clock speedup.

## Captured evidence

The [follow-up results](../../experiments/syntax-canonicalization-20260921/after/RESULTS.md)
contain 29 accepted probes and one expected removed-spelling rejection. The
multi-piece f-string changes from four concatenation sites to one join; immediate
byte slices/views contain no slice/view call; text extrema contain no encoding
call; stored dictionary views contain no list construction.

The [LLVM test record](../../experiments/syntax-canonicalization-20260921/after/llvm-tests.json)
records 19 passing guest tests across dictionary views, sorting, byte parsing,
comprehensions and formatting, with LLVM `-O3` and GC stress enabled.

## Validation

Using the repository's pinned Zig toolchain:

- `zig build -j2 --summary all`: 22/22 steps succeeded; all 88 Guardian checks passed.
- `zig build test -j6 --summary all`: 70/70 steps succeeded; 1,509 Zig tests passed
  (the runner's 15,465 skips are the other shards' tests). Language tests reported
  22 executed passes plus 213 cached passes, with no failures across 67 programs.
  Documentation coverage and executable examples passed.
- `zig build test-qbe test-qbe-build -j4 --summary all`: 48/48 steps succeeded,
  including golden parity after migrating the two implicit-snapshot fixtures.
- `zig build fmt-check` and `git diff --check`: passed.
- Imported generic views with managed list values passed their focused regression
  under GC stress, as did arena confinement and explicit escape tests.

Existing source callers and runnable documentation that needed snapshots now
request `list(...)` explicitly. The existing `byte_ranges_llvm.my` probe was also
given a module header and guest-test entry so the directory suite could run it.
