# Frontend restoration and type reuse

This experiment compares the frontend improvements against `main` at
`fa1160602`. Both compiler executables use ReleaseFast. Guest programs use
optimized debug, the runtime stays at O2, and stage-cache compression is disabled.

## Changes

Ordinary checked-body snapshots can reconstruct supported dynamic array, tuple
and function-value types through the current checker.
Dependency and source guards still apply. Callable recipes derive their expected
slot from current declarations and never install a cached effect or return-origin
contract. Reconstructed transitive shapes must match before body replay. Missing,
ambiguous or unsupported recipes remain conservative misses. The semantic store
version changes to `semantic-cache-v6`; earlier entries must be repopulated.
Generic direct callbacks can use their target's fresh standalone contract if its
entire shape matches. Dynamic nominal references may resolve against types
already registered in the current checker; they never trigger speculative
nominal materialization. Literal array recipes retain their original interning
site and reject lengths exceeding that site's source byte count.

The frontend can omit more unchanged typed bodies whose debug locations refer to
other declarations. Lowering receipts prove the touched original files by origin
ordinal, path and exact bytes. Proofs cover both typed source references and
synthesized lowering positions. Header and deferred payload provenance must
agree; these proofs also enter raw optimizer cache authority. Missing or changed
proofs fall back to complete bodies. External-file changes remain conservative.

Ordinary and specialization body replay now clones directly into reserved final
node/statement arrays, avoiding intermediate outer arrays left live in the
compilation arena. List lengths publish only after successful validation.

Allocation-bounded functions and their transitive callees remain concrete for
the allocation diagnostic pass. Global semantic dependency and effect/origin
validation still runs.

## Method

`compare.py` uses the same reachable EDA replicas and length-changing entry,
helper and three-file edits as the preceding experiment. The two compilers use
identical source paths and alternate order. Native setup seeds contain only
validated original objects and objects produced during the previous comparison's
setup; historical edited objects are excluded. Frontend and intermediate caches
start empty, and setup is excluded from edit timings.

Every build must pass replica usage, EDA export golden hashes and leak checks.
Measured edits must compile exactly one, one and three native units respectively.
At 191k lines, a separate eager cache-verification build regenerates every native
unit, forces fresh linking, compares the complete executable bytes and executes
the same checks. That verification is excluded from timing medians.

Measurements use reserved CPUs 2,3,10,11 under both shared timing locks. The host
can still run background work. Peak RSS is GNU time's maximum individual process
high-water mark, not simultaneous aggregate worker memory. Stage medians need
not sum to median wall time; the native interval includes linking.

`frontend_probe.py` separately measures a one-replica check session with a 128 MiB
semantic retention budget. It reports fresh and reused body deltas rather than
confusing cumulative counters with work in the latest request.

## Incremental results

Three samples per cell, paired on the same source paths. Wall time includes
frontend, IR, optimization, native compilation and linking. Parentheses give the
observed minimum–maximum, not confidence intervals.

| Lines | Edit | Main wall seconds | Candidate wall seconds | Main → candidate frontend seconds |
|---:|---|---:|---:|---:|
| 191,416 | Entry | 2.704 (2.536–4.728) | 2.608 (2.566–2.974) | 0.947 → 0.960 |
| 191,416 | Helper | 2.068 (1.738–2.154) | 1.705 (1.668–1.975) | 1.123 → 0.959 |
| 191,416 | Three files | 2.615 (2.551–2.767) | 2.611 (2.505–3.183) | 0.910 → 0.905 |
| 510,436 | Entry | 9.555 (6.011–11.256) | 7.915 (5.727–8.297) | 5.635 → 4.098 |
| 510,436 | Helper | 5.775 (5.214–9.300) | 4.880 (4.319–5.214) | 4.077 → 3.266 |
| 510,436 | Three files | 6.354 (6.135–7.028) | 5.901 (5.221–6.139) | 3.550 → 3.203 |

At 510k lines, median wall time improves by 7–17% and frontend time by 10–27%.
At 191k, helper edits improve by 18%; the entry and three-file timing differences
are small relative to sample variation. These measurements do not establish a
universal speedup for every edit. All measured candidate edits stay below
8.30 seconds; the 15-second threshold is satisfied for these fixtures and edits.

