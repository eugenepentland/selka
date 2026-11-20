# The cache model: notes (package K4)

How the Lean model maps to the Zig code, where it differs, and what the differentials found. The statement of the theorem is in
`README.md`; its assumptions are in `AXIOMS.md`.

## The mapping

| Zig (`src/core/`) | Lean (`Cache/`) | Note |
| --- | --- | --- |
| `inputs.Input` (`file`, `exists`, `listing`, `variable`) | the input identity `I` and its value `Option C` | Each kind's observation is an `Option` of something compared for equality: a file by digest (`none` = looked for and absent), existence by presence, a listing by the digest of the kept names, a variable by its value. The model gives each identity its own coordinate of the world. |
| `Handle.record`: a second sighting of an identity with another observation sets `torn` | `Consistent` trace; `consistent_run` | The model keeps every sighting; the code keeps the first per identity. Duplicates are checked twice and agree, so they change nothing. |
| `Handle.seal` returns null if torn or a file no longer matches | a torn run writes no record | `seal` also re-hashes every file at the end; the model needs only the consistency half. |
| `inputs.unchanged` / `same` / `unit_cache.checkDependency` | `Sys.check`, `Sys.inpOk` | A recorded stamp equal to the live one answers without reading; otherwise the digests are compared. `Live.observed` (the handle answers for a listing or variable it just observed) is the same observation under quiescence. |
| the stat tuple pinned only if old enough (`racy.zig`, `unit_cache.observedAt`, K3) | `World.settled`, `depOf`, `FsModel.world` | `settled i` is "`max(mtime, ctime) + W <= now` when the file was hashed". |
| the replay record (`build_replay.zig`): inputs, program, digest, stamp, report | `Rec` (`deps`, `out`) | The program is the output; `programIntact` is its stamp-or-digest check (AXIOMS O). |
| the replay key (compiler, flags, entry, configuration, toolchain, keyed environment) | the step identity `K` | AXIOMS K. |
| the tool identity and its toolchain inventory (`tool_identity.zig`) | inputs of the step (AXIOMS D3) | Not modelled separately. |
| a unit, program or foreign store entry: a content-keyed memo | a record whose one input is the content, found by digest | Covered by D0 and D2 only. |
| `test_runner_graph.prepare`: `changed` and `candidates` | `Admit.Complete`, `Matches` | `changed` = the nodes failing `Matches`. |
| `cache_plan_reference_v2.plan` | `Plan.plan` (program), `Admit.Dirty` and `Plan.checkDirty` (spec and certificate) | `reused` proved; reverse, groups, batches, work computed and compared. |
| the generic multi-step build with early cutoff | `Sys.buildAt` | The code has no such step graph yet: the replay record is one step, the stores are memos. The algorithm is what K2 and K3 build; the theorem is about it. |

## Choices in the model

* **The digest assumption is a hypothesis restricted to a session, not a Lean `axiom`.** BLAKE3 maps unboundedly many byte
  strings to 2^256 values, so a global injectivity axiom is false and, in Lean, inconsistent with the cardinality of any
  infinite type of contents. `CollisionFree sys H` asks the digest to separate the contents the history `H` shows; with `n`
  contents the failure probability is below `n² / 2^257`.
* **Faithfulness, not freshness.** The invariant is "every record in the store is a record some world of the history wrote". A
  stale, partial or empty store is faithful. The theorem needs nothing else of the store, so eviction, `keepNewest` pruning and
  concurrent writers (each record written atomically) cannot break it.
* **Fuel.** `buildAt n` is the build with `n` levels of demand; `build` uses the rank of the step plus one. Fuel only avoids a
  well-founded definition; `build_correct` shows it is sufficient and the result never `none`.
* **The stat tuple is one number per input** (`max(mtime, ctime)`): the age test uses that, and `size` and `inode` only make
  a coincidence of two tuples rarer.
* **The clean build is a solution of equations** (`IsClean`), unique by rank and existing for an inhabited output type.

## What the Lean side found in the Zig (reported, not fixed here)

1. **The record digest is BLAKE3**, not SHA-256 as the plan says. SHA-256 appears only in the planner request's snapshot and the
   component deployment digest.
2. **`cache_plan_reference_v2` is the test-receipt admission planner**, not a general step planner. The generic record
   algorithm has no Zig counterpart yet; the model has both layers.
3. **The racy-write window was not in the Zig stat path** (`unit_cache.checkDependency`, `build_replay.programIntact` trusted any
   equal tuple); it existed only in `scripts/verification_snapshot.py`. K3 added it (`a091aa835`, branch
   `cache/k3-test-receipts`, `W = 2 s`); `racy_without_age_test` is the model's counterexample to the old rule and
   `FsModel.stable` the proof for the new one.
4. The component and the reference planner count index and closure work differently (Kosaraju against Tarjan), as the
   protocol says; `cacheplan diff` compares the counts both compute the same way and the decision, batches and indexes exactly.
5. The retained index (`prior`) is validated only structurally (`validateIndexes`: the transpose is exact, representatives are
   self-grouped); the planner ignores its groups. In every real request that carried one, the retained groups and reverse rows
   equalled the recomputed ones.
