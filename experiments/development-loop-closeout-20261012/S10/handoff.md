# S10 acquisition handoff (in progress)

C0 `fbfcaa7a923186a8e773c3760f81c10aa345a432`; own branch
`codex/dl-closeout-20261012-S10`. Production/shared files unchanged. Owned files:
this experiment directory, including acquire.py, review.py, freeze_artifact.py,
retained_requests.py, timing_fixture.py, qualification.json,
timing-schedule.md and raw evidence. Implementation/handoff commit SHAs are returned after the normal commit hook.

The full C0 Git tree is archived in raw/C0-tree.txt.gz (hash covers decompressed bytes) and hashes/tools/affinity/cache
conditions in raw/C0-identity.json. Legacy pruning is blocked by `.prune-keep`;
frozen compiler installation lives under `.tmp-s10/frozen-release` and remains
protected for S06/S07 consumers. Pins/leases do not imply semantic validity.

`acquire.py release` delegates build admission to build-slot.sh. `acquire.py
complete` invokes the verification coordinator directly with `--force`; that
coordinator owns plan/preparation/gate admission. Command receipts archive full
argv, exit status and elapsed time including queues. Raw last-run admissions
provide separate queue/execution clocks. Operational acquisition is not an
isolated speed comparison. Shared global Zig and native runtime caches are never
wiped; private tier cold controls are declared in qualification.json.

Baseline complete gate passed: 45groups/95members,status 0,stable true,110.060s build admitted +1034.160s gate admitted;1196.052s total incl 1.139s queue. Independent review.py confirms exact action/member metadata coverage.

Missing data remain unqualified: paired
final candidate, edit/failure matrix, retained warm counters, isolated latency,
RSS/cold preparation comparisons, final complete verification and formatting.
No hard deadlines or performance wins are inferred from historical samples.

S01 supplies Python per-test telemetry, with guest/Guardian timings unknown.
S02 budgets remain report-only pending headroom evidence. S03 scalar root must
preserve eight named tests plus wrapper and oracle rows. S06 nine language members
retain facts/leaks/forced execution. S07 golden replay retains 604 cases/222 checked.
S08 current real retained counters need baseline/final request evidence. S09 full
DL7 remains open: external port ownership, authenticated seed stages, no fallback,
and every median/p95 ratio <=1.5; legacy admission migration requires owner adoption.

Timing schedule waits for cross-team root/A09 coordination. No worker requests an
independent full gate or uncontrolled measurement window. Final qualification must
run on exact frozen integrated source and match forced independent inventories.

Frozen artifacts: Debug SHA 7755a47e1e3f3eae11073effa41f4716fa7a99c818a4d836b8965c549fd0b57f (238915874 bytes); ReleaseFast SHA fef6fc25c6452099e2e2f443a706676b5c39c7a2546bcdf686b1b2507b79eb8f (68298856 bytes). Both protected by explicit versioned blob pins; raw/C0-*-artifact.json records ordered chunks and pin IDs. RF build status 0,423.261s including queue is operational only.

Baseline Debug complete environment: ZIG_LOCAL_CACHE_DIR=$PWD/.zig-s10-debug-cache, ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache, TMPDIR=$PWD/.tmp-s10. ReleaseFast used $PWD/.zig-s10-cache. Root source/HEAD stayed C0 throughout admitted baseline verification. No isolated p95 accepted.

Expanded tool closure: raw/C0-tools.json.gz archives 20348 actual tool snapshot files (Zig lib, Python stdlib, resolved tools/shared libraries and negative PATH membership recipes), decompressed SHA 2356f544e2c429342b96fbc4a3725b143f28502acd53f886b55ddae3ef49ffa6. Contents validated stable during acquisition.

C0 retained startup selected all 45 groups with an implementation identity mismatch. Supported SIGTERM cancellation of own active verify dispatch returned 143/okfalse at 335.428s; log says no new success receipts, all admission slots released. This request is incomplete, not a warm sample. A stale copy of the prior complete report is explicitly renamed; raw/C0-retained/status.json governs interpretation. Cause investigation is read-only S08.

S06 rejected discovery candidate isolated 20 reps passed exact inventory assertions under bounded 30s timing window, FIFO ticket 3 after 0s. Median ratios candidate/C0:8 tests 1.1344,1024 tests 0.8555,16384 tests 0.5855,shared 128 roots 1.0385. Small/shared regressions support rejection. Fixed baseline→candidate order and 20 samples establish no stable p95 or guest-loop speed claim. Raw samples and archived final source hashes preserved.

Final C1 a9a3208a4f3edbf17170cfc18d57f5f999af49c3 is frozen by root; retained force→warm2 qualification running against integration private .zig-cache/.tmp. S10 controller writes raw evidence in its own tree; integration source stays untouched. Final fullmatrix is explicitly accounted in final-matrix.md. No redundant final one-shot fullgate is run; absence is reported.
