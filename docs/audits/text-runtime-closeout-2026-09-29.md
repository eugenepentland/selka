# Text runtime follow-ups — 2026-09-29

WP-B3's two text items are complete on `codex/next-text-runtime-20260929`.
The implementation is `458b9dfc84640b2d1e38a4eb30be1ec3745c0476`, based on
the finished B1 tip `5ef8b06a`. This is an independent ABI3 lane; the integrator
merges it with ABI4 header/image work and runs the combined gate separately.
The B1 worktree and its compiler/source remained frozen throughout.

Every heavy build, native experiment, guest and Lox run used `build-slot.sh`.
Scratch, caches, TMPDIR, runtime snapshots and installed prefixes stayed in this
owned worktree. Timing used CPUs 2, 3, 10, 11 in two explicitly claimed and
released windows. No main merge, push, EDA write or source-worktree removal was
performed here. The integrator authorized removal of only the idle old B1
`.zig-cache/o`; its frozen binaries, runtime snapshots, receipts, corpus objects
and logs were retained after checking that no process had a cwd there.

## Streaming suffixes

`TEXT-VIEW-5` distinguishes a str slice with an omitted upper endpoint,
`s[pos:]`, from one with an explicit endpoint. A suffix of at least nine octets
shares its owned text even below the old quarter-of-owner threshold. Its offset
must fit u32, and its owner must live no deeper than the result. A tail of a tail
points directly at the first owned text, so lookup remains one hop. Eight-octet
and shorter tails copy; endpoint clamping and all value answers are unchanged.

This is an explicit retention exception: keeping a long-enough tail can retain
the whole input. `s[pos:len(s)]`, split pieces, trim results, and bytes slices
retain `TEXT-VIEW-3`'s bounded retention policy. The existing large-receiver
retention test now uses an explicit upper endpoint for its kept 60-octet piece.
Arena allocation, barriers and escape-copy behavior are preserved.

The internal tail operation is appended at ordinal 106. All 106 prior buffer
operation encodings remain unchanged. Allocation/effect and shallow-copy
classification, IR validation, RC read-only anchors and borrowed dictionary
range fusion cover the new operation. Its four-argument native ABI has an exact
LLVM declaration; ordinary bounded slices continue to select their old helper.

Tests cover the eight/nine-octet boundary, repeated tail flattening, astral
scalar offsets, negative/beyond-end endpoints, unchanged bounded/split policy,
arena escape, and B1 ranged-search, trim and repr consumers. A native work check
scans every suffix of the original owner's final quarter and proves that only
the final eight short tails copy payload octets, regardless of owner length.

## Immutable literal indexes

`TEXT-INDEX-4` gives a frozen non-ASCII str literal of at least 256 octets the
same 128-scalar sample spacing as a runtime text. Its offsets must fit u32.
`text_literal_index.zig` computes samples in one pass over the encoded UTF-8
payload. The C image object pads that payload to eight-byte alignment and
places a const sample member immediately behind it. C assertions verify the
16-byte cursor prefix, stride/minimum and actual member offset against the
runtime header. Literal common headers use `myl_native_object`, preserving the
16-byte immortal prefix independently of the RC allocation prefix.

The image-owned index's two cursor words stay zero. Runtime lookup uses a
separate read-only path and chooses an end or nearest sample; it never lazily
fills or updates these tables. The separate text header can still cache its
hash. Dynamic owned texts retain their existing lazy mutable cursor/index.
ASCII and shorter literals retain their original layout. Literal and embed
metadata both use the shared emitter; no host side table, Python build/runtime
dependency, locale or new GC-traced field is introduced.

Metadata tests check mixed one/two/four-octet sample offsets, padding, exact
flags, and the 255/256-octet boundary including a zero-logical-sample table.
The native test places the index on a protected read-only page, then exercises
forward/reverse/strided/random and inverse lookups, indexed views, hashing and
collection. A real 699-scalar literal guest checks all positive/negative
indexes, ranged search, views and arena escape. Its oracle is CPython 3.14.4,
Unicode 16.0.0; Python was used only for test/experiment expected values.

## Before/after work evidence

These are examined/copied octets, not wall-clock timing. The experiment builds
the frozen B1 C runtime snapshot and the candidate C runtime with the existing
test-only position counter, strict UBSan and `-O2`. Every result is asserted.

| Operation | Scalars/octet size | Control work | Candidate work |
| --- | ---: | ---: | ---: |
| Original owner's final-quarter ASCII suffixes | 4,096 octets | 523,776 copied octets | 36 |
| Original owner's final-quarter ASCII suffixes | 32,768 octets | 33,550,336 copied octets | 36 |
| Literal lookup forward and reverse | 4,096 scalars | 16,777,216 examined octets | 524,288 |
| Literal lookup forward and reverse | 32,768 scalars | 1,073,741,824 examined octets | 4,194,304 |

