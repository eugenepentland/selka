# RC performance close-out, 2026-09-27

Round 1 goal (user): the experimental reference-counting runtime (`--rc-runtime`,
D9 WP-4) at a **geomean of at most 1.3x the GC's retired instructions** on the
43-program corpus, on both backends. Round 2 goal (user, 2026-09-28): close out
the remaining rows, so **every row is at or below 1.3x** on both backends. GC
stays the default.
Branch `claude/rc-perf` (validated tip `d5804e40`), merged into `main` by fast-forward
at the user's request; it sits on `codex/d9-rc-integration` `fdf73b30`.

## Result

| 43 programs, full size, RC / GC instructions | QBE | LLVM |
|---|---:|---:|
| Geomean, start (`fdf73b30`) | 4.05 | 5.32 |
| Geomean, round 1 (`d5804e40`, on `main`) | 1.162 | 1.187 |
| **Geomean, round 2 (`4ca8b8a7`)** | **1.072** | **1.082** |
| Geomean without Lox | 1.060 | 1.064 |
| Rows at or below 1.3x | **43 / 43** | **43 / 43** |
| Worst row | sort_records 1.28 | sort_quick 1.28 |
| Median peak RSS, GC -> RC (KiB) | 7156 -> 4200 | 7000 -> 4240 |

All 86 rows print exactly the GC's output (stdout, and SVG hashes for schematic).
Both rounds' targets are met. D9 WP-4 acceptance additionally needs a geomean
of at most 1.0x and the frozen median-of-three protocol; the every-row cap and
lower median RSS now hold on this measurement.

No row is above 1.3x. Only scan_split uses more peak memory than GC (76 vs 66
MB): RC headers are 32 bytes against GC's 16 and size classes round to 16 bytes
(about 16 bytes on each of ~660K small strings; a layout change, left alone).

## Diagnosis that set the plan

The gap was the cost of each ownership operation, not their number. Lox
binary_trees N8 ran 27.4G instructions against the GC's 1.35G for about 78M
ownership operations, roughly 335 instructions each, where a counted retain or
release should be about 5. Each operation was an out-of-line runtime call that
looked metadata up in a hash table (about 120M lookups), interpreted a shape
generically, returned a status the caller checked, and drained a queue.
Per-frame journals that only served trap cleanup cost another quarter. Earlier
work had removed operations one proof at a time; this round made operations
cheap first, then removed the remaining ones with a per-site count.

## What changed (lanes, all merged into `claude/rc-perf`)

