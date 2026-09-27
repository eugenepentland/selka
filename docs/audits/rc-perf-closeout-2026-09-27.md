# RC performance close-out, 2026-09-27

Goal set by the user for this round: the experimental reference-counting runtime
(`--rc-runtime`, D9 WP-4) at a **geomean of at most 1.3x the GC's retired
instructions** on the 43-program corpus, on both backends. GC stays the default.
Branch `claude/rc-perf` (validated tip `d5804e40`), merged into `main` by fast-forward
at the user's request; it sits on `codex/d9-rc-integration` `fdf73b30`.

## Result

| 43 programs, full size, RC / GC instructions | QBE | LLVM |
|---|---:|---:|
| Geomean, start (`fdf73b30`) | 4.05 | 5.32 |
| **Geomean, now (`d5804e40`)** | **1.162** | **1.187** |
| Geomean without Lox | 1.148 | 1.153 |
| Rows at or below 1.3x | 34 / 43 | 32 / 43 |
| Median peak RSS, GC -> RC (KiB) | 7040 -> 4204 | 7208 -> 4360 |

All 86 rows print exactly the GC's output (stdout, and SVG hashes for schematic).
This meets the round's target. It is **not** D9 WP-4 acceptance, which also
needs a geomean of at most 1.0x, every row at or below 1.3x and the frozen
median-of-three protocol.

Rows still above 1.3x: schematic 2.04/2.03, Lox binary_trees 1.50/1.75, str_build
1.52/1.70, Lox method_call 1.40/1.68, knucleotide 1.53/1.32, Lox closures 1.36/1.48,
Lox instantiation 1.47/1.46, parity binary_trees LLVM 1.36, Lox trees LLVM 1.32.
Three rows use more peak memory than GC: knucleotide (45 vs 28 MB), scan_split
(79 vs 66 MB) and scan_replace (14 vs 11 MB).

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
| G | `claude/rc-sites` (merged via `claude/rc-merge-g`) | `--rc-runtime=sites` per-call-site ownership-op report, and ten eliminations it found (loans and pins on read-only and mut roots, return moves, self stores); Lox ownership ops fell 77-91% | RC-SITES-1, RC-READONLY-ANCHOR-1 and nine more |

Progress of the QBE / LLVM geomean as lanes merged (dev size): start 4.05/5.32;
D+A 2.89/3.40; +C 2.59/3.04; +E 2.57/3.01; +B 2.09/2.21; +F 1.77/1.98; +I
1.69/1.74; +G 1.26/1.29; +H 1.16/1.19 (full size 1.162/1.187).

## Validation of `d5804e40`

- `zig build` with Guardian (88 checks); `zig build test` 94/94 steps, 2,475
  tests; `test-qbe` 469/469; `test-qbe-build` 29/29; `fmt-check`;
  `test-native-memory` 23/23 and `test-native-heap` 10/10 steps.
- `mylang test tests/lang --force` under `--rc-runtime=stats`, `--rc-runtime`
  and both with `--release`: 1,113/1,113 assertions across 184 programs each,
  no failures, skips, cached verdicts or dropped files. Stats counts balance.
- Lox port tests under RC on both backends: 65/65 and driver cases 13/13.
- Every intermediate merge passed the same gate (`.tmp-gate/gate.sh` logs m1-m8).
  A conflict resolution of mine dropped a brace in `tests/native_rc_fast_test.c`
  in merge `8690ba2d`; `d5804e40` fixes it and is the validated tip.

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

## Per-row ratios (start: dev size at fdf73b30; now: full size at d5804e40)

| Program | QBE start | QBE now | LLVM start | LLVM now |
|---|---:|---:|---:|---:|
| parity/suite/binary_trees | 3.43 | 1.21 | 3.59 | 1.36 |
| parity/suite/fannkuch_redux | 1.74 | 1.04 | 1.02 | 0.99 |
| parity/suite/knucleotide | 6.12 | 1.53 | 6.68 | 1.32 |
| parity/suite/mandelbrot | 1.00 | 1.00 | 0.96 | 1.00 |
| parity/suite/matmul | 3.01 | 1.01 | 1.88 | 1.13 |
| parity/suite/nbody | 1.44 | 1.06 | 2.22 | 1.25 |
| parity/suite/raytrace | 1.44 | 1.06 | 1.95 | 1.05 |
| parity/suite/sieve | 2.96 | 1.02 | 3.51 | 1.00 |
| parity/suite/sort_builtin | 1.74 | 1.12 | 1.47 | 1.05 |
| parity/suite/sort_quick | 1.80 | 1.05 | 2.46 | 1.28 |
| parity/suite/sort_records | 4.64 | 1.28 | 6.17 | 1.20 |
| parity/suite/spectral_norm | 2.02 | 1.01 | 2.27 | 1.00 |
| parity/suite/text_ops | 3.59 | 1.11 | 3.20 | 0.99 |
| parity/lib/scan_count | 1.02 | 1.00 | 1.01 | 1.00 |
| parity/lib/scan_replace | 1.03 | 1.00 | 1.02 | 1.00 |
| parity/lib/scan_split | 2.34 | 0.71 | 2.02 | 0.65 |
| parity/micro/alloc_churn | 2.31 | 1.13 | 2.51 | 1.17 |
| parity/micro/bytes_scan | 1.11 | 1.08 | 1.08 | 1.01 |
| parity/micro/calls | 1.00 | 1.00 | 1.00 | 1.00 |
| parity/micro/dict_count | 1.34 | 1.13 | 1.33 | 1.16 |
| parity/micro/fib | 1.00 | 1.00 | 1.00 | 1.00 |
| parity/micro/float_loop | 1.08 | 1.08 | 1.00 | 1.00 |
| parity/micro/intloop | 1.00 | 1.00 | 1.00 | 1.00 |
| parity/micro/list_append_sum | 1.90 | 1.14 | 2.30 | 1.20 |
| parity/micro/list_records | 3.97 | 1.06 | 8.86 | 1.10 |
| parity/micro/records | 1.00 | 1.00 | 1.00 | 1.00 |
| parity/micro/str_build | 6.01 | 1.52 | 8.44 | 1.70 |
| schematic/fixture | 11.20 | 2.04 | 16.80 | 2.03 |
| schematic/changed-net | 11.13 | 2.04 | 16.58 | 2.03 |
| schematic/changed-value | 11.18 | 2.04 | 16.52 | 2.03 |
| lox/vm/binary_trees | 20.20 | 1.50 | 32.82 | 1.75 |
| lox/vm/closures | 19.38 | 1.36 | 34.28 | 1.48 |
| lox/vm/equality | 13.80 | 0.87 | 28.17 | 0.96 |
| lox/vm/fib | 16.62 | 1.13 | 30.78 | 1.12 |
| lox/vm/instantiation | 21.69 | 1.47 | 32.03 | 1.46 |
| lox/vm/invocation | 20.79 | 1.25 | 36.12 | 1.25 |
| lox/vm/method_call | wrong output | 1.40 | 41.88 | 1.68 |
| lox/vm/properties | 19.46 | 1.23 | 33.08 | 1.24 |
| lox/vm/string_equality | 11.94 | 0.93 | 27.45 | 1.10 |
| lox/vm/strings | 13.51 | 1.01 | 20.51 | 1.07 |
| lox/vm/trees | 17.95 | 1.25 | 29.15 | 1.32 |
| lox/vm/zoo | 18.58 | 1.17 | 31.93 | 1.16 |
| lox/vm/zoo_batch | 18.14 | 1.17 | 31.72 | 1.17 |
