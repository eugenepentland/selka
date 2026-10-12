# S06 handoff

C0: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
Historical experimental implementation/evidence commit (not for integration):
`f815abcffed15b03d2b74b12dc7ac7de2cd993dd`. Historical accompanying report
commit: `3a2e7373079e48490f750ab0057d01d1932265ef`. These two unpublished
worker-only commits were replaced with a C0-based evidence-only commit by explicit
coordinator authorization; the exact rejected source remains archived here.

Integration commit (evidence only, direct parent C0):
`79477b14da6acf2bbb97a518cc052a003c42b88f`.

Status: **fresh guest-loop reduction remains open; production indexing rejected**.
C0 production discovery is retained. Exact rejected source is archived in
`rejected_discovery.zig` (SHA-256 `578dd98f5d8b9380c9a6fdc63f71e1e11326e598c7469a1de4d19bfe508edfab`).
The rejected candidate improves synthetic large lookup work; operational small
rows regressed. These observations justify conservative rejection without an
isolated speedup claim. S10 may measure the frozen comparison afterward; that
optional timing must not delay the final freeze. Baseline nine-action coverage/control captures are complete. Full
runner phase metrics, final candidate guest qualification, isolated cold/warm/
edit latency and memory measurements remain outstanding. Do not label DL5 done.

## Ownership and behavior

Coordinator transferred exclusive ownership of `src/core/test_runner_discover.zig`
after S09 found no bootstrap delta there. Directory/receipt/frontend/main runner,
union/shared check lifetime and native build caller remain joint; no changes to
those files, effects, identity, seed, runtime/IR, memory modes or isolation occur.
Coordinator applied the experimental SPEC bullet in the historical candidate
commit; it is removed for the evidence-only final handoff. Production files and
SPEC have no cumulative change from C0.
Owned evidence/fixtures are under this S06 directory. Batch/work files were
transferred but remain unchanged. Shared patch requests are in
`runner-patch-request.md`; they use S01's phase/event contract and require root/
S09 ownership approval before implementation.

The candidate constructs immutable hash tables for source-module and declaration
lookup during each discovery call. Last module source wins, including a later
source missing an earlier declaration; first same-named declaration within a
source wins. Discovery's visibility, markings, sorted names/function IDs,
return shapes, parameter families and `only` closure filtering remain unchanged.
Tables are freed on completion/error, and partial scan allocations are released
on exhaustion. No persistent data/schema/receipt/producer identity changes occur.

The paired RF fixture calls exact C0 versus candidate `discover`/`within` on the
same real checked-program types. Largest 128×128 inventory replaces 2,097,152
module and 1,056,768 declaration equality comparisons with 32,768 hash lookups.
Those are selection-lookup operation counts, not total map operations or
instruction/CPU counts; scanning,
map construction, allocation, sorting and hash byte work remain in measured
component intervals. All-module cases compare exact names/IDs/shapes/parameter
families; the realistic shared-program case checks per-root selected count.
They do not prove production nine-action performance or source-mutation/crash
safety. The first operational run showed large 162.3ms→94.1ms, but tiny
0.273ms→0.327ms and medium 8.71ms→9.42ms; none is isolated qualification.

## Commands, checks and artifacts

`commands.sh` reproduces the standalone production discovery tests and prepares
its RF paired binary using pinned Zig, a private local cache and disk TMPDIR,
under shared build admission. Native tests use actual `src/typed.zig` through a
minimal namespace shim; they do not compile/install another whole compiler.
Three S06 tests passed (exit 0): duplicate/order behavior, every allocation-failure
point with cleanup, and selected visibility/shape/function identity behavior.
`discovery-tests.log` retains the output. Native compiler pin resolves to
`0.17.0-dev.1683+5ceec001b` (tool SHA recorded with baseline manifest).
`zig fmt --check` for changed Zig sources and `git diff --check` passed.
Python profiler/control helpers passed `python3 -m py_compile`.

Normal commit hooks passed all 88 Guardian checks, including the evidence-only
replacement. After restoration, the archived-source focused tests again passed
all three (exit 0; `archived-discovery-tests.log`). `git diff C0 -- src SPEC.md`
was empty. The final worktree is clean after the report commit. Its first attempt failed
because three `// spec:` declarations duplicated one ID; later related test
markers now use `// spec-case:`. No Guardian feedback entry was written.

Final paired artifact:
`/home/epentland/ai/canopy/mylang-dl-closeout-20261012-S06/.tmp/S06/discovery-profile-final`
SHA-256 `d1cc599a0de7b362c243d9caedb2f73dedacb9d031406d78516bd08776c84f00`.
`discovery-final-sha256.txt` pins exact rejected source, fixture, shim and frozen
C0 source input. The artifact compiled that exact candidate source at its original
production path; the same bytes now reside at the archived path, while production
has returned to C0. S10 owns 20 scheduled paired repetitions, pre/post artifact checks,
raw output and interpretation. No direct/nested timing locks are used. Old
`discovery-source-sha256.txt` describes the earlier formatting/spec-marker
snapshot; it is not the final candidate artifact manifest.

C0 mandatory profile exact command recipes/statuses/tools/hashes are in
`baseline-manifest.json`, raw stdout/stderr are losslessly gzipped in
`baseline-raw/`, and operational admission/action log is `guest-operational.log`.
Nine actions × cold/warm = 18 commands, all exit 0; 10,740 selected verdicts,
7,166 fresh executions and 3,574 reused verdicts. Per-mode inventories are
lang 1,552; value_semantics 140; ported 98. Fact+leak actions executed every test
in both tiers; debug/unoptimized warm lang executes three uncacheable tests.
`work-summary.json` preserves available canonical/lowering counters; absent
scope reports are unknown. `PROFILE.md` lists single operational wall times,
cache tiers and unavailable fields. These do not meet a median/p95 latency gate.

RF baseline controls in `controls-manifest.json`, `controls-raw/` and
`guest-controls.log` assert eight states: cold, warm, force, no-cache,
release/facts/leaks, edited failure, forced failure and revert. Force/no-cache/
facts/leaks report no cached tests; edited failure exits 1 with one failed test
and one unrelated cached test, force failure exits 1 with both executed, revert
exits 0 and reuses both prior successes. All eight control assertions passed.
Both profiles use S10's unchanged frozen C0 artifacts, not a compiler built from
this candidate. Candidate installed-command correctness remains unqualified.
The unsupported retired `--explain-invalidation` flag was rejected by C0 before
profiling and removed; supported `--json` contains existing work telemetry.

## Limits and integration order

Baseline measurements use explicit jobs=4 and private guest-cache tiers, with
shared global Zig cache available. Action clocks include subprocess startup,
collection, parsing and raw report writing; admission queue time is separate in
the raw log (no numeric queue summary). RSS/artifact-size deltas for the new
algorithm are unavailable. Existing frozen compiler artifact installation was
supplied by S10; its build cost was not presented as guest action latency.

Production indexing was rejected based on the operational small-row regression;
no cutoff was added. Exact source is retained as an experimental reproducer and
C0 production discovery restored. The coordinator removed the unused SPEC bullet.
S10's eventual isolated component results may support a future investigation,
without delaying this closeout. Joint once-per-shared-check
immutable preparation is the next candidate; repeated per-root indexing may be
the wrong boundary. Preserve the conservative runner while that ownership/
telemetry design is resolved. If accepted later, root must run the mandatory
nine-action and adversarial identity/source/effect/mode/isolation matrix on its
exact installed candidate plus S10's complete integrated gate. A focused shim
pass is not that gate, and the five-second/15-second-p95 targets remain open.