| Lines, helper edit | Main | Candidate | Reduction |
|---|---:|---:|---:|
| 191k peak RSS, GiB | 0.572 | 0.516 | 10% |
| 510k peak RSS, GiB | 1.822 | 1.639 | 10% |
| 191k freshly checked bodies | 133 | 40 | 70% |
| 510k freshly checked bodies | 353 | 100 | 72% |
| 191k typed bodies replayed | 3,466 | 1,811 | 48% |
| 510k typed bodies replayed | 9,166 | 4,751 | 48% |
| 191k typed bodies omitted | 10,562 | 12,310 | 1,748 more omitted |
| 510k typed bodies omitted | 28,182 | 32,850 | 4,668 more omitted |

Fresh checking counts for entry/helper/three-file edits are 42/40/44 at 191k and
102/100/104 at 510k, down from 135/133/137 and 355/353/357. The one-replica check
probe improves from 12 to 7 fresh bodies after an entry edit and from 11 to 6
after a prefix-only edit. Its six remaining misses are absent current nominal
type identities. Shared types can become available after earlier replicas are
checked, so the large-fixture counts are not six times the replica count.

Native work remains exactly 1/1/3 units for the three edit classes. Raw IR bodies
materialized remain 5/30/61 and final bodies 6/44/90 at both sizes. Entry and
three-file edits freshly lower one additional raw body (2 instead of 1; 4 instead
of 3), without increasing materialized-body or native compilation counts.

This is an incremental improvement. With native setup objects preseeded, initial
frontend/stage-cache population at 510k is essentially unchanged: 87.084 →
87.384 seconds and 5.268 → 5.280 GiB peak RSS. Those are not cold native build
times and are excluded from the edit medians.

## Remaining work

The frontend still accounts for about two thirds of the 510k helper-edit wall
time. Among its separately timed phases, fresh checking is about 0.69 s,
dependency preparation 0.33 s, ordinary body replay 0.23 s, source loading and
syntax replay about 0.22 s each, and specialization replay about 0.21 s. Actual
parsing is about 0.0005 s. Phase medians do not add to the enclosing frontend
median; the complete per-sample receipts retain both measurements.

More work can be saved by avoiding repeated graph/catalog preparation and by
supporting safe nominal type reconstruction with complete rollback on failure.
The current implementation deliberately requires these types to be present
already. External debug-source proofs also invalidate on any edit to a referenced
file, even if a more precise declaration-level proof could have survived it.

## Validation

All 41 benchmark builds pass replica execution, EDA export hashes and leak
checks. All 36 edited builds compile the expected number of native units. Their
new native objects are byte-identical between compiler versions. Executable
allocated sections also match; cross-version whole-file hashes differ because
runtime debug information names the two different compiler worktree paths.

The candidate's separate 191k eager verification regenerates and verifies all
760 native units, forces a fresh link (761 compiler/linker processes), and
produces an executable byte-identical to its incremental build. Its 142.827
seconds and 2.623 GiB peak RSS are excluded from incremental medians.

The final full `zig build test fmt-check -j4 --maxrss 8589934592` run passes
all 97 build steps and 2,475 executed tests across 28 Guardian runner groups,
with zero failures. Zig also reports 22,738 shard exclusions as skipped tests.

Focused validation passes 86 semantic-cache tests, 15 semantic-project tests,
9 demand-build tests and 16 portable-type tests (the latter overlap the 86).
Regression coverage includes
allocation failures, corrupted recipes, changed callback contracts, current
nominal shape availability, external debug provenance and allocation-bounded
callers. Whole-tree Guardian passes all 88 checks without weakening policy or
accepted baselines.

The timed candidate contains all performance changes. A subsequent description
correction in `src/features.json` changes the advertised checked-body format
from v5 to v6; it changes compiler identity but no compilation algorithms. The
updated compiler's feature report and one-replica probe are verified separately.

The implementation is commit `9a77dc754` on
`codex/frontend-demand-reuse-20261010`. [summary.json](summary.json) contains all
timing medians, ranges and work counts; [validation.json](validation.json) records
test results, compiler identities and evidence hashes. [evidence/](evidence/)
retains compressed raw measurements and validation logs.
