# Dictionary hashing and probing — wave 0, lane `perf/lib-dict-hash` — 2026-09-22

**Headline.** The dictionary runtime has four changes:

- a scalar key is hashed with one multiply;
- text is hashed eight octets at a time;
- each index slot stores its key's 32-bit hash, so a probe skips every entry
  whose hash differs;
- the second half of every get-then-set spelling is answered from a record of
  the first half, for every key type.

Measured against the Zig port in interleaved batches on a loaded machine (load
average 14–20). Paired ratios, 95% bootstrap intervals, two batches of the
final build:

| program | before | after | after ÷ before | acceptance | met? |
|---|---:|---:|---:|---:|---|
| `knucleotide` | 5.30× / 5.62× | **3.42×** [3.00, 3.47] / **3.60×** [3.39, 3.74] | 0.62 / 0.64 | ≤ 2.5× | **no** — slice allocation (wave 3) |
| `knucleotide_tuned` | 2.90× / 2.88× | **1.31×** [1.15, 1.37] / **1.34×** [1.31, 1.39] | 0.42 / 0.46 | ≤ 1.5× | **yes** |
| `dict_count` (micro) | 1.68× / 1.73× | **1.44×** [1.34, 1.57] / **1.40×** [1.36, 1.43] | 0.85 / 0.83 | ≤ 1.2× | **no** — the guest's root chain (wave 1–2) |

Nothing observable changed. Every arm printed byte-identical output. Insertion
order, iteration, printing, equality, `pop`, `setdefault`, `update`, `clear`,
`copy`, the arena escape and the memory-budget refusal path all answer exactly
as before. Peak RSS is unchanged: `knucleotide` 78.3 MB before and after (Zig
9.7 MB, 8.1×), `knucleotide_tuned` 27.7 MB before and after (2.9×). Index slots
are still eight bytes each.

The dictionary's own share of each program roughly halved. For the two missed
targets, what remains above them is outside `native_dictionary.c`, and the
profiles below show where.

## What changed and why

The changes are in `src/native_dictionary.{c,h}` and in the body of
`myl_native_text_hash` in `src/native_text.c`; the dictionary is that function's
only caller. No compiler file changed: every get-then-set spelling already
lowers to runtime calls the record can answer.

1. **Scalar keys: one multiply** (`[PY-DICT-3]`). An integer key's bytes are
   zero-extended to a word and put through one full 64×64-bit multiply. The
   product's two halves are xored and folded to 32 bits. The base hashed with
   8 FNV rounds (one dependent multiply per byte) followed by a three-step
   avalanche.

   Only integer and `str` keys exist: `E_DICT_KEY` rejects `float`, `bool` and
   enum keys (checked against the compiler). There is therefore no `0.0`/`-0.0`
   or NaN key case to preserve.
2. **Text keys: eight octets at a time** (`[PY-DICT-3]`). `myl_native_text_hash`
   folds each 8-octet word into a state seeded with the length, using the same
   multiply.
   - A payload of at most 8 octets is read as two overlapping halves.
   - A longer payload ends on the word that finishes at its last octet, so no
     read passes the payload.

   The result is still cached in the text header (`MYL_TEXT_HASHED`), and that
   function is still the header field's only writer, so the cache stays
   consistent. The hash has fixed constants and no seed.
3. **Hash tags** (`[PY-DICT-5]`). Each slot holds `hash32 << 32 | entry + 1`,
   still eight bytes.
   - A probe compares the stored hash before it loads an entry. A miss walks
     slots only, and keys are compared only when all 32 bits match.
   - When the table grows, slots are re-placed from their stored hashes. No key
     is read or rehashed.
   - `pop` removes its slot by backward shift and renumbers later entries in
     place. It hashes at most the popped key; the base rehashed every key on
     every `pop`.
