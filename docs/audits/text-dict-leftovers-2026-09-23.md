# Text, bytes and dictionary leftovers — lane report, 2026-09-23

**Headline.** A `str` slice that is only ever used as a dictionary key is no
longer built. `counts[key] = counts.get(key, 0) + 1` with `key = seq[i:i + k]`
now hashes and compares the slice's octets where they already are. It builds an
owned key only when the key is new. Every dictionary write also tries a no-allocation
overwrite first, so writing a key that is already present publishes no GC roots.

- **`knucleotide` goes from about 3.4× Zig to about 1.45× Zig.** The paired
  ratio to the base compiler is 0.43 [0.41, 0.45].
- **`dict_count` goes from 1.20× Zig to 1.08× Zig** (paired 0.90), and
  **`knucleotide_tuned` from 1.42× to 1.35×**.
- **`strings.repeat` and two-octet `bytes.find_any` are now linear.**

`text_ops` does not improve. It is 1–2.5% slower, and the cause is where the
code lands in memory, not the work it does (§5).

- Branch: `perf/text-dict-leftovers` from `base/parity-leftovers` (`160a2d08`).
- Timings: CPU 4 on a **loaded machine**, load average 4–12, with the
  hyperthread sibling (CPU 5) busy for most batches.
- Result JSONs:
  [`results/leftovers/`](../../experiments/perf-parity-plan-20260922/results/leftovers/).

## 1. Allocation-free dictionary keys (`DICT-RANGE-KEY-1`, `-2`)

**Lowering.** The new file `src/qbe_range_keys.zig` plans a function before it
is lowered. A slice is *described* rather than built when the proof below holds
for every instruction involved.

The value is either:

- a `str` slice, or
- a read of a *range local*.

It must flow, by falling through with no branch into the window, to one of:

- the next instruction's `store_local` into a range local; or
- the key operand of a `str`-keyed dictionary operation — `read`, `get`,
  `contains`, `write` or `d[k]` — with at most two constant or local pushes in
  between.

A **range local** is a non-parameter `str` local. Nothing else may name it,
except a `store_local` fed by such a value and a clearing `drop_local`. The set
of range locals is a greatest fixpoint.

Spellings covered:

- `d[s[a:b]]`, `d.get(s[a:b], x)` and `s[a:b] in d`;
- `d[s[a:b]] = v`, `d[s[a:b]] += v` and `d[s[a:b]] = d.get(s[a:b], 0) + 1`;
- the knucleotide shape through a named `key`, and `d[key] += 1`, which the
  front end copies into a hidden temporary.

**Representation.** The operand slot keeps a real managed text: the slice's
*receiver*. A 16-byte span beside it (`%rs{h}` per stack height, `%rl{i}` per
local) holds the octet offset and length. `myl_native_text_range` computes the
span with the slice's own clamping.

Because the slot holds an ordinary text, the following needed no change:

- roots, frame maps and `QBE-ROOTLIVE-1` liveness;
- the receiver's lifetime, which lasts exactly as long as the key could be read.

The runtime has four entry points: `myl_native_dictionary_{read,contains,overwrite,write}_range`.

- They hash the octets in place with the text hash, which is now the inline
  `myl_native_octets_hash`, so a text and a range of the same octets always
  hash equally.
- They compare against stored keys, which are owned.
- An insertion builds one owned key in the dictionary's region
  (`myl_native_text_piece_at`) with its hash already cached.

**Arena programs are excluded.** In a program that opens an arena, a built slice
is an arena object. The store barrier and `end_arena`'s retention scan trap on
that object, and a described slice would not trap. So a program that opens any
arena keeps building its slices, and its traps are unchanged by construction.
`knucleotide_arena` therefore stays at about 3.2×.

**Recording absences (item 4).** A slice lookup that misses records:

- the text it ranges over;
- the span;
- the empty slot the walk ended on;
- the heap's collection count.

The `write` of a read-modify-write then inserts without hashing or walking
again. The record is believed only under three conditions:

1. **No arena is open, and the collection count is unchanged.** A tracing-heap
   text is reclaimed only by a collection, so the recorded address still names
   the same immutable text.
2. **No insertion, table change, `pop`, `clear` or reindex has happened since.**
   Each of these drops the record.
3. **The lookup is for a slice.** A found record for a slice nominates only that
   same (text, offset, length) query. It is then proven by an octet comparison.
   The slice states are separate from the text-object states, so a lookup of the
   whole text never reads a record made for a slice of it.

Nominating by query identity, rather than by content, took a branch that
mispredicts half the time off the read path.

Recording a text *object's* absence stays out of scope. It would need `%heap`
passed into the existing `read`/`contains`. After this change, the fresh-slice
loops that motivated it no longer build text objects.

## 2. Writes link roots only on insert (`DICT-OVERWRITE-1`)

