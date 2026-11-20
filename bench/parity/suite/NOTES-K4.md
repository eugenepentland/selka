# K4 notes: json_roundtrip, netlist_union_find, hash_bytes, dict_churn

Lane K4 of the EDA port roadmap adds four program shapes the suite lacked: structured
text, irregular graphs, byte hashing and hash maps with deletes (SUITE.md sections
12 to 15). Each has `.selka`, `.zig`, `.rs` and `.expected`. `k4_oracle.py` writes the
`.expected` bytes from the SUITE.md text alone (CPython; `hashlib` and `zlib` for the
hashes), so no port is the reference for another.

Evidence (JSON, logs, perf profiles, repro timings):
`~/ai/canopy/mylang-evidence-archive/experiments/eda-roadmap-20261022/k4/`.

## Sizes (fixed in SUITE.md; Zig ReleaseFast 0.4 to 0.5 s)

| kernel | size | zig-fast median |
|---|---|---:|
| json_roundtrip | 120000 records, 27,336,185-byte text | 403.3 ms |
| netlist_union_find | 1,000,000 pins, 1,000,000 connections, 16 sources | 469.4 ms |
| hash_bytes | 64 MiB buffer | 415.4 ms |
| dict_churn | 800,000 string keys, 2,000,000 u64 keys | 443.9 ms |

The first sizes (40000 records, 2M/3M netlist, 400k/1M dict) were changed before any
timed run, from first Zig timings of 0.13 s, 2.0 s and 0.2 s.

## Results (ratio to zig-fast, median of per-round ratios, 95% bootstrap interval)

Pinned compiler `main-03e60dfff-rf` (ReleaseFast). CPU 2, quiet batch (load 1.1 to 1.8).
Default rounds (7) and warm-ups (2), except dict_churn `my`, which was qualified and
timed for 3 rounds, no warm-up (see the coordinator's instruction in the report).

| kernel | my | my-tuned | zig-safe | rust | rust-checked | rust-fx | instr my/zig |
|---|---|---|---|---|---|---|---:|
| json_roundtrip | 1.388 [1.380, 1.392] | - | 1.154 | 1.496 | 1.512 | - | 1.27 |
| hash_bytes | 1.267 [1.265, 1.278] | - | 1.018 | 1.014 | 1.007 | - | 1.97 |
| netlist_union_find | 1.207 [1.191, 1.216] | - | 1.189 | 1.080 | 1.118 | - | 1.59 |
| dict_churn | **386.27** (3 rounds) | 1.527 [1.511, 1.535] | 1.246 | 1.437 | 1.424 | 0.977 | 1608.7 |

Peak RSS (KB), zig-fast / my / rust: json 215,680 / 425,944 / 336,448; hash 65,936 /
134,844 / 67,804; netlist 84,972 / 55,780 / 78,832; dict 188,500 / 332,652 / 285,212
(dict my-tuned 387,472).

All arms of all four kernels print byte-identical output (the harness qualifies each
arm against `.expected`; dict_churn passed qualification on all seven arms).

## Profiles of the arms over 1.25x

Counts from `perf record` on the release binary (evidence `k4/perf-*.txt`).

- **dict_churn `my` (386x).** 99.8% of samples in `myl_core_dict_ordinal`
  (`src/core/runtime/core_dict.c`). After any delete, `for key in dict` calls the
  ordinal walk once per entry, and each call rescans from entry 0. Quadratic.
  Fixed by K4F (see the K4F update at the end): 386x became 1.26x.
- **dict_churn `my-tuned` (1.53x).** Top terms: `myl_core_str_append_ascii` 68%
  (key construction), `my.dict_churn_tuned::main` 43%, `dict_rebuild` 6%,
  `myl_core_dict_insert` 5%, `myl_core_str_eq` 4%, `myl_core_str_hash` 3%,
  drops about 4%. perf attributes 32% to `ld-linux` (unexplained, not checked).
  Key formatting alone is not the gap: a repro that formats the same keys with
  f-strings is faster in Selka than Zig's `allocPrint` (0.07 s against 0.16 s;
  1.62e9 against 2.34e9 instructions). The 1.5x gap is open.
