# The new compiler core, stage S2: collections, text and the 35 rows (design)

**Status:** design for S2, 2026-10-05, for the user's go/no-go. Branch
`claude/new-core-s2-design-20261005`, cut from the S1 head `b333ffc0`. Nothing under `src/`
changed. Companion to `new-core-ir.md` (S0) and `new-core-s1.md` (S1, including §6.1–6.4 and
§13–15 as built). Inputs: plan `docs/audits/new-core-plan-2026-10-05.md` §6 (S2 scope and exit
check), `runtime-language-levers-2026-10-04.md` §3.2, WP-7 and WP-10c/e, decisions R1, D1–D4
and N6 = B. The experiment is in `experiments/new-core-s2-design-20261005/`.

**S2 scope (plan §6):**
- dictionaries and sets, with the table layout chosen in §2;
- `str` and `bytes`, with a UTF-8 cursor, views and a borrowed `encode()`;
- `int_parse`, `int_format` and sort;
- this note adds **function values** (needed by the exit check) and **fixed arrays** (§5).

**Exit check (plan §6):**
- all 35 micro rows build under the new core and match the old core's checksums;
- the conformance set in §6 matches the old core, at debug and release;
- a coverage sweep, reported per refusal reason;
- then the user decides whether to commit to S3–S5.

**No language behaviour changes in this note.** Every decision keeps the old core's observable
answers: insertion order, iteration traps, hashing without a seed, the `int()` grammar, sort
stability and key semantics, `print` rendering. The behaviour questions that remain are in §10.

## 1. Where S1 leaves us

The figures below were measured on the S1 head.

**Coverage** (`coverage.py`): 2,248 of 3,509 functions are accepted. The refusals S2 can
remove are:

| Refusal | Functions |
|---|---:|
| dict | 340 |
| bytes | 325 |
| fixed array | 142 |
| function value | 53 |
| capability | 49 (S3) |

**Conformance** (`conformance-all-a09d8274.txt`): 735 of 1,470 tests are supported, and every
supported test matches. The blocking features of the 735 unsupported tests are counted by
first blocker only:

| Blocking feature | Tests / files |
|---|---:|
| dict type | 196 / 55 |
| bytes type | 145 / 43 |
| fixed array type | 93 / 31 |
| function values (both spellings) | 57 / 23 |
| capability, and tests with parameters | 48 / 10 (S3) |
| set type | 19 / 6 |
| sort | 17 / 8 |
| slice | 16 / 8 |
| split | 11 / 9 |
| index | 10 / 6 |
| text of a non-integer value | 9 / 8 |
| about 30 text methods (`replace`, `strip`, `find`, `upper`, `count`, …) | 1–6 each |

**The micro rows S2 must add** (35 micro rows in total; S1 builds 20):

| Group | Rows |
|---|---|
| collections | `dict_lookup`, `dict_lookup_str`, `dict_update`, `dict_update_str`, `set_dedup`, `sort_int`, `sort_records` |
| text | `bytes_scan`, `string_equal`, `string_search`, `string_split`, `string_join`, `int_parse`, `int_format` |
| compute | `call_indirect` (function values) |

The five application rows (`packet_decode`, `lox_eval`, `word_count`, `csv_aggregate`,
`json_transform`) are S3. `word_count` still shapes the dictionary and text decisions here.

**Where the old core stands on these rows** (frozen baseline, `baseline_main_20261003.md`;
ns per iteration, my-llvm against Zig ReleaseSafe, small / large):

| Row | Old core (my-llvm) / Zig Safe |
|---|---|
| `dict_lookup` | 1.05 / 1.01 |
| `dict_lookup_str` | 1.12 / 1.08 |
| `dict_update` | 3.07 / 1.91 |
| `dict_update_str` | 2.17 / 1.37 |
| `set_dedup` | 5.66 / 2.77 |
| `sort_int` | 1.04 / 0.68 |
| `sort_records` | 1.53 / 0.53 |
| `bytes_scan` | 0.31 / 0.27 |
| `string_equal` | 3.9 / 0.69 |
| `string_search` | 0.22 / 0.03 |
| `string_split` | 3.44 / 3.49 |
| `string_join` | 1.35 / 1.31 |
| `int_parse` | 1.76 / 1.57 |
| `int_format` | 1.58 / 1.63 |
| `call_indirect` | 1.04 / 1.05 |

The L1 gate is ≤ 1.10× Zig ReleaseSafe. Rows to beat: `dict_update*`, `set_dedup`,
`string_equal` (small), `string_split`, `string_join`, `int_parse` and `int_format`.

## 2. Dictionaries and sets: the table layout (WP-10e)

### 2.1 What the old core does

`src/native_dictionary.c` (read for this note) uses two structures.

**Entries.** An insertion-ordered array of `{key, value}` records.

**Index.** A separate open-addressing table of `u64` slots, each holding `hash32 << 32 |
(entry + 1)`:
- linear probing, at most 5/8 full;
- a slot whose stored hash differs is skipped without loading its entry;
- backward-shift deletion;
- dead entries are compacted by `settle`;
- a dict with no table scans.

**Hashes.**
- Integer keys: one fold-multiply.
- Strings: a word-at-a-time fold-multiply over the UTF-8 octets, with no seed (PY-DICT-2),
  cached in the text header (`SELKA_TEXT_HASHED`). A view's hash is recomputed on every use.
- Floats are refused as keys.

**Every read writes a last-probe record** (`dict->last`: `recall`/`locate`, DICT-GETORPUT-1,
PY-DICT-4), so that a following `d[k] = …` can skip its probe.

**Sets** are `dict[T, unit]`. The checker already lowers them (`set_lower.zig` runs inside
sema), so `typed.Program` carries sets as dictionary operations. **The new core gets sets
for free once it has dicts.**

### 2.2 Candidates measured

`experiments/new-core-s2-design-20261005/dict-layout/` is C. Build it with `zig cc -O3
-march=native` and run it with `taskset -c 10` (`run.sh`). The unit is user-mode core
cycles per operation from a perf counter, the median of 7 interleaved rounds. Raw output:
`results/layouts-20261005.txt`.

**Layouts:**

| Layout | Index | Values | Probe | Load | Order |
|---|---|---|---|---|---|
| **old** | `u64` `{hash32, entry+1}` | dense entries | linear, hash compared in the slot | ≤ 1/2 at full entries (the real one is 5/8, so this favours `old`) | the entry array |
| **old+hint** | the same | the same | the same, plus the old core's last-probe record written on every read and consulted by the upsert | | |
| **cpython** | `i32` entry number | dense entries `{hash, key, value}` | linear, hash compared in the entry (CPython 3.6 compact dict) | ≤ 1/2 | the entry array |
| **swiss** | 1-byte control tags (7 bits of hash), 16-slot SSE2 group match | `{key, value}` inline in the slots | group | ≤ 7/8 | a `u32` order array of slot numbers |
| **hybrid** | 1-byte control tags plus a `u32` entry-number array, 16-slot SSE2 group match | dense entries | group | ≤ 1/2 | the entry array |

**Deletion in `swiss` and `hybrid`.** A deleted slot becomes DELETED and is never reused
before the next rebuild. That keeps insertion order exact without an order-position field.

**Hashes.** Every layout uses the same hashes: a fold of the high half after one multiply
for integers, and a 128-bit multiply-fold over 8-byte words for strings, cached in the
header. The table position comes from the **top** bits, so the comparison isolates the
layout.

**Workloads.** They are the rows' own distributions, plus the controls WP-10e asks for:

| Workload | Keys and queries |
|---|---|
| `dict_lookup` | keys `0..n−1`; queries `(42 + 17j + b) mod 2n`, so half miss |
| `dict_update/2` | `dict_update` with separate `get` and `put` (two probes) |
| `dict_update/1` | `dict_update` with one fused upsert |
| `set_dedup` | the `set_dedup` row |
| `sparse_int` | random 64-bit keys, half of the queries miss: **the honest integer case** |
| `churn` | inserts, deletes and re-inserts with an order-sensitive checksum |
| `lookup_str` | keys `str(j)`; queries are the same objects |
| `update_str` | the `dict_update_str` row |
| `mixed_str` | 4–40-byte random keys; queries are equal copies, so a content compare runs |
| `word_count` | 6 distinct words; each lookup is a fresh piece with no cached hash; 3 probes per word, as the row's source does |

**Correctness check.** Every layout produced the same checksum on every workload,
including `churn`'s order-sensitive one.

**Results** (cycles per operation; lower is better):

| Workload | n | old | old+hint | cpython | swiss | **hybrid** |
|---|---:|---:|---:|---:|---:|---:|
| `dict_lookup` (dense keys) | 64 / 4096 / 65536 | 10.7 / 10.5 / 28.3 | 11.2 / 10.3 / 26.2 | **8.5 / 9.0 / 13.0** | 10.7 / 10.7 / 15.7 | 11.0 / 11.1 / 16.1 |
| `sparse_int` | 64 / 4096 / 65536 | 5.1 / 36.5 / 55.4 | 7.2 / 28.6 / 59.5 | 5.2 / 20.5 / 70.6 | 6.9 / 13.6 / 32.1 | **5.8 / 13.8 / 32.1** |
| `lookup_str` | 64 / 4096 / 65536 | 10.5 / 41.5 / 101 | 10.9 / 31.0 / 102 | 10.8 / 34.4 / 105 | 11.6 / **18.2 / 60.8** | 11.9 / 19.1 / 63.6 |
| `mixed_str` | 64 / 4096 / 65536 | 11.6 / 39.0 / 113 | 12.8 / 61.1 / 114 | 11.2 / 48.1 / 123 | 11.7 / **28.6 / 87.4** | 13.4 / 34.4 / 93.9 |
| `dict_update/1` (dense keys) | 64 / 4096 / 65536 | 27.3 / 25.4 / 52.6 | 28.2 / 26.0 / 53.7 | **26.0 / 21.9 / 44.0** | 47.1 / 37.8 / 64.3 | 37.9 / 30.0 / 43.9 |
| `update_str/1` | 64 / 4096 / 65536 | 28.7 / 58.0 / 122 | 29.3 / 56.3 / 123 | **24.3** / 50.8 / 108 | 54.7 / 61.6 / 157 | 46.5 / **48.7 / 102** |
| `set_dedup` | 64 / 4096 / 65536 | 18.1 / 26.5 / 21.3 | 19.9 / 26.4 / 21.6 | **16.1 / 14.3 / 13.8** | 26.1 / 21.9 / 21.6 | 22.3 / 18.6 / 17.9 |
| `churn` (delete + re-insert) | 64 / 4096 / 65536 | 87.5 / 71.3 / 84.5 | 90.0 / 73.8 / 87.4 | 71.7 / 68.0 / 74.4 | 74.7 / 68.9 / 72.9 | 74.0 / **64.3 / 68.9** |
| `word_count` (6 keys) | 64 / 4096 | 88.3 / 88.6 | 83.7 / 83.6 | **82.1 / 82.9** | 94.1 / 101.5 | 101.3 / 108.8 |
| `dict_update/1`, 2n reserved first | 64 / 4096 | 19.6 / 19.5 | 20.0 / 20.0 | **17.1 / 17.8** | 22.5 / 23.4 | 21.5 / 22.9 |
| `update_str/1`, 2n reserved first | 64 / 4096 | 21.5 / 39.2 | 22.2 / 39.6 | **19.3** / 36.5 | 26.1 / 34.7 | 28.0 / **33.4** |

**Reading.**

1. **Hash distribution, not layout, decides the dense-key rows.** Sequential integer keys
   with a multiplicative hash taken from the top bits land almost without collisions
   (Fibonacci hashing). Linear probing then never takes a second step, and the dense-key
   columns favour the linear layouts. This is the fixture luck WP-10e says not to count.
   With randomized hashes (`sparse_int`, every string workload at 4096 and above), the
   group-probed layouts are faster:

   | Workload, n = 4096 | swiss / hybrid against the linear layouts |
   |---|---|
   | `sparse_int` | 2.6× faster than old, 1.5× faster than cpython |
   | `lookup_str` | 1.6–2.2× faster |
   | `mixed_str` | 1.1–1.8× faster |

   At 65,536 entries the gap holds (`sparse_int` 1.7–2.2×, the string workloads 1.2–1.7×)
   and is cache-line traffic: a miss resolves in
   the control line, and the control and index lines are both addressed from the hash.
2. **Linear probing degrades at load ½ with random hashes; the control-byte probe does not.**
   Reserving 2n entries first (load ¼) brings `old`/`cpython` `lookup_str` from 34–41 down
   to about 15–17 cycles. The control-byte layouts stay at 18–19 at either load. A table that
   cannot know its final size (most of them) benefits from that robustness.
3. **The hint write costs more than it saves in compiled code.** In this C harness,
   `old+hint` is within noise of `old` on most rows. It is worse where the stored key
   pointer may alias the key's own header (`mixed_str` 61 against 39 at 4096): the store
   forces the hash and length to be reloaded. That is the mechanism behind the ladder
   study's 1.78× (WP-10c).
4. **`swiss` (values inline) loses on every update row** (`dict_update/1` 37.8 against 30.0
   for `hybrid`):
   - iteration goes through the order array;
   - an update touches a sparse slot array;
   - growth moves values.

   It wins only the string lookups, by 5–20%.
5. **`hybrid`'s remaining costs:**
   - **Growth.** Each rebuild re-hashes and group-probes every key. Reserving the size first
     cuts `dict_update/1` from 30 to 23 cycles. A rebuild that re-inserts with a cheap
     scalar probe, plus builder-known capacities, recovers most of the rest (§2.4).
   - **Tiny tables**: `word_count`'s 6 keys are +23–31% against `cpython`; the 64-entry
     update rows are +46–90%, mostly growth (+26–45% when presized).
     The old core's answer applies: no index below 8 entries, and a probe scans the dense
     entries, comparing cached hashes. The fused upsert (§2.4) removes 2 of `word_count`'s
     3 probes.