The larger literal has eight times the scalars and eight times the candidate
work, while the unindexed control grows by 64 times. The suffix experiment
keeps only one view in the control and 1,016/8,184 views in the candidate.
The native checked-in tests enforce the candidate's work bounds without a clock.

## Frozen gate

The source tree is `5e36024f5d2e5043a2449c6850e46435879535a4`.
The private frozen, fuzz-installed and gate-installed compiler bytes are equal:

- mylang SHA256: `1aa5fe081f549c3653785625f3240e1c60d47e958dbd559dfd35c7001ffd7efb`
- QBE SHA256: `3a82e47eab7323bf4b25f71a99bcde34f93ab661a57b3524f2641d7254ba2725`
- control mylang SHA256: `7fd3fcad3a5d83d29e37f51c33fe3fdb36f69e54e0ad32f67bb57f49540ed23c`

| Check | Actual result |
| --- | --- |
| Install | 19/19 steps |
| Full Zig gate | 96/96 steps after the documented cache warmup; all 2,662 unique selected tests covered |
| QBE gate | 51/51 steps; 480/480 tests |
| Golden replay | 231 checked: 175 source, 56 fixtures; 373 explicit skips; zero mismatches |
| Native build / formatting | 29/29 and 2/2 steps |
| Native memory / heap | 23/23 and 10/10 steps |
| Guest default, GC, release, stats, GC-stress | Each 1,464 tests / 221 programs; zero cached/failed/skipped/dropped |
| Lox default and GC | Each build, 65 tests / 10 programs and 13 driver cases; zero cached/failed/skipped/dropped |
| Fuzz seeds 1–100 | 21/21 steps; 98 ok, zero invalid, two known stress-only, zero RC divergences |
| Documentation | 225 features, 14 standard modules, 176 exports; 227 examples run, 57 checked, 11 explicit skips, zero failures/mis-tags |

The fresh global Zig cache caused the plan's known libunwind flake: one CLI
backend-parity assertion expected empty stderr but Zig printed `ar rcs …
libunwind.a`. The initial 94/96-step run selected 2,662 tests: 2,661 passed and
that one failed, with zero runner skips. The warmed rerun passed 96/96 steps;
only the affected 45-test shard reran (45/45 passed), retaining the other green
verdicts. The initial aggregate's 27,203 skips are shard exclusions; the warm
aggregate has 230 such exclusions. Both logs are preserved, with no source fix
or waiver for the cache warmup.

Fuzz used three workers, both generators and LLVM release every eighth seed.
Only the existing GC-stress cases remain: seed 19 exits 134 with descriptor
scan-plan/field mismatch; seed 87 exits 139. Their programs, findings and full
summary remain under `experiments/rc-fuzz/out/`. Forced language and Lox tests
have no skips; golden and documentation skip categories remain explicit.

## Corpus comparison

Both control and candidate built 58/58 unique corpus binaries. Each matched
GC outputs on all 86 pairs at dev and smoke. All original 43×2 row sets for
approved A5 m17, B1, control and candidate are preserved. No instruction count
increases by more than 1% against any of those references.

| Size/backend | Control geomean | Candidate geomean | <=1.3 | Largest increase vs control |
| --- | ---: | ---: | ---: | ---: |
| dev/QBE | 1.064486 | 1.064559 | 43/43 | +0.297857% |
| dev/LLVM | 1.069097 | 1.069093 | 43/43 | +0.008717% |
| smoke/QBE | 1.103444 | 1.103459 | 38/43 | +0.069974% |
| smoke/LLVM | 1.137129 | 1.137205 | 36/43 | +0.297385% |

Smoke's five QBE and seven LLVM cap misses are exactly the existing approved A5
and control misses; no new miss appears. The largest movement is `text_ops`.
The same candidate binary and argv also move by -0.113571% QBE and +0.297385%
LLVM between dev and smoke, consistent with the harness's documented
address-dependent instruction-count variability. No corpus speedup is claimed.
Every row and delta against control, approved A5 and B1 is in the companion
performance JSON, together with input-file hashes and the native work ledger.

## Guardian and handoff

The whole-tree source commit passed all 88 Guardian checks. Its spec check
caught duplicate primary `TEXT-VIEW-5` annotations and a `TEXT-INDEX-4` secondary
annotation on a global constant rather than a test; both were corrected. The
new mutation switch was formatted with `zig fmt`. No waiver, baseline edit or
structural-bound exception was needed. Centralized feedback is committed in
guardian-zig at `db487e44a4c69a7fd4e3eef2aceac4242793afed`.

The integrator merged the source as `062920d0` and clarified the generic header
retention paragraph as bounded-piece policy. That integration comment and the
ABI4 runtime belong to its combined validation, leaving this lane's source and
compiler freeze intact. Complete logs, installed prefixes, before-runtime
snapshot, private work experiment and corpus artifacts remain in this worktree;
the companion gate/performance JSON files preserve durable counts and receipts.
