# WP-B1 Python text surface closeout — 2026-09-29

WP-B1 starts from approved Phase A main `80dd51906c97ae76bf208474ac48c9baac3a11cd`
in `codex/next-text-20260929`. Final implementation source is
`c4c9e3d0eb8c5e41bb75ae7f8a26914ee2bfaa4c`; the private installed compiler at
`.tmp/b1-compat-frozen/bin/mylang` has SHA-256
`a0b894182d5e799be3a6058c0d22e4b99e6c909ed4016ede33057589bd24c8cf`.
The source and compiler bytes remain fixed for the final gate and corpus.
Caches and scratch stay inside this worktree, and every Zig build and heavy guest
command runs through `scripts/build-slot.sh`.

## Behavior

Approved main rejected byte-list sorting, byte keys, charset trim arguments and
bounded/reverse search forms; repr was unavailable. Empty whole-value find/count
trapped as empty separators. The final compiler accepts the specified forms and
returns CPython answers; the retained golden cases now return 0 and 4 for
`"abc".find("")` and `"abc".count("")`. Existing str-key sorting was preserved.

- `PY-BYTES-SORT-1`: stable `sorted` and in-place `.sort()` on `list[bytes]`, with
  unsigned-octet/prefix ordering. Scalar and flat tuple keys accept str and
  immutable bytes. Key callbacks run once per element; reverse sorting preserves
  equal-key order. Direct bool lists remain rejected; bool keys retain the
  existing integer ordering.
- `PY-TEXT-TRIM-1`: optional same-family charset arguments on all three str/bytes
  trim methods. Duplicate characters form a set; empty sets trim nothing.
  Argument-free str trim uses Unicode 16 whitespace and bytes trim uses six ASCII
  whitespace octets. Charset construction is linear, using a fixed small set or
  a budget-charged Unicode bitmap; a refused bitmap allocation publishes nothing.
- `PY-TEXT-RANGE-1/2`: seven str/bytes search methods accept positional start/end
  integers. Bounds and empty needles follow CPython, including reversed and
  beyond-end windows. Text answers count Unicode scalars globally; bytes answers
  count octets. Missing index/rindex trap `R_SUBSTRING_NOT_FOUND`. Reverse search
  uses a constant-space two-way matcher; indexed boundaries and streaming
  conversions preserve linear non-ASCII work on owned values and nested views.
- `PRELUDE-REPR-1`: repr for str, immutable bytes, all integer widths, float and
  bool. Quotes, escapes, signed zero and shortest round-trip float spelling match
  CPython. Unicode printability is checked-in static Unicode 16 data; there is no
  build/runtime Python or locale dependency. Lists, dictionaries, records, None,
  tuple affixes and explicit None charsets are outside this typed surface.

Ordinary float formatting retains its existing helpers; repr selects a separate
entry statically. Context-typed octet literals in legacy str declarations and
str dictionary keys remain accepted, while bytes needles/charsets passed to str
methods are rejected. Normal names can shadow repr. Constant declaration hinting
continues to avoid `Names.reference` side effects.

All 85 preexisting buffer-operation ordinals and ten valid key-shape nibbles are
preserved. Byte sort order 4 and formerly invalid key nibble 7 are additive.
GC/RC sort declarations, the 48-byte keyed-sort request and native ABI v9 are
unchanged. Cache identity includes changed runtime source/header bytes, including
static Unicode data, so old objects cannot satisfy the new content hash.

## Oracle and durable coverage

Pinned CPython 3.14.4 (`/usr/bin/python3.14`, SHA-256
`52e0a13e60a981d8c4b6478be2ba5176f69da07948a056bf49cf6f077e30cb41`)
uses Unicode 16.0.0. The seeded preparation contains 86,730 observations;
all 1,112,064 valid Unicode scalars were checked to derive 738 nonprintability
intervals and 29 whitespace scalars.

Strict-UBSan real-runtime probes passed 83,160 ranged cases, 546 trim cases,
560 str repr cases, 267 bytes repr cases and 25,000 seeded random reverse searches
with no diagnostic. The frozen default and LLVM sorting fixtures each passed
16/16; LLVM float repr passed 134/134 public tests containing all 2,134 pinned
binary64 observations. The earlier default float fixture also passed 134/134.

Checked-in coverage adds 21 surface tests and one repr-shadowing test, plus four
Zig diagnostics/runtime-trap tests. The focused Zig selection passed 15/15
(including its imported support tests). The native driver checks 4,000 random
reverse matches, adversarial periodic inputs, indexed Unicode windows/nested
views, linear-work counters, stressed ownership, arenas and allocation refusal.
Four new feature slugs have runnable documentation examples.

## Gate and performance

All final recorded stage statuses are zero. Expected-data-only golden commit
`9246511b` corrects the two deliberately changed empty-search contracts without
changing compiler/runtime bytes. Intermediate 36e84c58 and
46242c06 gate logs are retained separately; their compatibility findings led to
the final corrections above. The first private LLVM oracle lived directly beside
transient scratch snapshots and failed source inventory with FileNotFound;
separating its fixture and scratch directories passed all cases without a
compiler/cache change. A private zero-length probe memcpy warning was fixed in
the probe wrapper before the strict-UBSan clean run. These intermediate harness
results are not counted as final passes.