| Lane | Branch | Change | Spec tags |
|---|---|---|---|
| D | `claude/rc-method-call` | Wrong answer: RC `match` bindings copied narrow scalars (bool, u8, i16, i32) at their packed width into 8-byte slots; stale bytes printed Lox `false` as `true` on QBE (masked at the benchmark's full N). Introduced by `acee0c9d`. | RC-MATCH-SCALAR-1 |
| A | `claude/rc-glue` | Compile-time per-type ownership glue (generated C in the metadata unit, about 570 functions for Lox) plus inline IL fast paths for one-word values; no lookups, shape walks, status returns or count-limit checks on fast paths | RC-GLUE-1 |
| C | `claude/rc-runtime-fast` | Pointer-map metadata, flat plans for variants, slab pools from 2 MiB mmap ranges, immediate retire of edge-free objects, expensive invariants only in checked (stats/test) builds | RC-CHECKED-1, RC-SCOPE-SPARE-1 |
| B | `claude/rc-traps` (merged via `claude/rc-merge-b`) | Traps tear the heap down in one step after the GC-ordered resource cleanup; normal exits use static drops with per-slot guard/role words; per-frame journals removed (user approved) | RC-TRAP-TEARDOWN-1, RC-STATIC-DROPS-1, RC-EXIT-SCOPES-1, RC-FLAG-PROMOTE-1, RC-DEAD-DROPS-1, RC-UNUSED-ENTRY-READS-1 |
| E | `claude/rc-writeback` | `wb = owner.f; change(mut wb); owner.f = wb` moves instead of cloning (was quadratic; Lox tree engine 10-100x faster) | RC-CLOSED-FIELD-TRANSFER-2 |
| F | `claude/rc-loops` | Loop codegen: owned operands staged so operand words stop escaping, presized appends, no zeroing of plain growth, read-only loop versions for floats and records, anchored element borrows; RC now traps `R_LIST_ITERATION_MUTATION` like GC | RC-OPERAND-STAGE-1, RC-PRESIZED-APPEND-1, RC-ELEMENT-BORROW-1/2, RC-ITERATION-HOLD-TRANSFER-1, others |
| I | `claude/rc-llvm` | LLVM: receiver-scope fast paths forced inline; RC count words in their own alias scope so loan/unloan pairs fold | RC-SCOPE-FAST-1, LLVM-RC-PREFIX-1 |
| H | `claude/rc-alloc` | Per-size-class free-slot cache with inline allocation in generated code, call-free drain, the collector's allocation-free range keys under RC, byte copies for element types that own nothing, inline zeroing | RC-ALLOC-CACHE-1, RC-DRAIN-FLAT-1, RC-RANGE-KEY-1, RC-DICT-FAST-1, RC-PLAIN-TYPE-1, RC-LIST-HEADER-1, RC-INLINE-ZERO-1, RC-BUFFER-APPEND-1 |
| L (round 2) | `claude/rc-strings` | Byte-buffer loop hoisting, anchored range keys in `frequencies()`, early release of read-only named collections at last use, pairwise and per-type drain runs, large extents as their own mappings | RC-BUFFER-HOIST-1, RC-ANCHORED-RANGE-KEY-1, RC-NAMED-RELEASE-1, RC-DRAIN-PAIR-1, RC-DRAIN-TYPES-1, RC-LARGE-MAP-1 |
| J (round 2) | `claude/rc-schematic` (merged via `claude/rc-merge-j`) | Borrows for owning list elements of read-only parameters, inert byte-buffer receivers, interval anchors for `mut` list roots, anchors through borrowed calls and inlined arguments, flat list release | RC-ELEMENT-BORROW-3, RC-INERT-BYTES-RECEIVER-1, RC-OPERAND-ANCHOR-2, RC-INTERVAL-ANCHOR-2, RC-BORROW-CALL-ANCHOR-1, RC-READONLY-ANCHOR-2, RC-LIST-FLAT-RELEASE-1 |
| K (round 2) | `claude/rc-lox-vm` | Field moves at a record's last use, element payload takes in `match`, last-read handover of owned locals (also fewer GC copies), inert receivers for counted elements, inline publish/drop glue | RC-DEAD-FIELD-MOVE-1, RC-ELEMENT-TAKE-1, VALUE-SEMANTICS-13, RC-INERT-COUNTED-RECEIVER-1, RC-PUBLISH-FAST-1, RC-FLAT-DROP-1 |
| G | `claude/rc-sites` (merged via `claude/rc-merge-g`) | `--rc-runtime=sites` per-call-site ownership-op report, and ten eliminations it found (loans and pins on read-only and mut roots, return moves, self stores); Lox ownership ops fell 77-91% | RC-SITES-1, RC-READONLY-ANCHOR-1 and nine more |

Progress of the QBE / LLVM geomean as lanes merged (dev size): start 4.05/5.32;
D+A 2.89/3.40; +C 2.59/3.04; +E 2.57/3.01; +B 2.09/2.21; +F 1.77/1.98; +I
1.69/1.74; +G 1.26/1.29; +H 1.16/1.19 (full size 1.162/1.187). Round 2: +L 1.137/1.162; +J 1.096/1.118; +K 1.072/1.082 (full size).

## Validation of `4ca8b8a7` (round 2)

- `zig build` with Guardian (88 checks); `zig build test` 94/94 steps, 2,497
  tests; `test-qbe` 469/469; `test-qbe-build` 29/29; `fmt-check`;
  `test-native-memory` 23/23 and `test-native-heap` 10/10 steps.
- `mylang test tests/lang --force` under `--rc-runtime=stats`, `--rc-runtime`
  and both with `--release`: 1,172/1,172 assertions across 194 programs each,
  no failures, skips, cached verdicts or dropped files. Stats counts balance.
- Lox port tests under RC on both backends: 65/65 and driver cases 13/13.
- All 86 rows print the GC's output at full, dev and smoke size.
- Round 1's validated tip `d5804e40` passed the same gate (logs m1-m8); round 2
  intermediate merges m9 (`a08c4b5c`) and m10 (`af5a3487`) passed as well.

## Measuring and finding the next operations

- `experiments/rc-perf-20260927/quick.py` measures the whole corpus on both
  backends in about 20 s at dev size (15 s at full size now), against the
  accepted GC binaries, and checks every output against GC. One pinned run per
  program is enough: counts are deterministic to about 0.5% (unpinned runs on
  this hybrid CPU over-count). Dev-size ratios match full size; smoke sizes
  now read higher (1.32/1.39) because startup dominates tiny Lox inputs.
- `--rc-runtime=sites` (docs/tooling/ownership.md) prints the heaviest
  ownership-op sites by source line; `MYLANG_RC_SITES=file` writes JSON.

## Open items and risks

- Assumptions worth a proof: element borrows (F) accept a finalizer running
  during an unrelated release inside the borrow's live range; read-only
  anchors (G) rely on callers snapshotting a value passed both read-only and
  `mut`.
- Pre-existing divergence: in `f(r.field, g(mut r))` GC and RC may observe
  different values of `r.field` (evaluation order).
- Two pre-existing **GC** value-semantics bugs found in round 2 (RC is correct
  in both): `before = o; append(mut o, b"z")` through `o.buffer` shows the append
  in `before.buffer`, and `before = table.rows; store(mut table, 1, [4])` shows
  the store in `before`. An adversarial reviewer is investigating them and
  attacking the round-2 proofs.
- VALUE-SEMANTICS-13 (lane K) changes GC copy decisions as well as RC's.
- RC-NAMED-RELEASE-1, RC-INTERVAL-ANCHOR-2, RC-ELEMENT-TAKE-1 and
  RC-INERT-COUNTED-RECEIVER-1 are the subtlest round-2 proofs; the last two
  assume dropping an element never runs guest code (resource types excluded).
- Smoke-size Lox rows read higher (up to 2.38x on LLVM) because tiny inputs are
  dominated by startup; acceptance is measured at full size.
- Build cost: glue adds about 0.9 s to a cold Lox QBE build; LLVM full-LTO
  relink of the Lox port is about 2.5 s slower.
- Remaining costs by row (from lane reports): str_build runs a uniqueness
  check every iteration that cannot move to loop entry; schematic pays
  loan/retain/drop on a 128-byte two-string record read from `pins[j]` in
  O(n^2) loops plus receiver scopes (element borrows for owning elements would
  remove most of it); knucleotide's `frequencies()`; Lox `load_frame` copies a
  three-list frame per call.
- Incidents: one agent's `pkill -f` pattern killed three wait loops belonging
  to another session; agents briefly shared a scratchpad file and one built in
  another's worktree. The permission checker refused agents' merges of the
  shared integration branch; the orchestrator did all integration merges.

## Per-row ratios (start: dev size at fdf73b30; now: full size at 4ca8b8a7)

| Program | QBE start | QBE now | LLVM start | LLVM now |
|---|---:|---:|---:|---:|
| parity/suite/binary_trees | 3.43 | 1.11 | 3.59 | 1.18 |
| parity/suite/fannkuch_redux | 1.74 | 1.04 | 1.02 | 0.99 |
| parity/suite/knucleotide | 6.12 | 1.11 | 6.68 | 1.11 |
| parity/suite/mandelbrot | 1.00 | 1.00 | 0.96 | 1.00 |
| parity/suite/matmul | 3.01 | 1.01 | 1.88 | 1.13 |
| parity/suite/nbody | 1.44 | 1.06 | 2.22 | 1.25 |
| parity/suite/raytrace | 1.44 | 1.06 | 1.95 | 1.05 |
| parity/suite/sieve | 2.96 | 1.02 | 3.51 | 1.00 |
| parity/suite/sort_builtin | 1.74 | 1.12 | 1.47 | 1.05 |
| parity/suite/sort_quick | 1.80 | 1.05 | 2.46 | 1.28 |
| parity/suite/sort_records | 4.64 | 1.28 | 6.17 | 1.20 |
| parity/suite/spectral_norm | 2.02 | 1.01 | 2.27 | 1.00 |
| parity/suite/text_ops | 3.59 | 1.11 | 3.20 | 0.98 |
| parity/lib/scan_count | 1.02 | 1.00 | 1.01 | 1.00 |
| parity/lib/scan_replace | 1.03 | 1.00 | 1.02 | 1.00 |
| parity/lib/scan_split | 2.34 | 0.71 | 2.02 | 0.65 |
| parity/micro/alloc_churn | 2.31 | 1.09 | 2.51 | 1.12 |
| parity/micro/bytes_scan | 1.11 | 1.08 | 1.08 | 1.00 |
| parity/micro/calls | 1.00 | 1.00 | 1.00 | 1.00 |
| parity/micro/dict_count | 1.34 | 1.13 | 1.33 | 1.16 |
| parity/micro/fib | 1.00 | 1.00 | 1.00 | 1.00 |
| parity/micro/float_loop | 1.08 | 1.08 | 1.00 | 1.00 |
| parity/micro/intloop | 1.00 | 1.00 | 1.00 | 1.00 |
| parity/micro/list_append_sum | 1.90 | 1.14 | 2.30 | 1.20 |
| parity/micro/list_records | 3.97 | 1.06 | 8.86 | 1.10 |
| parity/micro/records | 1.00 | 1.00 | 1.00 | 1.00 |
| parity/micro/str_build | 6.01 | 0.99 | 8.44 | 1.12 |
| schematic/fixture | 11.20 | 1.23 | 16.80 | 1.19 |
| schematic/changed-net | 11.13 | 1.23 | 16.58 | 1.19 |
| schematic/changed-value | 11.18 | 1.23 | 16.52 | 1.19 |
| lox/vm/binary_trees | 20.20 | 1.16 | 32.82 | 1.15 |
| lox/vm/closures | 19.38 | 1.15 | 34.28 | 1.15 |
| lox/vm/equality | 13.80 | 0.87 | 28.17 | 0.97 |
| lox/vm/fib | 16.62 | 1.09 | 30.78 | 1.07 |
| lox/vm/instantiation | 21.69 | 1.27 | 32.03 | 1.22 |
| lox/vm/invocation | 20.79 | 1.19 | 36.12 | 1.16 |
| lox/vm/method_call | wrong output | 1.18 | 41.88 | 1.25 |
| lox/vm/properties | 19.46 | 1.18 | 33.08 | 1.17 |
| lox/vm/string_equality | 11.94 | 0.93 | 27.45 | 1.12 |
| lox/vm/strings | 13.51 | 1.00 | 20.51 | 1.04 |
| lox/vm/trees | 17.95 | 1.12 | 29.15 | 1.10 |
| lox/vm/zoo | 18.58 | 1.13 | 31.93 | 1.11 |
| lox/vm/zoo_batch | 18.14 | 1.13 | 31.72 | 1.12 |
