# Lane S1 report: substring views (2026-10-09)

**Who wrote this file.** An opus-lane agent ran lane S1 of `docs/audits/runtime-parity-plan-2026-10-08.md` §8. Its tool refused report files, so the coordinating Claude session wrote this file from the agent's final message, after checking the gate receipts.

**What the coordinator checked:**
- `gates/gate-test.log`: 88/88 steps, 2102 tests.
- fmt-check: success.
- `qualify-a/summary.json`: qualified on `c7d815440`. Conformance 1518/0/0 in debug and in release.
- `fuzz50/matrix.json`: qualified and complete, with the source and the oracles unchanged; all 9 kinds pass.
- Lox: 246 + 246 + 241 + 241, and port tests 65 passed.
- EDA: goldens 34/34 identical (plain and counting), and 310 tests passed.
- Parity: all match `.expected`.

**Where.** Branch `claude/s1-views`, based on `main` `cafe7fea7`. Nothing was merged or pushed.

## Exit

| criterion | result |
|---|---|
| knucleotide ≤ 1.0× Zig ReleaseSafe | **0.943×**: 392.4 M against 416.2 M cycles (CPU 6, 9 interleaved rounds). The base was 908.6 M (2.18×). |
| ≤ 0.05 allocations per position in `frequencies`, on insert only | **0.0405**: 283,155 allocations over 6,999,961 positions, against 7,000,016 in the base. That is one key copy per inserted key, plus 55 dictionary blocks. |
| nothing else slower than 1.03× | Instructions are ≤ 1.000 everywhere; cycles are within noise. |
| gates | all pass on `c7d815440` |

## Commits

| step | commit | what |
|---|---|---|
| 1 | `d22a9d945` | A slice used only as a text-dict key becomes a borrowed view (new op `str_slice_view`), and an insert copies its key from the view and reuses the view's probe (NEW-CORE-S1-VIEW-1). The inline span probe now also covers small, deleted-from and indexed tables (VIEW-2). |
| 2 | `a1aceef36` | A copy of part of an ASCII text inherits the flag without a re-scan: slices, materialized views, copy-on-write copies, trims and stepped slices (ASCII-1). |
| 3 | `1fc596011` | Keys of at most 16 bytes compare inline with overlapping word loads; longer keys use `memcmp` (VIEW-3). |
| 2b | `63697f866` | Byte-string slices copy without an ASCII scan. EDA instructions drop 1.7% and 2.1%. |
| 4 | `da89d18d8` | Read-only slices are views: `==`, `!=`, `len`, `startswith`, `endswith` and `in` call span forms of the runtime helpers (VIEW-4). A guard keeps a copy when the source is updated in place. |
| fix | `c7d815440` | Restores a C const qualifier, which removes a warning that failed the first gate run. |
| evidence | `db61a3bda`, `465c92dcd` | Gate receipts and final measurements. |

## knucleotide by step (CPU 6; each row from its own interleaved run)

| arm | Minstr | Mcyc |
|---|---:|---:|
| base | 2852.7 | 908.6 |
| step 1, runtime probe for indexed tables | 1499.2 | 451.4 |
| step 1, inline probe | 1226.6 | 444.0 |
| step 2 | 1225.8 | 451.4 |
| step 3 | 1189.7 | 395.6 |
| **final** | **1189.7** | **392.4** |
| Zig ReleaseSafe | 1377.2 | 416.2 |
| Zig ReleaseFast | 1064.7 | 370.0 |
| Rust with overflow checks | 2058.7 | 516.8 |

**The inner loop after S1** (`perf/knucleotide-frequencies.opt.ll`). Per position:
- the checked `i+k`;
- the inline ASCII clamps;
- one `myl_core_span_hash` call;
- one `<16 x i8>` control-group compare;
- per candidate, a length check and two in-place compares against `seq`'s bytes.

A hit does no allocation, copy, scan or free. A miss calls `myl_core_ir_str_from_span(…, ascii)`, then `myl_core_dict_insert`.

## Other programs

Instructions, final ÷ base:
- **text_ops:** 0.999. Split dominates it, and split is lane S2's.
- **EDA:** rds3+flat 0.983, labstation 0.979, from byte-string token views that are no longer scanned.
- **scan_split and scan_replace:** 0.995.
- **Read-only slice micro** (`tools/read_micro.my`): 2907 → 824 M instructions.

## No regression

- **Parity:** 7 rounds over all 28 programs with an `.expected`.
  - Instructions are 1.000 except knucleotide (0.417), text_ops (0.999), scan_replace (0.995) and scan_split (0.995).
  - Cycles are 0.985–1.020, excluding knucleotide (0.433). The highest, list_records at 1.020, has identical LLVM.