- **json_roundtrip `my` (1.39x).** Spread across the program, no single term:
  generation loop 21%, `walk` 7%, `serialize` 6%, `parse_value` 6%,
  `myl_core_buffer_push_checked` 5%, tree destruction (`drop_child_pending` 5%,
  `drop_owned` 2%), `parse_string` 4%, `block_alloc` 3%, `buffer_append_i64` 3%.
  Selka runs 27% more instructions than Zig at about the same IPC (2.0).
- **hash_bytes `my` (1.27x).** `hash_bytes::compress` 53%, `main` (the xorshift fill
  with one `byte_builder.append_byte` per octet) 32%, `buffer_push_checked` 6%.
  Zig: `compress` 41%, the fill inlined into `main`. Selka runs 1.97x the
  instructions at a higher IPC (3.85 against 2.35). The word-load repro below is the
  instruction cost of the big-endian loads in `compress`.

netlist_union_find `my` (1.21x) is under the 1.25x line and was not profiled.

## Language and runtime findings (not fixed in this lane)

1. **Iterating a dict after a delete is quadratic.** Repro: `k4/repro/iter_del_N.selka`
   (generator `gen.py`). N keys, one delete every 1000th key, then `for key in table`.
   Best of three wall times on the release build (`timings.txt`):

   | N | with deletes, iterate | with deletes, no iterate | no deletes, iterate |
   |---:|---:|---:|---:|
   | 10,000 | 0.1 s | 0.1 s | - |
   | 20,000 | 0.2 s | 0.1 s | - |
   | 40,000 | 0.5 s | 0.1 s | 0.1 s |
   | 80,000 | 1.8 s | 0.1 s | - |
   | 160,000 | 7.1 s | 0.1 s | - |

   Doubling N multiplies the time by about 4. `perf` on the 160k run: 78% in
   `myl_core_dict_ordinal`. Cause: `core_dict.c`, `myl_core_dict_ordinal`, the scan
   from entry 0 once `meta->dead` exists. The dict_churn `my` port is this repro at
   scale. Fixed in the runtime by K4F: the ordinal is a Fenwick descent, O(log n).

2. **Big-endian word loads from `bytes` cost 4.7x the instructions of Zig.** Repro
   `k4/repro/word_load.selka` and `word_load.zig`: 16.8M big-endian u32 reads over 64 MiB,
   identical checksum 1711276032. P-core counters: Selka 506.8M instructions, Zig
   108.1M; cycles 228.8M against 63.8M (`word_load_*.perf-stat.txt`). This is the
   cost inside `hash_bytes::compress`. Typed binary reads (deferred) would remove it.

3. **`check` runs out of memory on `unwrap_or` of a float option.**
   `k4/repro/float_option_oom.selka`: `unwrap_or(bytes.parse_float_range(data, 0, 7), 0.0)`
   with `import bytes` gives `selka: host failure: OutOfMemory`, exit 2. The same
   shape with `parse_int_range` and `0` passes (`int_option_oom.selka`). The json port
   avoids it with `match`.

4. **Managed keys are copied on every store.** `table[copy(keys[i])] = i` is needed
   because the key list keeps its key. Not measured separately; noted for the
   suite's dict ports.

## Thresholds (`thresholds.json`, rebaselined 2026-10-23, batch label `quiet`)

- json_roundtrip my 1.388, limit 1.60; hash_bytes my 1.267, limit 1.46; netlist_union_find
  my 1.207, limit 1.39; dict_churn my-tuned 1.527, limit 1.76. The my-tuned ratio was
  1.54 in the 3-round run and 1.53 in the 7-round run.
- **dict_churn `my`: threshold 1.26x (K4F, batch `2026-10-23-k4f-after`).** Set after the runtime fix;
  the 386x of K4 is the pre-fix measurement.
