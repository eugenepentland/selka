# The dictionary stops being an association list — 2026-09-21

**Headline.** `dict` lookup, write, `in`, `setdefault` and `update` were linear in
the entry count: `find` walked the whole insertion-ordered entry list comparing
keys one at a time. They are now expected constant time through an
open-addressing hash index built over that same entry list. On the audit's own
`dict_scaling` probe (300,000 read-modify-writes) the QBE arm goes from 1,509 ms
to 20 ms at 1,000 distinct keys and from 17.9 s to 34 ms at 10,000; the
matched `dict_count` micro-kernel falls from **605× Zig's `StringHashMap` to
5.6×** on QBE and from **384× to 3.2×** on LLVM O3 + LTO, a 109× and 122×
improvement in one interleaved batch. Nothing observable changed:
insertion order, snapshots, `keys`/`values`/`items`, printing, structural
equality, `pop`, `update`, `clear`, `copy` and the arena escape path all answer
exactly as before, byte for byte, on every benchmark arm.

This closes defect 1 of three in
[the parity audit](performance-parity-audit-2026-09-21.md) §3.

## What changed

`src/native_dictionary.c` still stores entries in one insertion-ordered
`myl_native_list`, so every consumer that reads `entries` — `native_print.c`,
`native_equal.c`, the snapshot and `key_at`/`value_at` primitives, the generated
code in `qbe_managed.zig` — is untouched. Beside it the dictionary now carries an
index:

- **Table.** Open addressing with linear probing, power-of-two capacity, load
  factor at most 5/8. A slot holds one past an entry index, so zero means empty.
  `find` probes from the masked hash and compares with exactly the predicate it
  used before; when the table is absent it falls back to the old scan, so the
  slow path is still a correct path.
- **Hash.** FNV-1a over precisely the units equality compares — a `str` key's
  Unicode scalars read from the `myl_native_text` scalar array, any other key's
  `key->size` bytes, which is what `memcmp` already compared — followed by one
  fixed avalanche so the low bits the table masks depend on the whole key. Fixed
  constants, no seed: Guardian forbids RNG and a wall clock in `src/`, and a
  dictionary has to behave identically on every run anyway.
- **Storage and lifetime.** The table is an untraced managed block
  (`MYL_NATIVE_PLAIN` elements, so the collector never walks its contents)
  allocated through `myl_native_heap_alloc_at` at
  `myl_native_object_region(heap, dict)` — the dictionary's *own* region, the
  same rule `myl_native_list_append` uses for grown backing — and reached through
  a second traced pointer field of the dictionary's record descriptor. So the
  collector marks it whenever the dictionary is live, an arena releases the two
  together, and its bytes are charged to the memory budget like every other
  allocation. A refused table drops the index and leaves the dictionary
  scanning rather than failing the write, and restores the heap's sticky
  `exhausted` flag so a later trap still names the real cause.
- **`pop` is the exception.** Removing an entry shifts every later entry down, so
  every stored slot number past it is wrong. `pop` refills the existing table in
  place, which needs no allocation — that is what lets `pop` keep its
  heap-free signature — and leaves `pop` linear in the entry count. This is
  documented in the header and in `[PY-DICT-2]`.
- **Arena escape.** `fill_dictionary` in `src/native_regions.c` still appends
  straight onto the clone's entry list. It must: the copier allocates every clone
  shallow and fills them afterwards, so a cloned `str` key is an empty shell
  while the dictionary is being filled and key equality and key hashes are not
  yet meaningful. A first attempt that routed those appends through
  `myl_native_dictionary_write` collapsed 799 distinct keys into 3 — one per
  distinct key *length* — because every unfilled clone of a given length compares
  equal. The escape now calls `myl_native_dictionary_reindex` on each cloned
  dictionary after the fill loop, still inside the suspended-collection window.
- **A `calloc` off the write path.** A new-key write staged its entry with
  `calloc`/`free`; entries up to 96 bytes now stage on the stack. The staged
  entry is rooted before anything can allocate, so the key it holds survives a
  collection even when the caller passed the only reference — which matters
  because the index allocation is a new safepoint on that path.

`myl_native_dictionary` grew from 7 to 8 fields. Guardian's type-size rule parses
Zig containers (`file_metrics.zig`), not C structs, and the whole-tree run passes.

## Before and after

