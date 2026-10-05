# S2-T1 — text and bytes

Base: `72eaae74`; accepted S2-I merge imported at `0563edd6` before final qualification.
Source commit: `ec44e2b6d100a047ca60d7d48b79d55234baf69e`. Commands below ran on that source in the locked
`codex/new-core-s2-text` worktree. No `tests/lang`, old-core, IR, or `own.zig` changes.
The coordinator records Guardian feedback once for the full Wave B task.

## As built

Text/bytes use one 32-byte leaf header: count/kind at 0/4, byte length/capacity
at 8/16, cache metadata at 24, data at 32. STR=1, BYTES=3. ASCII/HASHED/SCALARS/
CURSOR occupy kind bits 8–11; hash/scalar count occupy the low/high metadata words.
Immortals have compile-time metadata and never receive runtime cache writes.
`myl_core_str_hash` and `myl_core_span_hash` return the old deterministic `uint32_t`
word-fold hash. D uses the same symbol for owned keys and spans. T2 replaces
`build_text.number(Context, context, operation, type, span)` and owns numeric helpers.

Admitted text operations include UTF-8 length/index/slices (including negative/step
slices), concatenation and consuming append, equality, find/contains/prefix/suffix,
split/whitespace split and join. Bytes admit literals, validated integer-list
construction, length/index/slices/concat/equality/search/iteration and integer XOR.
Located runtime guards cover invalid byte values, empty separators, zero slice steps
and bounds. The borrowed `encode()` ownership/emitter patch from S2-I makes its common
loop use an identity pointer with no count traffic.

The immutable-receiver cursor rewrite uses the frozen IR; refreshed live-place
receivers retain scalar lookup to preserve D1 after replacement. ASCII scalars are
immortal. A scalar used only by append fuses into `str_append_char`; same-parent
appends preserve materialization to avoid a new ownership alias. Long non-ASCII
offset lookup counts continuation bits in 32-byte batches with a one-entry cursor.
Byte reduction vectors load `u8`, widen safely, and support bounded integer XOR;
verify mode checks the inferred ranges. Boolean masks and narrowing conversions
remain outside this new vector admission.

SSA views are emitted and cannot escape under the existing verifier. Split currently
materializes an owned list and pieces; no fused split loop or parameter-view ABI was
added. The split row passes with the accepted ABI. `count`, `replace`, case/strip
methods, `decode`, `ord`/`chr`, richer formatting and mutable byte buffers remain
precise feature refusals where not already supported. Full logs report these counts.

## Qualification commands

All build-producing checks use `scripts/build-slot.sh build`. Environment:

```sh
export TMPDIR="$PWD/.mylang-cache/s2-t1/tmp"
export ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache
oracle=/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s2-integration/zig-out/bin/mylang
evidence=experiments/new-core-s2-20261005/wave-b/s2-t1
```

The oracle is the accepted Wave A language compiler (with adjacent QBE), not the
pre-language baseline binary. Writable caches are private to this worktree.

| Check | Command (under the environment above) | Result at `ec44e2b6` |
|---|---|---|
| Rebuild | `scripts/build-slot.sh build -- /usr/bin/time -f 'rebuild %e seconds' zig build core --summary all` | 3/3 steps; rebuild 1.71 s; compiler MaxRSS 318M (`build-final.txt`) |
| test-core | `scripts/build-slot.sh gate -- bash -c '"$@"; result=$?; exit "$result"' -- scripts/build-slot.sh build -- /usr/bin/time -f 'test-core %e seconds' zig build test-core --summary all` | 191/191; 184.35 s; MaxRSS 132M run / 323M compile; gate wait 501 s and build admission 20 s excluded (`test-core-qualified.txt`) |
| Guardian | `guardian-check all . --full --summary` | 88/88; file-size/function-length/line-length/abi-layout findings are report-only |
| Full corpus | `scripts/build-slot.sh build -- python3 experiments/new-core-s1-20261005/conformance.py --set all --jobs 2 --why --mylang "$oracle" --cache-dir "$PWD/.mylang-cache/s2-t1/conformance-final"` | 1,540 tests: 897 matching / 0 mismatching / 643 unsupported in each mode (`conformance-final.txt`) |
| Text/bytes sweeps | own-file command below, debug/release with `--leakcheck --verify` | 199 tests: 82 matching / 0 mismatching / 117 unsupported in debug and fact-verified release; leak clean (`sweeps-final.txt`) |
| Text fuzz | qualification command below | 50/50 admitted; 750 comparisons; 1,000 native runs; zero mismatches/facts/leaks/crashes; qualified=true; 153.76 s (`fuzz-final/summary.json`) |
| S0/S1 code identity | `scripts/build-slot.sh build -- python3 experiments/new-core-s2-20261005/wave-a/compare_code.py --stage s2-t1-final` | 20/20 benchmark definitions identical (`code-final.txt`) |
| Coverage | `scripts/build-slot.sh build -- python3 experiments/new-core-s0-20261005/coverage.py` | 2,616/3,627 accepted functions; 3,370 proven / 2,635 exact checks in 2,481 analysed functions (`coverage-final.txt`) |
| Five rows | row command below | All 10 size/row entries pass ≤1.10× Zig and match all checksums (`rows-qualified.txt`) |