4. **One probe for get-then-set, every key type** (`[PY-DICT-4]`).

   How the spellings lower today (unchanged):

   | spelling | runtime calls |
   |---|---|
   | `d[k] = d.get(k, 0) + 1` | `read`, then `write` |
   | `d[k] += 1` | `read`, then `write` |
   | `if k in d: d[k] = …` | `contains`, `read`, `write` |
   | `d.setdefault(k, v)` | one call |

   The base's single-probe mechanism was `remembered_entry`
   (`[DICT-GETORPUT-1]`). It remembered the last *found* entry for a *`str`* key,
   and accepted it only when the queried text and the entry's stored key were
   the same object. That covered `dict_count`. It did not cover `knucleotide`:
   the slice queried there is never the stored object, so every hit was probed
   twice.

   Now:
   - **Found entries, every key type.** The record keeps a found entry for any
     key: the queried object's pointer for text, the key's bits for integers.
     Before it is used, it is checked against the live entry by *content*. For a
     fresh slice, the second call costs one comparison with a text already in
     cache.
   - **Integer absences.** An integer key's absence is recorded together with
     the empty slot a write would fill, so a `write` after a missed `read` or
     `contains` inserts without walking the table. Every insertion, growth,
     refused allocation, `pop`, `clear` and reindex drops that record first.
   - **Text absences are never recorded.** Between the two calls the queried
     text can be collected, and its address reused by an equal text that *is*
     present. `read` and `contains` do not see the heap, so no epoch can rule
     that out. The write after a missed text read walks the table again, over
     slots already in cache and comparing only stored hashes.
   - **`setdefault`** probes once whichever way it resolves; the base read and
     then wrote.
5. **A lean call structure.**
   - The key kind is fixed when the dictionary is created: text, eight-byte
     word, narrower integer, or wider bytes (reachable only from C). Each kind
     has its own probe loop.
   - A lookup returns `{entry, slot, hash}` in two registers.
   - An 8-byte value is copied with a register move.
   - Public `read`, `contains` and `write` are the inline record check plus
     at most one call into a single out-of-line walk.

   The base called libc `memcmp` for every key comparison and `memmove` for every
   value copy. In the base profiles, 22% of `dict_count`'s samples and 29% of
   `knucleotide_tuned`'s were in the shared C library; now 0.1% and 2.3%.

**Unchanged:**
- **Insertion order.** The entry list is untouched, and every observable answer
  comes from it.
- **Deletion and `pop`.**
- **Scan fallback.** A refused index allocation still leaves the dictionary
  scanning. So does a table past 2³¹ slots, which could not otherwise be
  represented.
- **Arena-escape reindex.** It drops the record and rebuilds the table from the
  filled keys.
- **Collector tracing of the index field.**
- **Budget accounting.** The table is still charged to the budget, and a refusal
  still restores `heap->exhausted`.
- **Every existing test.**

## Measurements

**Method.** Harness: `experiments/perf-parity-plan-20260922/bench.py` with
`--cpu 4`, 15 rounds for `knucleotide` and 15 and 21 for `dict_count`, and
2 warm-ups. Arms are shuffled in every round.

- **Before arm:** the audit's install `install-a3`, code-identical to this lane's
  base for guest programs, built into `<work>/<name>.before` and timed through
  `--cf before`.
- **After arm:** this branch's ReleaseFast install.

The load average was 14–20 throughout, and the Zig reference ran at
121–203 ms against the plan's quiet 104 ms. Only ratios within a batch are
claimed, and they are labelled "loaded machine". The per-round walls in the JSON
show load swings of up to 2× inside a batch.

| batch | file | Zig median | before | after | tuned before | tuned after |
|---|---|---:|---:|---:|---:|---:|
| knucleotide 1 | `results/wave0/dict-knucleotide.json` | 202.7 ms | 5.30 [5.17, 5.41] | 3.42 [3.00, 3.47] | 2.90 [2.74, 3.01] | 1.31 [1.15, 1.37] |
| knucleotide 2 | `results/wave0/dict-knucleotide-b2.json` | 162.1 ms | 5.62 [5.43, 6.05] | 3.60 [3.39, 3.74] | 2.88 [2.75, 3.04] | 1.34 [1.31, 1.39] |
| dict_count 1 | `results/wave0/dict-dict_count.json` | 61.5 ms | 1.68 [1.64, 1.82] | 1.44 [1.34, 1.57] | | |
| dict_count 2 | `results/wave0/dict-dict_count-b2.json` | 58.6 ms | 1.73 [1.66, 1.77] | 1.40 [1.36, 1.43] | | |