Method: `experiments/perf-parity-audit-20260921/probes/bench.py`, fresh process
per round, `taskset -c 8`, randomized interleaved arms, medians of the rounds
after warmups, stdout md5 compared across every arm of a batch (identical in
every batch). Both arms are the same compiler and the same source; only
`src/native_dictionary.{c,h}` and `src/native_regions.c` differ. mylang arms are
`--mode ReleaseFast`; the LLVM arms add `--backend llvm --llvm-opt 3 --lto`.
The machine is shared: the load average at the head of each batch is quoted, and
only within-batch ratios are claimed.

**`dict_scaling.my`** — 300,000 `counts[key] = counts.get(key, 0) + 1` over K
distinct `str` keys. Median ms.

| K | load | rounds | QBE before | QBE after | speed-up | LLVM before | LLVM after | speed-up |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 100 | 3.75 | 11 | 161.9 | **16.7** | 9.7× | 80.4 | **8.8** | 9.1× |
| 1,000 | 3.25 | 11 | 1,508.6 | **20.5** | 73.7× | 860.6 | **11.5** | 74.6× |
| 10,000 | 4.50 | 5 | 17,897.5 | **34.4** | 520× | 10,604.1 | **20.8** | 511× |

The K = 10,000 row's minima (15,344.8 / 30.2 ms on QBE, 9,075.6 / 17.9 ms on
LLVM) give 508× and 506×, so medians and minima agree there. A first pass at that
row taken while another session's gate was active gave 396× and 373× on medians
and 535× and 531× on minima; it is superseded by the numbers above, which come
from the quieter batch.

The shape is the real result. Holding the operation count at 300,000 and moving
K from 100 to 10,000, the QBE *before* time grows 9.3× and then 111× — the
linear search showing through, since the work per operation is what grows. The
*after* time grows 1.2× and then 2.1×, and what is left of that is the string
hashing, the per-key allocation of `"key" + str(i)` and cache misses over a
larger table, not search.

**`micro/dict_count.my`** — 2,000,000 read-modify-writes over 1,000 `str` keys
plus a final pass, against the Zig `StringHashMap` comparator built with
`zig build-exe dict_count.zig -O ReleaseFast` from inside the micro directory.
Five arms in one interleaved batch, 7 rounds after 2 warmups, load 4.60 at the
head; medians, with minima in brackets.

| arm | ms | × Zig | improvement |
|---|---:|---:|---:|
| Zig ReleaseFast `StringHashMap` | 27.45 [24.85] | 1.00 | |
| QBE before | 16,596.4 [15,513.8] | 605× | |
| QBE after | **152.2** [150.9] | **5.55×** | **109×** |
| LLVM O3 + LTO before | 10,542.6 [8,602.8] | 384× | |
| LLVM O3 + LTO after | **86.5** [79.7] | **3.15×** | **122×** |

The before arms reproduce the parity audit's published 591× and 329× for this
kernel within the spread of a shared machine, so the two batches agree on the
baseline. Read on the minima instead, the improvements are 103× and 108×. An
earlier batch of the same five binaries, run at load 9.13, gave 584× / 5.98× /
316× / 3.49× — the same conclusion from a noisier sample. The kernel now sits in
the same band as the other collection kernels of the parity audit's micro suite
(`list_append_sum` 3.3×, `alloc_churn` 3.9×, `str_build` 3.8× on the same arm)
rather than three orders of magnitude off.

**The `docs/performance.md` row.** That page's "20,000 `dict[str, int]` writes …
80 ms" row does not record how many distinct keys it used, so it cannot be rerun
as written; a reconstruction with 1,000 distinct keys has a peak RSS of 12.4 MB
against the row's 2.2 MB, which is enough to say it is not the same program. The
reconstruction *was* measured on both sides, and that is a matched pair: the
before arm is a compiler built from this worktree with only
`src/native_dictionary.{c,h}` and `src/native_regions.c` checked out from
`base/defects-20260921`, so nothing else differs. Nine interleaved rounds after
two warmups, load 12.5, stdout discarded, `taskset -c 8`: **134.5 ms median /
127.1 ms minimum before, 3.62 ms / 2.95 ms after**. The page now carries that
pair as a dated note instead of a rewritten row, because the rest of its table
was measured on an older tree too and rewriting one row would make it
inconsistent.

What remains between 3.2× and Zig is not search: it is the `str` representation
(four bytes per scalar, so hashing "key123" reads 24 bytes), one managed
allocation per `"key" + str(i)`, and the per-call frame protocol — the items the
parity audit ranks 2, 3 and 4. Those are out of scope here.

## Tests

