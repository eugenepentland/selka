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

## M0-003 — quiet timing admission

- Question: the inherited timing scripts hold the CPU-10 lock but do not exclude other build-slot users.
- Options: rely on scheduling by other runs, or hold all existing build/gate locks during timing.
- Evidence: other runs occupy build and gate slots; the plan explicitly requires no build during CPU-10 timing.
- Choice: the retargeted `quiet.py` acquires the admission, gate, three build and CPU-10 locks together, nonblocking with release-on-contention. Only prebuilt binaries run while it holds them. Parity acquires them after building and output qualification.
- Reversibility: measurement-tool-only change, no policy, oracle, benchmark or compiler changes.

## M0-004 — current-main conformance provenance

- Question: frontend fixes changed the historical conformance totals.
- Options: record the unadapted oracle result or use the additive frontend reference already reviewed on main.
- Evidence: `experiments/frontend-fixes-20261009/REPORT.md` records 1,547 matches per mode with its additive reference; two historical names are mapped and 29 frontend cases are additive.
- Choice: first run the plan's exact unadapted invocation and preserve its result; also establish the reviewed additive invocation as the complete comparison if needed. Never edit frozen references or ignore an unexplained discrepancy.
- Reversibility: invocation/evidence only.

## M0-005 — restore reference builds after QBE retirement

- Question: `expanded/run.py --build-only` rejects current main's compiler because it requires a QBE asset.
- Options: restore a retired compiler backend, abandon references after the allowed time box, or rebuild the reference arms with their existing recipes.
- Evidence: the first build attempt stops at `cannot locate QBE compiler asset`, before compiling a reference.
- Choice: `tools/rows_references.py` reproduces all 16 Rust/Zig RS/Zig RF/Go build recipes from the existing runner, including Cargo's locked text dependency, then verifies every registry edge probe. The eight retired mylang backend arms are not reference arms; the current mylang rows are built by `measure_all46.py`.
- Reversibility: tooling only; reference sources and historical evidence stay read-only. A reference checksum failure is not waived.

## M0-006 — repair two unmigrated row sources in private copies

- Question: current main still rejects two rows that FU-PORT already reported as unbuildable.
- Options: skip the rows (forbidden), change language semantics (forbidden), or repair only their incomplete syntax migration.
- Evidence: `row_json_transform.my:16` produces E_NUMERIC_PARSE; `row_union_find.my:10` assigns the immutable scalar parameter x. The current base's `mylang fix` changes only `int(text)` to `parse_int(text)` in the former.
- Choice: retain private copies under `M0/row-sources`, changing numeric parsing to its current spelling and introducing a mutable local cursor initialized from x for union-find. Parent mutation and all timed work stay the same. `M0/row-migration.patch` captures the exact edits. Both base and final must use the same copies and pass the references' checksums.
- Reversibility: source-compatibility bug fixes only; no repository benchmark or compiler file changes. Delete the copies when main supplies the equivalent migration.
