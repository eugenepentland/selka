# Runtime parity wave 3 decisions

## M0-001 — current main as base

- Question: the plan records `0689d3407`, while main is `41ed360fb361c49938488ad111795bad8a726b73`.
- Options: use its historical base or obey the launch instruction to branch from current main.
- Evidence: current main includes the launch plan itself; changes since the recorded hash are plan commits.
- Choice: freeze `41ed360fb361c49938488ad111795bad8a726b73` as M0's base; merge later main movement with real merge commits and rerun gates.
- Reversibility: the base install remains pinned, with subsequent merge provenance recorded separately.

## M0-002 — isolated environment and coordination

- Question: how to preserve existing work and obey machine resource limits.
- Options: edit the dirty original checkout or create the required private worktree.
- Evidence: original checkout has unrelated modifications; disk has 402 GiB free; other runs occupy build and gate slots.
- Choice: use a locked, prune-kept private worktree; put TMPDIR, Zig local cache and compiler-tagged runtime caches inside it; use the shared build-slot wrapper unchanged.
- Reversibility: all scratch and evidence are owned by this run. U2/S2/R start only after M0 succeeds.