6. The compiler writes `SELKA_HOST_LIMIT_CHECKPOINT` into its own environment (`memory_budget.guardHost`), and the replay
   record keys it as an input. A build under the same memory ceiling writes the same value; a differential that observes
   the environment from outside must supply it (`scripts/cache_replay_diff.py` does).

## The differentials (26 October 2026)

Compiler: the build of `d748298e6` (main before C9.1) for the replay table and the first planner runs, rebuilt from `9fa39e2b4` for
the EDA, K0-test and gate runs. Machine load average 10 to 240 (other agents), so wall times are upper bounds.

**Planner, `cacheplan diff` against the cache-plan component's reply** (decision, batches, groups, reverse index exactly; the
affected, reused and planned counts; the dirty set certified in every request):

| Source | Requests | Nodes | Tests | Reused | Result |
| --- | --- | --- | --- | --- | --- |
| `tests/lang`, all 299 entries; cold, rerun, one literal raised, put back | 565 (258 cold, 307 with a retained index) | 12,293 | 3,634 | 1,709 | 565 agree |
| selka markdown, `selka test .`; cold, first edit, part of the second | 374 (314 cold, 60 warm) | 11,631 | 1,631 | 886 | 374 agree |
| EDA stage 2, `selka test .` (142 test files); cold, first edit | 115 (86 cold, 18 warm, 11 of the version-one protocol) | 5,790 | 749 | 196 | 115 agree |
| K0's `test` group (83 cases: environment, flag, edit and slice cases) | 204 | 1,101 | 423 | 15 | 202 agree; 2 replies are malformed |
| random graphs: cyclic, acyclic, layered, repeated edges, equal digests; four of 100,000 nodes and one of 20,000 | 2,900 | 801,402 | 39,871 | 18,013 | all agree |

The two malformed replies are the K0 case `SELKA_OPTIONS=--print-result`, which reaches the component and appends `0\n` to its stdout; the
host rejects such a reply (`ComponentProtocol`) and so does `cacheplan diff` ("reply envelope"). The retained index
(`prior`) equalled the recomputed one in every request that carried one (307 + 60 + 18 + 12). Lean time: 565 requests in 1.4 s, 600
random graphs including one of 100,000 nodes in 0.7 s (`cacheplan diff` takes many requests in one process; one process per
request is about 60 ms each, all start-up).

**The host's `changed` list**, `cacheplan changed` on consecutive requests across a real edit or revert (tests/lang): 67 pairs, 1,702
nodes, 0 nodes outside the previous graph's (body digest, callee count) set; the control that drops one genuinely new node from the
list was caught in 47 of 47 pairs. No real graph in which `changed` missed a node was found.

**Replay, `cacheplan replay` against the compiler's decision**, before every warm `build`/`run` of the K0 table (193 cases, compiler
`d748298e6`), in `scripts/cache_replay_diff.py mutate`:

| Outcome | Warm builds | Meaning |
| --- | --- | --- |
| agree-replayed | 50 | Zig replayed and some record of its key is unchanged on disk |
| agree-miss | 93 | Zig did not replay and no record of its key is unchanged (or the key changed) |
| no-report | 34 | the warm build printed no cache line (it failed first) |
| outside-record | 16 | Zig did not replay though the record's own inputs are unchanged: `env-*`/`link-env-*` (a keyed variable newly set, which the key carries and a record of an unset variable does not), `HOME` and `XDG_CACHE_HOME` (they move the tool memo), `toolchain-*` (the toolchain identity) |
| VIOLATION | 0 | Zig replayed with no unchanged record |
| STALE | 0 | a recorded stat tuple unchanged over changed bytes |

191 records and 2,443 inputs were checked by Lean in 29.7 s (largest 1.96 s). The K0 harness's own verdict was STALE for one case,
`env-build-selka_friction_log` (and `env-test-selka_friction_log`): the warm and the clean build both print
`error(SafeAllocator): leaked [addr: ...]` for two 64-byte blocks, with different addresses. That is a leak in the Debug compiler when
`SELKA_FRICTION_LOG` is set, and K0's output normalisation does not strip the addresses; it is not a cache difference (reproduced
alone). Not fixed here.

Not run: the replay chains of `scripts/cache_replay_diff.py fuzz` (selka, EDA), and the planner chains past their first edits (the
selka and EDA chains stopped early), because the machine was shared; the K0 table includes `selka-build-*` and `eda-build-*` edit
cases. The replay differential is not in the gate action: it waits for K3's `core-build-replay-v5`.

## Timings of the Lean side

| Case | Wall time |
| --- | --- |
| `lake build`, cold (no `.lake`) | 11.3 s (22.4 s CPU) |
| `lake build`, nothing changed | 0.2 s |
| `lake build`, a proof body or comment edited | about 1 s (Lake cuts off when the interface is unchanged) |
| `lake build`, a definition in `Basic.lean` changed | 9.7 s |
| `lake exe cacheplan diff` over 565 requests | 1.4 s |
| `fixtures/check.sh` | under 1 s |
| the action `cache-proof` in the gate (warm Lean build, 25 `tests/lang` entries, 400 random graphs) | 14 s |