- **Lox, PM's 6 cells:** instructions 1.000; cycles 0.977–1.010. One 3-round reading of tree/equality at 1.077 reran at 0.996 over 15 rounds.
- **EDA:** instructions 0.983 and 0.979. A 3-round cycle reading of 1.031 reran at 1.007 over 15 rounds.
- **Emitted LLVM:**
  - Lox is identical except two prelude declarations.
  - 25 of 28 parity programs are identical except those two declarations. The three that differ are knucleotide, text_ops (a copy-on-write copy now passes the ASCII hint) and dict_count (its split-word keys now get the inline indexed probe).

## Why each view is safe

- **Confined to SSA.** The verifier lets a `str_view` be read only by:
  - `dict_find` on a text-keyed dict;
  - `str_from_view`;
  - `str_len`;
  - a copy;
  - a runtime parameter declared as a span.

  It can't be stored, returned, joined in a phi, or passed to a mylang function.
- **Lifetime.** `own.zig` counts a view's uses as uses of its source, so the source lives until the view's last use. If the source is consumed while a view is live, the update finds it shared and copies, so the view never sees freed or changed bytes. A guard keeps the slice a copy when its source, or a phi the source flows into, is updated in place or passed `mut`. That avoids a whole-source copy.
- **Clamping** is exactly `str_slice`'s: inline for ASCII sources, and through `myl_core_ir_str_slice_span` otherwise. `myl_core_ir_str_slice` itself now uses the same function.
- **Probe reuse.**
  - `myl_core_span_hash` of the view equals `myl_core_str_hash` of the copied key.
  - The verifier accepts an insert keyed by `str_from_view(v)` only with a probe from `dict_find(d, v)` on the same dict.
  - Copy-on-write of a shared dict re-probes the copy with the owned key.
- **The inline compare** covers every byte and reads nothing outside either key. A test with 50 colliding key pairs of 3–20 bytes, each differing in one 4-byte window, traps when the compare is deliberately broken.
- **The ASCII flag** is set only from an ASCII source; a clear flag is always safe. Byte strings never read it.

## Tests

- **Where:** `src/core/s1_views_test.zig` holds 7 tests. The fixtures are `test/core/s1_views.my`, `s1_view_counts.my`, `s1_collisions.my`, `s1_ascii.my`, `s1_bytes.my` and `s1_reads.my`.
- **How they run:** each in debug, release and release `--verify-facts`, under the leak check.
- **Expected outputs:** from CPython. The bytes fixture is the exception; its oracle is the base compiler.
- **Spec:** NEW-CORE-S1-VIEW-1..4 and NEW-CORE-S1-ASCII-1.

## Gate receipts (all on `c7d815440`)

| gate | result |
|---|---|
| Guardian | 88/88 |
| `zig build test --summary all` | 88/88 steps, 2102 tests |
| `fmt-check` | pass |
| `qualify_merge` | qualified: test-core 511/0/0; conformance 1518/0/0 in debug and in release |
| frozen fuzz 9×50 | all 9 kinds pass |
| Lox | conformance 974/974; port tests 65/65 |
| EDA | 34/34 goldens, plain and counting; 310/310 tests |
| parity | all programs match `.expected`, plain and counting |
| counting on/off | identical on 28 parity programs, 34 EDA cases and 6 Lox cells |

## Touches outside S1's areas (all minimal)

**F1's area:**
- `emit_llvm.zig`: two runtime declarations in the prelude, and `.str_slice_view` added to the text dispatch.
- No TBAA tags were added or changed.

**Shared files:**
- `ir.zig`: the new op;
- `verify_ir.zig`: the op signature, `str_slice_view` allowed to define a view, and the insert-probe rule;
- `print.zig`;
- `own.zig`: the view is classified as a borrow, and the copy-on-write re-probe uses the owned key;
- `passes.zig`: the new pass, release only;
- `flags.zig`;
- `cost.zig`;
- `count_runtime.zig`.

**The new pass:** `src/core/fuse_slice_key.zig`.

## Remaining limits

- **Views exist only in release builds.**
- **The pass runs before inlining.** A slice whose dict use appears only after inlining is not converted.
- **The update guard is conservative:** a source flowing into a phi that is later appended to keeps its slices as copies.
- **The span hash is still a call,** and the dict pointer is spilled across the insert call.
- **Byte-string slices and split pieces still allocate.** EDA's tokenizer stores its views in records, which an SSA-only view can't cover; that needs substring blocks or S2's split views.
- **`fuse_text_split` still re-probes with the materialized key on insert.** That is left to S2.
- **`mylang dump-ir` overflows the stack** on EDA's recursive types. This was already there; S1 did not touch it.