- `tests/lang/dictionary_hash_index.my`, six `public def test_*` programs, run by
  `zig build test-lang` which passes `--gc-stress` to every guest program. Tagged
  `# spec: PY-DICT-2` (primary) and `# spec-case: PY-DICT-2`. They cover 4,000
  string keys read, overwritten, present and absent; insertion order through
  growth and across three pops including a reinsert that must append at the end;
  `setdefault`, `update`, `clear` then reuse, and `copy` independence at 900
  entries; content equality of two 400-entry dictionaries built in opposite
  orders, and inequality after one value changes and after a pop; 3,000 `i64`
  keys including negatives plus a `u8`-keyed dictionary covering the whole key
  space; and an 800-entry dictionary built, popped and read inside
  `with arena():` then escaped, read again and appended to after the arena is
  gone.
- `tests/native_text_dictionary_test.c`, run by `scripts/test_native_memory.py`
  under `-fsanitize=undefined -Werror`. `index_sound` asserts the table
  invariants directly — power-of-two capacity, load factor at most 5/8, every
  live slot naming a live entry, no entry named twice, none left unnamed — after
  4,096 growing writes and again after a pop. Two `i64` keys are *searched out*
  to share one home slot in a table deliberately left at capacity 8, so linear
  probing, the probe-past-a-collision read, and `pop`'s rebuild are exercised on
  a real collision rather than on luck. A 16-byte padded key stands in for a
  record key (the checker rejects record keys with `E_DICT_KEY`, so this shape
  is only reachable from C). A heap with a 32 KiB budget exercises the refusal
  path: writes eventually fail, and every key the dictionary did accept still
  reads back.
- `SPEC.md` gains `- [PY-DICT-2]`.

## Gate

Run on `fix/dict-hash`, on a machine also running other sessions' gates: once
before this report was written and again with it in place, since the report adds
no source and no fenced example. All four steps passed both times; the second
run's numbers are below.

| step | result |
|---|---|
| `zig build test --summary all --maxrss 8000000000` | 70/70 steps succeeded; 1,555/17,152 tests passed (15,597 skipped, the shards' complement); guest `tests/lang` 241 passed / 0 failed across 68 programs under `--gc-stress`, and the doctest root 42 passed / 0 failed across 11; `doc-coverage: 0 failures` over 168 documented features; Guardian 88/88 |
| `zig build test-qbe --summary all` | 48/48 steps succeeded; 206/206 tests passed |
| `zig build test-qbe-build --summary all` | 30/30 steps succeeded |
| `zig build fmt-check` | exit 0 |

`scripts/test_native_memory.py`, which builds every C harness with
`-std=c11 -Wall -Wextra -Werror -fsanitize=undefined`, passes all nine suites.
Each of the four commits on this branch was made through Guardian's pre-commit
hook, which runs the whole-tree gate rather than the diff-scoped one: 88/88 each
time.

## Limits

- **`pop` is still linear**, by construction: entries shift, so the table is
  rebuilt. A loop that pops N keys is O(N²). Only a tombstoning scheme or an
  entry list with holes would fix that, and both change what `entries` means to
  every consumer that reads it today.
- **Dictionary equality is still O(n²).** `dictionary_value` in
  `src/native_equal.c` scans the other dictionary's entries for each entry of the
  first. It was deliberately left alone: the brief required that structural
  equality not depend on index layout, and it does not. Routing it through the
  index would be a separate, easy change.
- **Memory.** The table costs 8 bytes per slot at a load factor of at most 5/8,
  so at most 12.8 bytes per entry on top of the entry itself. The only peak RSS
  taken here is the 1,000-key reconstruction of the `docs/performance.md` row:
  12,320 kB before and 12,424 kB after, a 104 kB difference against a table that
  holds 2,048 slots. No large-dictionary memory figure was taken.
- **The machine was shared throughout.** No batch here ran on a quiet machine:
  load averages of 3.3 to 4.6 at the head of the four benchmark batches, and 12.5
  for the `docs/performance.md` reconstruction, with other sessions' gates
  starting during some of them. The arms of every batch are interleaved so a
  ratio is fair to both sides, medians and minima are both quoted where they
  disagree, and the two independent batches of `dict_count` and of the K = 10,000
  row reach the same conclusion from different samples.
- **The comparison is the runtime only.** Both arms use the same compiler build
  from this worktree; nothing in the frontend, the backends or the guest source
  differs between them.
- **Hash quality is asserted, not measured.** The C harness pins the table
  invariants and one constructed collision; there is no distribution test, and no
  adversarial-key test, which a deterministic unseeded hash cannot pass by
  construction. A guest that chooses to collide can still force the scan-like
  behaviour this change removes for ordinary keys.
