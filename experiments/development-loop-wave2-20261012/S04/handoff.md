# Wave 2 S04 handoff

B0: `c1857310e0bf623545380c8de24515f1b9970021`.
Implementation and deterministic evidence:
`d9c40d16244c257b60b8aaab3da575f84b1857b8`.
Timing harness: `9fb9f90e9740eaac32915708c756655c21fd459f`, followed by
import-resolution correction `87b85599df99e7f9a6901f23e83c21e4ba1a63de`.
Normal Guardian hooks passed all 88 checks on every commit. No feedback file,
shared production source, frozen baseline source, compiler/runtime semantics or
configuration pin was modified. Source loaded-code integration lines were left
for S08 and coordinator ownership.

Owned source: verification_snapshot.py/tests, new verification_selection_profile.py,
verification_revalidation_test.py, verification_planning_timing.py, S04 evidence.
Coordinator patch contracts are in shared-patch-request.md: adopt selected_files,
validate native producers against selected declared records with missing-closure
fallback, and remove only the immediate duplicate tool validation after resolving
provider paths. Root must port actor tests into the production coordinator suite.
The B0 suppression model is standalone evidence and must not suppress the first
remaining global validation after the caller is changed.

## Work and correctness

Snapshot.selected_files receives immutable path strings and copies only selected
records. Public identity retains its fully detached complete document contract.
No metadata, watches, negative dependencies, membership, remote-file checks,
process/borrower/reset bounds or publication authority change.

77 snapshot tests pass. Four bounded coordinator actor fixtures prove deferred
initial validation still rejects tool mutation/restoration before warm reuse or
cold execution/success, while clean retained reuse has zero hashes/enumeration.
Raw snapshot-tests.log and revalidation-tests.log. No full gate was launched.

Actual frozen 46-group union contains 4639 file records. Selection-copy work falls
from 213394 to 14021 records (199373 avoided, 93.4%). All selected projections and
canonical digests are identical. Selection adds no hashing, enumeration or metadata
observations. This count excludes two additional baseline full-union copies for
native producer authentication; actual copied-record reductions may be larger.
Raw actual-selection-profile.json, all scopes and source/inventory hashes included.

Six-snapshot retained lifecycle reconstruction exactly reproduces the observed
175816 metadata observations, 31 validations and 6 snapshot reuses. Tools contain
21791 observed paths and account for 130746 observations (74.4%). Other scopes:
configuration 1210, build/coordinator configuration 1270, preparation sources 17670,
prepared artifacts 200, action inputs 24720. Removing one immediate duplicate tool
scan yields 154025 observations and 30 validations: 21791 avoided (12.4%). Both
runs preserve zero hashes/enumeration and 6 retained reuses. No cross-snapshot stat
memo, watcher-only shortcut or source authority extension is proposed. Raw scope
baseline/candidate JSON. This is deterministic reconstruction, not a full live gate.

## Exact commands and limitations

Source `/home/epentland/.config/mylang/dev-env.sh` in this worktree. Tests:
`PYTHONDONTWRITEBYTECODE=1 python3 scripts/verification_snapshot_test.py` (exit 0).
`PYTHONDONTWRITEBYTECODE=1 python3 scripts/verification_revalidation_test.py` (exit 0; 4 actor tests, including eventless metadata rejection).
Profiles use `python3 scripts/verification_selection_profile.py --root FROZEN_ROOT
--inventory FROZEN_ROOT/zig-out/verification/inventory.json`; scope variants add
`--validation-scopes --zig "$ZIG"`, then `--omit-redundant-tool-check`. All exit 0.
FROZEN_ROOT is `/home/epentland/ai/canopy/mylang-dl-closeout-20261012-integration`.
These read-only profiling runs execute no gate/native compiler and publish no
verification success receipts. Python fixture tests write only private scratch in
this owned worktree. `git diff --check` passes.

S10 received bounded paired planning harness/immutable source SHA and exact args.
It measures all 46 actual payload/key/report construction groups in balanced AB/BA
order, asserts identical payload/summary digests, records setup and validation
separately, and writes no production receipts. Shared common context is deliberately
fixed to compare function semantics; production implementation identities are not
claimed interchangeable. S10 owns outer exclusive timing admission and must smoke
then run 40 pairs. No local latency measurement or p95 claim has been made.

## Remaining fresh work and acceptance

fresh-action-audit.json extracts the 11 required fresh groups and observed member
durations from both archived B0 warm requests. Language debug/unoptimized/release
members are the largest observed members (roughly 10–12 seconds each), while
input discovery is roughly 2 seconds and identity qualification roughly 5 seconds.
Durations overlap and are not summed. Mandatory fact/leak/forced execution and
component/seed authentication remain fresh; no waiver is proposed. These archived
operational runs are not isolated performance comparisons. Input-discovery's full
rehashing is a remaining lead, requiring a separate authenticated preparation
contract; this lane does not replace its fresh membership work with cached guesses.

Root/S10 must qualify actual adopted caller counts and failure behavior, and paired
planning latency. Final whole-loop improvements and 5-second feedback/15-second
p95 remain open until measured; 11 mandatory fresh groups were not removed. Final
configuration consumers/pin review must occur after source/build wiring stabilizes.
Snapshot/API-only changes do not justify an automatic pin update. S04 is available
for that final independent review. No bootstrap acceptance or memory-team rollout
change is inferred from these tooling changes.