| Check | Result |
| --- | --- |
| `zig build` | 19/19 steps; installed frozen compiler/runtime |
| `zig build test` | 96/96 steps; 2,659 selected tests passed |
| `test-qbe` | 51/51 steps; 480/480 tests |
| `test-qbe-build` | 29/29 steps |
| `fmt-check` | 2/2 steps |
| `test-native-memory` / `test-native-heap` | 23/23 and 10/10 steps |
| Guests: default, GC, release, counted RC, GC stress | Each 1,460/1,460 across 220 programs; zero cached/failed/skipped/dropped/unloaded |
| Lox: default and GC | Each project build, 65/65 tests across 10 programs and 13/13 driver cases; zero cached/failed/skipped/dropped |
| `test-rc-fuzz -Dfuzz-seeds=100` | 21/21 steps; 98 ok, zero invalid, two known stress-only, zero RC divergences |
| Guardian | 88/88 including whole-tree commit checks; no waiver/baseline changes |

Golden replay checked 231 cases (175 source and 56 fixtures), explicitly skipped
373 (27 documentation, 345 unmatched fixtures and one data-only), with zero
mismatches. Documentation coverage found 225 documented features, 14 standard
modules and all 176 public exports, with zero failures.

## Performance

The frozen compiler built all 58 unique corpus binaries. Dev and smoke each
matched all 86 RC/GC output pairs, with no failures. Timing used CPUs 2, 3, 10, 11
in an explicitly reserved window. Approved A5 m17 dev/smoke/full JSONs and the
original m14 dev baseline are preserved without edits; comparisons below use
m17 of the same size. Full row counts and baseline/candidate JSON hashes are in
`python-text-closeout-performance-2026-09-29.json`.

| Size | Backend | A5 geomean | B1 geomean | Worst ratio | Rows <=1.3 | Largest RC instruction increase |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| dev | QBE | 1.064485 | 1.064483 | 1.281418 | 43/43 | 0.001873% |
| dev | LLVM | 1.069091 | 1.069090 | 1.255955 | 43/43 | 0.004783% |
| smoke | QBE | 1.103401 | 1.103419 | 1.504823 | 38/43 | 0.013916% |
| smoke | LLVM | 1.137125 | 1.137121 | 2.358124 | 36/43 | 0.005094% |

All rows stay within the 1% regression limit. The per-row instruction movements
are bounded by -0.010618% to +0.013916%; these measurements do not support a
performance improvement claim. Existing static dispatch for ordinary numeric
formatting, sorting and whole-value search remains on its old helpers. Every dev
row meets the 1.3 cap. Smoke's five QBE and seven LLVM Lox startup cap misses are
exactly the same rows as approved A5; no new cap miss was introduced.

## Fuzz and skips

Seeds 1–100 ran with three workers, alternating both generators and adding LLVM
release RC every eighth seed. The exact frozen-compiler digest was confirmed for
the fuzzer's separate installed prefix. The final result is 98 ok, zero invalid,
two report-only GC-stress findings and zero RC divergences; the Zig step passed
21/21. Seeds 19 (exit 134, descriptor scan-plan/field mismatch) and 87 (exit 139)
match the known Phase A findings. Their programs and complete summary remain in
`experiments/rc-fuzz/out/found/` and `experiments/rc-fuzz/out/summary.json`.

Full Zig selected-test results have zero failures or skips. The aggregate summary
includes 27,170 skips because shards exclude tests allocated to other shards.
Doctests ran 227 examples and checked 57, with zero failures or mis-tagged blocks;
all four new examples ran. Eleven explicit documentation skips remain for the
removed feature, host/library fragments and proposed named-constraint syntax,
as on Phase A. Golden replay explicitly distinguishes selected source/fixture
cases from documentation, unmatched fixtures and data-only entries; these skips
are reported separately from guest tests. Every forced guest and Lox run has zero
cached, failed, skipped, dropped or unloaded tests.

## Guardian feedback and handoff

The centralized append-only B1 feedback is committed in guardian-zig at
`1947edefd24ac88052618a814bfc1ee9b4caf337`. It records concrete wins from
cognitive-complexity (31/27 above limit 25), routing boolean caps (7/5 above cap 3),
allocator hygiene in two test helpers and the 255-character sort-dispatch line
above the 240 hard limit. Structural helpers, allocator threading and one-tag
secondary comments resolved every finding, with no waiver or baseline edits.

Implementation commits are `36e84c58`, `46242c06` and `c4c9e3d0`; the expected-data
correction is `9246511b`. The frozen compiler, corpus binaries, complete lane,
guest, Lox, oracle and fuzz logs remain private in this worktree. The durable
report and per-row performance JSON form the final evidence commit. No main
merge, push, source-worktree removal or EDA write occurred in this lane.