The before arm's own ratio moves with load (the plan's quiet numbers are 4.90×,
2.84× and 1.60×). The paired after ÷ before ratio is the steadier result:

| program | after ÷ before |
|---|---:|
| `knucleotide` | 0.62–0.64 |
| `knucleotide_tuned` | 0.42–0.46 |
| `dict_count` | 0.83–0.85 |

Applied to the plan's quiet ratios, these project `knucleotide` ≈ 3.1×,
`knucleotide_tuned` ≈ 1.2–1.3× and `dict_count` ≈ 1.33–1.36×. That is a
projection; the coordinator's quiet re-measure is the number of record.

Peak RSS (`/usr/bin/time`, one run per arm, from the same JSON):

| program | Zig | before | after |
|---|---:|---:|---:|
| `knucleotide` | 9.7 MB | 78.3 MB | 78.3 MB |
| `knucleotide_tuned` | 9.7 MB | 27.5–27.7 MB | 27.7 MB |
| `dict_count` | 2.1 MB | 2.9–3.1 MB | 2.9 MB |

## Where the remaining time is

SIGPROF self-PC profiles of `--keep-symbols` LTO builds, pinned to CPU 4
(`results/wave0/dict-profiles/`). Under LTO the probe loops are attributed to
`probe_text`, `read_walk` and `locate`. The base's `find` includes its inlined
hash and comparison.

- **`knucleotide`, 3.4–3.6×.**
  - Dictionary: 44% of samples. `probe_text` 27.7%, text hash 6.6%,
    `read_walk` + `read` 7.5%, `insert` 1.4%. The base spent 54% in `find` and
    most of its 15% libc share on dictionary `memcmp`/`memmove`.
  - Slice allocation and collection: about 36%, now the largest item.
    `heap_alloc_at` 18.5%, `heap_collect` 5.8%, `slot_take` 2.7%, `trace` 2.2%,
    and libc 6.9%, which is the slice `memcpy`.
  - The guest loop: 17.6%.

  Most of what remains in `probe_text` is two cache misses in the k = 12 and
  k = 18 passes, whose tables hold about a million keys (16 MB of slots). One is
  the home-slot load; the other is the stored text's header on a hit. The 36%
  slice share is wave 3's shared-`str` work (plan §5.4). Scaling by the profile,
  not measured, removing it would put this program at about 2.2–2.3× on these
  batches: under the 2.5× target, but only just. The target is missed for that
  measured reason.
- **`knucleotide_tuned`, 1.31–1.34×.** Met. The dictionary is about 60% (the
  word probe is inlined into `read_walk`), the guest loop 34%, and libc 2.3%
  (28.7% before).
- **`dict_count`, 1.40–1.44×.** The dictionary is 62%. The guest function is
  38%, and that alone is about 16 ms of a 43 ms run against Zig's 35 ms total.
  Its emitted IL pushes nine 32-byte root records around every
  `myl_native_dictionary_write`, because `write` can allocate. It also stores a
  position and a step count per statement. Those are lane 5 and plan §6.3 (root
  liveness), not this file. As an estimate from the profile, the dictionary
  share alone (about 27 ms) is already below Zig's total. The 1.2× target is
  missed for that measured reason.

## Tests