The fixture `test/core/t_text.my` covers mixed ASCII/2-/4-byte scalars, empty pieces,
UTF-8 indexing over 256 bytes, reversed/step slices, shared snapshots, direct doubling,
named aliases, alias through a phi, capacity growth, encode and vector/scalar byte XOR.
Its two intentional trap tests are compared against the oracle; a core test runs the
eight successful cases and two traps in debug/release/verify modes.

Own sweep:

```sh
scripts/build-slot.sh build -- python3 experiments/new-core-s1-20261005/conformance.py \
  byte_buffer byte_buffer_from_list byte_iteration_reductions byte_range_fusion \
  byte_ranges_llvm byte_views embed immutable_equal python_bytes rc_borrowed_results \
  rc_buffer_loops rc_byte_loop_versions rc_byte_receivers rc_interval_anchors \
  rc_loop_guard_context rc_loop_operand_isolation rc_mut_list_aliases \
  rc_owning_element_borrows rc_plain_field_loans rc_readonly_bytes rc_readonly_calls \
  constant_list_image migrated/python_surface python_text_surface constant_methods \
  python_split_scalar python_strings standard_strings text_index text_literal_index \
  text_scanning tuples migrated/python_format print_rendering format_specs \
  test/core/t_text.my --jobs 2 --why --leakcheck --verify --mylang "$oracle" \
  --cache-dir "$PWD/.mylang-cache/s2-t1/sweeps-final"
```

Fuzz admission held one of the two shared fuzz slots:

```sh
scripts/build-slot.sh build -- python3 experiments/new-core-s2-20261005/wave-a/integration/fuzz_qualification.py \
  --kind s1 --harness "$PWD/$evidence/fuzz_text.py" --mylang "$oracle" \
  --core "$PWD/zig-out/bin/mylang-core" --cases 50 --seed 202610051 \
  --evidence "$PWD/$evidence/fuzz-final" --cache-root "$PWD/.mylang-cache/s2-t1/fuzz-final"
```

The `s1` label selects 15 comparisons per case in the wrapper; the overridden
generator covers random ASCII/non-ASCII strings, slices, find, split, byte XOR,
character rebuild and loop concatenation including named-alias doubling. Every case
must build at debug/release/verify and all native runs use the leak checker. The
wrapper rejects signal/negative exits as well as output/error differences.

Rows (seven interleaved rounds, CPU 10, private compiler/output caches):

```sh
scripts/build-slot.sh build -- flock /run/user/1000/mylang-s2-cpu10.lock \
  python3 "$evidence/measure_text.py" --build --rows bytes_scan,string_equal,string_search,string_split,string_join \
  --rounds 7 --cpu 10 --mylang "$oracle" --core "$PWD/zig-out/bin/mylang-core" \
  --bin "$PWD/.mylang-cache/s2-t1/rows-qualified"
```

The runner extends the established S1 method without changing it. `split_rows.py`
extracts each timed loop/setup from the same text suite, with untimed local string
construction and no imports. Normalization: byte scan 4,000/250,000 elements;
equality 200,000/200,000 iterations; search 40,000/40,000 iterations; split
400/25,000 elements; join 1,000/60,000 elements. The raw log includes new/old/
Zig/Rust cycle medians and checksum agreement. The separate split diagnostic
records instruction/branch/cache counters; the final table derives ratios.

## Final row and count table

Cycles per element, except equality/search per iteration; sizes 4,096 / 64.

