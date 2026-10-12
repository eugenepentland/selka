# Reviewable owner-authored native-link repair

Source patch: `adoption.patch`. **Approved and applied by the coordinator.**
The user explicitly replied “Adopt the existing fix” to the joint-ownership
request. Candidate qualification remains pending; the owner checkout is untouched.

Exact memory owner commit:
`6327267249fdfbedab4093a5787033a5485a442d`.
Original A01 worker commit:
`38dc781a897182ffbf1fff0906ec319a007a9154`.
The driver deltas in those two commits are byte-identical, SHA256
`4eb4f5055a47655013faf90409f6fd81088df2011ae097a791984eaccc40c384`.
A01's checked-in handoff describes this independent native driver repair; its
native-driver README explains the failure and focused evidence. The memory
coordinator has integrated the fixed commit. No reviewed owner document supplied
an explicit cross-workstream transfer. This is a concrete adoption request using
the owner's implementation, not a competing repair or takeover of its tree.

## Problem and exact change

An unapproved native tool keeps compiled unit objects in private request staging.
`unitObjects` deleted those objects on return, before the caller linked them;
real guest builds then failed with `native-link-.../<key>.o: FileNotFound`.

The exact owner patch restricts per-unit partial deletion to cacheable builds.
Uncacheable objects survive linking and are removed by the caller's existing
staging-tree defer on success or failure. Tool approval, tool/content identity,
cache eligibility, runtime ABI, ownership mode and rollout defaults are unchanged.
The helper preserves the driver's complexity bound.

The patch includes only:

- `src/core/driver.zig`: exact owner cleanup delta.
- `src/core/a01_native_driver_test.zig`: exact existing uniquely named A01 regression.
- `src/core/root_test.zig`: one manual import inserted after zero_rc_test, preserving
  this candidate's existing imports. It does not copy the memory root's other tests.

The regression uses an explicitly unproved fake native tool that refuses a link
when any input object is absent. Two successful multiunit links each compile both
units with zero reuse; a failed link also must remove private staging. Existing
unproved-tool cleanup coverage remains required.

## Qualification and application checks

The current development candidate's driver is byte-identical to the owner commit's
parent driver. `request.json` binds the observed candidate SHA, source hashes,
owner delta and patch digest. The proposed patch passes read-only `git apply
--check` on both the S09 worktree and current integration worktree. No shared
source or owner tree was modified during these checks.

`owner-final-focused.log` preserves the owner's terminal evidence, with only a
terminal blank line normalized: 2/2 selected tests passed, zero failures/skips,
including the new multiunit lifetime regression and existing unproved-tool
success/failure cleanup regression. These are owner-source focused results, not
qualification of our patched candidate or a replacement for its full gate.

After approval, root can apply the standalone patch (or cherry-pick the fixed
owner commit while manually retaining current root imports), record the joint
ownership decision, then run through normal shared admission:

```sh
source /home/epentland/.config/mylang/dev-env.sh
scripts/build-slot.sh build "$ZIG" build test-core -Dtest-filter='A01 uncached' -Dtest-filter='linkNative refuses unproved' -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"
```

Rebuild/install the compiler after changing src before rerunning the independently
failing real guest test/native-link reproducer. Repeat its debug/release/fact/leak
controls where applicable, failure cleanup and retry; capture exact source/tool/
artifact identities. Integrating this behavior invalidates affected compiler/test
receipts. Final complete verification remains root/S10 work on the frozen result.

## Remaining boundary and blocker

The joint-ownership condition is satisfied by the recorded user approval. The
coordinator applied the exact owner delta and current-root registration. Normal
focused and complete qualification of this integrated candidate remains required.

The owner's separate native-platform audit found changed `/etc/ld.so.cache`
while the five reviewed loader/runtime libraries remained identical. This patch
intentionally leaves that trust decision separate. Correct execution must work
when native cache approval is unavailable; warm-cache reuse assertions may still
need independent host qualification. Neither old C0 failures nor old bootstrap
seed results may be relabeled after this fix. No full-memory, full-bootstrap or
performance acceptance follows from this repair.