- **`tests/lang/dictionary_hashing.my`** (new): 12 `public def test_*`, all passing
  under `--gc-stress`. The primary tests are `# spec: PY-DICT-3`, `PY-DICT-4` and
  `PY-DICT-5`; the rest are `spec-case`. They cover:
  - **Integer keys:** negative and extreme values (`i64` min and max, ±2ⁿ for
    n < 62, the whole `i8` space, `u64` max, 2⁶³, `i16` extremes);
    keys that differ only above bit 32, or share their low 10 bits.
  - **Text keys:** the empty text and every length from 0 to 69; multi-octet
    scalars; keys that differ only in their last octet at lengths
    1/4/7/8/9/15/16/17/24/33; 600 keys behind one shared 8-octet prefix.
  - **Removal:** 400 pops out of a 1,200-key table, with reinsertion order
    checked; the whole table emptied back to front and refilled; text-key
    pop and reinsert.
  - **Growth:** 6,000 integer keys and 1,500 text keys, across many resizes.
  - **Get-then-set spellings:** the four spellings give identical counts over
    3,000 integer keys; `+=` works on present keys.
  - **Recorded absences:** a missed read never shadows a key inserted before the
    write — by another key possibly taking the recorded slot (39 cases), by
    `setdefault`, by `update`, through an alias, by growth, by `pop` and by
    `clear`, and for text.
  - **Fresh slices:** counting through fresh slices equals counting through one
    key object.
  - **Order independence:** printing and iteration follow insertion order.
  - **Arena escape:** an integer-keyed dictionary escapes an arena with a working
    index and a live absence record.
- **`tests/native_text_dictionary_test.c`**, run by
  `scripts/test_native_memory.py`, passes all nine suites under
  `-fsanitize=undefined`, and again with `MYLANG_TEST_ASAN=1`.
  - `index_sound` now decodes packed slots, and also asserts that every slot is
    reachable by linear probing from the home its stored hash names.
  - Two new cases:
    - `absent_records_are_dropped_by_every_change` (`spec-case: PY-DICT-4`);
    - `pops_close_collision_runs` (`spec-case: PY-DICT-5`).
  - Both cases catch injected bugs. An insertion that keeps a stale absence
    record fails the `setdefault` assertion. A removal that leaves a hole
    instead of shifting fails `index_sound`.
- **Unchanged tests:** `tests/lang/dictionary_hash_index.my` (7),
  `dictionary_views.my`, `python_collections.my`, `python_values.my` and
  `python_comprehension.my` pass unchanged.
- **`SPEC.md`**
  - Gains `[PY-DICT-3]`, `[PY-DICT-4]` and `[PY-DICT-5]`.
  - `[DICT-GETORPUT-1]` now says that `[PY-DICT-4]` extends the record to keys
    compared by value.
  - `[PY-DICT-2]` now names UTF-8 octets instead of scalars, and in-place
    renumbering for `pop`.
- **`docs/performance-roadmap.md` item 7** no longer calls the hash FNV-1a.

## Gate

The gate ran on the committed code. Each step went through `slot.sh gate`
(`fmt-check` through `slot.sh build`), and its log was compared with
`gate_diff.py` against the base logs:

| step | result | gate_diff vs base |
|---|---|---|
| `zig build test --summary all` | 53/73 steps, 1618/18549 tests passed, 46 failed — identical to base; guest `tests/lang` 263 passed / 0 failed across 70 programs (base 251 / 69); `doc-coverage: 0 failures`; Guardian 88/88 | base 47, lane 47, **NEW 0** |
| `zig build test-qbe --summary all` | 43/48 steps, 270/272 — identical to base | base 2, lane 2, **NEW 0** |
| `zig build test-qbe-build --summary all` | 30/30 steps | **NEW 0** |
| `zig build fmt-check` | exit 0 | **NEW 0** |

## Left for later

- **Slot footprint.** Big tables miss the cache at 8 bytes per slot, where Zig's
  metadata costs 1 byte. A split layout (a tag-byte array plus 32-bit entry
  indices) would cut a miss probe's footprint by 8×. But growth would then have
  to rehash keys: for text keys, one header load per entry. Worth measuring
  once slices stop dominating `knucleotide`.
- **Text absences** still cost a second, cache-hot table walk. Recording them
  safely needs the heap's collection or arena epoch at `read`/`contains`, which
  would mean passing `%heap` to those two calls: a lowering change, left out to
  stay clear of lane 5.
- **Linear in size.** `pop` and dictionary equality (`native_equal.c`) are still
  linear.
- **No adversarial resistance.** The hash is unseeded, as before, so
  adversarially chosen keys can still collide.