### 2.3 Decision: the hybrid layout

**Layout.** One dictionary block holds:

```
header (32 B)   {u32 count, u32 kind=DICT|size class, i64 len (live entries), i64 cap (entry slots), i64 reserved → index block or null}
entries         [cap] × {K key, V value}       insertion order; dense; key and value inline at their natural layout
```

The index is a separate untracked block, allocated once there are more than 8 entries:

```
index block     {u32 slots (power of 2), u32 used (live + DELETED), u32 elen (entries written), u32 dead}
                ctrl[slots + 15]   u8: EMPTY 0x80 | DELETED 0xFE | 7-bit tag; the first 15 mirrored at the end
                entry[slots]       u32 entry numbers
```

**Probe.** `pos = h >> (64 − log2 slots)`, `tag = h & 0x7f`. Load the 16 control bytes at
`pos` and test the `cmpeq` mask; on a tag match read `entry[i]`, then the entry's key. A
group containing an EMPTY ends a miss, and **that group's first EMPTY is the insertion
slot**. Triangular group steps. The index stays at most ½ full, counting DELETED.

**Iteration** walks `entries[0 .. elen)` and skips dead entries. A dead entry is marked in
a per-entry bitmap that is allocated on the first deletion (`dict_entry_live`), as in the
experiment; a dict with no deletions never reads it.

**Deletion** (`pop`, `del`, `discard`):
- marks the control byte DELETED and the entry dead;
- releases the key and value;
- never reuses the slot before a rebuild, so a re-inserted key goes to the end (Python's
  order).

**Growth.** When the index reaches ½ full:
- rebuild it at twice the size if the live entries are above ¼ of the slots, or at the same
  size otherwise (cleaning out the DELETED slots);
- compact dead entries in order;
- re-insert with a scalar empty-slot probe.

**The entry array** grows like a list (size classes, then `realloc`), independently of the
index.

**Small dicts** (at most 8 entries) have no index. A lookup scans the entries:
- integer keys compare the key directly;
- string keys compare cached hashes first.

This is the old core's "no table" path, kept as the fast path.

**Hashes:**
- `int`, `bool` and narrow integers: `x · 0x9E3779B97F4A7C15`, then `x ^ (x >> 32)`.
- `str` and `bytes`: the word-at-a-time multiply-fold (as the old core's
  `myl_native_octets_hash`), cached in the string header (§3.1).
- Records, unions, `Option` and fixed arrays of hashable fields: a field walk generated by
  the emitter per key type (`@myl.hash.N`, beside the `@myl.layout.N` descriptors of S1).
- No seed: the same table on every run (PY-DICT-2).

**Key equality:**
- integers: `==`;
- strings: the same pointer, then the same length and cached hash (when both are cached),
  then `memcmp`;
- aggregates: the emitter's structural equality (V-2's `==` expansion).

**Why this layout:**
- the best randomized-hash lookups (within 5% of `swiss`);
- the old core's iteration, order and memory shape, with no order indirection;
- updates on par with `cpython` for randomized hashes once growth is fixed, and 1.3×
  behind it on dense sequential keys (the fixture luck);
- miss probes that never touch entries;
- the index and the entries are separate blocks, so a copy-on-write copy shares nothing
  mutable and an index rebuild never moves values.

### 2.4 IR operations and emission

The probe result is an SSA value. Value semantics make the old core's runtime hint
unnecessary: a probe of `d` and an insertion into that same SSA `d` cannot have a write in
between.

**Types** (`ir.Compound`):
- `dict: {key: Type, value: Type}`;
- a set is `dict` with value `.void`;
- the key type must be hashable (the checker already enforces this).