| Row | New core | Zig ReleaseSafe | Rust | New/Zig | New/Rust | Count traffic in repeated work |
|---|---|---|---|---|---|---|
| bytes_scan | 1.240 / 1.631 | 1.402 / 1.769 | 1.136 / 1.201 | 0.884 / 0.922 | 1.092 / 1.358 | zero per byte and kernel iteration |
| string_equal | 135.095 / 15.886 | 277.760 / 16.932 | 135.727 / 12.693 | 0.486 / 0.938 | 0.995 / 1.252 | zero per comparison |
| string_search | 1080.594 / 89.298 | 12927.329 / 384.311 | 5583.528 / 184.103 | 0.084 / 0.232 | 0.194 / 0.485 | zero per search |
| string_split | 63.219 / 67.529 | 65.499 / 69.148 | 28.074 / 35.542 | 0.965 / 0.977 | 2.252 / 1.900 | one list release per call, whose free walks fresh pieces; zero in piece score; immortal separator count test |
| string_join | 5.800 / 6.539 | 18.052 / 20.336 | 13.967 / 14.530 | 0.321 / 0.322 | 0.415 / 0.450 | one result release per call; zero in copy/score; immortal separator count test |

`counts.txt` records named emitted-function count-update sites and calls. A release
LLVM audit (`counts-optimized.txt`) uses the exact driver CPU flags. LLVM inlines the
timed functions into `main`; the audit follows their preserved names/blocks and
source SSA refs. Separator selects retain a count load/test, although decrement
stores disappear. Fresh list/result releases take the unique free arm; shared-arm
conditional decrement stores remain in generated code. Allocation initializes fresh
headers to one. Input construction and final cleanup are outside repeated kernels.

Each row was emitted separately for inspection under the build slot:

```sh
scripts/build-slot.sh build -- zig-out/bin/mylang-core build test/core/row_ROW.my \
  -o .mylang-cache/s2-t1/row-code/ROW --release \
  --emit-llvm .mylang-cache/s2-t1/row-code/ROW.ll \
  --cache-dir .mylang-cache/s2-t1/row-code/cache \
  --link benchmarks/runtime/ports/native_clock.c
scripts/build-slot.sh build -- zig cc -O3 -march=native -mllvm \
  -x86-experimental-pref-innermost-loop-alignment=6 -Wno-override-module \
  -S -emit-llvm .mylang-cache/s2-t1/row-code/ROW.ll \
  -o .mylang-cache/s2-t1/row-code/ROW.opt.ll
```

`ROW` ranges over the five rows. `counts-optimized.txt` records the inspected result
at `ec44e2b6`; the inspected private LLVM is retained in this worktree's cache.

## Diagnoses retained

- `conformance-doubling-failure.txt` and `sweeps-doubling-failure.txt`: 22 full-corpus
  mismatches were runtime uniqueness traps from repeated-string helpers. The own
  pass tested the left operand's uniqueness before retaining an identical right
  operand, then sent count=2 to consuming append. Builder concatenation now uses a
  fresh result when both resolved source SSA refs are identical; the ordinary
  consuming path remains. Distinct refs through a phi pass with old snapshots.
  `doubling-repaired.txt`: all 37 supported cases match in both modes with leak and
  fact checks, including the added direct/named/phi regressions.
- `offset-diagnosis.txt`: long-Unicode reverse slicing initially returned an empty
  string because the omitted end sentinel was treated as a normal end. The runtime
  now uses the shared checker's exact `INT64_MIN`/`INT64_MAX` omitted-bound sentinels.
- `fuzz-generator-failure.txt`: two initial harness setup failures (hyphenated
  filename, then module/filename disagreement) happened before differential runtime
  qualification. Files and module names now both use `text_0000`; final qualification
  admits all requested programs.
- `rows-initial.txt`: search missed at 1.802× Zig. A bounded first-byte candidate
  search now falls back to the established two-way libc search; there is no
  fixture-specific shortcut.
- `split-diagnostic.ll` and `split-counters.txt`: before accepted I import, the
  inner score loop called encode/retain/release per piece, short pieces paid the
  vector setup, and split called growth even below capacity. A 4,096-token ×400
  run took 119,825,362 cycles, 572,275,551 instructions and 121,448,656 branches
  (17,719 branch misses; 14,916 cache misses), checksum 703954400. Borrowed encode
  plus a capacity test removes that traffic; the accepted ABI passes.
- `rows-accepted.txt`: join still missed (1.339×/1.124×). The old core's general
  ≤16-byte short-copy kernel was ported: one sizing pass classifies piece/separator
  widths, then hoists endpoint loads; longer pieces use bulk copies. `join-final.txt`
  records 0.323×/0.322× Zig after this repair. No view ABI change was needed.

Superseded successful logs and transient failure samples are removed. No hash
manifests are frozen; the code comparison log is the tool's ordinary output.