Every dictionary write now lowers to two calls:

1. `myl_native_dictionary_overwrite` (or `_overwrite_range`). It allocates
   nothing and is a pure callee. It replaces a present key's value and returns 1.
2. Only when that returns 0, `myl_native_dictionary_write` inside its own root
   push (`inline_roots`).

A counting loop's writes after each key's first therefore push none of the
root records the dictionary lane measured around every write. A miss is
recorded exactly as a lookup's, so the insert after it does not walk the table
again. This change, not the slice keys, is what moved `dict_count` and
`knucleotide_tuned`.

## 3. `strings.repeat` and `bytes.find_any`

- **`strings.repeat` (`STANDARD-STRINGS-2`).** `out` now doubles while the copy
  count stays within `times`, and one prefix tops it up. It copies at most about
  3n octets over a logarithmic number of concatenations. It is written in
  mylang, so it takes about log n allocations rather than one; each octet is
  copied at most three times. The guest test builds `repeat("abc", 300000)`:
  0.7 s on this branch, while the base compiler hits `R_STEP_LIMIT`.
- **`find_any` with two octets (`PY-BYTES-22`).** It searches a window at a time,
  starting at 64 octets and doubling. Within a window, the second octet is
  searched only up to the first octet's hit, so a search costs at most about
  twice the distance to its answer. The guest test runs 20,000 searches over
  4 MB with one octet absent: 0.61 s on this branch against 2.51 s on the base
  compiler (whole `mylang test` wall time, build included).

## 4. The view accessor (item 5) and slot size (item 6)

**Item 5 — the view accessor.** The view test that cost 2–3% on text-keyed loops
is gone from the loops that paid it. A described slice resolves its receiver's
storage once per operation (`span_of`), and nothing hashes or compares a view
per octet. For ordinary text keys the test already ran once per lookup
(`probe_text`, `myl_native_text_hash`). A payload pointer in every text was not
needed, so no text grew.

**Item 6 — slot size: measured, not changed.** A model of the million-key passes
(`results/leftovers/slot-footprint-model.c`) inserts 1M distinct keys, each after
a missed probe, into a table that grows at load 5/8. It compared two index
layouts:

- today's 8-byte slots: 47.5 ms and 31.0 ms (two runs, best of 9);
- a 1-byte tag array plus a 4-byte index array: 45.7 ms and 30.9 ms.

The insert's index write and growth miss the cache either way. In a profile of
the k = 12 and k = 18 passes, the home-slot load is 21% of samples, but the
split layout would not remove that miss for an insert-heavy pass. It stays
8 bytes per slot.

## 5. Numbers

