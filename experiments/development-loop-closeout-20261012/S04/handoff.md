# S04 handoff

C0: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
Implementation: `1301efb189d81e1599c7ee26e79a782bd5525d9f`.
Reviewed legacy-provider compatibility correction:
`f866ced33b009ba223c3b64e1a13f46ec8f06b66`.
Apply both in order; this handoff adds documentation only. No shared integration
files, compiler semantics, bootstrap sources or configuration pin were committed.

Owned changes: `scripts/verification_artifacts.py`, new
`scripts/verification_producers.py`, `scripts/verification_producers_test.py`,
and this S04 evidence directory. Normal commit hooks ran Guardian: 88 checks
passed on each implementation commit. No Guardian feedback file was modified.

## Delivered behavior and contract

The artifact writer emits version 2 with exact locations and explicitly opted-in
producer metadata. It authenticates independently built tooling-units (11 sources)
and S03 text-scalar-units (7 sources, including two embedded test oracles).
Unknown/dynamic/expanded imports cannot silently inherit a narrower declaration.
The helper separates implementation/source bytes from interface, ABI, mode,
external seed and inherited tool/build contexts. A transitive semantic edit
changes identity even when emitted executable bytes happen to remain unchanged.
Missing/schema/ABI/seed/mode/source mismatch declines opted-in narrow reuse.

Preexisting reviewed providers retain their existing artifact-byte projections
and broad source recipes. Unknown newly claimed narrow boundaries retain whole
artifacts until reviewed. Components and fuzz/performance compiler consumers keep
their current authenticated/broad contracts; this lane does not invent a native
checker equivalence from matching protocol versions.

Shared-file patch requests and exact caller requirements are in `contract.md`.
Root owns actual action v4 wiring, imported-code identity, native build qualifiers,
registration and declared test inputs. S03 implementation dependency:
`250fce286ed802739549b189ea5378aaa6d6b9b4`. Integrate that root before enabling
text-scalar qualification. S09's bootstrap inventory remains separate; no compiler
stage or strict bootstrap ratio acceptance is claimed here.

## Commands, results and source/tool evidence

`PYTHONDONTWRITEBYTECODE=1 python3 scripts/verification_producers_test.py`: exit 0,
14/14 tests executed, none skipped or reused. Raw output `python-tests.log`.
Coverage: independent compiler edit, transitive source identity and revert,
artifact replacement, missing/legacy metadata, schema/ABI/mode/seed/tool changes,
missing/duplicate/symlink source, dynamic/new imports, source/artifact ABA during
lookup, mutation during capture/publication, embedded oracle changes, equivalent
second-worktree producer identity, and atomic writer rejection.

`PYTHONDONTWRITEBYTECODE=1 python3 experiments/development-loop-closeout-20261012/S04/native-mutation.py`:
exit 0. The script owns three admitted native requests with private local cache,
disk TMPDIR, shared global cache and pinned Zig. Exact command/environment/hash
records are in `native-mutation.json`; raw outputs baseline/semantic-mutation/revert
logs. Each selected two tests (one named plus import-root wrapper): baseline 2/2
pass; semantic mutation 1/2 pass, 1 failure, build exit 1; revert 2/2 pass. Failure
was `TestExpectedEqual`, not an infrastructure or parse failure. The temporary
`fix_plan.zig` mutation was restored byte-for-byte and was never committed.

`ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-S04" ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache TMPDIR="$PWD/.mylang-cache/S04-tmp" scripts/build-slot.sh build /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig build test-tooling-units --summary all`:
exit 0, 28/28 tests passed; raw `native-full-tooling.log`. Compile MaxRSS 166M,
run MaxRSS 6M, observed test wall 0.02s. These are operational observations.

`PYTHONDONTWRITEBYTECODE=1 python3 scripts/verification_artifacts.py experiments/development-loop-closeout-20261012/S04/native-artifacts.json --qualify tooling-units Debug tooling-units .zig-cache-S04/o/454f7b509922319895added2987002af/tooling-unit-tests`:
exit 0. Actual native executable/source metadata archived in `native-artifacts.json`.
Executable SHA256: `29900e9418e5585c48a5fab2fe4fdcaceafefd8ec467445184c55fbcf3b005ac`.
Pinned Zig `0.17.0-dev.1683+5ceec001b` SHA256:
`1d314883fd8cf4490c1c29dd73ad8b64e319a8a53c4d9087d1135b52977df37f`.
`git diff --check`: exit 0.

## Qualification limits and required integration work

S04 is a reviewed implementation plus native dependency/failure evidence. Full
end-to-end adoption into cached action receipts is **not yet qualified** until
root applies the shared wiring and S10 tests the integrated candidate. The new
text-scalar producer's root/registration comes from S03, not this lane. Standalone
metadata tests do not close DL4 alone.

Configuration consumers were audited at C0 in `contract.md`. Pin mismatch safely
retains broad invalidation; no automatic refresh occurred. Root/S04 must explicitly
review final consumers following all build changes and regressions before any
new qualification digest is committed.

Outstanding: integrated source-edit/semantic-failure action execution, missing
metadata fallback, both pure producer modes and reverted evidence, mutation while
shared receipt lookup/publication occurs, compatible worktree action policy,
forced versus cached action parity, final inventory and complete gate/formatting.
S05 may consume qualified identities only for actual independent producer inputs;
compiler fuzz/Juice consumers remain broad. Current common root/environment fields
keep action receipts distinct across worktrees; producer equivalence tests do not
claim action cross-worktree reuse.

Cold/warm/edit isolated medians and p95: unavailable here, owned by S10. Native
mutation operational totals 4.06s/7.01s/6.80s include admission and are not latency
claims. Global cache warmth was not isolated. No complete gate, cold-cost bound,
artifact-size regression threshold or RSS comparison is inferred from these runs.