- Each entry comes from one 7-round run. The README asks for two batches to see
  between-batch noise, so these tolerances are the default 15%, not pooled.

## Decisions (question, evidence, choice, reversibility)

1. **Expected output from an independent oracle.** The ports must agree with
   SUITE.md, and a port that matched another port could share its bug. Choice:
   `k4_oracle.py` (CPython; `hashlib` and `zlib` for the hashes). Reversible: yes.
2. **Sizes.** Choice: the sizes in the table above, set before any timed run so
   that the Zig ReleaseFast port runs in 0.4 to 0.5 s. Reversible: yes, edit SUITE.md
   and the ports together.
3. **JSON text values are `bytes` in Selka.** The escapes decode to ASCII octets, and
   `str` would need a UTF-8 decode per string (`decode()` returns a `Result`). Numbers
   use `bytes.parse_int_range` and `bytes.parse_float_range`, the same correctly
   rounded grammar as Zig and Rust. Reversible: yes.
4. **dict_churn `_tuned` rebuilds the map after the deletes.** The rebuilt dict has no
   tombstones, so the iteration phase takes the O(1) path. The output is unchanged.
   It closes most of the gap (1.53x against 386x). This is a workaround, not a fix:
   the runtime fix stays with the runtime lane. Reversible: yes.
5. **dict_churn_fx.rs uses an Fx-style hasher** (rotate, xor, multiply by the Fx
   constant, per byte for strings and per word for `u64`). Output is identical;
   0.98x of Zig. Reversible: yes.
6. **hash_bytes is hand-written in every port.** `hashes.sha256` in the stdlib is a
   standard-library crypto function, so the Selka port does not call it; the stdlib
   file was read only for the u32 idioms. `hash_bytes_std.zig` is not written in this
   lane. Reversible: yes.
7. **netlist indices.** Zig and Rust use `usize`; Selka uses `int` lists built with
   `lists.filled`. No `_tuned.selka` was written: the port is 1.21x, under the line.
8. **No `_tuned.selka` for json_roundtrip or hash_bytes.** I did not try a formulation
   that might close the gap. The hash gap is the word-load cost (finding 2), which
   no formulation inside selka removes today. The json gap is spread (profile
   above). Reversible: yes; a tuned variant can be added later with the same harness.
9. **dict_churn `my` was not thresholded while the walk was quadratic.** K4F fixed the walk and
   set its threshold from one 7-round run. Reversible: yes.

## K4F update (2026-10-23): the dictionary iteration fix

`myl_core_dict_ordinal` now finds the i-th live entry with a Fenwick descent over dead
counts per 64-entry word (`core_dict.c`), then a bit select: O(log n) per call, with
no write on the read path. The four K4 kernels and `knucleotide`, `dict_count`
before and after (ratio to Zig, same machine, `after.json` and `before.json` in
`k4f/timing/`):

| benchmark | my before | my after |
|---|---:|---:|
| dict_churn | 386.27 (K4, 3 rounds) | 1.26 (7 rounds, batch loaded) |
| knucleotide | 1.28 | 1.07 |
| dict_count (micro) | 0.51 threshold, 0.66 measured | 0.67 |
| json_roundtrip | 1.38 | 1.38 |
| hash_bytes | 1.27 | 1.28 |
| netlist_union_find | 1.22 | 1.22 |

The K4 repro (`iter_del_N`, release build, best of three): 160k keys 7.33 s before,
27 ms after; 10k keys 38 ms before, 8 ms after. `dict_count` already failed its
threshold before the fix (0.66x against 0.59x); that is a stale threshold, not this change.

Rebaseline item (for the coordinator, not changed here): `dict_count` `my` has threshold 0.512 from batch
`2026-10-17-ownership-default-r3`, and it measured 0.66 on the pre-fix compiler and 0.67 after the fix on the same
machine. The threshold is stale; a rebaseline of `dict_count` is needed.