**Operations** (all checks name the old core's trap kinds):

| op | operands | result | notes |
|---|---|---|---|
| `dict_new` | `a` capacity hint (`u64`) | dict | the builder passes a known count (a literal's size, a comprehension's trip count, a `for j in range(n): d[...] = …` fill loop's trip count from the facts), else 0 |
| `dict_len` | `a` | `u64` | live entries |
| `dict_find` | `a` dict, `b` key | `i64` probe | ≥ 0: the entry number; < 0: `−(slot + 1)`, the insertion slot (or −1 with no index). **Pure: writes nothing** (WP-10c). |
| `dict_entry_key` / `dict_entry_value` | `a` dict, `b` entry number | key / value, borrowed | like `list_get` (borrow rules of S1 §6.1) |
| `dict_set_value` | `a` dict, `b` entry, `extra[0]` value | dict, consumes `a` | releases the old value |
| `dict_insert` | `a` dict, `b` probe, `extra` = key, value | dict, consumes `a` | `b` must be a `dict_find` of the same `a` that returned < 0 (the verifier checks the operand); grows and re-probes if needed |
| `dict_remove` | `a` dict, `b` entry | dict, consumes `a` | |
| `dict_entries` | `a` | `u64` | entries written (`elen`), the iteration bound |
| `dict_entry_live` | `a`, `b` entry | `bool` | false only after deletions (one load of a flag word, then the bitmap) |
| `dict_copy` | `a` | dict | copy-on-write copy: entries memcpy plus a retain of the managed keys and values; the index is copied as is |
| `dict_clear` | `a` | dict, consumes `a` | |

**Builder lowering** (the typed tree's dictionary nodes):

| Source | Lowering |
|---|---|
| `d[k]` | `e = find`; `e < 0` → trap `R_MISSING_KEY` (cold); else `entry_value` |
| `d.get(k, x)` | `find`, then a select of `entry_value` and `x` |
| `k in d` | `find ≥ 0` |
| `d[k] = v` | `e = find`; `e ≥ 0` ? `set_value(d, e, v)` : `insert(d, e, k, v)` |
| `counts[w] = counts.get(w, 0) + 1`, and `d[k] = f(d[k]) if k in d else …` | **One probe.** A fuse rule (`fuse.zig`, beside S1's projection fusion) folds every `find(d, k)` on the same `d` and the same key SSA value within a block into one, so `word_count`'s `contains` + `get` + `put` becomes one `find`, one branch, and `set_value` or `insert`. This replaces DICT-GETORPUT-1's runtime hint by construction. |
| `for k in d`, `for k, v in d.items()`, `keys()`, `values()` | an index loop over `0 .. dict_entries(d)` with `entry_live` skips; the iteration check compares `dict_len` with the value at entry (the existing `iteration_check` node) |
| `pop(k)`, `pop(k, x)`, `setdefault`, `update`, comprehensions, `==` | compositions of the ops above; `==` ignores order: equal lengths, then every entry of one found in the other |
| set operators | arrive already lowered to dict operations (`set_lower`) |

**Inline fast paths** (`emit_llvm` `runtime_fast_paths`, like S1's list allocator): the
`dict_find` probe for integer keys and for string keys with a cached hash is emitted inline
as LLVM IR:
- the multiply-hash;
- one 16-byte control load, `icmp eq <16 x i8>`, `bitcast` to `i16`, `cttz`;
- the entry read and key compare;
- the EMPTY test.

The rest goes to the C slow path: a second group, small-table scans, string hashes not yet
cached, aggregate keys. Insertion, growth and removal are C calls.

### 2.5 Ownership, copy-on-write and views

**A dict is a value, like a list.** `own.zig` applies S1's three forms to the consuming
updates (`set_value`, `insert`, `remove`, `clear`):
- form 1, statically unique: in place;
- form 2: an `is_unique` test, otherwise `dict_copy`;
- form 3, borrowed: copy first.

Step 0 (§8) gives `ir.zig` an op property `consumesOperand0(op)`, so `own.zig`'s phase A
needs no per-op edits.

**Entry reads** borrow from the dict (phase B treats `dict_entry_*` like `list_get`). The
promotion rule applies when the dict is updated while an earlier read is still used.

**`mut dict` parameters** use V-1's by-value `mut` ABI unchanged:
`mut_dictionary_arguments` and `mut_argument_places` (12 dict tests).

**D2, views.** `keys()`, `values()` and `items()` are non-storable (the checker enforces it,
DICT-VIEWS-1 and D2), so a view never needs a runtime object. The builder represents a view
as its dictionary *place* and re-reads the place's current SSA value at each use. That is
D1's live-place rule, so a view reflects value updates made after it was taken.
- `list(view)` is a snapshot: a fresh list filled in one pass.
- `items()` yields `DictItem` records built in registers (`record_make`, no allocation).

**Facts:**
- `dict_len` intervals: `dict_new` 0; `insert` +1, but only on a path where `find` < 0;
  `remove` −1.
- **Key and value hulls**, by the list element-hull rule: the hull of every key or value
  inserted or set, for a dict built in the function. So
  `lookup[j] = values[j] % 1009` gives every `get` result `[0, 1008] ∪ default`.
- **Not in S2:** dense-integer-key specialization (a dict whose keys are proven to be `0..n`
  lowered to an array). It is fixture-shaped (§2.2, item 1) and changes no row's verdict
  that a fixed hash cannot reach.
- Facts do not cross calls (the `batch_result` dicts are parameters), as in S1.

**Runtime file:** `src/core/runtime/core_dict.c`, a second runtime C file. `driver.zig`
compiles both into the cached runtime object; the split keeps file ownership disjoint
(§8).

## 3. Text and bytes

### 3.1 One block layout for `str` and `bytes`

Both are the S0 block with UTF-8 or raw octets after a 32-byte header:

```
{u32 count, u32 kind, i64 len (bytes), i64 cap (bytes of room), u64 meta}
kind:  low byte STR (1) or BYTES (3); byte 1 flags: ASCII 1, HASHED 2, SCALARS 4, CURSOR 8 (§3.3); high byte size class (O-2a)
meta:  u32 hash (valid if HASHED), u32 scalar count (valid if SCALARS; strings over 2^32 − 1 scalars never set it)
data:  len bytes, then one NUL (the C helpers' convenience; not part of the value)
```

**ASCII flag.** It is set when a string is built:
- literals at compile time;
- concatenation and join: the AND of the parts;
- slices of ASCII strings;
- `decode()`, and `str(int)` (always ASCII);
- otherwise one SIMD scan in the builder function.

The flag gives:
- `len(s)` = `len` (no count), and `s[i]` = byte `i`;
- a cursor step of exactly one byte.

**`HASHED` and `SCALARS`** are caches filled on first use. They are never written into an
immortal block (count saturated): a constant's hash and scalar count are computed at
compile time instead.

**`cap`** is the room for an in-place append (§3.4). Strings are otherwise immutable
values.

**`bytes`** uses the same layout, so:
- `text.encode()` is the same pointer, a borrow, or +1 if it escapes (**borrowed `encode()`
  at zero cost**);
- `b.decode()` validates UTF-8 (SIMD), sets ASCII and returns the same block with the type
  changed in the IR;
- the `kind` byte only decides free and print behaviour, and neither has children.

The old core's `score(text)` (`raw = text.encode(); for value in raw: …`) becomes a plain
byte loop over the string's own data.

`bytes` element reads, `len`, iteration and slicing are the list operations on a `u8`
element type. `ir.zig` gets `Type.bytes` as a block type whose element is `u8`, so
`list_get`/`list_len` and the S0 vector lowering apply. `bytes_scan` is S0's narrow-lane
reduction over `u8` lanes (the old core's LLVM build already runs it at 0.27–0.31× Zig
Safe).

### 3.2 `for ch in text`: a UTF-8 cursor (WP-7 step 1)

The checked tree gives an index loop, `i in 0 .. len(text)` with `read(text, i)`. Two
builder rules turn it into a byte cursor when the loop reads `text` only through
`read(text, i)` (and `i` itself, as `enumerate` does):
1. a loop-carried byte offset `off` (a phi beside `i`);
2. `read(text, i)` becomes `str_char(text, off)` and the step `off' = off + str_width(text,
   off)`.

The loop bound stays the scalar count (`len(text)`). For an ASCII string, which an inline
flag test chooses as a versioned copy (S0's `version.zig` machinery), `off == i` and the
cursor folds away. The iteration check is unchanged. This removes the 30% `csv_aggregate`
cost of the ladder study (`locate` per character).

**The character value** `ch` is a `str`:
- an ASCII scalar is one of 128 **immortal** one-byte blocks in a static table
  (`@myl.ascii`), so no allocation and no count traffic (WP-7 step 2);
- a non-ASCII scalar is a fresh 1–4-byte block from the size-class allocator.

`fuse.zig` rewrites the common uses so most loops never materialize `ch`:
- `ch == "x"` (any one-scalar literal) becomes `str_code(text, off) == 0x78`;
- `ch in "abc"` becomes a code compare chain;
- `field += ch` becomes `str_append_char(field, text, off)` (§3.4).

### 3.3 Code-point indexing and `len`

- **`len(s)`:** `len` if ASCII; otherwise the cached scalar count, computed once by a SIMD
  count of non-continuation bytes (V-2's `myl_core_str_chars`, vectorized) and stored in
  `meta`.
- **`s[i]`, `s[a:b]`, `find`'s returned index** (scalar positions):
  - ASCII: direct (inline flag test).
  - Non-ASCII: `myl_core_str_offset(s, i)` walks with the SIMD scalar count from the nearer
    of the start and the end. For strings of at least 256 bytes it also uses a one-entry
    cursor `{scalar, byte}` kept in `cap` when the string is immutable and not immortal (a
    `cap` that equals `len` is free for this; the flag `CURSOR` (8) says which).
  - That makes sequential index loops amortized O(1) and random access O(n/32) per call.
- **Not ported:** the old core's 1-in-128 sample array (`SAMPLED`/`INDEXED`). It needs a
  block after the payload, which conflicts with in-place append, and no row or test needs
  random access into long non-ASCII text. If a real program does, it is a later addition
  behind the same function (§10, Q5).

### 3.4 Building strings: append in place, join, format

**`s += t` and `s = s + t`** where `s` is an owned local: `str_append(s, t) → s'` consumes
`s`. It runs in place, with S1's forms 1–3 and growth by size class, just like
`list_push`. Then:
- `csv_rows`' `field += ch` is an amortized O(1) byte append;
- `"".join(chunks)` and f-strings size once and copy once (V-2's `myl_core_str_join`
  already does).

**`str(int)`** is §4.2. **`str(float)`, `repr` and `print` of floats** use a shortest
round-trip formatter (a port of the old core's float text). The 9 "text of a non-integer
value" tests and `format_specs` need it; it sits in lane T's stretch (§8).

### 3.5 Slices, `split`, views

**Slices `s[a:b]` copy** (Python's semantics). The copy is a size-class block, cheap for
the short pieces that dominate. The old core's views (an owner pointer plus offset, at
least 9 bytes) are **not** ported as a runtime form. A view form would put a branch on
every data access, and one-count RC makes a view hold its owner alive.

**Views are SSA-only instead.** A slice, or a `split` piece, that never escapes its block
is a borrowed `(ptr, len)` pair of the source in SSA (`str_view`, a new IR type that has no
memory representation and cannot be stored). The verifier rejects it as an operand of a
store, `push`, `insert`, `ret`, phi or call, except to runtime helpers that take a span.
`own.zig` makes it a borrow of its source. Escaping uses get `str_from_view` (a copy).

**The fused split loop.** `for part in text.split(sep): body` becomes a cursor loop:
`find(sep)` from the offset, `part` a `str_view`, no list. It applies when `body` uses
`part` only by borrowing uses: `len`, `encode()`, iteration, `==`, a dict lookup key, or a
call whose parameter is a borrowed `str` with views admitted (§10, Q4). `string_split`
(3.4× Zig Safe on the old core) and `word_count` are the targets.

**`split()` with no argument** splits on whitespace runs. `split` that escapes (a stored
list) builds a list of copies, sized by a first counting pass, as the old core does.

### 3.6 The `string_*` rows' semantics

These are ported from the old core and must match it byte for byte:

| Row / operation | Semantics (old core) | New core |
|---|---|---|
| `string_equal`: `a == b` | pointer, then byte length, then octets (scalar order equals byte order in UTF-8) | inline: pointer and length test, ≤ 16 bytes with two overlapping 8-byte loads, else `memcmp`; the cached hash rejects early only when both are cached |
| `string_search`: `s.find(t)` | the scalar index of the first match, or −1 | `memchr` of the first byte with up to 8 inline candidates, then a two-way search for longer needles (the old `octets_find`); the byte offset becomes a scalar index (§3.3; free for ASCII) |
| `string_split`: `s.split(sep)` | the empty separator traps `R_EMPTY_SEPARATOR`; `split()` uses whitespace runs | count, size, cut; fused loop as above |
| `string_join`: `sep.join(xs)` | one sizing pass and one copy | V-2's helper, with an unrolled path for pieces ≤ 16 bytes |
| `replace`, `strip`, `count`, `startswith`, `upper`, `lower`, `splitlines`, `rfind`, `index`, `ord`, `chr`, `repr` | the old core's `native_text_methods.c` | ported one-for-one into `core_text.c`; each is a runtime call (`extern_c` through `ModuleBuilder.runtimeFunction`, so no IR change) except where a row needs it inline |
| ordering `<` | `memcmp` on the common prefix, then length | `myl_core_str_cmp` |

## 4. `int_parse`, `int_format` and sort

### 4.1 `int(text)`

**Grammar** (pinned, `docs/bytes.md`; already `myl_core_str_parse_int`):
- surrounding ASCII whitespace;
- one optional sign;
- digits, with single `_` between digits;
- leading zeros allowed;
- overflow gives `None`.

**Inline fast path** (the `str_parse_int` op, emitted inline): when `1 ≤ len ≤ 16` and the
first byte is a digit or a sign, read the bytes in two 8-byte SWAR words and test them all
for digits (`(x − 0x30…) | (x + 0x46…)` high bits). Combine them with three multiplies
(the 8-digit SWAR reduction) into the value. Any failure goes to the full C grammar: a
non-digit, `_`, whitespace or more than 16 bytes. 17–19 digits use the C path, which keeps
the exact overflow test.

The result is the `Option[int]` `{i8, i64}` pair in registers.
- Target: the old core is 1.6–1.8× Zig Safe; Zig parses byte by byte, so SWAR plus no call
  should reach about 0.6×.
- The row's six input shapes (positive, `-`, `00` prefix, trailing `x`, `oops`, empty)
  exercise both paths.

### 4.2 `str(int)` and printing integers

`myl_core_int_format(i64) → str`:
- the digit count from `lzcnt` and a power-of-ten table;
- two digits at a time from a 200-byte `"00".."99"` table, written backwards into a fresh
  64-byte size-class block (header plus at most 20 bytes);
- `INT64_MIN` by its own constant.

The same routine writes `print`'s integers into the stream buffer, replacing `snprintf` in
`myl_core_str_from_i64` and `print_i64`.

**Inline part:** the allocation (the O-2a inline allocator). The digit loop is a C call
marked `inline` in the cached runtime object, so LTO can inline it in release builds.

**`int_format`'s `score(str(n))`** (`encode()` then iterate the bytes) is then: format into
a block, borrow it as bytes, sum and release. **Stretch:** `promote.zig` can put a
non-escaping `str(n)` on the stack (a 64-byte `alloca`), which removes the allocation
entirely.

### 4.3 Sort

**`list.sort()` / `sorted()`** port the old core's stable adaptive merge sort
(`native_collections.c`):
- natural runs;
- strictly descending runs reversed;
- binary insertion sort up to minrun;
- powersort merge order;
- `n/2` scratch.

There is one specialized entry per element kind: `i64`, `u64`, `f64` (NaNs last), `str`,
`bytes`, narrow integers.

**Op:** `list_sort(l, kind) → l'` consumes `l`. It runs in place under S1's forms; a shared
list is copied first.

**For `i64`/`u64` lists** stability is unobservable. The port keeps the old algorithm
(already 0.19–0.26× Go on `sort_int`), and S2 does not add a radix path.

**`sort(key=f)` / `sorted(key=f)`** arrive in the typed tree as `sort_keyed(list, keys,
reverse)`: the checker already computes the key list in guest code
(`buffer_operations.zig`). The new core:
- builds that loop (a direct or `call_indirect` call per element, §5.1);
- calls the port of `myl_native_list_sort_keyed`:
  - pack keys into order-preserving `u64` words;
  - use a counting sort when the key range is below `n`;
  - otherwise sort `(word << bits | position)` as `u64`;
  - use a stable merge over `(word, position)` for text and tuple keys.
- permutes the records by the resulting positions with one gather into a fresh list (or in
  place by cycle-walking when unique).

`sort_records` needs exactly this (`key=row_key`).

Records are not directly sortable (the checker refuses it), so nothing more is needed.

## 5. Scope additions: function values and fixed arrays

### 5.1 Function values: **in S2 (required)**

**Why:**
- `call_indirect` is one of the 35 micro rows;
- `sort_records`, `keyed_sorting`, `sorted_keys` and `lambda_sort_keys` pass `key=f`;
- 57 tests and 53 functions are blocked on them.

**Semantics.** selka has no closures: a function value names a top-level function
(lambdas are lifted by the checker). So the IR needs:
- `Type.fn(signature)`, an LLVM `ptr`;
- `func_ref` (`data` = the function index);
- `call_indirect(callee, args)` with the internal calling convention.

`func_ref` is a constant, and `call_indirect` of a known `func_ref` (directly, or through a
phi of constants after unswitching) is rewritten to `call` before inlining. For
`call_indirect`, `function = affine_a if seed % 2 == 0 else affine_b` is loop-invariant:
S0's unswitching gives two loops with direct, inlinable calls. That is the old core's 1.04×
Zig and should come out below it.

**Cost:** about 0.5 day in the IR, builder and emitter. Function values are not managed (no
RC).

### 5.2 Fixed arrays `[N]T`: **in S2, as a parallel lane's second half (recommended)**

**Why:**
- the third-largest refusal (142 functions, 93 first-blocker tests, 118 in files that
  otherwise need only S2 features);
- no row needs it, but the S2 coverage sweep is the go/stop evidence, and fixed arrays are
  cheap in this core.

**Representation.** `[N]T` is a value aggregate, which is exactly S1's records with N equal
fields:
- `Compound.array: {elem, N}` reuses the record layout helpers (stride, alignment, `words`)
  and V-1's representation rule;
- at most 4 words go in registers as an LLVM `[N x T]` struct value;
- larger arrays are memory-backed slots (V-1's memory-backed values: `sret`, read-only
  pointer parameters, in-place `record_set` when the other readers have run).

**Operations:**
- `array_get(a, i)` is a GEP plus a load, bounds-checked against the constant `N`, so the
  S0 facts prove most checks;
- `array_set(a, i, v) → a'` is the typed tree's `replace`;
- negative indices use the list rule (`array_negative_index`);
- arrays inside records and lists are inline (`list_get_field` paths gain an `index` step);
- managed elements are counted per element, like record fields.

**Estimate:** about 1 lane-day after step 0.

**If the user prefers a smaller S2:** drop fixed arrays to S3. Coverage then stays about
142 functions lower, and the 26 `s2+fa` files in §6 move out.

## 6. Conformance: the S2 set

**Method.** The S1 result file lists every unsupported test's first blocking feature, per
file. A file enters the S2 set when all its blocking features are S2 features. The
classification is in `experiments/new-core-s2-design-20261005/conformance_groups.py`; run it
against the next `conformance.py --set all` output to refresh it.

Grading follows S1 §13: per test function, against the old core, at debug and release. A
test whose second blocker is outside S2 stays "unsupported"; the exit check then requires
**0 mismatching** and the counts reported, as S1 did.

**S2 core: 80 files, 397 tests unsupported today.**

*Dict and set (37 files):*
- `borrowed_roots`, `collection_read_callbacks`, `dict_comprehensions`,
  `dictionary_hash_index`, `dictionary_hashing`, `dictionary_views`;
- `discard_names`, `gc_footprint`, `live_view_snapshots`, `mut_dictionary_arguments`;
- `python_comprehension`, `rc_box_writeback`, `rc_compact_journal`, `rc_dictionary_keys`;
- `rc_dictionary_loops`, `rc_dictionary_tails`, `rc_dictionary_text_loops`,
  `rc_dictionary_views`;
- `rc_field_transfers`, `rc_journal_types`, `rc_mut_payload_snapshots`, `rc_named_releases`;
- `rc_nested_read_loans`, `rc_plain_replacements`, `rc_range_key_anchors`,
  `rc_semantic_history`;
- `rc_semantic_publication`, `rc_view_receivers`, `rc_writeback_moves`;
- `scalar_dictionary_publication`, `sets`, `migrated/managed_values`, `python_values`,
  `python_collections`, `record_field_snapshots`, `text_views`, `standard_json` (see the
  import note).

*Bytes (24 files):*
- `byte_buffer`, `byte_buffer_from_list`, `byte_iteration_reductions`, `byte_range_fusion`;
- `byte_ranges_llvm`, `byte_views`, `embed`, `immutable_equal`;
- `python_bytes`, `rc_borrowed_results`, `rc_buffer_loops`, `rc_byte_loop_versions`;
- `rc_byte_receivers`, `rc_interval_anchors`, `rc_loop_guard_context`,
  `rc_loop_operand_isolation`;
- `rc_mut_list_aliases`, `rc_owning_element_borrows`, `rc_plain_field_loans`,
  `rc_readonly_bytes`;
- `rc_readonly_calls`, `constant_list_image`, `migrated/python_surface`,
  `python_text_surface`.

*Text (11 files):*
- `constant_methods`, `python_split_scalar`, `python_strings`, `standard_strings`;
- `text_index`, `text_literal_index`, `text_scanning`, `tuples`;
- `migrated/python_format`, `print_rendering`, `format_specs`.

*Sort and list leftovers (8 files):*
- `rc_fresh_loop_roots`, `rc_temporary_lifetimes`, `scalable_sorting`,
  `generator_arguments`;
- `field_augmented` (`extend`), `python_expressions`, `option_equality` (`parse_float`),
  `contracts` (print options).

**With function values: +12 files, 65 tests.**
- `callback_slots`, `callbacks`, `keyed_sorting`, `lambda_sort_keys`, `sorted_keys`;
- `option_niche`, `rc_borrowed_calls`, `rc_borrowed_loops`, `rc_borrowed_readonly_entries`;
- `rc_call_lifetimes`, `rc_collection_builtins`, `migrated/structural_constraints`.

**With fixed arrays: +26 files, 118 tests.**
- `aggregate_refs`, `array_negative_index`, `array_places`, `array_writes`;
- `backlog/const_lengths___*` (2), `dictionary_range_keys`, `expected_type_inference`;
- `loop_rebinding`, `migrated/generic_arrays`, `migrated/surface_statements`,
  `mut_argument_places`;
- `mut_reference_roots`, `nominal_bodies`, `nominal_instances`, `number_literals`,
  `python_arrays`;
- `rc_aggregate_values`, `rc_glue_values`, `rc_match_scalars`, `rc_plain_aggregates`;
- `rc_plain_retains`, `rc_read_loans`, `rc_readonly_managed_calls`,
  `rc_scalar_replacements`, `value_equality`.

**Both: +2 files, 18 tests.** `migrated/generic_inference`, `operand_snapshots`.

**Total in scope: 120 files, 598 of today's 735 unsupported tests.** Expect 70–85% of them
to become supported. The rest have second blockers (generics, a capability) and stay
reported, not failed.

**Import note.** 15 files above import a module:
- `standard_json`, `standard_strings`, `constant_methods`, `embed`, `number_literals`,
  `value_equality`, `callback_slots`;
- `keyed_sorting`, `sorted_keys`, `migrated/{generic_arrays, managed_values, python_format,
  python_surface, structural_constraints, surface_statements}`.

S1 already grades their tests that do not call into the imported module (R-3). Tests that
call stdlib functions (`json`, `strings`) stay excluded until S3, by name filter in
`conformance.py`.

**Stays excluded, with the reason:**
- **Capabilities and test parameters** (`capability_fields`, `rc_capability_values`,
  `test_capabilities`, `properties`, `rc_contract_results`, `rc_inert_returns`,
  `error_traces`): S3.
- **Float math builtins** (`f64_sqrt`, `trunc`, `floor`, `sin`, `cos`, the
  `u64`↔`f64` conversions): `rounding`, `float_constants`, `float_environment`,
  `float_integer_casts`, `integer_float_rounding`, `math_trig`, `rc_record_field_reads`,
  `python_core`. These are LLVM intrinsics and cost about an hour; **recommended as a lane-F
  stretch** (§8), which would add 16 tests.
- **`shift_right`** (`stable_sorting`) and **`saturating_add`** (`checked_arithmetic`): the
  same stretch, small.
- **Behaviour the new core refuses by choice in S1 (V-2):**
  - writes through a receiver whose place an argument rewrote: `rc_empty_frames`,
    `rc_inert_receivers`, `rc_loop_uniqueness`, `rc_owned_values`,
    `rc_plain_record_writes`, `rc_site_eliminations` (1 test);
  - writes to a list while it is iterated: `iteration_identity`, `rc_nonheld_captures`,
    `rc_pin_elide`, `root_liveness`;
  - conditional `mut` rebinding: `mut_rebinding`;
  - recursive-value equality: `recursive_values` (3).

  These need a user decision (S1 §15). S2 does not change them.
- **Generics, arenas and imports:** unchanged from S1 §9/§11 and R-3.

## 7. Rows: the features each needs and the split programs

Like S1 (`test/core/row_*.selka`), each row is a single-kind program. Its body is the
benchmark kind copied verbatim. The setup is the benchmark's setup, reduced to what that
kind reads. The timing comes from `runtime_bench_now` through `--link`.

**Checksums.** The oracle is the old core's build of the **unmodified** `main.selka` for the
same row, size, iteration count and seed. The old core's checksum must equal the split
program's. The setup is the same computation, so a mismatch is a bug in either core.

**Text rows.** The text benchmark imports `strings` and `json` (S3/S4). The split programs
replace `strings.repeat(t, n)` with a local `repeat` (a `join` of a comprehension) that
produces the same string.

| Row | Split program | Needs |
|---|---|---|
| `dict_lookup` | `row_dict_lookup.selka` | dict int→int; `get(k, d)`; `dict` parameter (borrowed) |
| `dict_lookup_str` | `row_dict_lookup_str.selka` | the above with `str` keys, `str(j)`, `list[str]` |
| `dict_update` | `row_dict_update.selka` | fill, fused get/set (one probe, §2.4), `items()` with two names |
| `dict_update_str` | `row_dict_update_str.selka` | the same with `str` keys, `in` plus `[]` (fused) |
| `set_dedup` | `row_set_dedup.selka` | `set()`, `add`, iteration, `max` |
| `sort_int` | `row_sort_int.selka` | `list_sort` (`i64`) |
| `sort_records` | `row_sort_records.selka` | function value `key=row_key`, `sort_keyed`, list of records |
| `call_indirect` | `row_call_indirect.selka` | `func_ref`, `call_indirect`, unswitching on it |
| `bytes_scan` | `row_bytes_scan.selka` | `bytes(list)`, byte iteration, `^` (vector lowering on `u8`) |
| `string_equal` | `row_string_equal.selka` | `str ==` inline, `repeat` (local), `+`, `str(int)` |
| `string_search` | `row_string_search.selka` | `find`, non-ASCII needles (`"absentΩ"`, `"é"`), scalar index |
| `string_split` | `row_string_split.selka` | `split(sep)` (fused loop), `encode()` borrowed, `join` |
| `string_join` | `row_string_join.selka` | `join`, `encode()` |
| `int_parse` | `row_int_parse.selka` | `int(text)` fast and slow paths, `+=` on `str` |
| `int_format` | `row_int_format.selka` | `str(int)`, `encode()`, byte iteration |

**Measurement.** `measure_rows.py` from S1, on CPU 10, against the frozen Zig ReleaseSafe
and Rust binaries in `runtime-baseline-20261003/.selka-cache/runtime-expanded/runner/bin`:
- cycles per element at both sizes;
- count updates in innermost loops, which must be 0 for every row except
  `alloc`-shaped work.

**Gate per row:** ≤ 1.10× Zig ReleaseSafe. A row that misses is reported with its counter
evidence, as S1 did, and does not block S2's exit.

## 8. Lanes

**Step 0, IR first** (integrator, about 1–1.5 agent-hours). `ir.zig` is frozen after it.

*Types:*
- `Compound.dict{key, value}`;
- `Type.bytes`;
- `Compound.array{elem, n}`;
- `Compound.fn(signature)`;
- `str_view` (SSA-only).

*Ops:*
- dict: the §2.4 table;
- text: `str_char`, `str_width`, `str_code`, `str_append`, `str_append_char`, `str_slice`,
  `str_view_of`, `str_from_view`;
- lists and arrays: `list_sort`, `array_get`, `array_set`;
- functions: `func_ref`, `call_indirect`;
- the op property `consumesOperand0`, which `own.zig` phase A reads.

*Verifier rules:*
- a `dict_insert` probe comes from a `dict_find` of the same dict;
- `str_view` operands only where admitted;
- `call_indirect` signatures.

*Files:*
- `print.zig` support;
- emitter stubs;
- **new files with dispatch stubs**: `build_dict.zig`, `build_text.zig`, `build_fn.zig`,
  `emit_dict.zig`, `emit_text.zig`, `emit_fn.zig`, `runtime/core_dict.c`,
  `runtime/core_text.c`, `runtime/core_sort.c`;
- `build.zig` and `emit_llvm.zig` gain only the calls into them;
- `driver.zig` compiles the three new C files into the cached runtime object.

*Exit:* test-core green, and a hand-built-IR test per new op.

| Lane | Model | Owns (disjoint) | Depends on | Exit check | Estimate |
|---|---|---|---|---|---|
| **D: dictionaries and sets** | Opus | `build_dict.zig`, `emit_dict.zig` (the inline probe), `runtime/core_dict.c`, the dict fuse rule in a new `fuse_dict.zig`, dict facts in `facts.zig` (its dict section only), `test/core/row_dict_*.selka`, `row_set_dedup.selka`, `test/core/d_*.selka` | step 0 | the 5 rows build, match and are measured; the dict and set files of §6 at 0 mismatches; fuzz extended with dict programs (aliasing, `mut`, deletion, iteration traps) clean; leak check 0 | 4–5 agent-hours |
| **T: text, bytes, numbers** | Opus (the cursor, views and ownership of `str_append` are subtle) | `build_text.zig`, `emit_text.zig`, `runtime/core_text.c` (header flags, hash, ASCII table, cursor, slices, `split`/`find`/`join`/`replace`/…, `int_parse` C path, `int_format`, float text stretch), `fuse_text.zig` (`ch ==` literal, `+= ch`, fused split), `test/core/row_string_*.selka`, `row_bytes_scan.selka`, `row_int_*.selka`, `test/core/t_*.selka` | step 0; D's string hash function (T owns `myl_core_str_hash` and D calls it) | the 7 text rows build, match and are measured; the bytes and text files of §6 at 0 mismatches; `str_view` never escapes (verify build asserts); Unicode cases (mixed ASCII, 4-byte scalars, empty, at least 256 bytes non-ASCII indexing) | 5–6 agent-hours |
| **F: functions, sort, fixed arrays** | Sonnet | `build_fn.zig`, `emit_fn.zig`, `runtime/core_sort.c`, `build.zig`/`emit_llvm.zig` **only** for the `array` cases (array types reuse the record paths V owns; F is the S2 owner of those paths), `test/core/row_call_indirect.selka`, `row_sort_*.selka`, `test/core/f_*.selka`; stretch: the float intrinsics and `shift_right`/`saturating_add` | step 0 | `call_indirect`, `sort_int` and `sort_records` build, match and are measured; the function-value and fixed-array files of §6 at 0 mismatches; `call_indirect` of a known target becomes a direct call (IR test) | 3–4 agent-hours |

**Shared files.**
- **`own.zig`:** step 0's `consumesOperand0` property covers the dict, `str_append` and
  `list_sort` updates. A lane that needs more (D: the promotion rule for `dict_entry_*`
  borrows) sends a patch through the integrator, as `ir.zig` changes do.
- **`conformance.py` pins and `test-core` list:** lanes only append (R-4).
- **`coverage.py` refusal names:** the integrator.

**Order.**
1. Step 0.
2. D, T and F start in parallel.
3. T publishes `myl_core_str_hash` and the string header flags in its first commit (about
   30 minutes in), because D's string-key paths call them; D works on integer keys until
   then.
4. F's `sort_records` needs `call_indirect` (its own) and records (S1).

**Total:** about 13–17 agent-hours across three lanes plus step 0. With 3 lanes in
parallel, roughly 6–7 hours of wall time. Calibration: S1 took about 5 agent-hours across
4–5 lanes. S2 has more runtime C to port (dict, text, sort: about 2.5k lines of the old
core's algorithms) but simpler IR.

**Stop conditions:** S1's R-5 unchanged. A test-core run over 5 minutes is a stop, so the
row programs' default sizes stay small, as S1's do.

## 9. Measurement and correctness plan

**Differential fuzz** (`fuzz.py`) gains, at debug, release and verify:
- dict and set programs: random insert, delete and lookup sequences; aliasing `b = a` then
  writes; `mut` dict helpers; iteration with and without size change (the trap);
- string programs: random ASCII and non-ASCII strings, slicing, `find`, `split`,
  concatenation in loops, `int()` of random digit strings including the 19-digit edges.

**Verify builds also assert:**
- the dict probe invariant: an insert's probe slot is EMPTY at insert time;
- `count == 1` before every in-place `str_append` and dict update (S1's form-1 assertion).

**The dict layout experiment** is reproducible with `run.sh`. Before lane D's merge,
re-measure the chosen layout with D's real emitted probe against `old` on CPU 10. The
expected order: sparse and string lookups at least 1.8× faster than old's shape; dense
`dict_update` within 1.3× of `cpython`'s shape.

## 10. Risks and open questions for the user

No question below changes language behaviour unless it says so.

1. **Go/no-go and scope.** The recommendation is S2 with function values (required by the
   35-row check) and fixed arrays (cheap, and +142 functions of coverage). Do you want fixed
   arrays in S2 or deferred to S3?
2. **Hashing without a seed** (PY-DICT-2) stays. The table is deterministic, so a
   hash-flooding input is possible: adversarial keys could make lookups linear. Python
   randomizes per process. Seeding would change no answer (iteration is insertion order
   either way); it would only make performance vary from run to run, which the benchmarks
   dislike. **Keep unseeded** unless you want
   flood resistance; that is your call.
3. **Short strings: not in S2.** Under one count, an inline short-string form makes every
   `str` a 16-byte value and puts an "inline?" branch in every retain, release, hash and
   data access. S2 instead uses:
   - immortal one-scalar ASCII strings;
   - size-class blocks (O-2a: about 18 cycles to allocate and free);
   - SSA-only views for non-escaping slices and split pieces.

   Re-decide at S3 with `word_count`/`csv_aggregate` profiles. The old plan (WP-7 step 3)
   already required a separate go-ahead for an inline form.
4. **Borrowed `str` parameters that admit views (§3.5)** would let `score(part)` take a
   split piece without a copy. That is an ABI choice: a `str` parameter becomes `(ptr, len)`
   plus an optional owner. It changes no behaviour, but it touches every `str` call. S2
   admits views only to runtime helpers and inlined callees. Do you want the ABI change
   evaluated in S2 if `string_split` misses the gate?
5. **Random access into long non-ASCII text** is O(n/32) per index without the old core's
   sample array (§3.3). Correct, but asymptotically slower for that one pattern. Accept, or
   port the samples?
6. **The 14 tests the new core refuses by choice** (S1 V-2: writes through rewritten
   receivers, writes to a list while it is iterated, conditional `mut` rebinding) stay
   refused. Deciding them is a language decision (D1 and COW-MUT-REBIND-1 territory) that S2
   does not make.
7. **Risk: the old core's SPEC tags for runtime protocols** (DICT-GETORPUT-1, PY-DICT-4,
   RC-DICT-SCALAR-INSERT-1, text views) describe old-core mechanisms. The new core meets
   their observable parts but not their mechanisms, so S5's deletion must retire those
   bullets, not port them.
8. **Risk: dense-key rows.** On the fixture's sequential integer keys, the CPython-shaped
   index is 20–37% faster than the chosen layout (§2.2, item 1). If `dict_update` misses the
   gate, the levers in order are:
   - builder-known capacity;
   - the scalar-probe rebuild;
   - (fixture-shaped, not recommended) dense-key specialization.
9. **Missing measurement.** The experiment is C with hand-written probes, not the new
   core's emitted code. The layout ranking is the decision input; the rows' final numbers
   come from lane D. The `word_count` small-table gap (+23–31%) is measured but its fix (the
   no-index scan below 8 entries) is not.

## 11. Integrator review (2026-10-05)

- **The S2 gate rows test the layout's weak case.** `dict_lookup`, `dict_update` and `set_dedup` use dense sequential keys, where the CPython layout measured 20–37% faster than `hybrid` (§2.2 reading 1), and `word_count` is a tiny table, where `hybrid` is 23–31% slower until the scan-below-8 path exists. `hybrid` is still the right default for real programs (random and string keys, 1.5–2.6× faster), but:
  - Keep the dictionary IR operations (§2.4) independent of the layout, so the table can be swapped without touching the builder or the facts.
  - Lane D measures the rows against the L1 gate (Zig ReleaseSafe) as soon as `get`/`set` work. If a dense-key row misses the gate with `hybrid`, the first remedy is builder-known capacity and the cheap-rebuild path. The fallback is the CPython layout behind the same operations. Record the decision with the numbers here.
  - Never tune the hash to the fixtures' sequential keys (WP-10e).
- **S2 does not start without the user.** §10's questions go to the user with the S1 summary.

## 12. User decisions (2026-10-05)

The user accepted every recommendation:
1. **S2 goes ahead,** with function values and **fixed arrays in S2** (lane F).
2. **Hashing stays unseeded** (PY-DICT-2): it is deterministic, and the flooding risk is accepted.
3. **Short strings are not in S2.** They are re-decided at S3 with profiles.
4. **A `str` parameter that accepts views** (an ABI change) is evaluated in S2 **only if `string_split` misses the gate.**
5. **O(n/32) random indexing into long non-ASCII text is accepted.** The sample array is not ported.
6. **Language change, `MUT-OVERLAP-RECEIVER`:** an assignment or update whose receiver place overlaps a `mut` argument evaluated in the same statement, for example `items[f(mut items)] = v`, `m.stack[grow(mut m)] = v` or `rows[0].append(clear(mut rows))`, is a compile error. It extends D3's `E_MUTATION_OVERLAP`. A separate front-end lane implements it in the shared checker with SPEC, docs and `tests/lang` updates; the new core then has nothing to lower.

7. **Language change, `MUT-REBIND-CALLER-1`** (decided 2026-10-05):
   - Rebinding a `mut` list, dict or set parameter as a whole reaches the caller, as it already does for `mut` records and tuples (VALUE-SEMANTICS-3/11). `mut` means "this is the caller's variable" for every type.
   - Fixed arrays keep `E_ASSIGNMENT_TARGET`.
   - It replaces `COW-MUT-REBIND-1`.
   - In the new core, the by-value `mut` ABI writes back the final value; S1 V-2's detach logic and its refusals go.
8. **D1 holds regardless of sharing** (decided 2026-10-05):
   - A `for` loop over a place re-reads it every step and sees writes made during the loop, whether or not the payload is shared. A copy taken before the loop is unaffected.
   - This is the accepted D1. The old core's shared-case answer was an accident.
   - `iteration_identity.selka`'s named-snapshot test changes to 10.
   - The old core moves first (package S2-Lb, which takes over the one-count plan's C4 front-end half). The new core follows (S2-I, per s1 §15.1).

Packages, order and gates: `docs/audits/new-core-s2-implementation-plan-2026-10-05.md`.

## 13. As built in S2-0 (Wave A, 2026-10-05)

This is the IR foundation. Source lowering for the new features remains behind precise
`E_CORE_UNSUPPORTED` refusals until the Wave B packages fill the dispatch files. The
coordinator freezes `ir.zig` when accepting S2-0; subsequent changes go through it.

**Types and layout.** `Type.bytes` is an 8-byte counted block pointer. It admits
`list_len` and `list_get` (the latter returns `u8`), and shares the string header/data
layout. `Compound.dict{key, value}` is an 8-byte counted pointer; no operation exposes
index slots, control bytes or another table-layout detail. An option of either type
uses the existing null-pointer niche. A set is a dictionary with `.void` values.

`Compound.array{elem, n: u32}` is inline at `n * size(elem)` bytes, aligned like its
element. It is managed exactly when it has at least one managed element. Arrays over
four words use the existing pointer-argument and `sret` ABI. `FieldPath` steps may select
constant array indices as well as record fields and union cases. `record_make` constructs
an array from exactly `n` operands of type `elem`; register construction, stores into
consumers, element-layout descriptors and retain/release traversal reuse the aggregate
paths. `array_get` and `array_set` use normalized integer indices and check against `n`;
`array_set.data` packs one extra operand, the replacement element.

`Compound.fn(Signature)` is an unmanaged LLVM `ptr`. Interning copies and compares the
parameter types and all signature metadata. `func_ref.data` is an internal function
index; it is a constant, not a value operand. `call_indirect.a` is the function value
and `data` packs the argument list. The verifier checks the target's full signature,
and indirect calls use the same owned-argument bits and aggregate return ABI as direct
calls. Known-target folding and source function-value lowering remain S2-F work.

**Operations.** The twelve dictionary operations retain §2.4's operands and results.
Entry numbers and probes are `i64`, capacities and counts are `u64`. `dict_insert`
requires a `dict_find` of the same resolved dictionary and key SSA operands. When
ownership copies or merges the dictionary operand, it recomputes the probe on the new
operand before the insert, preserving that invariant.

The eight text operations have these concrete extra operands:

| operation | operands | result |
|---|---|---|
| `str_char`, `str_width`, `str_code` | `a: str`, `b: u64` byte offset | `str`, `u64`, `u32` respectively |
| `str_append` | `a: str`, `b: str` | `str` |
| `str_append_char` | `a: str`, `b: str`, `extra[0]: u64` byte offset in `b` | `str` |
| `str_slice` | `a: str`, `b: i64` start scalar, `extra[0]: i64` end scalar | `str` |
| `str_view_of` | `a: str`, `b: u64` byte offset, `extra[0]: u64` byte length | `str_view` |
| `str_from_view` | `a: str_view` | owned `str` |

`list_sort` takes `a: list`, `b: bool` reverse order and returns the same list type;
the element type determines the eventual sort specialization. Keyed sorting remains a
runtime helper composition, not another IR op.

**Views.** `str_view` is an SSA `{ptr, i64}` byte span and has no storage layout
(`size` is zero as a marker). It is unmanaged, but ownership tracks it as a borrow of
its source, keeping that source alive across every use without counting the span.
The verifier rejects it in aggregate types, phis, stores, returns and ordinary calls.
Admitted uses are `str_from_view`, byte `str_len`, and the key of `dict_find` on a
string-keyed dictionary. `Signature.views` additionally marks explicit borrowed extern-C
`str` parameters that use a `(data, byte_length)` helper ABI. A marked parameter cannot
be owned; internal signatures never admit views. This is only runtime span-helper
admission, and does not implement or change source `str` parameter ABI (decision 4).

**Ownership.** `Op.consumesOperand0()` covers list push/set/pop/sort, record and array
set, dictionary set-value/insert/remove/clear and string append/append-char. Block
updates use S1's three COW forms and verify-mode uniqueness assertions. Dictionary
copies use `dict_copy`; string copies use a full byte span followed by `str_from_view`.
Block uniqueness excludes value aggregates. Managed dictionary entry and array element
reads borrow their owners; array replacement releases its previous managed element.

**Dispatch and runtime.** New builder dispatch files preserve the prior refusal reasons.
The three emitter dispatch files provide valid LLVM for every new operation. Fixed-array
accesses, internal function references/calls, UTF-8 `str_char` and span materialization
execute in hand-built IR. Other new operations call the placeholder runtime, which exits
1 with `E_CORE_UNSUPPORTED` before an answer is observable. The character helper handles
ASCII and 2–4-byte scalars; the immortal ASCII table and full text fast paths remain S2-T.
`driver.zig` embeds all four C files, concatenates them into one translation unit, and
hashes that complete source for the cached runtime object. No old-core runtime is linked.

**Verification evidence.** `src/core/s2_ir_test.zig` provides one hand-built test per new
op, LLVM compilation/execution, wrong operand/result rejection, COW probe provenance,
view admission and lifetime, managed-array layout and cleanup, and owned indirect calls
with register and `sret` returns. Evidence and development-loop logs are under
`experiments/new-core-s2-20261005/wave-a/s2-0/`. Full conformance, rows, kernels, fuzz and
coverage are graded by the coordinator after S2-La/S2-Lb merge, as the Wave A plan requires.

## 14. D1 in the shared front end and old core (S2-Lb as built)

The checker now prepares managed iteration sources in `iteration_place.zig`, used
by ordinary `for`/`enumerate` and the prelude desugars. A loop whose body may write
below its stable source root refreshes the place before every element and on every
continued/final step. Each indexed ancestor has an exact entry-length
`iteration_check`; each path index is evaluated and normalized once at entry.
This makes shared-payload writes, writes through `mut` callees, and record-field
write-back visible while preserving independent copies taken before the loop.
The back edge reads the root, which also prevents last-read field moves from
removing a value the next iteration needs.

For a live list or mutable byte buffer, the terminal guard compares its current
length to the last observed length: growth updates the bound and is visited;
a decrease traps `R_LIST_ITERATION_MUTATION`. Growth followed by shrink on a later
step traps even when the new length equals the entry length. Guards observe length
at iteration boundaries, so a transient grow-and-shrink entirely within one body
is not detected when the observed length is unchanged. Dictionaries and sets,
and every indexed ancestor, retain exact length equality. `break` bypasses the
next guard, as before. `reversed` retains its fixed bound and exact terminal guard.

Direct syntactic assignment to the root in the body (including a root target in
destructuring) selects an independent entry snapshot. Field assignment to a
stable record root stays live. A `mut` callee's write-back, including whole
collection rebinding under `MUT-REBIND-CALLER-1`, stays live; the exception is a
syntactic root assignment in the body, not a transitive call-effect rule. The
combined callee-rebinding tests are in
`experiments/new-core-s2-20261005/wave-a/s2-lb/mut_callee_rebinding.my`, to run after
S2-La and S2-Lb merge.

Non-place sources remain owned at entry. Immutable string/bytes places refresh
too, including same-length field replacement; terminal lengths remain exact
(Unicode scalar count for text), and managed indexed ancestors retain guards.
Fixed-array places follow D1 too: stable local and
parameter roots are read directly, and fields/indexed places refresh each step.
Their terminal length needs no guard, while managed indexed ancestors retain
exact-length guards. Named copies stay independent; syntactic root assignment
still selects an entry snapshot. The old array tests expected snapshot iteration
after element writes; these were amended because §12's D1 decision has no array
exception. Read-only loops keep the entry-borrow path.
Direct collection forms of `sum`, `any`, and `all` use the shared source/guard
helpers; their numeric/Boolean folds call no user callback and have no
source-writing body, so the entry borrow
is sufficient. Generator folds and comprehensions can call user code; both the
dedicated unfiltered form and generated loop form use the same D1 helper.
`iteration_effects.zig` follows syntax IDs through statements and expressions,
including produced values, filters and nested clauses. Generated statement
spans cover only a clause/filter, so span-based scans were insufficient.
Assignment expressions are unavailable, so a comprehension cannot syntactically
rebind its source root; whole-root write-back through a mut callee stays live.
C4's shared-front-end/old-core semantic work moved from WP-5 to
S2-Lb; the remaining RC hold-count re-plumbing stays paused. Existing lifetime
holds remain for hidden receivers and snapshots.

Evidence and the package's gate results are in
`experiments/new-core-s2-20261005/wave-a/s2-lb/`.


## 15. Caller variables and receiver overlap (S2-La as built)

The shared checker enforces `MUT-OVERLAP-RECEIVER-1` on complete receiver and
explicit mut-argument paths. Equal roots with a prefix relationship overlap;
other roots and provably disjoint constant siblings remain legal. Readonly
arguments keep value snapshots. The located diagnostic asks for a separate
call statement and provides structured `selka fix` edits when that rewrite
is certain. Existing fixtures and the runnable mut documentation use the
accepted two-statement form.

A whole assignment to a mut list, dictionary or set parameter now writes the
caller variable. Per-parameter caller-storage inference follows whole-variable
forwarding through direct calls, recursion and callbacks; interior stores do
not make the outer parameter rebound. Direct parameters that never rebind keep
the mutable-payload ABI and `RC-MUT-UNIQUE-1`. Function values use uniform
caller-storage adapters while each target retains its canonical direct ABI.
The inferred mask survives bytecode, module interfaces (format v4), semantic
stand-ins (format v5), archive comparison and native test facts. Imported
producer authority is restored before adaptation. Reserved callback identities
and synthetic metadata keep warm, selective and whole/module emission equal.

Interior mut arguments capture the selected leaf before later arguments run.
At call entry, an unchanged leaf receives writes through its actual storage;
a replaced leaf uses an owning fallback for the captured value. Parent and
payload lifetimes stay protected. GC roots distinguish whole slot references
from borrowed call results. A whole-local mut argument reloads the current
caller variable after argument evaluation under RC, GC and callback calls.

The new core's by-value mut ABI writes back the parameter's final SSA value on
every return. Detachment tracking and conditional/loop rebinding refusals are
removed. A changed ancestor of a captured interior mut path receives the
precise refusal `interior mut argument ancestor changed during later argument
evaluation`. This closes a pre-existing S1 wrong answer without adding an IR
shape; conditional and disjoint sibling writes under that root can also be
refused conservatively. Stable interior paths and whole-current-root reads
remain admitted. Fixed-array whole rebinding keeps `E_ASSIGNMENT_TARGET`.

Package evidence is under `experiments/new-core-s2-20261005/wave-a/s2-la/`.
The external Lox checkout requires four documented migrations and was left
untouched, as authorized by the user. The old frontend's pre-existing managed
origin overflow at parameter position 16 is reported rather than widened.
Aggregate Wave A qualification is recorded in
`experiments/new-core-s2-20261005/wave-a/REPORT.md`.


## 16. Live-place iteration and text ownership (S2-I as built)

The accepted checker already expresses D1 as a refreshed hidden receiver at each
step, with an entry snapshot when the body syntactically rebinds the root. The
new builder now accepts those refresh assignments instead of refusing writes
through its former syntactic alias table. Place write-back still follows the
existing SSA receiver paths. No frozen IR shape changed.

An `iteration_check` on a refreshed receiver loads the current length, compares
it with the entry length and branches to a located `R_LIST_ITERATION_MUTATION`
trap on a difference. Strings use scalar length and dictionaries use dict length;
stable entry receivers omit the guard. Element writes, same-length replacements
and appends followed by break/continue follow the accepted old-core behavior.
Facts belong to each refreshed SSA value, so a changing place gets no immutable
entry-length claim. The 20 S0/S1 benchmark definitions remain identical.

The exact extern helper `myl_core_text_encode(str) -> bytes` is a pointer identity
when its signature borrows the source. Ownership ties borrowed byte uses to that
source and retains an escaping byte value. This removes allocation and count
traffic for a borrowed encode while preserving an independently escaping result.
Record phis remain owned. The existing leak fixture helper now checks exit status
and stdout as well as stderr, including its intentional status-255 trap fixture.

Package commands, results and the implementation commit are recorded in
`experiments/new-core-s2-20261005/wave-b/s2-i/README.md`.
## 17. Functions, sort and fixed arrays (S2-F as built in Wave B)

Source function values map to the frozen `func_ref` and `call_indirect` IR.
Callback signatures use the direct functions' by-value copy-in/copy-out mut
ABI and the full u64 owned-argument mask. Arguments evaluate in source order;
whole mut places reload at call entry, while a later ancestor rewrite of a
captured interior argument retains the accepted precise refusal.
Functions with mut fixed-array or record parameters remain checker-refused
as values under PY-ARRAY-MUT-1; their direct calls preserve caller write-back.

A resolved function constant becomes a direct call before inlining. A
2-target phi of constants whose arms share one scalar branch is expanded to
ordinary direct-call control flow using the original condition. The existing
S0 unswitcher can then separate the inner loops, and leaf inlining exposes the
arithmetic. The inliner also clones blockless `func_ref` constants returned by
choosers and folds their following calls. Dynamic targets remain indirect.

Unkeyed sorting now uses the consuming `list_sort` op and S1 ownership's COW
forms. `core_sort.c` independently ports the old core's stable natural-run
powersort, including signed/unsigned/narrow integers, NaN-last float ordering,
text and bytes. Reverse comparison preserves tie order. Keyed sorts use the
already checked guest key-building loop, counting/packed numeric-key paths,
and a stable merge for text, bytes and flat tuple keys. One sorted owning
copy leaves every alias unchanged. The runtime takes exact source/key strides
packed in a u64: unmanaged aggregates carry no reference-layout descriptor,
so their stride must never be inferred from the `reserved` pointer.

Fixed arrays map to `Compound.array` and use aggregate construction, equality,
place rebuilding and the frozen `array_get`/`array_set` ops. Signed negative
indices normalize once before a mut place is captured; enum table indices
extract the enum tag. Array element writes are value updates and mut returns
write back the final array. Whole mut-array rebinding remains checker-refused.
The accepted checker refreshes array places during D1 iteration, and each
lowered array read observes that current SSA value. Earlier named copies stay
independent. Managed array elements retain S2-0's aggregate ownership rules.

Package commands, results, repairs and source commits are recorded in
`experiments/new-core-s2-20261005/wave-b/s2-f/README.md`.

## 18. Ordered dictionaries and sets (S2-D as built)

The runtime retains the hybrid layout of §2.3: dense naturally aligned entries,
cached full hashes, a separate half-full 16-byte control index with 32-bit entry
numbers, and a hash-filtered scan for eight entries or fewer. Deletes mark both
the index and the dense-entry bitmap. A rebuild compacts live entries without
changing their order and uses the same triangular group sequence as lookup.
Scalar rebuilds find an empty group without comparing keys. Hashes are fixed
production hashes; no sequential-key specialization is used. Literal and
comprehension capacity hints reach `dict_new`; counted fill-loop hinting remains
a possible remedy if a dense row misses the gate.

Integer probes and cached string probes have an LLVM first-group path; later
groups and small tables use the C path. Structural record, array and union keys
hash fields recursively, ignoring padding and inactive union payloads. Borrowed
string-view lookups hash and compare the byte span directly. Pure probes of the
same dictionary and key SSA values share a dominating probe, including across
the default-value branch. Ownership retains borrowed managed entries before an
update and uses the existing dictionary copy operation on shared receivers.
The runtime joins dictionary children to the iterative release worklist.

Length and scalar key/value hulls are facts of each immutable dictionary SSA
value. Removal and insertion update lengths; insertion's lower bound increases
only where a missing probe is proved. Phi joins widen rather than assume a
loop's dictionary stays fixed. Verification checks the probe provenance and
unique count before consuming updates, as well as emitted length and hull facts.

**Measured layout decision.** `layout_real.py` extracts the production LLVM
first-group probes from emitted dictionary rows and links them with the complete
new runtime into the reference dense, sparse, miss and churn workloads using
`zig cc -O3 -march=native -flto`. Measurements use CPU 10, the shared CPU lock,
and three interleaved rounds; all layouts have matching checksums. These are
user cycles per operation for the old table shape and the emitted hybrid:

| Workload | 4096 old | 4096 hybrid | 65536 old | 65536 hybrid |
|---|---:|---:|---:|---:|
| dense integer lookup | 9.57 | 13.18 | 26.38 | 19.83 |
| integer update, two probes | 28.72 | 56.90 | 54.64 | 72.73 |
| integer update, one probe | 35.90 | 77.09 | 48.11 | 67.03 |
| set deduplication | 25.65 | 26.08 | 21.20 | 27.31 |
| sparse integer keys | 26.73 | 17.38 | 56.48 | 39.37 |
| deletion churn | 70.91 | 81.22 | 83.92 | 86.66 |
| string lookup | 45.06 | 21.44 | 98.49 | 59.44 |
| mixed-length string misses | 57.84 | 36.46 | 114.47 | 98.34 |
| tiny-word count | 58.35 | 96.72 | 59.26 | 95.77 |

The C layout control exposes the expected dense-update and small-word costs;
the five compiled-language dictionary/set rows pass the L1 gate against Zig
ReleaseSafe. Therefore the hybrid remains selected and the CPython fallback is
not triggered. Tiny-word costs remain evidence for S2-T2 and final integration,
not grounds to tune a hash to the benchmark keys. Complete size-64 controls,
candidate comparisons and row timings are retained in the package evidence.

**View precision.** The checker permits more persistent view storage than the
original §2.5 premise assumed. Existing source-place provenance supports a fresh
unshared local-root view, direct temporary iteration views, and explicit
`list(view)` snapshots. A persistent interior view must retain the original
child identity after its ancestor changes; rereading that ancestor is incorrect.
The frozen IR cannot distinguish all those identities, so the builder gives a
precise `E_CORE_UNSUPPORTED` for interior, escaping, aggregate/list-stored or
mut-argument views, explicit view/root rebinding, ordinary dictionary snapshots
combined with a persistent view, and writes through the view's mapping field.
It also refuses a dictionary snapshot returned from a view argument. These
refusals preserve the old-core result instead of creating a snapshot where a
live view is required. No IR shape or language behavior changed.

A final audit found ordinary aggregate aliases need the same boundary: storing
the dictionary in a record before binding the view makes the old core retain
the original mapping. A refresh would read the updated root instead. The
builder now validates identity after SSA construction, following dictionary
origins, copy/phi aliases, explicitly marked view wrappers and mapping
projections. It refuses ordinary record/tuple/array/union/list/dictionary stores,
returns and opaque calls that expose that mapping before or after binding. A
persistent view with conditional or unproved source provenance is also refused;
only fresh origins without exposed aliases are admitted. Direct temporary
iteration views retain the shared checker's exact receiver behavior.
The nine new identity fixtures cover those aggregate and returned cases. The
repaired source has 919 matches and 621 refusals / 1540 tests with no mismatch
in either mode; its own leak/verify sweep has 220 matches and 121 refusals / 341.
All five measured row binaries retain identical machine code after this builder
repair, so the existing row gates and layout decision remain valid.

Integration with S2-F also refuses a fixed array whose element type is a live
dictionary view, using the same type boundary as lists and ordinary aggregate
fields. The added stored-view fixture passes on the old core: a view held in
an array observes the mapping's subsequent value update. The new core reports
`fixed array storage of live dictionary views` rather than copying that view's
mapping pointer and changing its identity. Arrays containing ordinary dictionary
values remain available; their aliases are checked by the view identity analysis.

Package commands, qualification counts, implementation commit and complete
evidence are recorded in `experiments/new-core-s2-20261005/wave-b/s2-d/README.md`.

## 19. Text and bytes (S2-T1 as built in Wave B)

The 32-byte leaf header is shared by strings and bytes: count/kind at offsets
0/4, byte length/capacity at 8/16, cache metadata at 24 and bytes at 32.
STR=1 and BYTES=3; ASCII/HASHED/SCALARS/CURSOR use kind bits 8–11. The low/high
metadata words hold the deterministic 32-bit hash and scalar count. Saturated
headers are never written. `myl_core_str_hash` and `myl_core_span_hash` provide
the same unseeded hash for owned and borrowed dictionary keys.

UTF-8 scalar iteration uses a byte-offset cursor when the receiver is immutable;
a refreshed live place retains scalar lookup. ASCII characters are immortal.
Indexing and slices preserve scalar semantics, negative bounds and steps; long
non-ASCII lookup counts continuation bits in 32-byte groups with a cursor cache.
Character append fusion avoids materialization when it adds no alias. Byte
reductions load u8, widen safely and admit bounded integer XOR, with range
verification. Encode borrows the same pointer and retains only when it escapes.

Append consumes a unique receiver. Identical resolved operands use fresh
concatenation to avoid creating count=2 after a uniqueness check. Join sizes once
and uses the general short-copy path for pieces at most sixteen bytes. Split
currently builds owned pieces and a list; the proposed fused split cursor was
not implemented. The split row passes the existing ABI, so the conditional
parameter-view ABI evaluation was not triggered. SSA views retain the frozen
verifier's no-escape restrictions. These are measured implementation limits,
documented alongside remaining precise feature refusals in the exit report.

The package source is `ec44e2b6`, merged at `dd1ea75a`; its five rows, Unicode
fixtures, 50-case strict fuzz, leak/fact sweeps and qualification commands are in
`experiments/new-core-s2-20261005/wave-b/s2-t1/README.md`.

## 20. Numbers in text (S2-T2 as built in Wave B)

`build_text.number` dispatches through `build_number.zig`. Emitted LLVM supplies
an always-inline eight-digit SWAR fast path. Loads cover only the actual bytes:
1/2/3/4-byte loads for short words, overlapping four-byte loads for widths 5–7,
and one eight-byte load for width eight. Short words use a 32-bit pair reduction;
longer words use parallel pair weighting. An endpoint check avoids redundant
fallback work on invalid text. Longer numbers, separators, surrounding ASCII
whitespace and 19-digit overflow edges use the exact old-core grammar port in
`core_number.c`. The path assumes the accepted x86-64 target.

Decimal rendering and integer printing share a two-digit writer with an
integer digit-count estimate and unsigned magnitude for INT64_MIN. Fresh text
uses the T1 header and ASCII flag. Float text remains outside this implementation.
No frozen IR, persisted format or language rule changed.

Source `e5139598` was qualified after the T1 dependency merge `a7f2944a`.
The initial parse row missed; endpoint classification and short-word reduction
repaired it. The final package's seven-round new/Zig ratios at 4096/64 were
0.987/1.090 for parsing and 0.319/0.316 for formatting, with identical checksums.
All twenty S0/S1 timed kernels remain identical; only untimed `parse_number`
calls change to the helper. Commands, results, refusals and retained diagnosis
are in `experiments/new-core-s2-20261005/wave-b/s2-t2/README.md`.

## 21. S2 exit qualification (Wave B)

The full exit record is also retained in
`experiments/new-core-s2-20261005/wave-b/REPORT.md`.

Date: 2026-10-06. Branch: `codex/new-core-s2-integration`.
Accepted starting head: `72eaae74`. Final repaired compiler: merge `996d9baa`.
Wave B combined compiler: `b70a6a3f`; pre-repair S2-X evidence: `090dabd5`.
All named S2 exit gates qualify. S3 has not started; the stage stops here
for the user's go/stop decision.

One explicit planned optimization is unimplemented: the fused split cursor
of design §3.5. Split materializes owned pieces and a list. The measured
split rows pass the named exit gates; that does not waive the planned fusion.
This is an as-built deviation for the user's S3 go/stop decision. The separate
conditional parameter-view ABI evaluation was not triggered.

### Package commits and merge checks

Each package began in its own locked worktree. D, T1 and F ran in parallel with
the coordinator's I worktree; T2 started from the first I merge. At most four
build-heavy agents and two strict fuzz jobs run concurrently. No `main` merge
or push was made; the original dirty checkout and runtime reference worktree
remain intact.

| Package | Source | Qualified evidence | Integration merge | Held unit gate on resolved integration tree | Full corpus, each mode |
|---|---|---|---|---|---|
| S2-I | b68232d3 | 1b3de437 | 0563edd6 | 189/189, 169.53 s | 795 match / 0 mismatch / 745 refused |
| S2-T1 | ec44e2b6 | 4b12d578 | dd1ea75a | 191/191, 166.05 s | 897 / 0 / 643 |
| S2-F | 3465f423 | e8424a59 | 746d3b8b | 193/193, 215.87 s | 1061 / 0 / 479 |
| S2-D | 89f65316 | 62656609 | 6a918a94 | 197/197, 232.75 s | 1224 / 0 / 316 |
| S2-T2 | e5139598 | 995823e6 | b70a6a3f | 198/198, 238.76 s | 1224 / 0 / 316 |
| S2-X fact repair | 0c6029d7 | 41deb663 | 996d9baa | 200/200, 242.43 s | 1224 / 0 / 316 |

The checks ran on each fully resolved staged merge tree before its merge commit;
logs identify that Git tree and package, then the table associates the actual
merge commit. Later experiment/document commits do not change compiler inputs.
Package READMEs record exact commands, results and source commits. Per package:
held test-core, full debug/release comparison, own-file leak/fact sweeps, strict
50-case feature fuzz, S0/S1 identity or explicit parser nonregression proof,
own rows and coverage. Full old gates, 200-case matrix and all 35 were reserved
for S2-X.

### Final S2-X gate and conformance

The combined old-core gate is qualified in `integration/full-old-gate/combined-summary.json`. The final repaired full leak/fact sweep and the complete strict matrix also pass.

The full old `test` run initially had 111/115 successful steps; both failed
incremental drivers filtered out their copied fixtures because the private
TMPDIR contained `.selka-cache`. Their 5/4 candidates became 0/0. The corrected
private `.zig-cache` scratch replay passes `test-incremental` 24/24, with both
120-step and 60-step drivers at zero mismatches (64.46 s). The original
passing old tests are not repeated. QBE passes 519/519 (75.41 s); QBE build
passes 29/29 steps (3.01 s); formatting passes 2/2 (0.22 s). All reported
test-shard RSS stays within the ceiling; no overrun diagnostics. Final held formatting after the dictionary-fact edit passes 2/2 (0.24 s,
MaxRSS 47,936 KiB). The old unit/QBE roots exclude the core facts and core
tests; their accepted proof is unaffected by the repair, as independently
checked against the build graph.

The initial full strict sweep has debug 1224/0/316 and release 1223/1/316:
`dictionary_hashing::test_text_keys_count_the_same_through_one_key_object_or_many`
traps `R_CORE_FACT` only with release verification. The cause is explained: dictionary updates inherit unsettled unknown call
facts, so a loop phi permanently skips that populated back edge and asserts
length zero against actual length 27. The dictionary analogue of the existing
`pendingList` rule repairs it in `0c6029d7`; evidence `41deb663`. Six native
regressions plus an explicit IR-copy regression exercise the missing case.
The repaired package passes 200/200 held tests in 293.07 s, full conformance
1224/0/316 in both modes, its leak/fact sweep 264/0/84 in both, and strict
50-case dictionary fuzz (750 comparisons, zero failures). Its integration
checks pass: rebuild 2.16 s, held unit gate 200/200 in 242.43 s
(runner 205M / compiler 328M), and full ordinary conformance in 44.01 s.
The final full leak/fact replay on `996d9baa` passes 1224/0/316 in both modes
(exit zero, 49.99 s, MaxRSS 325,508 KiB). Separately, the wrapper incorrectly rejected documented
empty-selection status 3. It now admits only an exact empty native report with
zero counters; 16 synthetic process/report checks retain signal, blank-output
and inconsistent-status rejection. This harness repair does not qualify the
dictionary fact failure.

The full-corpus comparison uses the inherited `--set all` selection, without
`--include-arena`: it omits `arena_managed`, `arena_scopes`,
`arena_class_escape`, `arena_regions`, `rc_arena_values`, and test names
matching `*arena*`. This is the unchanged S1/Wave A comparison scope.

The final ordinary conformance run has 1540 selected test functions: each of debug and
release has 1224 matching, zero mismatching and 316 precisely unsupported.
Wave A's accepted 769 matching / zero mismatch grows by 455 matching functions.
The protected oracle is `.selka-cache/wave-b/baseline/selka`, copied with
adjacent QBE from the accepted 72 compiler before the old gate could reinstall
`zig-out/bin/selka`. The pre-language Wave A baseline executable was not used
to grade these packages. Native status/stdout/stderr and outer compiler signals
are checked; stderr-only acceptance is forbidden.

The final strict matrix qualifies all nine kinds: 1,800 accepted cases,
25,800 comparisons and 35,600 successful native executions, at most two jobs.
Every case is admitted by the oracle and compiles in debug, release and
verification modes; zero rejects, refusals, build failures, mismatches,
crashes, leaks or fact failures. RC runs its oracle once per mode/argument
pair, hence 3,600 executions rather than 2,400.

Eight kinds run on the repaired final compiler `996d9baa`. The previously
passing 200-case rebinding run on `090dabd5` is reused: all 200 complete IR/fact
dumps agree byte for byte, none contains dictionary operations, and only
`facts.zig` changed in the compiler. `integration/rebinding-reuse.json`
records that checked proof. The matrix includes the original qualification
source and proof link; its 4,000 executions are included in the total above,
with 31,600 fresh executions on the repaired compiler. The earlier dictionary
run is superseded by the final repaired-source run. Paused dispatch and the
explained repairs are retained, and no incomplete run is qualified.

`integration/fuzz-final-200/matrix.json` is complete and qualified; each kind
has its full command, source, process result, harness transcript and summary.
Elapsed seconds below are execution after build-slot admission.

| Kind | Accepted cases | Comparisons | Native executions | Seconds | Qualification source |
|---|---:|---:|---:|---:|---|
| s0 | 200 | 3000 | 4000 | 449.32 | `996d9baa` |
| s1 | 200 | 3000 | 4000 | 616.20 | `996d9baa` |
| rc | 200 | 1800 | 3600 | 393.92 | `996d9baa` |
| rebinding | 200 | 3000 | 4000 | 1351.51 | `090dabd5`, justified reuse |
| iteration | 200 | 3000 | 4000 | 874.58 | `996d9baa` |
| dict | 200 | 3000 | 4000 | 1177.99 | `996d9baa` |
| text | 200 | 3000 | 4000 | 433.00 | `996d9baa` |
| number | 200 | 3000 | 4000 | 479.25 | `996d9baa` |
| functions | 200 | 3000 | 4000 | 531.17 | `996d9baa` |

Exact commands, process results and compiler commits are retained in the
following evidence. Private cache environment and slot-admission wait are
included in the logs; quoted times describe execution after admission.

Raw evidence is retained verbatim. The archived `integration/full-old-gate/test.log`
and `integration/rebinding-reuse-facts.diff` contain their original whitespace;
`git diff --check 996d9baa` passes with only those two transcripts excluded.
Authored documentation, tools and compiler inputs have no whitespace errors.

| Exit check | Compiler source | Command/tool and retained evidence |
|---|---|---|
| Final rebuild and held core unit gate | `996d9baa` resolved merge tree | `scripts/build-slot.sh build -- zig build core`; held gate plus build slot for `zig build test-core --summary all`; `integration/merge-s2-x-fact-{build,test-core}.txt` and `merge-s2-x-fact.md` |
| Full old gate and affected setup replay | `090dabd5`, unaffected by the facts-only repair | `full_old_gate.py`: `test`, `test-incremental`, `test-qbe`, `test-qbe-build`, `fmt-check`; `integration/full-old-gate/combined-summary.json` and all step logs |
| Final ordinary and leak/fact conformance | `996d9baa` | `conformance_checked.py --set all --jobs 4 --why`, also `--leakcheck --verify`; `integration/merge-s2-x-fact-conformance.txt`, `s2-x-leak-verify-after-fact.txt` |
| Full strict matrix | `996d9baa`, rebinding reuse qualified by unchanged IR/facts | `fuzz_matrix.py --kinds dict,s1,iteration,functions,text,number,s0,rc --evidence …/fuzz-final-200 --reuse-rebinding …/fuzz-200/rebinding/summary.json`; per-kind commands/logs and final `matrix.json` |
| All35 seven-round measurement and count audit | Measured `090dabd5`; all 35 complete modules identical on `996d9baa` | `measure_all35.py --build --rounds 7 --cpu 10` under the CPU lock; `audit_all35.py`; `integration/all35.{json,txt}`, `count-audit.{json,txt}`, `count-notes.md`, `rows-after-fact.{json,txt}` |
| S0/S1 timed-kernel nonregression | `090dabd5`, extended to final by complete-module identity | `wave-a/compare_code.py` and `s2-t2/inspect_definitions.py`; `integration/code-{identity,nonregression}.txt` |
| Standard coverage and complete before/after loop attribution | Before `72eaae74`, final `996d9baa` | `wave-a/qualify_coverage.py`; `integration/coverage_loops.py`; `s2-x-coverage-standard-after-fact.txt`, `coverage-standard-after-fact/admission-proof.json`, `coverage-loops.{json,txt}` |
| Final formatting | `996d9baa` | Held gate plus build slot for `zig build fmt-check --summary all`; `integration/fmt-after-fact.txt` |

### All35 rows and count updates

All 35 rows build in both compilers; all 70 row/size pairs pass, with 2,800
successful samples and matching checksums. The final fact-repair source proves all 35 complete LLVM modules byte-identical
to the measured `090dabd5` modules; runtime, emitters, driver, native clock
and row sources are unchanged. `integration/rows-after-fact.json` records
35 successful final native builds and the qualified reuse; no measurement
or count-audit replay is needed. The complete
measured row table follows; static count-site explanations are retained in
`integration/count-notes.md`.
Seven interleaved rounds use CPU 10 under the shared timing lock, compare every
old/new/Rust/Zig ReleaseSafe checksum, and subtract startup user-cycle samples.
Both sizes 4096/64 are reported. S0 kernel identity is a permitted nonregression
proof; identical binary_search IR permits its documented layout noise. Every
other row must be at most 1.10× Zig at both sizes.

Every numeric row cell is `4096 / 64`, in CPU-10 user cycles per the listed
unit. `I/P/N` means static tagged count-store sites in timed innermost loops /
parent-exclusive loops / timed nonloop cleanup. These include initialization
and conditional release arms, and exclude opaque runtime bodies.

The count audit distinguishes timed innermost stores, parent-exclusive stores,
initialization, conditional decrement arms, saturated-header reads and opaque
callee/runtime scope. Static sites are not presented as dynamic event counts.

| Row | Unit | Old | New | Zig ReleaseSafe | Rust | New/Zig | New/Rust | I/P/N |
|---|---|---:|---:|---:|---:|---:|---:|---|
| record_reads | iteration | 24.472 / 24.496 | 17.783 / 17.632 | 23.912 / 23.910 | 17.401 / 17.262 | 0.744 / 0.737 | 1.022 / 1.021 | 0/0/0 |
| tagged_stack | iteration | 63.284 / 63.270 | 33.330 / 33.309 | 47.931 / 47.856 | 25.940 / 25.905 | 0.695 / 0.696 | 1.285 / 1.286 | 0/0/0 |
| mutate_unique | iteration | 17.138 / 17.091 | 14.577 / 14.583 | 16.960 / 16.936 | 13.169 / 13.129 | 0.859 / 0.861 | 1.107 / 1.111 | 0/0/0 |
| mutate_shared | element | 0.955 / 7.123 | 0.637 / 0.637 | 1.121 / 0.999 | 0.627 / 0.642 | 0.568 / 0.637 | 1.015 / 0.992 | 0/0/0 |
| record_construct | element | 11.627 / 11.717 | 2.304 / 2.396 | 10.494 / 11.031 | 6.902 / 7.330 | 0.220 / 0.217 | 0.334 / 0.327 | 0/0/0 |
| record_update | element | 11.719 / 11.790 | 6.183 / 6.290 | 11.161 / 11.638 | 6.904 / 7.330 | 0.554 / 0.540 | 0.896 / 0.858 | 0/0/0 |
| option_handle | element | 4.036 / 4.055 | 1.954 / 2.496 | 6.506 / 7.411 | 2.415 / 3.156 | 0.300 / 0.337 | 0.809 / 0.791 | 0/0/0 |
| result_propagate | element | 6.201 / 5.605 | 4.043 / 3.970 | 7.095 / 7.456 | 3.513 / 4.118 | 0.570 / 0.532 | 1.151 / 0.964 | 0/0/0 |
| list_scan | element | 3.847 / 4.011 | 3.968 / 4.035 | 4.569 / 4.658 | 2.703 / 2.792 | 0.868 / 0.866 | 1.468 / 1.445 | 0/0/1 |
| list_append | element | 7.239 / 14.086 | 7.068 / 9.682 | 12.283 / 16.792 | 6.200 / 10.211 | 0.575 / 0.577 | 1.140 / 0.948 | 0/2/0 |
| list_filter | element | 9.262 / 17.611 | 7.900 / 10.621 | 10.592 / 13.847 | 5.737 / 10.052 | 0.746 / 0.767 | 1.377 / 1.057 | 0/3/0 |
| alloc_short | element | 244.897 / 249.942 | 4.722 / 5.075 | 21.812 / 22.193 | 5.013 / 5.329 | 0.216 / 0.229 | 0.942 / 0.952 | unknown (manual 0) |
| alloc_retained | element | 142.927 / 152.561 | 36.249 / 37.742 | 80.661 / 78.560 | 80.263 / 82.051 | 0.449 / 0.480 | 0.452 / 0.460 | 1/1/0 |
| mutate_nested | element | 29.188 / 46.418 | 12.283 / 14.675 | 75.435 / 73.896 | 81.281 / 72.220 | 0.163 / 0.199 | 0.151 / 0.203 | 2/0/0 |
| bytes_scan | element | 0.083 / 0.246 | 1.246 / 1.736 | 1.372 / 1.815 | 1.135 / 1.201 | 0.908 / 0.956 | 1.098 / 1.446 | 0/0/5 |
| string_equal | iteration | 53.707 / 16.679 | 134.607 / 15.260 | 277.655 / 16.809 | 135.459 / 12.711 | 0.485 / 0.908 | 0.994 / 1.201 | 0/0/5 |
| string_search | iteration | 420.276 / 79.811 | 1081.894 / 89.172 | 12923.277 / 387.888 | 5584.115 / 182.514 | 0.084 / 0.230 | 0.194 / 0.489 | 0/0/5 |
| string_split | element | 201.801 / 210.588 | 69.675 / 71.658 | 65.569 / 69.066 | 27.999 / 35.783 | 1.063 / 1.038 | 2.488 / 2.003 | 0/1/5 |
| string_join | element | 6.122 / 9.958 | 5.822 / 6.579 | 18.116 / 20.372 | 13.878 / 14.936 | 0.321 / 0.323 | 0.419 / 0.440 | 0/1/5 |
| dict_lookup | element | 31.080 / 16.984 | 15.668 / 15.124 | 52.235 / 30.957 | 41.943 / 41.013 | 0.300 / 0.489 | 0.374 / 0.369 | 0/0/4 |
| dict_lookup_str | element | 61.795 / 28.868 | 22.487 / 19.502 | 62.413 / 31.877 | 60.300 / 57.605 | 0.360 / 0.612 | 0.373 / 0.339 | 0/0/4 |
| dict_update | element | 828.676 / 733.364 | 196.748 / 200.324 | 550.219 / 309.074 | 414.143 / 400.552 | 0.358 / 0.648 | 0.475 / 0.500 | 0/1/4 |
| dict_update_str | element | 1016.314 / 852.210 | 282.968 / 265.426 | 729.773 / 404.923 | 919.045 / 860.744 | 0.388 / 0.655 | 0.308 / 0.308 | 0/2/4 |
| set_dedup | element | 175.418 / 168.280 | 24.547 / 29.841 | 81.057 / 37.629 | 62.648 / 62.484 | 0.303 / 0.793 | 0.392 / 0.478 | 0/1/4 |
| int_parse | iteration | 46.212 / 41.438 | 29.089 / 26.527 | 28.864 / 24.338 | 21.992 / 19.216 | 1.008 / 1.090 | 1.323 / 1.380 | 0/0/4 |
| int_format | iteration | 221.152 / 216.686 | 68.646 / 62.790 | 214.758 / 197.557 | 63.711 / 62.190 | 0.320 / 0.318 | 1.077 / 1.010 | 0/1/4 |
| call_indirect | element | 5.013 / 5.080 | 0.302 / 0.312 | 9.013 / 9.502 | 7.192 / 7.825 | 0.033 / 0.033 | 0.042 / 0.040 | 0/0/0 |
| sort_int | element | 45.474 / 11.705 | 46.678 / 9.691 | 67.428 / 17.721 | 70.051 / 15.486 | 0.692 / 0.547 | 0.666 / 0.626 | 0/1/0 |
| sort_records | element | 55.648 / 66.818 | 31.429 / 39.289 | 117.653 / 50.766 | 40.781 / 44.783 | 0.267 / 0.774 | 0.771 / 0.877 | 0/5/0 |
| int_math | element | 8.696 / 9.069 | 0.357 / 0.493 | 7.808 / 8.314 | 5.706 / 6.183 | 0.046 / 0.059 | 0.063 / 0.080 | 0/0/0 |
| float_math | element | 8.297 / 8.428 | 1.568 / 1.709 | 6.515 / 7.029 | 6.970 / 7.323 | 0.241 / 0.243 | 0.225 / 0.233 | 0/0/0 |
| call_direct | element | 3.039 / 3.147 | 0.300 / 0.321 | 3.020 / 4.115 | 2.017 / 2.934 | 0.099 / 0.078 | 0.149 / 0.109 | 0/0/0 |
| branch_predictable | element | 4.024 / 4.149 | 0.395 / 0.496 | 7.679 / 7.943 | 3.198 / 3.252 | 0.051 / 0.063 | 0.123 / 0.153 | 0/0/0 |
| branch_mixed | element | 4.119 / 4.128 | 0.398 / 0.498 | 9.244 / 9.062 | 4.870 / 4.518 | 0.043 / 0.055 | 0.082 / 0.110 | 0/0/0 |
| binary_search | element | 143.777 / 32.984 | 32.877 / 18.453 | 137.108 / 27.887 | 37.633 / 19.493 | 0.240 / 0.662 | 0.874 / 0.947 | 0/0/1 |

All 70 row/size pairs pass the 1.10 Zig gate. The tightest ratio is `int_parse/64` at 1.0899657224757722. No binary-search noise exception was needed for this measurement.

### Dictionary layout decision

The production hybrid stays selected: ordered dense entries, cached hashes,
half-full 16-byte control groups and u32 entry indices, scan at most 8 entries,
tombstones and scalar rebuild. Capacity hints and the cheap rebuild are present;
no fixture-specific hash tuning or CPython fallback was needed because all five
package rows passed. Real emitted probe controls have matching checksums.

At 4096 elements, old-shape/hybrid cycles per operation: dense lookup 9.57/13.18,
sparse 26.73/17.38, cached string 45.06/21.44, mixed string miss 57.84/36.46,
churn 70.91/81.22, tiny-word count 58.35/96.72. Dense update and tiny-table costs
are visible limits, not hidden by the language row results. Design §18 and
s2-d/layout-real.txt retain all workloads/sizes and the decision.

### Coverage and every remaining refusal

Before is the preserved 72 new core; after is the frozen combined core, on
exactly the same corpus. The report retains the legacy name-deduplicated
function metric and per-file function/typed-loop instances separately. Loops
inside a refused function are attributed to its first blocker; this does not
claim independent loop-fragment admission. Frontend rejection lists are retained.

| Count definition | Before accepted | Final accepted | Total |
|---|---:|---:|---:|
| Qualified function names, deduplicated within each corpus | 2329 | 3185 | 3627 |
| Per-file function instances | 2756 | 3687 | 4250 |
| Checked loop instances in accepted functions | 607 | 1260 | 1539 |

The checked standard coverage run took 71.18 s; all four child statuses are
zero and stderr is empty. Final standard coverage on `996d9baa` took 2.64 s:
all four children exit zero with empty stderr, with the same 3185/3627,
4757 proven and 3764 exact checks across 3017 qualified names. The final
admission proof compares every one of 4253 ordered raw function occurrences,
all individual check metrics, all 11 frontend diagnostics and all input lists:
every result matches `090dabd5`. Only core facts and their tests changed;
the typed frontend and corpus are unchanged. This qualifies reuse of the
per-file function and loop table on the final source.
The before/after loop run took 312.48 s. Both compiler
versions reject the same seven example and four language files in the frontend.
Function/loop attribution and methodology are in
`integration/s2-x-coverage-summary.md`, with JSON and raw evidence alongside it.
The complete 71 remaining observed reasons follow (fixed-array live-view
storage has an additional precise boundary demonstrated outside this corpus).

| First refusal | Standard functions | Per-file functions | Checked loops |
|---|---:|---:|---:|
| capability type | 52 | 104 | 3 |
| byte_buffer type | 77 | 81 | 42 |
| aggregate storage of live dictionary views | 29 | 29 | 28 |
| shift_right | 12 | 26 | 46 |
| f64_sqrt | 10 | 22 | 25 |
| text of a non-integer value | 18 | 18 | 28 |
| count | 11 | 13 | 3 |
| operator on an aggregate value | 10 | 13 | 6 |
| equality of a recursive value | 11 | 11 | 2 |
| replace | 8 | 10 | 10 |
| shift_left | 3 | 10 | 9 |
| extend | 9 | 9 | 10 |
| find_any | 9 | 9 | 4 |
| view | 9 | 9 | 1 |
| decode | 7 | 8 | 1 |
| interior mut argument ancestor changed during later argument evaluation | 8 | 8 | 0 |
| resource type | 6 | 8 | 0 |
| strip | 7 | 8 | 0 |
| host function | 3 | 7 | 1 |
| live dictionary view of an interior place | 7 | 7 | 8 |
| ordinary dictionary snapshot combined with a live view | 7 | 7 | 6 |
| f64_cos | 3 | 6 | 0 |
| f64_sin | 3 | 6 | 0 |
| lower | 5 | 6 | 0 |
| number_format | 6 | 6 | 0 |
| parse_float | 5 | 6 | 2 |
| parse_int_range | 6 | 6 | 0 |
| extern | 3 | 5 | 0 |
| live dictionary view with unproved source identity | 5 | 5 | 8 |
| text_repr | 5 | 5 | 1 |
| upper | 4 | 5 | 2 |
| contains | 3 | 4 | 0 |
| escaping live dictionary view | 4 | 4 | 4 |
| is_alpha | 3 | 4 | 0 |
| is_digit | 3 | 4 | 0 |
| is_space | 3 | 4 | 0 |
| lstrip | 3 | 4 | 0 |
| reverse | 4 | 4 | 2 |
| rstrip | 3 | 4 | 0 |
| text_chr | 4 | 4 | 10 |
| array | 3 | 3 | 0 |
| f64_to_u64 | 3 | 3 | 0 |
| find_range | 3 | 3 | 1 |
| index_of | 3 | 3 | 0 |
| rfind_range | 3 | 3 | 0 |
| text_ord | 3 | 3 | 4 |
| aggregate or captured dictionary alias combined with a live view | 2 | 2 | 3 |
| dictionary key type | 2 | 2 | 0 |
| f64_floor | 2 | 2 | 0 |
| find_start | 2 | 2 | 0 |
| float_round | 2 | 2 | 0 |
| hex | 2 | 2 | 2 |
| keyword call with a mut argument that is not a local | 2 | 2 | 0 |
| list storage of live dictionary views | 2 | 2 | 4 |
| mut live dictionary view argument | 2 | 2 | 2 |
| rebinding a live dictionary view | 2 | 2 | 1 |
| strip_chars | 2 | 2 | 0 |
| f64_from_u64 | 1 | 1 | 0 |
| f64_trunc | 1 | 1 | 0 |
| file handle type | 1 | 1 | 0 |
| from_hex | 1 | 1 | 0 |
| parse_int receiver | 1 | 1 | 0 |
| pop_at | 1 | 1 | 0 |
| print options | 1 | 1 | 0 |
| record field type | 1 | 1 | 0 |
| rfind | 1 | 1 | 0 |
| saturating_add | 1 | 1 | 0 |
| scalar_count | 1 | 1 | 0 |
| slice_step | 1 | 1 | 0 |
| splitlines | 1 | 1 | 0 |
| text_format | 1 | 1 | 0 |

Persistent dictionary views are precise: fresh unshared local roots, direct
temporary views and explicit list snapshots are supported. Interior, shared
ordinary-snapshot, aggregate-stored, escaping, mut-argument, rebound or unproved
persistent identities are refused. F's fixed-array storage now has the same
explicit boundary. Character/text methods, richer number text, mutable byte
buffers, recursive equality, capabilities/resources and other unsupported
constructs are enumerated by the complete first-refusal table.

The proposed fused split cursor was not implemented; split materializes its
owned list/pieces. Its package row passes the existing ABI, so the conditional
view-parameter ABI evaluation was not triggered. No short-string representation
or float-text stretch was added. These limits are recorded in design §19–20.

### Dev loop, invariants and hand-off

Meaningful integration rebuilds: I 2.83 s, T1 2.55 s, F initial 3.43 s and helper
repair 1.31 s, D initial 1 s (subsequent cached check 0.01 s), T2 2.22 s, fact repair 2.16 s. Final held
unit gate 242.43 s; runner MaxRSS 205M, test compiler 328M. Each accepted unit gate
is under 300 s, including F's package maximum 294.04 s; rebuilds under 10 s and
RSS ceilings checked even when the runner reports a green step.

The F semantic merge exceeded Guardian's `cognitive-complexity` ceiling for `bufferOperation`
(26 versus 25) after its first passing merge checks. Moving the existing keyed
sort body to a typed private helper repaired the check; source changed, so core
build, held unit gate and full conformance were rerun. No baseline waiver.
D's aggregate-view identity wrong answer was explained and repaired with precise
refusals before merge, followed by its complete affected package qualification.
Other explained repairs remain in package READMEs; no unexplained mismatch is
accepted. Invalid unheld timings are not qualification evidence.

`ir.zig` stays byte-identical to 72. No record phi is emptied. Aggregate parameter
positions remain 64-bit; persisted formats stay module-interface-v5,
check-summaries-v6 and mutation-v2. No Wave B shared frontend/old core or
`tests/lang` edit was made. The external Lox migrations remain documented only.
Locked worktrees, private evidence caches and runtime references are preserved.
The required Guardian feedback is recorded separately in
`/home/epentland/ai/canopy/guardian-zig/FEEDBACK.md`; its commit follows this
exit-evidence commit.

Only user decision: go/stop on S3, with the split-fusion deviation above
explicitly recorded in the complete S2 exit evidence.
S3 has not started.
