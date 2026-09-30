# WP-C1 EDA closeout — 2026-09-30

The handwritten EDA port and its required development evidence are complete on
owned review branches. This phase does not update either main ref. Phases A and B
were already merged with the user's earlier approvals.

The application source checkpoint is EDA `0ba0761fe889d1b9357f4451b3484fd13d1a7377`,
based on `af8cf03`; all subsequent source/asset/project hashes remain unchanged.
The final compiler source is `e88fcf3c98d6f0e0090e0719472e1081fb81f119`, installed
in Debug mode with binary SHA-256
`6259edca26ea90f93b85037a17b5fc2692505a4e6f4cdd05cca23554b1bb0bcc`.
All existing qualification and timings keep this mode. Future compiler builds
use `-Doptimize=ReleaseFast`, as requested after this run began.

## Application acceptance

- All 57 source-Zig keys mapped, with every 279 named original test retained.
- 319 fresh native tests across 59 programs: 279 originals, 33 support tests,
  one parser property and six model supplements. Zero cached/failed/skipped/dropped;
  zero unloaded rows observed, no separate unloaded terminal counter.
- Six separate native footprint supplements pass, including real 90° rotation.
- All 34 reference cases byte-identical, with full embedded schematic fixtures.
- All 122 module checks exit zero; existing unused warnings remain recorded.
- Format passes, all 20 guide examples pass, strict correspondence/map pass.
- Counts: 123 files, 18,813 nonblank lines, 5,004 test and 13,809 non-test lines.
- All 12 development-loop metrics complete; 43 command logs, nine normal edit/
  restore pairs and unchanged source/prefix hashes are archived.

The source-Zig, golden inputs, expected data and harness implementation were not
changed. Expected comparisons are harness-only. The executable SHA-256 is
`2c829e2291e7c017a9219d0367fd279b6f64d1445711ce62036c84cc9ff78d34`.
The old provisional `0289edb6` evidence retains its original identity.

## Compiler qualification and scope

[eda-trig-interface-2026-09-30.md](eda-trig-interface-2026-09-30.md) explains the
native binary64 sin/cos implementation, cache-safe standard-library guards and
symbolic generic float-intrinsic repair, with rejected and accepted checkpoints.
Four broad targets pass: test (115/115 build steps, 2,806 selected Zig passes),
QBE tests (505/505), QBE build (29/29 cached steps) and format (2/2). Sparse
registration skips are not fresh passes. Default and GC-stress each run 1,490
fresh guest tests. The common-lane addendum also passes release/stats (1,490 each),
Lox RC/GC (65 suite tests and 13 driver cases each), native checks and 100 valid
fuzz seeds. There are zero RC divergences and the two exact known GC-only
findings from Phase B. Native heap's cached executables are disclosed.

This scope does not claim a new full 27-step compiler integration/performance
matrix or qualification of the combined source with concurrent main changes.
Main was observed at `5041d690` (compiler) and `af8cf03` (EDA); original checkouts
remain untouched. Guardian feedback is committed in guardian-zig as `9faf6b8`
and `764b8ff`.

## Practical use

Value semantics, native byte-key collections, explicit capability/Result data
flow, embedding and useful located diagnostics supported the port well.
The recurring costs were copy/mutate/store-back for record fields, limited record
defaults, explicit Option inference, noncapturing callbacks and compatibility
helpers for Zig float formatting/parsing/hash APIs. The invalid constructor
`set[bytes]()` still returns a bare host InternalError (G25); the port uses valid
`set()`. General authenticated projection for future private-intrinsic standard
templates remains a documented compiler limitation, not an unfinished current
application path.

The material D4 filesystem scope remains explicit: unavailable stat/entry-kind,
rename, symlink, threads and atomic generation cannot be faithfully supplied;
whole-file byte limits are checked after allocation. Existing permitted map/
module/width/capability adaptations remain documented in the EDA guide.

The Debug sample is 334.572 s cold, 0.333 s no-op and 6.990–13.828 s incremental
build; edited tests take 61.866–118.844 s. Reserved cores still shared package,
memory, thermal load and SMT sibling activity. The 386 s admission queue is
excluded from metrics. This is one descriptive sample per metric, with no
regression or future ReleaseFast claim.

## Evidence and review branches

EDA branch: `codex/next-eda-integration-20260930` in
`/home/epentland/ai/canopy/eda-bench-wt/codex-next-eda-integration-20260930`.
Compiler branch: `codex/next-eda-compiler-20260930` in this worktree.

- [EDA acceptance and scope](/home/epentland/ai/canopy/eda-bench-wt/codex-next-eda-integration-20260930/mylang/COMPLETION.md).
- [Practical friction and lane repair costs](/home/epentland/ai/canopy/eda-bench-wt/codex-next-eda-integration-20260930/mylang/FRICTION.md).
- [Full timing table and environment](/home/epentland/ai/canopy/eda-bench-wt/codex-next-eda-integration-20260930/mylang/TIMING-AUDIT.md).
- [Independent witness review](/home/epentland/ai/canopy/eda-bench-wt/codex-next-eda-integration-20260930/mylang/evidence/c1/completion-review/README.md).
- [Broad compiler receipt](evidence/eda-trig-qualified-20260930/receipt.json).
- [Remaining common-lane receipt](evidence/eda-trig-common-lane-20260930/receipt.json).

Reviewers can assess the concrete committed result without changing shared main
or the original dirty checkout. The handoff plan's explicit-main-approval rule
continues to apply to the new Phase C changes.
