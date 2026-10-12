# S03 wave2 handoff

Frozen comparison sources: C0 `fbfcaa7a923186a8e773c3760f81c10aa345a432`,
B0 `c1857310e0bf623545380c8de24515f1b9970021`.
No additional native roots or production optimization were introduced in wave2.

Completed evidence commits:

- `e20931e37346be9ad491100b21590c776d4acc8f`: 40 unique oracle-comment edits
  per variant, same eight named tests and unchanged fixtures; 80 successful
  command executions with 40 unique artifact hashes per variant.
- `604de6bccf303ba725d2b191955c8247278834d6`: two complete, order-balanced
  true-cold compile/link pairs preparing the same whole unit inventory
  (C0 1541; B0 broad 1532 plus scalar 9).
- `52dc2fbb7695cd0cc8b2a72b0c59dd1f010a5dc1`: repaired fallback golden
  preparation and cooperatively canceled operational runs, explicitly not
  qualified; exact manifests/logs and private cold cache cleanup.

All commits passed normal 88-check Guardian hooks. No Guardian feedback,
shared cache cleanup, duplicate compiler build or worker full gate was performed.

The scalar split has a measured tradeoff. Warm command median rises from
1.041 to 1.210 seconds; empirical nearest-rank p95 falls from 2.644 to
2.090 seconds. Supported whole-root PASS feedback median is 0.544/0.524
seconds and p95 1.109/1.002 seconds. Median maximum process RSS falls from
180,470 to 158,436 KiB. These are 40-observation empirical results, not a
population p95 or general speed claim.

Two cold whole-root wall pairs are near equal (65.794/64.793 and
64.838/64.451 seconds). Maximum process RSS increases 4.06% and 3.28%;
installed unit artifacts increase approximately 25.74 MB/11.58%, with
approximately 25.8 MB extra private local cache. Cold means fresh private
Zig local/global caches; frozen tools, compiler generation and OS page cache
are excluded. Two pairs are descriptive, not p95. The earlier incomplete
focused true-cold attempt is not paired or qualified.

Golden source audit preserves all 222 intended actual compiler executions,
167 source and 55 fixture cases, fresh mutable directories and 444 fixtures.
Preparation reduces source writes 222 to 165 and bytes 90,182 to 66,752.
This static/compile-only evidence does not establish runtime parity. Original
frozen compiler golden replay was not attempted after independent native-link
blocker reproduction. The repaired fallback operational runs were canceled
at coordinator request after 95/74 prepared source directories; completed
execution count is unknown and neither passed. Their compiler/context is
retained as historical evidence, not relabeled as cacheable.

Final compiler `cc827c4e79243f299dc92327fa86049669307d1f0edfa816a5b641dc443176b0`
from source `9d1b51f310477e4ceccffd8ad41ecf6fc2156e13` now qualifies old C0
harness runtime: all 222 cases, zero mismatches, selected/passed 1/1. Its
ordinary operational replay was 30.620 seconds; this is not paired timing.
Both old/new test artifacts bind that same prefix manifest.

Candidate golden correctness is also qualified by the exact9d1 primer: all
222 executions, zero mismatches, 165 writes/66,752 bytes/222 fresh work
directories and 4/4 selected tests passed. Golden source SHA matches B0
archive and compiler SHA matches the final frozen prefix. Its different
four-test wrapper is not paired timing.

Completed final golden timing: two matched order-balanced pairs, all 222
actual compiler calls per run (888 total), zero mismatches. C0/B0 wall
26.302/24.227 seconds and 26.116/24.288 seconds: descriptive 7–8% reductions,
not p95. Process RSS increases 3.98%/0.085%; prepared test artifact grows
55,061 bytes. Each sample has a fresh private runtime cache and warm shared
Zig global cache. The original operational run has its own different tier.
The measured golden preparation benefit preserves all executions and fresh
mutable state. No fully cold global-cache golden cohort was run. No compiler-generation or fresh-seed
comparison is claimed. Final full gate and broad roadmap acceptance belong
coordinator/S10. No further splitting is justified by these samples alone.