`results/leftovers/text-dict-suite.json`: 11 interleaved rounds on CPU 4, load
average 7–12 during the batch. `before` is the base install `install-w4`
(`160a2d08`'s tree). Ratios are paired medians with 95% bootstrap intervals.
Every arm printed byte-identical output.

| program | Zig ms | before ×Zig | this ×Zig | this / before | peak RSS before → this (Zig) |
|---|---:|---:|---:|---:|---|
| `knucleotide` | 167.8 | 3.44 | **1.52** [1.46, 1.58] | **0.435** [0.413, 0.449] | 63.1 → **29.2 MB** (9.7) |
| `knucleotide_tuned` | | 1.42 | 1.36 | | 27.0 → 26.9 MB |
| `dict_count` | 30.1 | 1.20 | **1.08** [1.06, 1.09] | **0.898** [0.886, 0.921] | 3.4 → 3.0 MB (2.0) |
| `text_ops` | 32.4 | 3.58 | 3.80 [3.73, 3.86] | 1.051 [1.032, 1.061] | 35.7 → 45.0 MB (8.0) |
| `sort_builtin` | 244.6 | 0.53 | 0.52 | 0.996 [0.990, 1.020] | unchanged |
| `sort_records` | 135.7 | 0.28 | 0.29 | 1.001 [0.975, 1.038] | unchanged |
| `sort_quick` | 204.8 | 1.29 | 1.30 | 1.008 [0.992, 1.019] | unchanged |
| `scan_split` | 39.6 | 3.36 | 3.33 | 0.997 [0.994, 1.007] | unchanged |
| `scan_count` | 100.4 | 1.02 | 0.97 | 0.984 [0.952, 1.002] | unchanged |
| `scan_replace` | 173.5 | 0.35 | 0.35 | 0.980 [0.967, 1.027] | unchanged |
| `slice_walk` | 1.9 | 2.70 | 2.73 | 1.006 [0.993, 1.014] | unchanged |

**`knucleotide` in other batches.** On the same install and machine:

| batch | this ×Zig | before ×Zig |
|---|---:|---:|
| `knucleotide-dict-count.json`, 11 rounds | 1.48 [1.37, 1.63] | 3.54 |
| an earlier 7-round batch | 1.42 | 3.45 |
| an earlier 11-round batch | 1.46 | 3.39 |

- **Where the time goes now:** the dictionary walk inlined into the guest, then
  the guest loop itself. There is no slice allocation any more.
- **Remaining gap:** the text-keyed program is within about 0.1× of the
  integer-keyed `knucleotide_tuned`. The rest of that shared gap is the guest
  loop's frame and step protocol, which is outside this lane.
- **Probes:** in the small-k passes, the stored key's header load is the hottest
  instruction. In the million-key passes, it is the home-slot miss.

**`text_ops` is slower through layout and collection phase, not work.**

- Its emitted IL is byte-identical to the base's except `strings::repeat`.
- The runtime functions it calls are unchanged in source.
- In one runtime, the new `repeat` against the old one, copied into the program,
  is 0.967 [0.960, 0.989] (CPU time, 21 rounds).
- Two binaries from identical source that differ only in file name differ by
  1.031 [1.015, 1.037]. The hot runtime functions (`mark`,
  `myl_native_heap_alloc_at`, `myl_native_text_split`) start at different
  offsets within their cache lines.
- The peak RSS change is the collector's trigger phase:
  - The new `repeat` returns the shared one-copy literal instead of a fresh
    text, which makes about 28,000 fewer allocations. Peak RSS goes from 35.7 MB
    to 45.0 MB.
  - Adding one allocation per call puts it back at 35.7 MB. Adding two raises
    it to 47.3 MB.
  - These variants are in `text-ops-phase.json`. Excluding the one with two
    extra allocations, their time moves 1.3–2.4%.
- The collector's trigger belongs to the memory-footprint lane.

**Acceptance.**

| target | result | met? |
|---|---|---|
| `knucleotide` ≤ 1.5× Zig | 1.42–1.52 across four loaded batches (medians), paired 0.42–0.44 of before | met in 3 of 4 batches; borderline |
| `text_ops` improves | 1.02–1.05× before; layout and GC phase (§5) | **no** |
| `strings.repeat`, `find_any` linear | guest tests that scale; base compiler: `R_STEP_LIMIT` / 4× slower | yes |
| nothing slower | `dict_count` 0.90, `knucleotide_tuned` faster, `sort_*` and scans within noise; `text_ops` as above | yes except `text_ops` |

## 6. Tests and gate

**Zig tests** (`src/qbe_range_keys_test.zig`) pin the lowering:

- `DICT-RANGE-KEY-1`: no `text_slice` in the counting loop, and every spelling
  described;
- a slice with any other reader is still built;
- an arena program keeps building its slices;
- `DICT-OVERWRITE-1`: no root on a present-key write.

**Guest tests**, all passing with `--gc-stress`:

- `tests/lang/dictionary_range_keys.my`, 7 tests, comparing against built
  slices:
  - every spelling;
  - clamping, negative and past-the-end endpoints;
  - non-ASCII receivers;
  - keys outliving their receiver across collections;
  - owned and described keys hashing alike;
  - absence records across an insertion of the same octets, a whole-text
    lookup, collections, `pop` and `clear`.
- `STANDARD-STRINGS-2` and `PY-BYTES-22` in `standard_strings.my` and
  `python_bytes.my`, including window-boundary hits.

**C tests** (`tests/native_text_dictionary_test.c`):

- span/slice equivalence over 225 endpoint pairs under the stress collector, in
  hash, octets, stored keys, flags, order and values;
- record dating, whether a record answers a different span, and overwrite
  semantics.

These pass under UBSan and ASan+UBSan.

**Pre-existing failures, identical on the base tree:**

- `native_print`: assertion at `native_print_test.c:58`;
- `native_text_views_test.c` does not compile: `MYL_NATIVE_OBJECT_FREE` no
  longer exists after the alloc-gc merge.

**Gate:**

| step | result |
|---|---|
| `zig build test` | green, 73/73 steps; `gate_diff` against `w4-test.log`: 0 new, the 1 base failure cleared (by `160a2d08`) |
| `test-qbe` | 305/305; `gate_diff` 0 new |
| `test-qbe-build` / `test-schematic` / `test-byte-io` / `fmt-check` | green |
| `tests/lang` | 502 passed, both plain and `--gc-stress` |

## 7. Left

- **Arena programs** (`knucleotide_arena`, 3.2×). To describe a slice there, the
  write would need an equivalent check that the current depth is at most the
  dictionary's, and range locals would need `end_arena`'s retention scan.
- **The shared guest-loop cost** in `knucleotide` and `knucleotide_tuned`: step
  and position stores, the frame protocol.
- **`text_ops` peak RSS** depends on the collector's trigger phase: 35.7 MB or
  45 MB for the same work.
